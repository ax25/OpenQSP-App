import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:openqsp_app/features/messages/presentation/conversation_screen.dart';

void main() {
  testWidgets('groups messages by local day, shows times, alignment and status ticks', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10, 22);
    final yesterday = DateTime(now.year, now.month, now.day - 1, 10, 21);
    final older = DateTime(now.year, now.month, now.day - 3, 9, 20);
    final repository = _Repository([
      _message('old', older, from: 'N0CALL'),
      _message('yesterday', yesterday, from: 'EA3GNU', deliveryStatus: MessageDeliveryStatus.delivered),
      _message('today-1', today, from: 'N0CALL'),
      _message('today-2', today.add(const Duration(minutes: 2)), from: 'EA3GNU', deliveryStatus: MessageDeliveryStatus.read),
    ]);
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: ConversationScreen(controller: controller, remoteCallsign: 'N0CALL')));
    await tester.pumpAndSettle();
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('${older.day.toString().padLeft(2, '0')}/${older.month.toString().padLeft(2, '0')}/${older.year}'), findsOneWidget);
    expect(find.text('10:21'), findsOneWidget);
    expect(find.text('10:22'), findsOneWidget);
    expect(find.text('10:24'), findsOneWidget);
    expect(tester.widget<Align>(find.byKey(const Key('message-today-1'))).alignment, Alignment.centerLeft);
    expect(tester.widget<Align>(find.byKey(const Key('message-today-2'))).alignment, Alignment.centerRight);
    final deliveredIcon = tester.widget<Icon>(find.byKey(const Key('status-yesterday')));
    final readIcon = tester.widget<Icon>(find.byKey(const Key('status-today-2')));
    expect(deliveredIcon.icon, Icons.check);
    expect(deliveredIcon.color, Colors.green);
    expect(readIcon.icon, Icons.check);
    expect(readIcon.color, Colors.blue);
    expect(find.byKey(const Key('status-today-1')), findsNothing);
  });

  testWidgets('shows placeholders only for bounded incoming conversation gaps', (
    tester,
  ) async {
    final now = DateTime.now();
    final repository = _Repository([
      _message(
        'incoming-10',
        now,
        from: 'N0CALL',
        conversationSequence: 10,
      ),
      _message(
        'sent-between',
        now.add(const Duration(minutes: 1)),
        from: 'EA3GNU',
      ),
      _message(
        'incoming-12',
        now.add(const Duration(minutes: 2)),
        from: 'N0CALL',
        conversationSequence: 12,
      ),
    ]);
    final controller = await _controller(repository);
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

    expect(find.byKey(const Key('missing-message-11')), findsOneWidget);
    expect(find.text('Message not downloaded'), findsOneWidget);
    expect(find.text('#11'), findsOneWidget);
    expect(find.byKey(const Key('missing-message-1')), findsNothing);
    expect(find.byKey(const Key('missing-message-9')), findsNothing);
  });

  testWidgets('composer allows overflow but disables send and refuses blank messages', (tester) async {
    final repository = _Repository([]);
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: ConversationScreen(controller: controller, remoteCallsign: 'N0CALL')));
    await tester.pumpAndSettle();
    final composer = find.byKey(const Key('messageComposer'));
    final send = find.byKey(const Key('sendMessage'));

    await tester.enterText(composer, List.filled(maximumMessageLength + 1, 'x').join());
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller!.text, hasLength(maximumMessageLength + 1));
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.tap(send);
    await tester.pump();
    expect(repository.sentTexts, isEmpty);

    await tester.enterText(composer, List.filled(maximumMessageLength, 'x').join());
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(repository.sentTexts.single, hasLength(maximumMessageLength));

    await tester.enterText(composer, '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.tap(send);
    await tester.pump();
    expect(repository.sentTexts, hasLength(1));
  });

  testWidgets('sending keeps focus in the message composer', (tester) async {
    final repository = _Repository([]);
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: ConversationScreen(controller: controller, remoteCallsign: 'N0CALL')));
    await tester.pumpAndSettle();
    final composerFinder = find.byKey(const Key('messageComposer'));
    await tester.tap(composerFinder);
    await tester.enterText(composerFinder, 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendMessage')));
    await tester.pumpAndSettle();
    final composer = tester.widget<TextField>(composerFinder);
    expect(repository.sentTexts, ['hello']);
    expect(composer.controller!.text, isEmpty);
    expect(composer.focusNode!.hasFocus, isTrue);
  });

  testWidgets('incoming message automatically scrolls to the latest message', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final repository = _Repository([
      for (var index = 0; index < 18; index++) _message('initial-$index', now.subtract(Duration(minutes: 18 - index)), from: index.isEven ? 'N0CALL' : 'EA3GNU'),
    ]);
    final realtime = _Realtime();
    final controller = MessagesController(callsign: 'EA3GNU', token: 'token', repository: repository, realtime: realtime, localStore: _MemoryLocalStore());
    await controller.start();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: ConversationScreen(controller: controller, remoteCallsign: 'N0CALL')));
    await tester.pumpAndSettle();
    final listFinder = find.byKey(const Key('messageList'));
    final scrollableFinder = find.descendant(of: listFinder, matching: find.byType(Scrollable));
    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    scrollable.position.jumpTo(0);
    await tester.pump();
    expect(scrollable.position.pixels, 0);
    realtime.emit(_message('live-message', now.add(const Duration(minutes: 1)), from: 'N0CALL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final liveMessage = find.byKey(const Key('message-live-message'));
    expect(liveMessage, findsOneWidget);
    expect(tester.getBottomRight(liveMessage).dy, lessThanOrEqualTo(600));
    expect(scrollable.position.pixels, greaterThan(0));
  });
}

