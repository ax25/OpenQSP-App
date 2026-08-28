import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class ServerStatusClient {
  Future<bool> isAvailable();
}

class InternetServerStatusClient implements ServerStatusClient {
  InternetServerStatusClient({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
  }) : _statusUri = baseUri.resolve('/api/v1/status'),
       _client = client ?? http.Client();

  final Uri _statusUri;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _client.get(_statusUri).timeout(timeout);
      if (response.statusCode != 200) return false;

      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> && decoded['status'] == 'ok';
    } on Object {
      return false;
    }
  }
}
