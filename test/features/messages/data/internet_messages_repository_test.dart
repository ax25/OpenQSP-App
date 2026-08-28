import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openqsp_app/features/messages/data/internet_messages_repository.dart';

void main() {
  const token = 'access-token';
  final baseUri = Uri.parse('https://openqsp.example:8443');

  test('GET messages authenticates, paginates and parses real fields', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.headers['authorization'], 'Bearer $token');
      expect(request.url.path, '/api/v1/messages');
      expect(request.url.queryParameters['limit'], '200');
      if (requests == 1) {
        expect(request.url.queryParameters['cursor'], isNull);
        return http.Response(
          jsonEncode({
            'messages': [messageJson('one')],
            'next_cursor': 'next',
          }),
          200,
        );
      }
      expect(request.url.queryParameters['cursor'], 'next');
      return http.Response(
        jsonEncode({
          'messages': [messageJson('two')],
          'next_cursor': null,
        }),
        200,
      );
    });
    final repository = InternetMessagesRepository(
      baseUri: baseUri,
      httpClient: client,
    );
    final result = await repository.messages(callsign: 'EA3GNU', token: token);
    expect(result.map((item) => item.id), ['one', 'two']);
  });

  test('history sends normalized with query', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['with'], 'EA3ABC');
      return http.Response('{"messages":[],"next_cursor":null}', 200);
    });
    final repository = InternetMessagesRepository(
      baseUri: baseUri,
      httpClient: client,
    );
    await repository.messages(
      callsign: 'EA3GNU',
      token: token,
      withCallsign: 'ea3abc',
    );
  });

  test('POST sends bearer token, body and stable per-attempt idempotency key', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/messages');
      expect(request.headers['authorization'], 'Bearer $token');
      expect(request.headers['idempotency-key'], 'logical-attempt-1');
      expect(jsonDecode(request.body), {'to': 'EA3ABC', 'body': 'Hello'});
      return http.Response(jsonEncode({'message': messageJson('server-id')}), 201);
    });
    final repository = InternetMessagesRepository(
      baseUri: baseUri,
      httpClient: client,
      idempotencyKeyFactory: () => 'logical-attempt-1',
    );
    final sent = await repository.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'ea3abc',
      text: 'Hello',
      token: token,
    );
    expect(sent.id, 'server-id');
  });

  test('sync includes cursor and server errors are surfaced', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/sync');
      expect(request.url.queryParameters['cursor'], 'sync-1');
      return http.Response('unavailable', 503);
    });
    final repository = InternetMessagesRepository(
      baseUri: baseUri,
      httpClient: client,
    );
    expect(
      repository.sync(token: token, cursor: 'sync-1'),
      throwsA(
        isA<MessagesHttpException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });
}

Map<String, Object> messageJson(String id) => {
  'id': id,
  'from': 'EA3GNU',
  'to': 'EA3ABC',
  'body': 'Hello',
  'created_at': '2026-08-28T12:00:00Z',
};
