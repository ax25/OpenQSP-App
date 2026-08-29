import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tnc_device.dart';

abstract interface class BluetoothTncStorage {
  Future<TncDevice?> read();
  Future<void> write(TncDevice device);
  Future<void> clear();
}

abstract interface class AprsSsidStorage {
  Future<int> readSsid();
  Future<void> writeSsid(int ssid);
}

class PreferencesBluetoothTncStorage
    implements BluetoothTncStorage, AprsSsidStorage {
  static const _idKey = 'tnc.bluetooth.id';
  static const _nameKey = 'tnc.bluetooth.name';
  static const _ssidKey = 'tnc.aprs.ssid';

  @override
  Future<int> readSsid() async =>
      (await SharedPreferences.getInstance()).getInt(_ssidKey) ?? 0;

  @override
  Future<void> writeSsid(int ssid) async {
    if (ssid < 0 || ssid > 15) throw RangeError.range(ssid, 0, 15);
    await (await SharedPreferences.getInstance()).setInt(_ssidKey, ssid);
  }

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
