import '../domain/message_models.dart';

abstract interface class MessagesRepository {
  String get syncCursorKey;

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

abstract interface class MessagesRealtimeClient {
  Stream<MessagingEvent> get events;
  Stream<RealtimeConnectionState> get connectionStates;

  Future<void> connect({required String callsign, required String token});
  Future<void> close();
}
