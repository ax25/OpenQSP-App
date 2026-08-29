import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
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
      _message(
        'yesterday',
        yesterday,
        from: 'EA3GNU',
        deliveryStatus: MessageDeliveryStatus.delivered,
      ),
      _message('today-1', today, from: 'N0CALL'),
      _message(
        'today-2',
        today.add(const Duration(minutes: 2)),
        from: 'EA3GNU',
        deliveryStatus: MessageDeliveryStatus.read,
      ),
    ]);
    final controller = _controller(repository);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          controller: controller,
          remoteCallsign: 'N0CALL',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(
      find.text(
        '${older.day.toString().padLeft(2, '0')}/'
        '${older.month.toString().padLeft(2, '0')}/${older.year}',
      ),
      findsOneWidget,
    );
    expect(find.text('10:21'), findsOneWidget);
    expect(find.text('10:22'), findsOneWidget);
    expect(find.text('10:24'), findsOneWidget);
    expect(
      tester.widget<Align>(find.byKey(const Key('message-today-1'))).alignment,
      Alignment.centerLeft,
    );
    expect(
      tester.widget<Align>(find.byKey(const Key('message-today-2'))).alignment,
      Alignment.centerRight,
    );

    final deliveredIcon = tester.widget<Icon>(
      find.byKey(const Key('status-yesterday')),
    );
    final readIcon = tester.widget<Icon>(
      find.byKey(const Key('status-today-2')),
    );
    expect(deliveredIcon.icon, Icons.check);
    expect(deliveredIcon.color, Colors.green);
    expect(readIcon.icon, Icons.check);
    expect(readIcon.color, Colors.blue);
    expect(find.byKey(const Key('status-today-1')), findsNothing);
  });

  testWidgets('composer limits input and refuses blank messages', (tester) async {
    final repository = _Repository([]);
    final controller = _controller(repository);
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

    await tester.enterText(
      composer,
      List.filled(maximumMessageLength + 1, 'x').join(),
    );
    expect(
      tester.widget<TextField>(composer).controller!.text,
      hasLength(maximumMessageLength),
    );
    await tester.tap(find.byKey(const Key('sendMessage')));
    await tester.pumpAndSettle();
    expect(repository.sentTexts.single, hasLength(maximumMessageLength));

    await tester.enterText(composer, '   ');
    await tester.tap(find.byKey(const Key('sendMessage')));
    await tester.pump();
    expect(repository.sentTexts, hasLength(1));
  });

  testWidgets('sending keeps focus in the message composer', (tester) async {
    final repository = _Repository([]);
    final controller = _controller(repository);
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
    await tester.enterText(composerFinder, 'hello');
    await tester.tap(find.byKey(const Key('sendMessage')));
    await tester.pumpAndSettle();

    final composer = tester.widget<TextField>(composerFinder);
    expect(repository.sentTexts, ['hello']);
    expect(composer.controller!.text, isEmpty);
    expect(composer.focusNode!.hasFocus, isTrue);
  });

  testWidgets('incoming message automatically scrolls to the latest message', (
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
    final realtime = _Realtime();
    final controller = MessagesController(
      callsign: 'EA3GNU',
      token: 'token',
      repository: repository,
      realtime: realtime,
    );
    await controller.start();
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

    final listFinder = find.byKey(const Key('messageList'));
    final scrollableFinder = find.descendant(
      of: listFinder,
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    scrollable.position.jumpTo(0);
    await tester.pump();
    expect(scrollable.position.pixels, 0);

    realtime.emit(
      _message('live-message', now.add(const Duration(minutes: 1)), from: 'N0CALL'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final liveMessage = find.byKey(const Key('message-live-message'));
    expect(liveMessage, findsOneWidget);
    expect(tester.getBottomRight(liveMessage).dy, lessThanOrEqualTo(600));
    expect(scrollable.position.pixels, greaterThan(0));
  });
}

MessagesController _controller(_Repository repository) => MessagesController(
  callsign: 'EA3GNU',
  token: 'token',
  repository: repository,
  realtime: _Realtime(),
);

InternetMessage _message(
  String id,
  DateTime createdAt, {
  required String from,
  MessageDeliveryStatus deliveryStatus = MessageDeliveryStatus.stored,
}) => InternetMessage(
  id: id,
  from: from,
  to: from == 'EA3GNU' ? 'N0CALL' : 'EA3GNU',
  body: 'message $id',
  createdAt: createdAt,
  deliveryStatus: deliveryStatus,
);

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
