import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/message_models.dart';
import 'messages_transport.dart';

class MessagesHttpException implements Exception {
  const MessagesHttpException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'Messages request failed ($statusCode)';
}

class InternetMessagesRepository implements MessagesRepository {
  InternetMessagesRepository({
    required Uri baseUri,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 8),
    String Function()? idempotencyKeyFactory,
  }) : _messagesUri = baseUri.resolve('/api/v1/messages'),
       _conversationsUri = baseUri.resolve('/api/v1/conversations/'),
       _syncUri = baseUri.resolve('/api/v1/sync'),
       _httpClient = httpClient ?? http.Client(),
       _idempotencyKeyFactory = idempotencyKeyFactory ?? _newKey;

  final Uri _messagesUri;
  final Uri _conversationsUri;
  final Uri _syncUri;
  final http.Client _httpClient;
  final Duration timeout;
  final String Function() _idempotencyKeyFactory;

  @override
  String get syncCursorKey => 'internet';

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async {
    final result = <InternetMessage>[];
    String? cursor;
    do {
      final query = <String, String>{'limit': '200'};
      if (withCallsign != null) query['with'] = withCallsign.toUpperCase();
      if (cursor != null) query['cursor'] = cursor;
      final response = await _httpClient
          .get(
            _messagesUri.replace(queryParameters: query),
            headers: _headers(token),
          )
          .timeout(timeout);
      final body = _decode(response);
      result.addAll(_parseMessages(body['messages']));
      cursor = body['next_cursor'] as String?;
    } while (cursor != null && cursor.isNotEmpty);
    return result;
  }

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) async {
    final key = _idempotencyKeyFactory();
    if (key.isEmpty || key.length > 128) {
      throw StateError('Invalid idempotency key');
    }
    final response = await _httpClient
        .post(
          _messagesUri,
          headers: {..._headers(token), 'Idempotency-Key': key},
          body: jsonEncode({'to': remoteCallsign.toUpperCase(), 'body': text}),
        )
        .timeout(timeout);
    final body = _decode(response);
    final message = body['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('Missing message response');
    }
    return InternetMessage.fromJson(message);
  }

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {
    final peer = remoteCallsign.toUpperCase();
    final uri = _conversationsUri.resolve('$peer/read');
    final response = await _httpClient
        .post(uri, headers: _headers(token))
        .timeout(timeout);
    _decode(response);
  }

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) async {
    final uri = cursor == null
        ? _syncUri
        : _syncUri.replace(queryParameters: {'cursor': cursor});
    final response = await _httpClient
        .get(uri, headers: _headers(token))
        .timeout(timeout);
    final body = _decode(response);
    final nextCursor = body['cursor'];
    if (nextCursor is! String) {
      throw const FormatException('Missing sync cursor');
    }
    final parsed = _parseMessages(body['messages']);
    return SyncBatch(
      messages: parsed,
      cursor: nextCursor,
      // /sync currently returns at most 200 changes. Exactly 200 may be the
      // final page; an extra empty request is harmless and captures high-water.
      hasMore: parsed.length == 200,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MessagesHttpException(response.statusCode);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid messages response');
    }
    return decoded;
  }

  List<InternetMessage> _parseMessages(Object? value) {
    if (value is! List) throw const FormatException('Missing messages list');
    return value.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid message in list');
      }
      return InternetMessage.fromJson(item);
    }).toList();
  }

  static String _newKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return '${DateTime.now().microsecondsSinceEpoch}-${base64UrlEncode(bytes)}';
  }
}
