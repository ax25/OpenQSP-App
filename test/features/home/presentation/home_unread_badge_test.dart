import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/auth/application/auth_session.dart';
import 'package:openqsp_app/features/auth/data/auth_client.dart';
import 'package:openqsp_app/features/auth/data/auth_token_store.dart';
import 'package:openqsp_app/features/home/presentation/home_screen.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:openqsp_app/core/network/server_status_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home badge counts unread conversations, not messages', (
    tester,
  ) async {
    final realtime = _Realtime();
    final tokens = _TokenStore()..token = 'stored-token';
    final authSession = AuthSession(client: _AuthClient(), tokenStore: tokens);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          callsign: 'EA3GNU',
          onEditCallsign: () {},
          serverStatusClient: _ServerStatusClient(),
          authSession: authSession,
          messagesRepository: _MessagesRepository(),
          messagesRealtimeFactory: () => realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unreadBadge-Messages')), findsNothing);

    realtime.addMessage(
      InternetMessage(
        id: '1',
        from: 'EA3ABC',
        to: 'EA3GNU',
        body: 'first',
        createdAt: DateTime.utc(2026, 9, 2, 1),
      ),
    );
    realtime.addMessage(
      InternetMessage(
        id: '2',
        from: 'EA3ABC',
        to: 'EA3GNU',
        body: 'second same conversation',
        createdAt: DateTime.utc(2026, 9, 2, 1, 1),
      ),
    );
    realtime.addMessage(
      InternetMessage(
        id: '3',
        from: 'EA3XYZ',
        to: 'EA3GNU',
        body: 'another conversation',
        createdAt: DateTime.utc(2026, 9, 2, 1, 2),
      ),
    );
    await tester.pumpAndSettle();

    final badgeFinder = find.byKey(const Key('unreadBadge-Messages'));
    expect(badgeFinder, findsOneWidget);
    expect(find.descendant(of: badgeFinder, matching: find.text('2')), findsOneWidget);

    await authSession.close();
    await realtime.dispose();
  });
}

class _ServerStatusClient implements ServerStatusClient {
  @override
  Future<bool> isAvailable() async => true;

  @override
  void close() {}
}

class _AuthClient implements AuthClient {
  @override
  Future<LoginResult> login({
    required String callsign,
    required String password,
  }) async => const LoginSuccess('stored-token');

  @override
  Future<AuthValidationResult> validateToken({
    required String token,
    required String callsign,
  }) async => AuthValidationResult.valid;

  @override
  void close() {}
}

class _TokenStore implements AuthTokenStore {
  String? token;

  @override
  Future<String?> read(String callsign) async => token;

  @override
  Future<void> write(String callsign, String token) async {
    this.token = token;
  }

  @override
  Future<void> delete(String callsign) async {
    token = null;
  }
}

class _MessagesRepository implements MessagesRepository {
  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => [];

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
  }) => throw UnimplementedError();

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      const SyncBatch(messages: [], cursor: 'initial');
}

class _Realtime implements MessagesRealtimeClient {
  final _events = StreamController<MessagingEvent>.broadcast();
  final _connections = StreamController<RealtimeConnectionState>.broadcast();

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Stream<RealtimeConnectionState> get connectionStates => _connections.stream;

  @override
  Future<void> connect({required String callsign, required String token}) async {
    _connections.add(RealtimeConnectionState.connected);
  }

  void addMessage(InternetMessage message) {
    _events.add(MessageReceived(message));
  }

  @override
  Future<void> close() async {}

  Future<void> dispose() async {
    await _events.close();
    await _connections.close();
  }
}
