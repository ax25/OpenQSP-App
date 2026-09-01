import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/conversation_visibility_store.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';

void main() {
  test('cleared conversation stays empty after controller recreation', () async {
    final local = _MemoryLocalStore()
      ..items.addAll([
        _message('one', DateTime.utc(2026, 9, 1, 0, 0)),
        _message('two', DateTime.utc(2026, 9, 1, 0, 1)),
      ]);
    final visibility = MemoryConversationVisibilityStore();

    var controller = _controller(local, visibility);
    await controller.start();
    expect(controller.historyFor('N0CALL'), hasLength(2));

    await controller.clearConversation('N0CALL');
    expect(controller.historyFor('N0CALL'), isEmpty);
    expect(local.items, hasLength(2));
    expect(controller.conversations.single.remoteCallsign, 'N0CALL');
    expect(controller.conversations.single.latestMessage, isNull);
    controller.dispose();

    controller = _controller(local, visibility);
    await controller.start();
    expect(controller.historyFor('N0CALL'), isEmpty);
    expect(controller.conversations.single.remoteCallsign, 'N0CALL');
    expect(controller.conversations.single.latestMessage, isNull);

    final newer = _message('three', DateTime.utc(2026, 9, 1, 0, 2));
    await local.upsert('EA3GNU', newer);
    controller.dispose();

    controller = _controller(local, visibility);
    await controller.start();
    expect(controller.historyFor('N0CALL').map((item) => item.id), ['three']);
    expect(controller.conversations.single.latestMessage?.id, 'three');
    controller.dispose();
  });
}

MessagesController _controller(
  _MemoryLocalStore local,
  ConversationVisibilityStore visibility,
) => MessagesController(
  callsign: 'EA3GNU',
  token: 'token',
  repository: _Repository(),
  realtime: _Realtime(),
  localStore: local,
  visibilityStore: visibility,
);

InternetMessage _message(String id, DateTime createdAt) => InternetMessage(
  id: id,
  from: 'N0CALL',
  to: 'EA3GNU',
  body: id,
  createdAt: createdAt,
);

class _MemoryLocalStore implements LocalMessagesStore {
  final items = <InternetMessage>[];
  final cursors = <String, String>{};

  @override
  Future<List<InternetMessage>> messages(String callsign) async => List.of(items);

  @override
  Future<void> upsert(String callsign, InternetMessage message) =>
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
  Future<String?> cursor(String callsign, String transport) async => cursors[transport];

  @override
  Future<void> setCursor(String callsign, String transport, String value) async {
    cursors[transport] = value;
  }
}

class _Repository implements MessagesRepository {
  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => const [];

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {}

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      const SyncBatch(messages: [], cursor: 'cursor');
}

class _Realtime implements MessagesRealtimeClient {
  final _events = StreamController<MessagingEvent>.broadcast();
  final _states = StreamController<RealtimeConnectionState>.broadcast();

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Stream<RealtimeConnectionState> get connectionStates => _states.stream;

  @override
  Future<void> connect({required String callsign, required String token}) async {}

  @override
  Future<void> close() async {
    await _events.close();
    await _states.close();
  }
}
