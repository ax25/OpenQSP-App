import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/app/app.dart';
import 'package:openqsp_app/core/network/server_status_client.dart';
import 'package:openqsp_app/features/auth/data/auth_client.dart';
import 'package:openqsp_app/features/auth/data/auth_token_store.dart';
import 'package:openqsp_app/features/callsign/data/callsign_store.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CallsignStore implements CallsignStore {
  @override
  Future<String?> read() async => 'EA3GNU';

  @override
  Future<void> write(String callsign) async {}
}

class _StatusClient implements ServerStatusClient {
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
  }) async => const LoginSuccess('replacement-token');

  @override
  Future<AuthValidationResult> validateToken({
    required String token,
    required String callsign,
  }) async => AuthValidationResult.valid;

  @override
  void close() {}
}

class _TokenStore implements AuthTokenStore {
  String? token = 'initial-token';

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
  final _states = StreamController<RealtimeConnectionState>.broadcast();

  @override
  Stream<RealtimeConnectionState> get connectionStates => _states.stream;

  @override
  Stream<MessagingEvent> get events => const Stream.empty();

  @override
  Future<void> connect({required String callsign, required String token}) async {
    _states.add(RealtimeConnectionState.connected);
  }

  void requireAuthentication() {
    _states.add(RealtimeConnectionState.authenticationRequired);
  }

  @override
  Future<void> close() => _states.close();
}

void main() {
  testWidgets(
    'expired session returns home and reauthenticates without framework errors',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final realtime = _Realtime();
      final tokens = _TokenStore();

      await tester.pumpWidget(
        OpenQspApp(
          callsignStore: _CallsignStore(),
          serverStatusClient: _StatusClient(),
          authClient: _AuthClient(),
          authTokenStore: tokens,
          messagesRepository: _MessagesRepository(),
          messagesRealtimeFactory: () => realtime,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('messagesTile')));
      await tester.pumpAndSettle();
      expect(find.text('No conversations yet'), findsOneWidget);

      realtime.requireAuthentication();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Password for EA3GNU'), findsOneWidget);
      expect(find.text('No conversations yet'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('serverPasswordField')),
        'secret',
      );
      await tester.tap(find.byKey(const Key('connectButton')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tokens.token, 'replacement-token');
      expect(find.byKey(const Key('homeCallsign')), findsOneWidget);
    },
  );
}
