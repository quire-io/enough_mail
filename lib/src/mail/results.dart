import 'dart:async';

import 'package:collection/collection.dart' show IterableExtension;

import '../../enough_mail.dart';

/// Base class for operation results based on messages
class MessagesOperationResult {
  /// Creates a new message operation result
  MessagesOperationResult(
    this.originalSequence,
    this.originalMailbox,
    this.targetSequence,
    this.targetMailbox,
    this.mailClient, {
    required this.canUndo,
    this.messages,
  }) {
    applyMessageIds(originalSequence, targetSequence, messages);
  }

  /// Is this delete result undoable?
  @Deprecated('Use canUndo instead')
  bool get isUndoable => canUndo;

  /// Can the move operation be undone?
  final bool canUndo;

  /// The originating mailbox
  final Mailbox originalMailbox;

  /// The original message sequence used
  final MessageSequence originalSequence;

  /// The resulting message sequence of the deleted messages
  final MessageSequence? targetSequence;

  /// The target mailbox, can be null
  final Mailbox? targetMailbox;

  /// The associated mail client
  final MailClient mailClient;

  /// The deleted messages, if known
  final List<MimeMessage>? messages;

  /// Apply the message IDs from the [targetSequence] to the [messages]
  bool applyMessageIds(
    MessageSequence originalSequence,
    MessageSequence? targetSequence,
    List<MimeMessage>? messages,
  ) {
    if (messages != null && targetSequence != null) {
      final originalIds = originalSequence.toList();
      final targetIds = targetSequence.toList();
      if (originalIds.length != targetIds.length) {
        print('Unable to apply new message IDs: Unexpected different length of '
            'original and target sequence: '
            'original=$originalSequence, target=$targetSequence');

        return false;
      }
      final isUid = originalSequence.isUidSequence;
      for (var i = 0; i < originalIds.length; i++) {
        final originalId = originalIds[i];
        final message = messages.firstWhereOrNull(
          (message) => isUid
              ? message.uid == originalId
              : message.sequenceId == originalId,
        );
        if (message != null) {
          if (isUid) {
            message.uid = targetIds[i];
          } else {
            message.sequenceId = targetIds[i];
          }
        }
      }
    }

    return true;
  }
}

/// The internal action that was used for deletion.
/// This is useful for undoing and delete operation.
enum DeleteAction {
  /// The message(s) were marked as deleted with a flag
  flag,

  /// The message(s) were moved
  move,

  /// The message(s) were copied and then flagged
  copy,

  /// The message(s) were deleted via POP3 protocol
  pop,
}

/// Provides information about a delete action
class DeleteResult extends MessagesOperationResult {
  /// Creates a new result for an delete call
  DeleteResult(
    this.action,
    MessageSequence originalSequence,
    Mailbox originalMailbox,
    MessageSequence? targetSequence,
    Mailbox? targetMailbox,
    MailClient mailClient, {
    required bool canUndo,
    List<MimeMessage>? messages,
  }) : super(
          originalSequence,
          originalMailbox,
          targetSequence,
          targetMailbox,
          mailClient,
          canUndo: canUndo,
          messages: messages,
        );

  /// The internal action that was used to delete
  final DeleteAction action;

  /// Reverses the result
  /// so that the original sequence and mailbox becomes the target ones.
  DeleteResult reverse() {
    final targetSequence = this.targetSequence;
    if (targetSequence == null) {
      throw InvalidArgumentException(
        'Unable to reverse DeleteResult without target sequence',
      );
    }
    final targetMailbox = this.targetMailbox;
    if (targetMailbox == null) {
      throw InvalidArgumentException(
        'Unable to reverse DeleteResult without target mailbox',
      );
    }

    return DeleteResult(
      action,
      targetSequence,
      targetMailbox,
      originalSequence,
      originalMailbox,
      mailClient,
      canUndo: canUndo,
      messages: messages,
    );
  }

  /// Reverses the result
  /// and includes the new sequence from the given [result].
  DeleteResult reverseWith(UidResponseCode? result) {
    final resultTargetSequence = result?.targetSequence;
    final targetMailbox = this.targetMailbox;
    final targetSequence = this.targetSequence;
    if (resultTargetSequence != null &&
        targetMailbox != null &&
        targetSequence != null) {
      return DeleteResult(
        action,
        targetSequence,
        targetMailbox,
        resultTargetSequence,
        originalMailbox,
        mailClient,
        canUndo: canUndo,
        messages: messages,
      );
    }

    return reverse();
  }
}

/// Possible move implementations
enum MoveAction {
  /// Messages were moved using the `MOVE` extension
  move,

  /// Messages were copied to the target mailbox and then deleted
  /// on the originating mailbox
  copy
}

