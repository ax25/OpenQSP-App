abstract interface class AuthClient {
  Future<String> login({required String callsign, required String password});
  Future<bool> validateToken({required String callsign, required String token});
}

abstract interface class AuthTokenStore {
  Future<String?> read(String callsign);
  Future<void> write(String callsign, String token);
  Future<void> delete(String callsign);
}

class AuthSession {
  AuthSession({required this.client, required this.tokens});

  final AuthClient client;
  final AuthTokenStore tokens;
  String? _callsign;
  String? _token;

  String? get token => _token;
  String? get callsign => _callsign;

  Future<bool> restore(String callsign) async {
    final normalized = callsign.trim().toUpperCase();
    final stored = await tokens.read(normalized);
    if (stored == null) return false;
    if (!await client.validateToken(callsign: normalized, token: stored)) {
      await tokens.delete(normalized);
      return false;
    }
    _callsign = normalized;
    _token = stored;
    return true;
  }

  Future<void> login(String callsign, String password) async {
    final normalized = callsign.trim().toUpperCase();
    final value = await client.login(callsign: normalized, password: password);
    await tokens.write(normalized, value);
    _callsign = normalized;
    _token = value;
  }

  Future<void> clear() async {
    if (_callsign != null) await tokens.delete(_callsign!);
    _callsign = null;
    _token = null;
  }
}