Future<MessagesController> _controller(_Repository repository) async {
  final controller = MessagesController(callsign: 'EA3GNU', token: 'token', repository: repository, realtime: _Realtime(), localStore: _MemoryLocalStore());
  await controller.start();
  return controller;
}

InternetMessage _message(
  String id,
  DateTime createdAt, {
  required String from,
  int? conversationSequence,
  MessageDeliveryStatus deliveryStatus = MessageDeliveryStatus.stored,
}) => InternetMessage(
  id: id,
  from: from,
  to: from == 'EA3GNU' ? 'N0CALL' : 'EA3GNU',
  body: 'message $id',
  createdAt: createdAt,
  conversationSequence: conversationSequence,
  deliveryStatus: deliveryStatus,
);

class _MemoryLocalStore implements LocalMessagesStore {
  final _items = <InternetMessage>[];
  final _cursors = <String, String>{};
  @override Future<List<InternetMessage>> messages(String callsign) async => List.of(_items);
  @override Future<void> upsert(String callsign, InternetMessage message) async => upsertAll(callsign, [message]);
  @override Future<void> upsertAll(String callsign, Iterable<InternetMessage> messages) async { for (final incoming in messages) { final index = _items.indexWhere((item) => item.id == incoming.id); if (index < 0) { _items.add(incoming); } else { _items[index] = incoming; } } _items.sort((a,b) => a.createdAt.compareTo(b.createdAt)); }
  @override Future<String?> cursor(String callsign, String transport) async => _cursors[transport];
  @override Future<void> setCursor(String callsign, String transport, String value) async { _cursors[transport] = value; }
}

class _Repository implements MessagesRepository {
  _Repository(this.items);
  final List<InternetMessage> items;
  final List<String> sentTexts = [];
  @override Future<List<InternetMessage>> messages({required String callsign, required String token, String? withCallsign}) async => List.of(items);
  @override Future<InternetMessage> send({required String callsign, required String remoteCallsign, required String text, required String token}) async { sentTexts.add(text); return _message('sent-${sentTexts.length}', DateTime.now(), from: callsign); }
  @override Future<void> markConversationRead({required String remoteCallsign, required String token}) async {}
  @override Future<SyncBatch> sync({required String token, String? cursor}) async => const SyncBatch(messages: [], cursor: 'cursor');
}

class _Realtime implements MessagesRealtimeClient {
  final _events = StreamController<MessagingEvent>.broadcast();
  final _states = StreamController<RealtimeConnectionState>.broadcast();
  @override Stream<MessagingEvent> get events => _events.stream;
  @override Stream<RealtimeConnectionState> get connectionStates => _states.stream;
  @override Future<void> connect({required String callsign, required String token}) async {}
  void emit(InternetMessage message) => _events.add(MessageReceived(message));
  @override Future<void> close() async { await _events.close(); await _states.close(); }
}
