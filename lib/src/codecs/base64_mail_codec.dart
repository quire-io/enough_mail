import 'dart:convert';
import 'dart:typed_data';

import '../mail_conventions.dart';
import '../private/util/ascii_runes.dart';
import 'mail_codec.dart';

/// Provides base64 encoder and decoder.
///
/// Compare https://tools.ietf.org/html/rfc2045#page-23 for details.
class Base64MailCodec extends MailCodec {
  /// Creates a new base64 mail codec
  const Base64MailCodec();

  /// Encodes the specified text in base64 format.
  ///
  /// [text] specifies the text to be encoded.
  /// [codec] the optional codec, defaults to utf8 [MailCodec.encodingUtf8].
  /// Set [wrap] to `false` in case you do not want to wrap lines.
  @override
  String encodeText(
    String text, {
    Codec codec = MailCodec.encodingUtf8,
    bool wrap = true,
  }) {
    final charCodes = codec.encode(text);

    return encodeData(charCodes, wrap: wrap);
  }

  /// Encodes the header text in base64 only if required.
  ///
  /// [text] specifies the text to be encoded.
  /// Set the optional [fromStart] to true in case the encoding should
  /// start at the beginning of the text and not in the middle.
  /// Set the [nameLength] for ensuring there is enough place for the
  /// name of the encoding.
  @override
  String encodeHeader(
    String text, {
    int nameLength = 0,
    bool fromStart = false,
  }) {
    final runes = List.from(text.runes, growable: false);
    var numberOfRunesAbove7Bit = 0;
    var startIndex = -1;
    var endIndex = -1;
    for (var runeIndex = 0; runeIndex < runes.length; runeIndex++) {
      final rune = runes[runeIndex];
      if (rune > 128) {
        numberOfRunesAbove7Bit++;
        if (startIndex == -1) {
          startIndex = runeIndex;
          endIndex = runeIndex;
        } else {
          endIndex = runeIndex;
        }
      }
    }
    if (numberOfRunesAbove7Bit == 0) {
      return text;
    } else {
      const qpWordHead = '=?utf8?B?';
      const qpWordTail = '?=';
      const qpWordDelimiterSize = qpWordHead.length + qpWordTail.length;
      if (fromStart) {
        startIndex = 0;
        endIndex = text.length - 1;
      }
      // Available space for the current encoded word
      var qpWordSize = MailConventions.encodedWordMaxLength -
          qpWordDelimiterSize -
          startIndex -
          (nameLength + 2);
      final buffer = StringBuffer();
      if (startIndex > 0) {
        buffer.write(text.substring(0, startIndex));
      }
      final textToEncode =
          fromStart ? text : text.substring(startIndex, endIndex + 1);
      final encoded = encodeText(textToEncode, wrap: false);
      buffer.write(qpWordHead);
      if (encoded.length < qpWordSize) {
        buffer.write(encoded);
      } else {
        // Reuses startIndex for folding
        startIndex = 0;
        while (startIndex < encoded.length) {
          final chunk = startIndex + qpWordSize > encoded.length
              ? encoded.substring(startIndex)
              : encoded.substring(startIndex, startIndex + qpWordSize);
          buffer.write(chunk);
          startIndex += qpWordSize;
          if (startIndex < encoded.length) {
            buffer
              ..write(qpWordTail)
              // NOTE Per specification, a CRLF should be inserted here,
              // but the folding occurs on the rendering function.
              // Here we leave only the WSP marker
              // to separate each q-encoded word.
              // ..writeCharCode(AsciiRunes.runeCarriageReturn)
              // ..writeCharCode(AsciiRunes.runeLineFeed)
              // Assumes per default a single leading space for header folding
              ..writeCharCode(AsciiRunes.runeSpace)
              ..write(qpWordHead);
            qpWordSize =
                MailConventions.encodedWordMaxLength - qpWordDelimiterSize - 1;
          }
        }
      }
      buffer.write(qpWordTail);
      if (endIndex < text.length - 1) {
        buffer.write(text.substring(endIndex + 1));
      }

      return buffer.toString();
    }
  }

  @override
  Uint8List decodeData(final String part) {
    var cleaned = part.replaceAll('\r\n', '');
    var numberOfRequiredPadding =
        cleaned.length % 4 == 0 ? 0 : 4 - cleaned.length % 4;
    if (numberOfRequiredPadding > 0 && cleaned.endsWith('=')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
      numberOfRequiredPadding =
          cleaned.length % 4 == 0 ? 0 : 4 - cleaned.length % 4;
    }
    if (numberOfRequiredPadding > 0) {
      final buffer = StringBuffer(cleaned);
      var paddingRequired = true;
      while (paddingRequired) {
        buffer.write('=');
        numberOfRequiredPadding--;
        paddingRequired = numberOfRequiredPadding > 0;
      }
      cleaned = buffer.toString();
    }

    return base64.decode(repairBase64(cleaned));
  }

  @override
  String decodeText(String part, Encoding codec, {bool isHeader = false}) {
    final outputList = decodeData(part);

    return codec.decode(outputList);
  }

  /// Encodes the specified [data] in base64 format.
  /// Set [wrap] to false in case you do not want to wrap lines.
  String encodeData(List<int> data, {bool wrap = true}) {
    var base64Text = base64.encode(data);
    if (wrap) {
      base64Text = _wrapText(base64Text);
    }

    return base64Text;
  }

  String _wrapText(String text) {
    const chunkLength = MailConventions.textLineMaxLength;
    var length = text.length;
    if (length <= chunkLength) {
      return text;
    }
    var chunkIndex = 0;
    final buffer = StringBuffer();
    // ignore: invariant_booleans
    while (length > chunkLength) {
      final startPos = chunkIndex * chunkLength;
      final endPos = startPos + chunkLength;
      buffer
        ..write(text.substring(startPos, endPos))
        ..write('\r\n');
      chunkIndex++;
      length -= chunkLength;
    }
    if (length > 0) {
      final startPos = chunkIndex * chunkLength;
      buffer.write(text.substring(startPos));
    }

    return buffer.toString();
  }
}

/// Repair a malformed Base64 [input]. The additional bits will be truncated.
String repairBase64(
    String input, {
      String paddingChar = '=',
      String alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',
    }) {
  var inputLength = input.length;
  while (inputLength > 0 && input[inputLength - 1] == paddingChar) {
    inputLength--;
  }

  if (inputLength == 0) {
    return input;
  }

  final remainder = inputLength % 4;
  final lastCharPos = inputLength - 1;
  // Remainder = 0: No need to repair.
  if (remainder == 0) {
    return input;
  }
  // Remainder = 1: Impossible in theory. Should truncate all 6 bits.
  if (remainder == 1) {
    return input.substring(0, lastCharPos);
  }

  final lastChar = input[lastCharPos];
  final base64Index = alphabet.indexOf(lastChar);
  if (base64Index == -1) {
    throw FormatException(
        'Invalid Base64 character in input.', input, lastCharPos);
  }

  // Remainder = 3: Keep only the first 6 bits, truncate last 2 bits.
  // Remainder = 2: Keep only the first 4 bits, truncate last 4 bits.
  final mask = remainder == 3 ? ~0x3 : ~0xF;
  return input.substring(0, lastCharPos) +
      alphabet[base64Index & mask] +
      paddingChar * (4 - remainder);
}
