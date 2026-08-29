import 'package:flutter/foundation.dart';

import '../data/bluetooth_tnc_service.dart';
import '../data/bluetooth_tnc_storage.dart';
import '../domain/tnc_connection_state.dart';
import '../domain/tnc_device.dart';

class TncSettingsController extends ChangeNotifier {
  TncSettingsController({required this.storage, required this.service});

  final BluetoothTncStorage storage;
  final BluetoothTncService service;
  TncConnectionState state = TncConnectionState.loading;
  TncDevice? device;
  TncFailure? failure;

  Future<void> initialize() async {
    device = await storage.read();
    state = device == null
        ? TncConnectionState.notConfigured
        : TncConnectionState.configured;
    notifyListeners();
  }

  Future<List<TncDevice>?> loadDevices() async {
    failure = null;
    try {
      return await service.bondedDevices();
    } on TncServiceException catch (error) {
      _setError(error.failure);
    } catch (_) {
      _setError(TncFailure.unknown);
    }
    return null;
  }

  Future<void> select(TncDevice selected) async {
    await disconnect();
    await storage.write(selected);
    device = selected;
    failure = null;
    state = TncConnectionState.configured;
    notifyListeners();
  }

  Future<void> connect() async {
    final selected = device;
    if (selected == null) return;
    failure = null;
    state = TncConnectionState.connecting;
    notifyListeners();
    try {
      await service.connect(selected);
      state = TncConnectionState.connected;
      notifyListeners();
    } on TncServiceException catch (error) {
      _setError(error.failure);
    } catch (_) {
      _setError(TncFailure.unknown);
    }
  }

  Future<void> disconnect() async {
    await service.disconnect();
    if (state == TncConnectionState.connected ||
        state == TncConnectionState.connecting) {
      state = device == null
          ? TncConnectionState.notConfigured
          : TncConnectionState.configured;
      failure = null;
      notifyListeners();
    }
  }

  Future<void> forget() async {
    await service.disconnect();
    await storage.clear();
    device = null;
    failure = null;
    state = TncConnectionState.notConfigured;
    notifyListeners();
  }

  void _setError(TncFailure value) {
    failure = value;
    state = TncConnectionState.error;
    notifyListeners();
  }
}
