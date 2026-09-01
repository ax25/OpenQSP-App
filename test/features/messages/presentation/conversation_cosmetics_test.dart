import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:openqsp_app/features/messages/presentation/conversation_screen.dart';

void main() {
  testWidgets('clear messages only hides the current view', (tester) async {
    final now = DateTime.now();
    final repository = _Repository([
      _message('one', now.subtract(const Duration(minutes: 2)), from: 'N0CALL'),
      _message('two', now.subtract(const Duration(minutes: 1)), from: 'EA3GNU'),
    ]);
    final realtime = _Realtime();
    final controller = await _controller(repository, realtime);
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

    expect(find.byKey(const Key('message-one')), findsOneWidget);
    expect(find.byKey(const Key('message-two')), findsOneWidget);

    await tester.tap(find.byKey(const Key('conversationMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vaciar conversación'));
    await tester.pump();

    expect(find.byKey(const Key('message-one')), findsNothing);
    expect(find.byKey(const Key('message-two')), findsNothing);
    expect(controller.historyFor('N0CALL'), isEmpty);
    expect(repository.items, hasLength(2));

    realtime.emit(_message('three', now, from: 'N0CALL'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-one')), findsNothing);
    expect(find.byKey(const Key('message-two')), findsNothing);
    expect(find.byKey(const Key('message-three')), findsOneWidget);
    expect(controller.historyFor('N0CALL'), hasLength(1));
  });

  testWidgets('conversation opens at the newest message', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final repository = _Repository([
      for (var index = 0; index < 20; index++)
        _message(
          'initial-$index',
          now.subtract(Duration(minutes: 20 - index)),
          from: index.isEven ? 'N0CALL' : 'EA3GNU',
        ),
    ]);
    final controller = await _controller(repository, _Realtime());
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

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('messageList')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
    expect(find.byKey(const Key('message-initial-19')), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(const Key('message-initial-19'))).dy,
      lessThanOrEqualTo(600),
    );
  });

  testWidgets('sending keeps keyboard focus and scrolls to the sent message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final repository = _Repository([
      for (var index = 0; index < 18; index++)
        _message(
          'initial-$index',
          now.subtract(Duration(minutes: 18 - index)),
          from: index.isEven ? 'N0CALL' : 'EA3GNU',
        ),
    ]);
    final controller = await _controller(repository, _Realtime());
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

    final composerFinder = find.byKey(const Key('messageComposer'));
    await tester.tap(composerFinder);
    await tester.enterText(composerFinder, 'new outgoing message');
    await tester.tap(find.byKey(const Key('sendMessage')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    final composer = tester.widget<TextField>(composerFinder);
    expect(composer.focusNode!.hasFocus, isTrue);
    expect(repository.sentTexts, ['new outgoing message']);

    final sent = find.byKey(const Key('message-sent-1'));
    expect(sent, findsOneWidget);
    expect(tester.getBottomRight(sent).dy, lessThanOrEqualTo(600));
  });
}

Future<MessagesController> _controller(
  _Repository repository,
  _Realtime realtime,
) async {
  final controller = MessagesController(
    callsign: 'EA3GNU',
    token: 'token',
    repository: repository,
    realtime: realtime,
    localStore: _MemoryLocalStore(),
  );
  await controller.start();
  return controller;
}

InternetMessage _message(
  String id,
  DateTime createdAt, {
  required String from,
}) => InternetMessage(
  id: id,
  from: from,
  to: from == 'EA3GNU' ? 'N0CALL' : 'EA3GNU',
  body: 'message $id',
  createdAt: createdAt,
  deliveryStatus: MessageDeliveryStatus.stored,
);

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
    _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
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

class _Repository implements MessagesRepository {
  _Repository(this.items);

  final List<InternetMessage> items;
  final List<String> sentTexts = [];

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
  }) async {
    sentTexts.add(text);
    return _message('sent-${sentTexts.length}', DateTime.now(), from: callsign);
  }

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

  void emit(InternetMessage message) => _events.add(MessageReceived(message));

  @override
  Future<void> close() async {
    await _events.close();
    await _states.close();
  }
}
