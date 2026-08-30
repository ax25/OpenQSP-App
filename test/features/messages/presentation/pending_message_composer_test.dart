import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:openqsp_app/features/messages/presentation/conversation_screen.dart';
import 'package:openqsp_app/features/messages/presentation/pending_message_composer.dart';

void main() {
  testWidgets('pending send survives leaving and reopening the conversation', (
    tester,
  ) async {
    final repository = _DelayedRepository();
    final controller = MessagesController(
      callsign: 'EA3GNU',
      token: 'token',
      repository: repository,
      realtime: _Realtime(),
      localStore: _MemoryLocalStore(),
    );
    await controller.start();
    addTearDown(() {
      pendingMessageComposer.clear(controller, 'N0CALL');
      controller.dispose();
    });

    Widget conversation() => MaterialApp(
      home: ConversationScreen(
        controller: controller,
        remoteCallsign: 'N0CALL',
      ),
    );

    await tester.pumpWidget(conversation());
    await tester.pumpAndSettle();

    final composer = find.byKey(const Key('messageComposer'));
    await tester.enterText(composer, 'still sending');
    await tester.tap(find.byKey(const Key('sendMessage')));
    await tester.pump();

    expect(repository.sentTexts, ['still sending']);
    expect(
      tester.widget<TextField>(composer).controller!.text,
      'still sending',
    );
    expect(tester.widget<TextField>(composer).readOnly, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(conversation());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final reopenedComposer = find.byKey(const Key('messageComposer'));
    expect(
      tester.widget<TextField>(reopenedComposer).controller!.text,
      'still sending',
    );
    expect(tester.widget<TextField>(reopenedComposer).readOnly, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const Key('sendMessage')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    repository.completeSend();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.widget<TextField>(reopenedComposer).controller!.text, isEmpty);
    expect(tester.widget<TextField>(reopenedComposer).readOnly, isFalse);
  });
}

final class _DelayedRepository implements MessagesRepository {
  final List<String> sentTexts = [];
  Completer<InternetMessage>? _pending;

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => const [];

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {}

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) {
    sentTexts.add(text);
    final pending = Completer<InternetMessage>();
    _pending = pending;
    return pending.future;
  }

  void completeSend() {
    _pending!.complete(
      InternetMessage(
        id: 'sent-1',
        from: 'EA3GNU',
        to: 'N0CALL',
        body: sentTexts.single,
        createdAt: DateTime.now(),
        deliveryStatus: MessageDeliveryStatus.stored,
      ),
    );
  }

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      const SyncBatch(messages: [], cursor: '0');
}

final class _MemoryLocalStore implements LocalMessagesStore {
  final List<InternetMessage> _messages = [];
  final Map<String, String> _cursors = {};

  @override
  Future<String?> cursor(String callsign, String transport) async =>
      _cursors[transport];

  @override
  Future<List<InternetMessage>> messages(String callsign) async =>
      List.unmodifiable(_messages);

  @override
  Future<void> setCursor(
    String callsign,
    String transport,
    String value,
  ) async {
    _cursors[transport] = value;
  }

  @override
  Future<void> upsert(String callsign, InternetMessage message) async {
    await upsertAll(callsign, [message]);
  }

  @override
  Future<void> upsertAll(
    String callsign,
    Iterable<InternetMessage> messages,
  ) async {
    for (final message in messages) {
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index < 0) {
        _messages.add(message);
      } else {
        _messages[index] = message;
      }
    }
  }
}

final class _Realtime implements MessagesRealtimeClient {
  final _events = StreamController<MessagingEvent>.broadcast();
  final _states = StreamController<RealtimeConnectionState>.broadcast();

  @override
  Stream<RealtimeConnectionState> get connectionStates => _states.stream;

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Future<void> close() async {
    await _events.close();
    await _states.close();
  }

  @override
  Future<void> connect({required String callsign, required String token}) async {}
}
