import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openqsp_app/core/network/server_status_client.dart';

void main() {
  final baseUri = Uri.parse('http://openqsp.test:8000');

  InternetServerStatusClient client(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 1),
  }) => InternetServerStatusClient(
    baseUri: baseUri,
    httpClient: MockClient(handler),
    timeout: timeout,
  );

  test('returns available for 200 with ok status', () async {
    final statusClient = client(
      (request) async => http.Response('{"status":"ok"}', 200),
    );
    expect(await statusClient.isAvailable(), isTrue);
  });

  test('returns unavailable for non-200 response', () async {
    final statusClient = client((request) async => http.Response('', 503));
    expect(await statusClient.isAvailable(), isFalse);
  });

  test('returns unavailable for malformed response', () async {
    final statusClient = client(
      (request) async => http.Response('not json', 200),
    );
    expect(await statusClient.isAvailable(), isFalse);
  });

  test('returns unavailable for network exception', () async {
    final statusClient = client((request) async => throw Exception('offline'));
    expect(await statusClient.isAvailable(), isFalse);
  });

  test('returns unavailable after timeout', () async {
    final response = Completer<http.Response>();
    final statusClient = client(
      (request) => response.future,
      timeout: const Duration(milliseconds: 10),
    );
    expect(await statusClient.isAvailable(), isFalse);
  });
}
