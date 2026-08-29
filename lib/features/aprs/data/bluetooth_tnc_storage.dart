import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tnc_device.dart';

abstract interface class BluetoothTncStorage {
  Future<TncDevice?> read();
  Future<void> write(TncDevice device);
  Future<void> clear();
}

class PreferencesBluetoothTncStorage implements BluetoothTncStorage {
  static const _idKey = 'tnc.bluetooth.id';
  static const _nameKey = 'tnc.bluetooth.name';

  @override
  Future<TncDevice?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final id = preferences.getString(_idKey);
    final name = preferences.getString(_nameKey);
    return id == null || name == null ? null : TncDevice(id: id, name: name);
  }

  @override
  Future<void> write(TncDevice device) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_idKey, device.id);
    await preferences.setString(_nameKey, device.name);
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_idKey);
    await preferences.remove(_nameKey);
  }
}
