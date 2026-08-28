import '../domain/message_models.dart';

abstract interface class MessagesRepository {
  Future<List<ConversationSummary>> conversations({
    required String callsign,
    required String token,
  });

  Future<List<InternetMessage>> history({
    required String callsign,
    required String remoteCallsign,
    required String token,
  });

  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  });

  Future<void> deleteMessage({
    required String callsign,
    required String remoteCallsign,
    required String messageId,
    required String token,
  });

  Future<void> deleteConversation({
    required String callsign,
    required String remoteCallsign,
    required String token,
  });
}

abstract interface class MessagesRealtimeClient {
  Stream<MessagingEvent> get events;
  Stream<RealtimeConnectionState> get connectionStates;

  Future<void> connect({required String callsign, required String token});
  Future<void> close();
}

/// Production placeholder used until the OpenQSP server publishes a messaging
/// contract. Deliberately does not guess URLs, payloads, or WebSocket events.
class UnsupportedMessagesRepository implements MessagesRepository {
  const UnsupportedMessagesRepository();

  UnsupportedError get _error => UnsupportedError(
    'The server messaging HTTP contract is not available in this repository.',
  );

  @override
  Future<List<ConversationSummary>> conversations({required String callsign, required String token}) =>
      Future.error(_error);
  @override
  Future<void> deleteConversation({required String callsign, required String remoteCallsign, required String token}) => Future.error(_error);
  @override
  Future<void> deleteMessage({required String callsign, required String remoteCallsign, required String messageId, required String token}) => Future.error(_error);
  @override
  Future<List<InternetMessage>> history({required String callsign, required String remoteCallsign, required String token}) => Future.error(_error);
  @override
  Future<InternetMessage> send({required String callsign, required String remoteCallsign, required String text, required String token}) => Future.error(_error);
}

class UnsupportedMessagesRealtimeClient implements MessagesRealtimeClient {
  const UnsupportedMessagesRealtimeClient();
  @override
  Stream<RealtimeConnectionState> get connectionStates =>
      const Stream.empty();
  @override
  Stream<MessagingEvent> get events => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<void> connect({required String callsign, required String token}) =>
      Future.error(UnsupportedError(
        'The server WebSocket contract is not available in this repository.',
      ));
}
