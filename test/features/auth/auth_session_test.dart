import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/auth/data/auth.dart';

class MemoryTokens implements AuthTokenStore {
  final values = <String, String>{};
  @override Future<void> delete(String callsign) async { values.remove(callsign); }
  @override Future<String?> read(String callsign) async => values[callsign];
  @override Future<void> write(String callsign, String token) async { values[callsign] = token; }
}
class FakeAuth implements AuthClient {
  bool valid = true; int logins = 0;
  @override Future<String> login({required String callsign, required String password}) async { logins++; return '$callsign-token'; }
  @override Future<bool> validateToken({required String callsign, required String token}) async => valid;
}
void main() {
  test('valid scoped token restores without login', () async {
    final tokens = MemoryTokens()..values['EA3GNU'] = 'saved';
    final auth = FakeAuth(); final session = AuthSession(client: auth, tokens: tokens);
    expect(await session.restore('ea3gnu'), isTrue); expect(session.token, 'saved'); expect(auth.logins, 0);
  });
  test('invalid token is removed without affecting another callsign', () async {
    final tokens = MemoryTokens()..values['EA3GNU'] = 'old'..values['N0CALL'] = 'other';
    final session = AuthSession(client: FakeAuth()..valid = false, tokens: tokens);
    expect(await session.restore('EA3GNU'), isFalse); expect(tokens.values['EA3GNU'], isNull); expect(tokens.values['N0CALL'], 'other');
  });
}
