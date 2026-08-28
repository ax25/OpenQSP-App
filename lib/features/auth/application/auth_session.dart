import '../data/auth_client.dart';
import '../data/auth_token_store.dart';

enum AuthGateResult { connected, needsPassword, serverUnavailable }

class AuthSession {
  AuthSession({required this.client, required this.tokenStore});

  final AuthClient client;
  final AuthTokenStore tokenStore;

  Future<AuthGateResult> authenticateStoredToken(String callsign) async {
    final token = await tokenStore.read(callsign);
    if (token == null || token.isEmpty) return AuthGateResult.needsPassword;
    final validation = await client.validateToken(
      token: token,
      callsign: callsign,
    );
    switch (validation) {
      case AuthValidationResult.valid:
        return AuthGateResult.connected;
      case AuthValidationResult.invalid:
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
    }
    return result;
  }
}
