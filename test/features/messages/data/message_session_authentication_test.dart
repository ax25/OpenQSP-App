import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openqsp_app/features/messages/data/internet_messages_repository.dart';
import 'package:openqsp_app/features/messages/data/messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';

void main() {
  final baseUri = Uri.parse('https://openqsp.example');

  for (final statusCode in [401, 403]) {
    test('HTTP $statusCode is surfaced as authentication required', () async {
      final repository = InternetMessagesRepository(
        baseUri: baseUri,
        httpClient: MockClient((_) async => http.Response('expired', statusCode)),
      );

      expect(
        repository.sync(token: 'expired-token'),
        throwsA(isA<MessagesAuthenticationException>()),
      );
    });
  }

  test('session-aware repository triggers reauthentication for every operation', () async {
    var authenticationRequests = 0;
    final repository = SessionAwareMessagesRepository(
      delegate: _ExpiredRepository(),
      onAuthenticationRequired: () async {
        authenticationRequests++;
      },
    );

    await expectLater(
      repository.messages(callsign: 'EA3GNU', token: 'expired'),
      throwsA(isA<MessagesAuthenticationException>()),
    );
    await expectLater(
      repository.send(
        callsign: 'EA3GNU',
        remoteCallsign: 'EA3ABC',
        text: 'hello',
        token: 'expired',
      ),
      throwsA(isA<MessagesAuthenticationException>()),
    );
    await expectLater(
      repository.markConversationRead(
        remoteCallsign: 'EA3ABC',
        token: 'expired',
      ),
      throwsA(isA<MessagesAuthenticationException>()),
    );
    await expectLater(
      repository.sync(token: 'expired'),
      throwsA(isA<MessagesAuthenticationException>()),
    );

    expect(authenticationRequests, 4);
  });

  test('non-authentication failures do not request a new password', () async {
    var authenticationRequests = 0;
    final repository = SessionAwareMessagesRepository(
      delegate: _UnavailableRepository(),
      onAuthenticationRequired: () async {
        authenticationRequests++;
      },
    );

    await expectLater(
      repository.sync(token: 'token'),
      throwsA(isA<StateError>()),
    );
    expect(authenticationRequests, 0);
  });
}

class _ExpiredRepository implements MessagesRepository {
  Never _expired() => throw const MessagesAuthenticationException();

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => _expired();

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) async => _expired();

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async => _expired();

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      _expired();
}

class _UnavailableRepository implements MessagesRepository {
  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async => throw StateError('unavailable');

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) async => throw StateError('unavailable');

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async => throw StateError('unavailable');

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      throw StateError('unavailable');
}
