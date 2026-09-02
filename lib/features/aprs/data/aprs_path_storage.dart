import 'package:shared_preferences/shared_preferences.dart';

import '../domain/aprs_path.dart';

abstract interface class AprsPathStorage {
  Future<AprsPathMode> read();
  Future<void> write(AprsPathMode mode);
}

class PreferencesAprsPathStorage implements AprsPathStorage {
  static const _key = 'tnc.aprs.path_mode';

  @override
  Future<AprsPathMode> read() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return AprsPathMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AprsPathMode.oneHop,
    );
  }

  @override
  Future<void> write(AprsPathMode mode) async {
    await (await SharedPreferences.getInstance()).setString(_key, mode.name);
  }
}
