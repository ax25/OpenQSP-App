import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:openqsp_app/features/messages/presentation/conversation_screen.dart';

void main() {
  testWidgets('opening conversation starts at the bottom', (tester) async {
    await _configurePhoneViewport(tester);
    final controller = await _controllerWithHistory(30);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          controller: controller,
          remoteCallsign: 'N0CALL',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final position = _messageListPosition(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
  });

  testWidgets('keyboard keeps bottom visible when composer is opened at bottom', (
    tester,
  ) async {
    await _configurePhoneViewport(tester);
    final controller = await _controllerWithHistory(30);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          controller: controller,
          remoteCallsign: 'N0CALL',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final composer = find.byKey(const Key('messageComposer'));
    await tester.tap(composer);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.pumpAndSettle();

    final position = _messageListPosition(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
  });

  testWidgets('keyboard does not force bottom when user is reading older messages', (
    tester,
  ) async {
    await _configurePhoneViewport(tester);
    final controller = await _controllerWithHistory(30);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          controller: controller,
          remoteCallsign: 'N0CALL',
        ),
      ),
    );
    await tester.pumpAndSettle();

    var position = _messageListPosition(tester);
    position.jumpTo(0);
    await tester.pump();
    expect(position.pixels, 0);

    final composer = find.byKey(const Key('messageComposer'));
    await tester.tap(composer);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.pumpAndSettle();

    position = _messageListPosition(tester);
    expect(position.pixels, lessThan(position.maxScrollExtent));
  });
}

Future<void> _configurePhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding.zero;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

ScrollPosition _messageListPosition(WidgetTester tester) {
  final list = find.byKey(const Key('messageList'));
  final scrollable = find.descendant(of: list, matching: find.byType(Scrollable));
  return tester.state<ScrollableState>(scrollable).position;
}

Future<MessagesController> _controllerWithHistory(int count) async {
  final now = DateTime.now();
  final repository = _Repository([
    for (var index = 0; index < count; index++)
      InternetMessage(
        id: 'message-$index',
        from: index.isEven ? 'N0CALL' : 'EA3GNU',
        to: index.isEven ? 'EA3GNU' : 'N0CALL',
        body: 'A sufficiently long message number $index for scroll testing',
        createdAt: now.subtract(Duration(minutes: count - index)),
        deliveryStatus: MessageDeliveryStatus.stored,
      ),
  ]);
  final controller = MessagesController(
    callsign: 'EA3GNU',
    token: 'token',
    repository: repository,
    realtime: _Realtime(),
    localStore: _MemoryLocalStore(),
  );
  await controller.start();
  return controller;
}

class _Repository implements MessagesRepository {
  _Repository(this.items);
  final List<InternetMessage> items;

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => List.of(items);

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) async => throw UnimplementedError();

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {}

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      const SyncBatch(messages: [], cursor: 'cursor');
}

class _MemoryLocalStore implements LocalMessagesStore {
  final _items = <InternetMessage>[];
  final _cursors = <String, String>{};

  @override
  Future<List<InternetMessage>> messages(String callsign) async =>
      List.of(_items);

  @override
  Future<void> upsert(String callsign, InternetMessage message) async =>
      upsertAll(callsign, [message]);

  @override
  Future<void> upsertAll(
    String callsign,
    Iterable<InternetMessage> messages,
  ) async {
    for (final incoming in messages) {
      final index = _items.indexWhere((item) => item.id == incoming.id);
      if (index < 0) {
        _items.add(incoming);
      } else {
        _items[index] = incoming;
      }
    }
  }

  @override
  Future<String?> cursor(String callsign, String transport) async =>
      _cursors[transport];

  @override
  Future<void> setCursor(
    String callsign,
    String transport,
    String value,
  ) async {
    _cursors[transport] = value;
  }
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
