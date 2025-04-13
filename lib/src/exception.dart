/// Base exception for any IMAP, POP, SMTP or highlevel API exceptions
class BaseMailException implements Exception {
  /// Creates a new exception
  const BaseMailException(this.message);

  /// The error message
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Notifies about an invalid argument
class InvalidArgumentException extends BaseMailException {
  /// Creates a new invalid argument exception
  InvalidArgumentException(super.message);
}
