import '../data/auth_client.dart';
import '../data/auth_token_store.dart';

enum AuthGateResult { connected, needsPassword, serverUnavailable }

class AuthSession {
  AuthSession({required this.client, required this.tokenStore});

  final AuthClient client;
  final AuthTokenStore tokenStore;
  String? _activeCallsign;
  String? _activeToken;

  String? tokenFor(String callsign) =>
      _activeCallsign == _normalize(callsign) ? _activeToken : null;

  Future<AuthGateResult> authenticateStoredToken(String callsign) async {
    final token = await tokenStore.read(callsign);
    if (token == null || token.isEmpty) return AuthGateResult.needsPassword;
    final validation = await client.validateToken(
      token: token,
      callsign: callsign,
    );
    switch (validation) {
      case AuthValidationResult.valid:
        _setActive(callsign, token);
        return AuthGateResult.connected;
      case AuthValidationResult.invalid:
        _clearActive(callsign);
        await tokenStore.delete(callsign);
        return AuthGateResult.needsPassword;
      case AuthValidationResult.networkError:
      case AuthValidationResult.serverError:
        return AuthGateResult.serverUnavailable;
    }
  }

  Future<LoginResult> login(String callsign, String password) async {
    final result = await client.login(callsign: callsign, password: password);
    if (result case LoginSuccess(:final accessToken)) {
      await tokenStore.write(callsign, accessToken);
      _setActive(callsign, accessToken);
    }
    return result;
  }

  void _setActive(String callsign, String token) {
    _activeCallsign = _normalize(callsign);
    _activeToken = token;
  }

  void _clearActive(String callsign) {
    if (_activeCallsign == _normalize(callsign)) {
      _activeCallsign = null;
      _activeToken = null;
    }
  }

  String _normalize(String callsign) => callsign.trim().toUpperCase();
}
