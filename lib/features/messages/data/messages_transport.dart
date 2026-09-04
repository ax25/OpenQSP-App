import '../domain/message_models.dart';
export '../domain/message_models.dart' show RealtimeConnectionState;

class MessagesAuthenticationException implements Exception {
  const MessagesAuthenticationException();

  @override
  String toString() => 'Message session authentication required';
}

abstract interface class MessagesRepository {
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  });

  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  });

  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  });

  Future<SyncBatch> sync({required String token, String? cursor});
}

class SessionAwareMessagesRepository
    implements
        MessagesRepository,
        MessagesSyncCursorNamespace,
        MissingMessageRepository {
  SessionAwareMessagesRepository({
    required this.delegate,
    required this.onAuthenticationRequired,
  });

  final MessagesRepository delegate;
  final Future<void> Function() onAuthenticationRequired;

  @override
  String get syncCursorKey => messagesSyncCursorKey(delegate);

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on MessagesAuthenticationException {
      await onAuthenticationRequired();
      rethrow;
    }
  }

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) => _guard(
    () => delegate.messages(
      callsign: callsign,
      token: token,
      withCallsign: withCallsign,
    ),
  );

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) => _guard(
    () => delegate.send(
      callsign: callsign,
      remoteCallsign: remoteCallsign,
      text: text,
      token: token,
    ),
  );

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) => _guard(
    () => delegate.markConversationRead(
      remoteCallsign: remoteCallsign,
      token: token,
    ),
  );

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) => _guard(
    () => delegate.sync(token: token, cursor: cursor),
  );

  @override
  Future<InternetMessage> getMessage({
    required String peer,
    required int conversationSequence,
    required String token,
  }) {
    final missing = delegate;
    if (missing is! MissingMessageRepository) {
      throw UnsupportedError('Selective message download is not supported');
    }
    final selective = missing as MissingMessageRepository;
    return _guard(
      () => selective.getMessage(
        peer: peer,
        conversationSequence: conversationSequence,
        token: token,
      ),
    );
  }
}

abstract interface class RetryableMessagesRepository {
  Future<void> retryMessage(InternetMessage message);
}

abstract interface class MissingMessageRepository {
  Future<InternetMessage> getMessage({
    required String peer,
    required int conversationSequence,
    required String token,
  });
}

extension MissingMessageRepositoryAccess on MessagesRepository {
  Future<InternetMessage> getMessage({
    required String peer,
    required int conversationSequence,
    required String token,
  }) {
    final repository = this;
    if (repository is! MissingMessageRepository) {
      throw UnsupportedError('Selective message download is not supported');
    }
    return (repository as MissingMessageRepository).getMessage(
      peer: peer,
      conversationSequence: conversationSequence,
      token: token,
    );
  }
}

/// Optional capability for repositories whose incremental cursor is not the
/// Internet `/sync` cursor namespace.
abstract interface class MessagesSyncCursorNamespace {
  String get syncCursorKey;
}

String messagesSyncCursorKey(MessagesRepository repository) {
  if (repository is MessagesSyncCursorNamespace) {
    return (repository as MessagesSyncCursorNamespace).syncCursorKey;
  }
  return 'internet';
}

abstract interface class MessagesRealtimeClient {
  Stream<MessagingEvent> get events;
  Stream<RealtimeConnectionState> get connectionStates;

  Future<void> connect({required String callsign, required String token});
  Future<void> close();
}
