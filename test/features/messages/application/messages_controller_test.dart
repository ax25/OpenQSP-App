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

  test('groups peers and sorts conversations by latest message', () async {
    repository.items.addAll([
      message('1', from: 'EA3GNU', to: 'N0CALL', day: 1),
      message('2', from: 'W1AW', to: 'EA3GNU', day: 3),
      message('3', from: 'N0CALL', to: 'EA3GNU', day: 2),
    ]);
    await controller.start();
    expect(
      controller.conversations.map((item) => item.remoteCallsign),
      ['W1AW', 'N0CALL'],
    );
    expect(realtime.connectedToken, 'scoped-token');
  });

  test('history is chronological and HTTP plus websocket is deduplicated', () async {
    final newer = message('2', from: 'EA3GNU', to: 'N0CALL', day: 2);
    final older = message('1', from: 'N0CALL', to: 'EA3GNU', day: 1);
    repository.items.addAll([newer, older]);
    await controller.start();
    await controller.openConversation('n0call');
    realtime.emit(MessageReceived(newer));
    await Future<void>.delayed(Duration.zero);
    expect(controller.historyFor('N0CALL').map((item) => item.id), ['1', '2']);
  });

  test('incoming peer creates conversation and local unread is cleared on open', () async {
    await controller.start();
    realtime.emit(
      MessageReceived(message('1', from: 'N0CALL', to: 'EA3GNU', day: 1)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.conversations.single.unreadCount, 1);
    await controller.openConversation('N0CALL');
    expect(controller.conversations.single.unreadCount, 0);
  });

  test('send uses response identity and websocket echo does not duplicate', () async {
    await controller.start();
    await controller.send('N0CALL', ' hello ');
    realtime.emit(MessageReceived(repository.sent!));
    await Future<void>.delayed(Duration.zero);
    expect(repository.lastSentText, 'hello');
    expect(controller.historyFor('N0CALL'), hasLength(1));
  });

  test('send rejects blank and oversized messages', () async {
    await controller.start();
    await controller.send('N0CALL', '   ');
    expect(repository.lastSentText, isNull);

    await expectLater(
      controller.send(
        'N0CALL',
        List.filled(maximumMessageLength + 1, 'x').join(),
      ),
      throwsArgumentError,
    );
    expect(repository.lastSentText, isNull);

    await controller.send(
      'N0CALL',
      List.filled(maximumMessageLength, 'x').join(),
    );
    expect(repository.lastSentText, hasLength(maximumMessageLength));
  });

  test('connected after reconnect performs incremental sync with cursor', () async {
    await controller.start();
    repository.syncItems.add(
      message('missed', from: 'N0CALL', to: 'EA3GNU', day: 2),
    );
    realtime.state(RealtimeConnectionState.reconnecting);
    realtime.state(RealtimeConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(repository.lastSyncCursor, 'cursor-1');
    expect(controller.historyFor('N0CALL').single.id, 'missed');
  });
}

InternetMessage message(
  String id, {
  required String from,
  required String to,
  required int day,
}) => InternetMessage(
  id: id,
  from: from,
  to: to,
  body: 'message $id',
  createdAt: DateTime.utc(2026, 1, day),
);

class FakeRepository implements MessagesRepository {
  final items = <InternetMessage>[];
  final syncItems = <InternetMessage>[];
  String? lastSentText;
  String? lastSyncCursor;
  InternetMessage? sent;

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => withCallsign == null
      ? List.of(items)
      : items
            .where(
              (item) =>
                  item.peerFor(callsign).toUpperCase() ==
                  withCallsign.toUpperCase(),
            )
            .toList();

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) async {
    lastSentText = text;
    return sent = message(
      'sent-id',
      from: callsign,
      to: remoteCallsign,
      day: 3,
    );
  }

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async {
    lastSyncCursor = cursor;
    return SyncBatch(
      messages: List.of(syncItems),
      cursor: cursor == null ? 'cursor-1' : 'cursor-2',
    );
  }
}

class FakeRealtime implements MessagesRealtimeClient {
  final eventController = StreamController<MessagingEvent>.broadcast();
  final stateController = StreamController<RealtimeConnectionState>.broadcast();
  String? connectedToken;
  @override
  Stream<MessagingEvent> get events => eventController.stream;
  @override
  Stream<RealtimeConnectionState> get connectionStates => stateController.stream;
  @override
  Future<void> connect({required String callsign, required String token}) async {
    connectedToken = token;
    stateController.add(RealtimeConnectionState.connected);
  }
  void emit(MessagingEvent event) => eventController.add(event);
  void state(RealtimeConnectionState state) => stateController.add(state);
  @override
  Future<void> close() async {
    await eventController.close();
    await stateController.close();
  }
}