/// Result for move operations
class MoveResult extends MessagesOperationResult {
  /// Creates a new result for an move call
  MoveResult(
    this.action,
    MessageSequence originalSequence,
    Mailbox originalMailbox,
    MessageSequence? targetSequence,
    Mailbox? targetMailbox,
    MailClient mailClient, {
    required bool canUndo,
    List<MimeMessage>? messages,
  }) : super(
          originalSequence,
          originalMailbox,
          targetSequence,
          targetMailbox,
          mailClient,
          canUndo: canUndo,
          messages: messages,
        );

  /// The internal action that was used to delete
  final MoveAction action;

  /// Reverses the result
  /// so that the original sequence and mailbox becomes the target ones.
  ///
  /// Throws [MailException] when either the [targetSequence] or the
  /// [targetMailbox] are `null`.
  MoveResult reverse() {
    final targetSequence = this.targetSequence;
    final targetMailbox = this.targetMailbox;
    if (targetSequence == null || targetMailbox == null) {
      throw MailException(
        mailClient,
        'Unable to reverse move operation without target sequence',
      );
    }

    return MoveResult(
      action,
      targetSequence,
      targetMailbox,
      originalSequence,
      originalMailbox,
      mailClient,
      canUndo: canUndo,
      messages: messages,
    );
  }
}

/// Encapsulates a thread result
class ThreadResult {
  /// Creates a new result with the given [threadData], [threadSequence],
  /// [threadPreference], [fetchPreference] and the pre-fetched [threads].
  const ThreadResult(
    this.threadData,
    this.threadSequence,
    this.threadPreference,
    this.fetchPreference,
    this.since,
    this.threads,
  );

  /// The source data
  final SequenceNode threadData;

  /// The paged message sequence
  final PagedMessageSequence threadSequence;

  /// The thread preference
  final ThreadPreference threadPreference;

  /// The fetch preference
  final FetchPreference fetchPreference;

  /// Since when the thread data is retrieved
  final DateTime since;

  /// The threads that have been fetched so far
  final List<MimeThread> threads;

  /// Retrieves the total number of threads.
  ///
  /// This can be higher than `threads.length`.
  int get length => threadData.length;

  /// Checks if the [threadSequence] has a next page
  bool get hasMoreResults => threadSequence.hasNext;

  /// Shortcut to find out if this thread result is UID based
  bool get isUidBased => threadSequence.isUidSequence;

  /// Eases access to the [MimeThread] at the specified [threadIndex] or `null`
  /// when it is not yet loaded.
  ///
  /// Note that the [threadIndex] is expected to be based on full [threadData],
  /// meaning 0 is the newest  thread and length-1 is the oldest  thread.
  MimeThread? operator [](int threadIndex) {
    final index = length - threadIndex - 1;
    if (index < 0 || threadIndex < 0) {
      return null;
    }

    return threads[threadIndex];
  }

  /// Distributes the given [unthreadedMessages] to the [threads]
  /// managed by this result.
  void addAll(List<MimeMessage> unthreadedMessages) {
    // the new messages could
    // a) complement existing threads, but only when threadPreference is
    //    ThreadPreference.all, or
    // b) create complete new threads
    final isUid = threadData.isUid;
    if (threadPreference == ThreadPreference.latest) {
      for (final node in threadData.children.reversed) {
        final id = node.latestId;
        final message = isUid
            ? unthreadedMessages.firstWhereOrNull((msg) => msg.uid == id)
            : unthreadedMessages
                .firstWhereOrNull((msg) => msg.sequenceId == id);
        if (message != null) {
          final thread = MimeThread(node.toMessageSequence(), [message]);
          threads.insert(0, thread);
        }
      }
      threads.sort((t1, t2) => isUid
          ? (t1.latest.uid ?? 0).compareTo(t2.latest.uid ?? 0)
          : (t1.latest.sequenceId ?? 0).compareTo(t2.latest.sequenceId ?? 0));
    } else {
      // check if there are messages for already existing threads:
      for (final thread in threads) {
        if (thread.hasMoreMessages) {
          final ids = thread.missingMessageSequence.toList().reversed;
          for (final id in ids) {
            final message = isUid
                ? unthreadedMessages.firstWhereOrNull((msg) => msg.uid == id)
                : unthreadedMessages
                    .firstWhereOrNull((msg) => msg.sequenceId == id);
            if (message != null) {
              unthreadedMessages.remove(message);
              thread.messages.insert(0, message);
            }
          }
        }
      }
      // now check if there are more threads:
      if (unthreadedMessages.isNotEmpty) {
        for (final node in threadData.children.reversed) {
          final threadSequence = node.toMessageSequence();
          final threadedMessages = <MimeMessage>[];
          final ids = threadSequence.toList();
          for (final id in ids) {
            final message = isUid
                ? unthreadedMessages.firstWhereOrNull((msg) => msg.uid == id)
                : unthreadedMessages
                    .firstWhereOrNull((msg) => msg.sequenceId == id);
            if (message != null) {
              threadedMessages.add(message);
            }
          }
          if (threadedMessages.isNotEmpty) {
            final thread = MimeThread(threadSequence, threadedMessages);
            threads.add(thread);
          }
        }
        threads.sort((t1, t2) => isUid
            ? (t1.latest.uid ?? 0).compareTo(t2.latest.uid ?? 0)
            : (t1.latest.sequenceId ?? 0).compareTo(t2.latest.sequenceId ?? 0));
      }
    }
  }

