import '../domain/models.dart';

abstract interface class MessagesApi {
  Future<List<Conversation>> conversations();
  Future<List<InternetMessage>> history(String remoteCallsign);
  Future<InternetMessage> send(String remoteCallsign, String text);
  Future<void> deleteMessage(String id);
  Future<void> deleteConversation(String remoteCallsign);
}

abstract interface class MessagesSocket {
  Stream<MessagingEvent> get events;
  Stream<MessagingConnectionState> get states;
  Future<void> connect(String token);
  Future<void> disconnect();
}

/// Used by production until the OpenQSP server contract is published.
/// It deliberately performs no request: inventing paths or payloads would make
/// the client incompatible with the canonical server.
class UndocumentedMessagesApi implements MessagesApi {
  Never _unsupported() => throw UnsupportedError(
    'The OpenQSP messaging HTTP contract is not documented in this repository.',
  );

  @override
  Future<List<Conversation>> conversations() async => _unsupported();
  @override
  Future<void> deleteConversation(String remoteCallsign) async => _unsupported();
  @override
  Future<void> deleteMessage(String id) async => _unsupported();
  @override
  Future<List<InternetMessage>> history(String remoteCallsign) async =>
      _unsupported();
  @override
  Future<InternetMessage> send(String remoteCallsign, String text) async =>
      _unsupported();
}
