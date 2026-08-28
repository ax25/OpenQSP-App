import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';

void main() {
  late FakeRepository repository;
  late FakeRealtime realtime;
  late MessagesController controller;

  setUp(() {
    repository = FakeRepository();
    realtime = FakeRealtime();
    controller = MessagesController(
      callsign: 'EA3GNU',
      token: 'scoped-token',
      repository: repository,
      realtime: realtime,
    );
  });

  tearDown(() => controller.dispose());

  test('loads conversations and makes one authenticated realtime connection', () async {
    repository.summaries.add(const ConversationSummary(remoteCallsign: 'N0CALL', latestMessage: 'hello'));
    await controller.start();
    expect(controller.conversations.single.remoteCallsign, 'N0CALL');
    expect(realtime.connectedCallsign, 'EA3GNU');
    expect(realtime.connectedToken, 'scoped-token');
  });

  test('loads chronological history and deduplicates HTTP and realtime message', () async {
    final newer = message('2', DateTime.utc(2026, 1, 2));
    final older = message('1', DateTime.utc(2026, 1, 1));
    repository.messages.addAll([newer, older]);
    await controller.start();
    await controller.openConversation('n0call');
    realtime.emit(MessageReceived(newer));
    await Future<void>.delayed(Duration.zero);
    expect(controller.historyFor('N0CALL').map((item) => item.id), ['1', '2']);
  });

  test('incoming message creates and updates unread conversation', () async {
    await controller.start();
    realtime.emit(MessageReceived(message('1', DateTime.utc(2026), direction: MessageDirection.received)));
    await Future<void>.delayed(Duration.zero);
    expect(controller.conversations.single.latestMessage, 'message 1');
    expect(controller.conversations.single.unreadCount, 1);
  });

  test('send, message deletion and conversation deletion update state', () async {
    await controller.start();
    await controller.send('N0CALL', ' hello ');
    expect(repository.lastSentText, 'hello');
    expect(controller.historyFor('N0CALL'), hasLength(1));
    await controller.deleteMessage('N0CALL', 'sent');
    expect(controller.historyFor('N0CALL'), isEmpty);
    await controller.deleteConversation('N0CALL');
    expect(controller.conversations, isEmpty);
  });

  test('HTTP error is recoverable through another load', () async {
    repository.failure = StateError('offline');
    await controller.loadConversations();
    expect(controller.error, contains('offline'));
    repository.failure = null;
    await controller.loadConversations();
    expect(controller.error, isNull);
  });
}

InternetMessage message(String id, DateTime time, {MessageDirection direction = MessageDirection.sent}) => InternetMessage(
  id: id,
  remoteCallsign: 'N0CALL',
  text: 'message $id',
  direction: direction,
  sentAt: time,
  canDelete: true,
);

class FakeRepository implements MessagesRepository {
  final summaries = <ConversationSummary>[];
  final messages = <InternetMessage>[];
  Object? failure;
  String? lastSentText;

  void check() { if (failure != null) throw failure!; }
  @override
  Future<List<ConversationSummary>> conversations({required String callsign, required String token}) async { check(); return List.of(summaries); }
  @override
  Future<List<InternetMessage>> history({required String callsign, required String remoteCallsign, required String token}) async => List.of(messages);
  @override
  Future<InternetMessage> send({required String callsign, required String remoteCallsign, required String text, required String token}) async { lastSentText = text; return InternetMessage(id: 'sent', remoteCallsign: remoteCallsign, text: text, direction: MessageDirection.sent); }
  @override
  Future<void> deleteMessage({required String callsign, required String remoteCallsign, required String messageId, required String token}) async {}
  @override
  Future<void> deleteConversation({required String callsign, required String remoteCallsign, required String token}) async {}
}

class FakeRealtime implements MessagesRealtimeClient {
  final eventController = StreamController<MessagingEvent>.broadcast();
  final stateController = StreamController<RealtimeConnectionState>.broadcast();
  String? connectedCallsign;
  String? connectedToken;
  @override
  Stream<MessagingEvent> get events => eventController.stream;
  @override
  Stream<RealtimeConnectionState> get connectionStates => stateController.stream;
  @override
  Future<void> connect({required String callsign, required String token}) async { connectedCallsign = callsign; connectedToken = token; }
  void emit(MessagingEvent event) => eventController.add(event);
  @override
  Future<void> close() async { await eventController.close(); await stateController.close(); }
}
