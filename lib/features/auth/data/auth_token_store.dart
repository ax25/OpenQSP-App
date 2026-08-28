import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AuthTokenStore {
  Future<String?> read(String callsign);
  Future<void> write(String callsign, String token);
  Future<void> delete(String callsign);
}

class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String callsign) => 'auth_token_${callsign.toUpperCase()}';

  @override
  Future<String?> read(String callsign) => _storage.read(key: _key(callsign));

  @override
  Future<void> write(String callsign, String token) =>
      _storage.write(key: _key(callsign), value: token);

  @override
  Future<void> delete(String callsign) =>
      _storage.delete(key: _key(callsign));
}
