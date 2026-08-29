import '../domain/message_models.dart';

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

/// Optional capability for repositories whose incremental cursor is not the
/// Internet `/sync` cursor namespace.
abstract interface class MessagesSyncCursorNamespace {
  String get syncCursorKey;
}

String messagesSyncCursorKey(MessagesRepository repository) =>
    repository is MessagesSyncCursorNamespace
    ? repository.syncCursorKey
    : 'internet';

abstract interface class MessagesRealtimeClient {
  Stream<MessagingEvent> get events;
  Stream<RealtimeConnectionState> get connectionStates;

  Future<void> connect({required String callsign, required String token});
  Future<void> close();
}
