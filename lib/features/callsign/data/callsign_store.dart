import 'package:shared_preferences/shared_preferences.dart';

abstract interface class CallsignStore {
  Future<String?> read();

  Future<void> write(String callsign);
}

class PreferencesCallsignStore implements CallsignStore {
  static const _key = 'callsign';

  @override
  Future<String?> read() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return value == null || value.trim().isEmpty ? null : value;
  }

  @override
  Future<void> write(String callsign) async {
    await (await SharedPreferences.getInstance()).setString(_key, callsign);
  }
}
