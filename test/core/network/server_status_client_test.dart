import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openqsp_app/core/network/server_status_client.dart';

void main() {
  final baseUri = Uri.parse('http://example.test:8000');

  InternetServerStatusClient clientFor(
    FutureOr<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 1),
  }) => InternetServerStatusClient(
    baseUri: baseUri,
    client: MockClient(handler),
    timeout: timeout,
  );

  test('returns available for 200 with ok status', () async {
    final client = clientFor((request) {
      expect(request.url.path, '/api/v1/status');
      return http.Response('{"status":"ok"}', 200);
    });
    expect(await client.isAvailable(), isTrue);
  });

  test('returns unavailable for a non-200 response', () async {
    final client = clientFor((_) => http.Response('error', 503));
    expect(await client.isAvailable(), isFalse);
  });

  test('returns unavailable for malformed JSON', () async {
    final client = clientFor((_) => http.Response('not-json', 200));
    expect(await client.isAvailable(), isFalse);
  });

  test('returns unavailable for a network exception', () async {
    final client = clientFor((_) => throw Exception('connection refused'));
    expect(await client.isAvailable(), isFalse);
  });

  test('returns unavailable after timeout', () async {
    final client = clientFor(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 1),
    );
    expect(await client.isAvailable(), isFalse);
  });
}
