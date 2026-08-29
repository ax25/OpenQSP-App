import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';

void main() {
  late FakeRepository repository;
  late FakeRealtime realtime;
  late MemoryLocalStore localStore;
  late MessagesController controller;

  setUp(() {
    repository = FakeRepository();
    realtime = FakeRealtime();
    localStore = MemoryLocalStore();
    controller = MessagesController(
      callsign: 'EA3GNU',
      token: 'scoped-token',
      repository: repository,
      realtime: realtime,
      localStore: localStore,
    );
  });

  tearDown(() => controller.dispose());

  test('loads local history first and merges incremental sync', () async {
    localStore.items.addAll([
      message('1', from: 'EA3GNU', to: 'N0CALL', day: 1),
      message('2', from: 'N0CALL', to: 'EA3GNU', day: 2),
    ]);
    repository.syncItems.add(
      message('3', from: 'W1AW', to: 'EA3GNU', day: 3),
    );

    await controller.start();

    expect(
      controller.conversations.map((item) => item.remoteCallsign),
      ['W1AW', 'N0CALL'],
    );
    expect(realtime.connectedToken, 'scoped-token');
    expect(localStore.items.map((item) => item.id), containsAll(['1', '2', '3']));
    expect(localStore.cursors['internet'], 'cursor-1');
  });

  test('history is chronological and realtime echo is deduplicated', () async {
    final newer = message('2', from: 'EA3GNU', to: 'N0CALL', day: 2);
    final older = message('1', from: 'N0CALL', to: 'EA3GNU', day: 1);
    localStore.items.addAll([newer, older]);
    await controller.start();
    await controller.openConversation('n0call');
    realtime.emit(MessageReceived(newer));
    await Future<void>.delayed(Duration.zero);
    expect(controller.historyFor('N0CALL').map((item) => item.id), ['1', '2']);
    expect(repository.markedReadPeers, ['N0CALL']);
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
    expect(localStore.items.single.id, '1');
  });

  test('send persists response and websocket echo does not duplicate', () async {
    await controller.start();
    await controller.send('N0CALL', ' hello ');
    realtime.emit(MessageReceived(repository.sent!));
    await Future<void>.delayed(Duration.zero);
    expect(repository.lastSentText, 'hello');
    expect(controller.historyFor('N0CALL'), hasLength(1));
    expect(localStore.items, hasLength(1));
  });

  test('delivery and read events are persisted', () async {
    localStore.items.addAll([
      message('1', from: 'EA3GNU', to: 'N0CALL', day: 1),
      message('2', from: 'EA3GNU', to: 'N0CALL', day: 2),
    ]);
    await controller.start();

    realtime.emit(
      MessageDelivered(
        messageId: '1',
        deliveredAt: DateTime.utc(2026, 1, 3),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.historyFor('N0CALL').first.deliveryStatus,
      MessageDeliveryStatus.delivered,
    );

    realtime.emit(const MessageRead(peer: 'N0CALL', lastReadMessageId: '2'));
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.historyFor('N0CALL').map((item) => item.deliveryStatus),
      [MessageDeliveryStatus.read, MessageDeliveryStatus.read],
    );
    expect(
      localStore.items.map((item) => item.deliveryStatus),
      [MessageDeliveryStatus.read, MessageDeliveryStatus.read],
    );
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

  test('reconnect resumes from persisted transport cursor', () async {
    localStore.cursors['internet'] = 'cursor-old';
    await controller.start();
    expect(repository.lastSyncCursor, 'cursor-old');

    repository.syncItems.add(
      message('missed', from: 'N0CALL', to: 'EA3GNU', day: 2),
    );
    realtime.state(RealtimeConnectionState.reconnecting);
    realtime.state(RealtimeConnectionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.lastSyncCursor, 'cursor-1');
    expect(controller.historyFor('N0CALL').single.id, 'missed');
    expect(localStore.cursors['internet'], 'cursor-2');
  });

  test('duplicate connected events do not trigger repeated sync', () async {
    await controller.start();
    expect(repository.syncCalls, 1);

    realtime.state(RealtimeConnectionState.connected);
    realtime.state(RealtimeConnectionState.connected);
    realtime.state(RealtimeConnectionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.syncCalls, 1);

    realtime.state(RealtimeConnectionState.reconnecting);
    realtime.state(RealtimeConnectionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.syncCalls, 2);
  });
}

InternetMessage message(
  String id, {
  required String from,
  required String to,
  required int day,
  MessageDeliveryStatus deliveryStatus = MessageDeliveryStatus.stored,
}) => InternetMessage(
  id: id,
  from: from,
  to: to,
  body: 'message $id',
  createdAt: DateTime.utc(2026, 1, day),
  deliveryStatus: deliveryStatus,
);

class MemoryLocalStore implements LocalMessagesStore {
  final items = <InternetMessage>[];
  final cursors = <String, String>{};

  @override
  Future<List<InternetMessage>> messages(String callsign) async => List.of(items);

  @override
  Future<void> upsert(String callsign, InternetMessage message) async =>
      upsertAll(callsign, [message]);

  @override
  Future<void> upsertAll(
    String callsign,
    Iterable<InternetMessage> messages,
  ) async {
    for (final incoming in messages) {
      final index = items.indexWhere((item) => item.id == incoming.id);
      if (index < 0) {
        items.add(incoming);
      } else {
        items[index] = incoming;
      }
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<String?> cursor(String callsign, String transport) async =>
      cursors[transport];

  @override
  Future<void> setCursor(
    String callsign,
    String transport,
    String value,
  ) async => cursors[transport] = value;
}

class FakeRepository
    implements MessagesRepository, MessagesSyncCursorNamespace {
  final syncItems = <InternetMessage>[];
  final markedReadPeers = <String>[];
  String? lastSentText;
  String? lastSyncCursor;
  InternetMessage? sent;
  int syncCalls = 0;

  @override
  String get syncCursorKey => 'internet';

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => throw StateError('remote history must not be loaded');

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
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {
    markedReadPeers.add(remoteCallsign);
  }

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async {
    lastSyncCursor = cursor;
    syncCalls++;
    return SyncBatch(
      messages: List.of(syncItems),
      cursor: 'cursor-$syncCalls',
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
