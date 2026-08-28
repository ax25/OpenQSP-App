import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum LoginFailure { incorrectPassword, network, server, malformedResponse }

sealed class LoginResult {
  const LoginResult();
}

final class LoginSuccess extends LoginResult {
  const LoginSuccess(this.accessToken);
  final String accessToken;
}

final class LoginError extends LoginResult {
  const LoginError(this.failure);
  final LoginFailure failure;
}

enum AuthValidationResult { valid, invalid, networkError, serverError }

abstract interface class AuthClient {
  Future<LoginResult> login({
    required String callsign,
    required String password,
  });

  Future<AuthValidationResult> validateToken({
    required String token,
    required String callsign,
  });

  void close();
}

class InternetAuthClient implements AuthClient {
  InternetAuthClient({
    required Uri baseUri,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 4),
  }) : _loginUri = baseUri.resolve('/api/v1/auth/login'),
       _meUri = baseUri.resolve('/api/v1/me'),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final Uri _loginUri;
  final Uri _meUri;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration timeout;

  @override
  Future<LoginResult> login({
    required String callsign,
    required String password,
  }) async {
    try {
      final response = await _httpClient
          .post(
            _loginUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'callsign': callsign, 'password': password}),
          )
          .timeout(timeout);
      if (response.statusCode == 401) {
        return const LoginError(LoginFailure.incorrectPassword);
      }
      if (response.statusCode != 200) {
        return const LoginError(LoginFailure.server);
      }
      final body = jsonDecode(response.body);
      final token = body is Map<String, dynamic>
          ? body['access_token']
          : null;
      if (token is! String || token.isEmpty) {
        return const LoginError(LoginFailure.malformedResponse);
      }
      return LoginSuccess(token);
    } on TimeoutException {
      return const LoginError(LoginFailure.network);
    } on http.ClientException {
      return const LoginError(LoginFailure.network);
    } on FormatException {
      return const LoginError(LoginFailure.malformedResponse);
    }
  }

  @override
  Future<AuthValidationResult> validateToken({
    required String token,
    required String callsign,
  }) async {
    try {
      final response = await _httpClient.get(
        _meUri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(timeout);
      if (response.statusCode == 401) return AuthValidationResult.invalid;
      if (response.statusCode != 200) return AuthValidationResult.serverError;

      final body = jsonDecode(response.body);
      final responseCallsign = switch (body) {
        {'callsign': final String value} => value,
        {'user': {'callsign': final String value}} => value,
        _ => null,
      };
      if (responseCallsign == null ||
          _normalizeCallsign(responseCallsign) != _normalizeCallsign(callsign)) {
        return AuthValidationResult.invalid;
      }
      return AuthValidationResult.valid;
    } on TimeoutException {
      return AuthValidationResult.networkError;
    } on http.ClientException {
      return AuthValidationResult.networkError;
    } on FormatException {
      return AuthValidationResult.invalid;
    }
  }

  String _normalizeCallsign(String callsign) => callsign.trim().toUpperCase();

  @override
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