  /// Checks if the page for the given thread [threadIndex] is already requested
  /// in a [ThreadPreference.latest] based result.
  ///
  /// Note that the [threadIndex] is expected to be based on full [threadData],
  /// meaning 0 is the newest thread and length-1 is the oldest thread.
  bool isPageRequestedFor(int threadIndex) {
    assert(threadPreference == ThreadPreference.latest,
        'This call is only valid for ThreadPreference.latest');
    final index = length - threadIndex - 1;

    return index >
        length - (threadSequence.currentPageIndex * threadSequence.pageSize);
  }
}

/// Contains information about threads
///
/// Retrieve the thread sequence for a given message UID
/// with `threadDataResult[uid]`.
/// Example:
/// ```dart
/// final sequence = threadDataResult[mimeMessage.uid];
/// if (sequence != null) {
///   // the mimeMessage belongs to a thread
/// }
/// ```
class ThreadDataResult {
  /// Creates a new result with the given [data] and [since].
  ThreadDataResult(this.data, this.since) {
    for (final node in data.children) {
      if (node.isNotEmpty) {
        final sequence = node.toMessageSequence();
        final ids = sequence.toList();
        if (ids.length > 1) {
          for (final id in ids) {
            _sequencesById[id] = sequence;
          }
        }
      }
    }
  }

  /// The source data
  final SequenceNode data;

  /// The day since when threads were requested
  final DateTime since;

  final _sequencesById = <int, MessageSequence>{};

  /// Checks if the given [id] belongs to a thread.
  bool hasThread(int id) => _sequencesById[id] != null;

  /// Retrieves the thread sequence for the given message [id].
  MessageSequence? operator [](int id) => _sequencesById[id];

  /// Sets the [MimeMessage.threadSequence] for the specified [mimeMessage]
  void setThreadSequence(MimeMessage mimeMessage) {
    final id = data.isUid ? mimeMessage.uid : mimeMessage.sequenceId;
    final sequence = _sequencesById[id];
    mimeMessage.threadSequence = sequence;
  }
}

/// Base class for actions that result in a partial fetching of messages
class PagedMessageResult {
  /// Creates a new paged result
  PagedMessageResult(this.pagedSequence, this.messages, this.fetchPreference)
      : _requestedPages = <int, Future<List<MimeMessage>>>{};

  /// Creates a new empty paged message result with the option
  /// [fetchPreference] ([FetchPreference.envelope]) and [pageSize](`30`).
  PagedMessageResult.empty({
    FetchPreference fetchPreference = FetchPreference.envelope,
    int pageSize = 30,
  }) : this(
          PagedMessageSequence.empty(pageSize: pageSize),
          [],
          fetchPreference,
        );

  /// The message sequence containing all IDs or UIDs, may be null
  /// for empty searches
  final PagedMessageSequence pagedSequence;

  /// The number of all matching messages
  int get length => pagedSequence.length;

  /// Checks if this result is empty
  bool get isEmpty => length == 0;

  /// Checks if this result is not empty
  bool get isNotEmpty => length > 0;

  /// The fetched messages, initially this contains only the first page
  final List<MimeMessage> messages;

  /// The original fetch preference
  final FetchPreference fetchPreference;

  /// Requested pages
  final Map<int, Future<List<MimeMessage>>> _requestedPages;

  /// Checks if the `messageSequence` has a next page
  bool get hasMoreResults => pagedSequence.hasNext;

  /// Shortcut to find out if this search result is UID based
  bool get isUidBased => pagedSequence.isUidSequence;

  /// Inserts the given [page] of messages to this result
  void insertAll(List<MimeMessage> page) => messages.insertAll(0, page);

  /// Adds the specified message to this search result.
  void addMessage(MimeMessage message) {
    final id = isUidBased ? message.uid : message.sequenceId;
    if (id == null) {
      throw InvalidArgumentException('Unable to add message without ID');
    }
    pagedSequence.add(id);
    messages.add(message);
  }

  /// Adds the specified message to this search result.
  void removeMessage(MimeMessage message) {
    final id = isUidBased ? message.uid : message.sequenceId;
    if (id == null) {
      throw InvalidArgumentException('Unable to remove message without ID');
    }
    pagedSequence.remove(id);
    messages.remove(message);
  }

