import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:openqsp_app/features/messages/presentation/conversation_screen.dart';

void main() {
  testWidgets(
    'tapping a missing-message placeholder downloads, fades in and highlights the recovered message',
    (tester) async {
      final now = DateTime.now();
      final repository = _MissingRepository([
        _message('incoming-10', now, sequence: 10),
        _message(
          'incoming-12',
          now.add(const Duration(minutes: 2)),
          sequence: 12,
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

      expect(find.text('Message not downloaded'), findsOneWidget);
      expect(find.byKey(const Key('missing-message-download-11')), findsOneWidget);

      await tester.tap(find.byKey(const Key('missing-message-11')));
      await tester.pump();

      expect(repository.requestedPeer, 'N0CALL');
      expect(repository.requestedSequence, 11);
      expect(find.byKey(const Key('missing-message-spinner-11')), findsOneWidget);
      expect(find.text('Downloading message'), findsOneWidget);

      repository.completeLookup(
        _message(
          'recovered-11',
          now.add(const Duration(minutes: 1)),
          sequence: 11,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(find.byKey(const Key('missing-message-11')), findsNothing);
      expect(find.byKey(const Key('message-recovered-11')), findsOneWidget);
      expect(find.text('message recovered-11'), findsOneWidget);

      final highlighted = tester.widget<AnimatedContainer>(
        find.byKey(const Key('message-highlight-recovered-11')),
      );
      final highlightedDecoration = highlighted.decoration! as BoxDecoration;
      expect(highlightedDecoration.color, isNot(Colors.transparent));

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 250));

      final normal = tester.widget<AnimatedContainer>(
        find.byKey(const Key('message-highlight-recovered-11')),
      );
      final normalDecoration = normal.decoration! as BoxDecoration;
      expect(normalDecoration.color, Colors.transparent);
    },
  );
}

InternetMessage _message(
  String id,
  DateTime createdAt, {
  required int sequence,
}) => InternetMessage(
  id: id,
  from: 'N0CALL',
  to: 'EA3GNU',
  body: 'message $id',
  createdAt: createdAt,
  conversationSequence: sequence,
);

class _MissingRepository implements MessagesRepository, MissingMessageRepository {
  _MissingRepository(this.items);

  final List<InternetMessage> items;
  final Completer<InternetMessage> _lookup = Completer<InternetMessage>();
  String? requestedPeer;
  int? requestedSequence;

  void completeLookup(InternetMessage message) => _lookup.complete(message);

  @override
  Future<InternetMessage> getMessage({
    required String peer,
    required int conversationSequence,
    required String token,
  }) {
    requestedPeer = peer;
    requestedSequence = conversationSequence;
    return _lookup.future;
  }

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
  }) => throw UnimplementedError();

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {}

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      SyncBatch(messages: const [], cursor: cursor ?? '0');
}

class _MemoryLocalStore implements LocalMessagesStore {
  final List<InternetMessage> _items = <InternetMessage>[];
  final Map<String, String> _cursors = <String, String>{};

  @override
  Future<List<InternetMessage>> messages(String callsign) async => List.of(_items);

  @override
  Future<void> upsert(String callsign, InternetMessage message) =>
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

class _Realtime implements MessagesRealtimeClient {
  final StreamController<MessagingEvent> _events =
      StreamController<MessagingEvent>.broadcast();
  final StreamController<RealtimeConnectionState> _states =
      StreamController<RealtimeConnectionState>.broadcast();

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
