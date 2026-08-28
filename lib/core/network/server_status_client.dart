import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class ServerStatusClient {
  Future<bool> isAvailable();

  void close();
}

class InternetServerStatusClient implements ServerStatusClient {
  InternetServerStatusClient({
    required Uri baseUri,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 4),
  }) : _statusUri = baseUri.resolve('/api/v1/status'),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final Uri _statusUri;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration timeout;

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _httpClient.get(_statusUri).timeout(timeout);
      if (response.statusCode != 200) return false;

      final body = jsonDecode(response.body);
      return body is Map<String, dynamic> && body['status'] == 'ok';
    } on Object {
      return false;
    }
  }

  @override
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