  /// Removes the specified [removeSequence] from this result
  /// and returns all messages that have been loaded.
  ///
  /// Note that the [removeSequence] must be based on the same type of IDs
  /// (UID or sequence-ID) as this result.
  List<MimeMessage> removeMessageSequence(MessageSequence removeSequence) {
    assert(removeSequence.isUidSequence == pagedSequence.isUidSequence,
        'Not the same sequence ID types');
    final isUid = pagedSequence.isUidSequence;
    final ids = removeSequence.toList();
    final result = <MimeMessage>[];
    for (final id in ids) {
      pagedSequence.remove(id);
      final match = messages.firstWhereOrNull(
        (msg) => isUid ? msg.uid == id : msg.sequenceId == id,
      );
      if (match != null) {
        result.add(match);
        messages.remove(match);
      }
    }

    return result;
  }

  /// Retrieves the message for the given [messageIndex].
  ///
  /// Note that the [messageIndex] is expected to be based on
  /// full `messageSequence`, where index 0 is newest message and
  /// `size-1` is the oldest message.
  /// Compare [isAvailable]
  MimeMessage operator [](int messageIndex) {
    final index = messages.length - messageIndex - 1;
    if (index < 0) {
      throw RangeError(
        'for messageIndex $messageIndex in a result with the length $length '
        'and currently loaded message count of ${messages.length}',
      );
    }

    return messages[index];
  }

  /// Checks if the message for the given [messageIndex] is already loaded.
  ///
  /// Note that the [messageIndex] is expected to be based on
  /// full `messageSequence`, where index 0 is newest message and
  /// `size-1` is the oldest message.
  bool isAvailable(int messageIndex) {
    final index = messages.length - messageIndex - 1;

    return index >= 0 && messageIndex >= 0;
  }

  /// Retrieves the message ID at the specified [messageIndex].
  ///
  /// Note that the [messageIndex] is expected to be based on
  /// full `messageSequence`, where index 0 is newest message and
  /// `size-1` is the oldest message.
  int messageIdAt(int messageIndex) {
    final index = length - messageIndex - 1;

    return pagedSequence.sequence.elementAt(index);
  }

  /// Checks if the page for the given [messageIndex] is already requested.
  ///
  /// Note that the [messageIndex] is expected to be based on
  /// full `messageSequence`, where index 0 is newest message and
  /// `size-1` is the oldest message.
  bool isPageRequestedFor(int messageIndex) {
    final index = length - messageIndex - 1;

    return index >
        length - (pagedSequence.currentPageIndex * pagedSequence.pageSize);
  }

  /// Retrieves the message at the given index.
  ///
  /// Note that the [messageIndex] is expected to be based on
  /// full `messageSequence`, where index 0 is newest message and
  /// `size-1` is the oldest message.
  Future<MimeMessage> getMessage(
    int messageIndex,
    MailClient mailClient, {
    Mailbox? mailbox,
    FetchPreference fetchPreference = FetchPreference.envelope,
  }) async {
    Future<List<MimeMessage>> queue(int pageIndex) {
      final sequence = pagedSequence.getSequence(pageIndex);
      final future = mailClient.fetchMessageSequence(
        sequence,
        mailbox: mailbox,
        fetchPreference: fetchPreference,
      );
      _requestedPages[pageIndex] = future;

      return future;
    }

    if (isAvailable(messageIndex)) {
      return this[messageIndex];
    }
    final pageIndex = pagedSequence.pageIndexOf(messageIndex);
    if (pageIndex > 0) {
      // ensure that previous pages are loaded first:
      final previousRequest = _requestedPages[pageIndex - 1];
      if (previousRequest != null) {
        await previousRequest;
      }
    }
    final request = _requestedPages[pageIndex] ?? queue(pageIndex);
    final messages = await request;
    if (_requestedPages.containsKey(pageIndex)) {
      unawaited(_requestedPages.remove(pageIndex));
      insertAll(messages);
    }
    final relativeIndex =
        (pageIndex * pagedSequence.pageSize + messages.length) -
            (messageIndex + 1);

    return messages[relativeIndex];
  }
}

/// Contains the result of a search
class MailSearchResult extends PagedMessageResult {
  /// Creates a new search result
  MailSearchResult(
    this.search,
    PagedMessageSequence pagedSequence,
    List<MimeMessage> messages,
    FetchPreference fetchPreference,
  ) : super(pagedSequence, messages, fetchPreference);

  /// Creates a new empty search result
  MailSearchResult.empty(this.search)
      : super.empty(
          fetchPreference: search.fetchPreference,
          pageSize: search.pageSize,
        );

  /// The original search
  final MailSearch search;
}
