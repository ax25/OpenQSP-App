import 'dart:async';

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
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    device = await storage.read();
    state = device == null
        ? TncConnectionState.notConfigured
        : TncConnectionState.configured;
    _notify();
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
    _notify();
  }

  Future<void> connect() async {
    final selected = device;
    if (selected == null) return;
    failure = null;
    state = TncConnectionState.connecting;
    _notify();
    try {
      await service.connect(selected);
      if (_disposed) return;
      state = TncConnectionState.connected;
      _notify();
    } on TncServiceException catch (error) {
      if (_disposed) return;
      _setError(error.failure);
    } catch (_) {
      if (_disposed) return;
      _setError(TncFailure.unknown);
    }
  }

  Future<void> disconnect() async {
    await service.disconnect();
    if (_disposed) return;
    if (state == TncConnectionState.connected ||
        state == TncConnectionState.connecting) {
      state = device == null
          ? TncConnectionState.notConfigured
          : TncConnectionState.configured;
      failure = null;
      _notify();
    }
  }

  Future<void> forget() async {
    await service.disconnect();
    await storage.clear();
    device = null;
    failure = null;
    state = TncConnectionState.notConfigured;
    _notify();
  }

  void _setError(TncFailure value) {
    failure = value;
    state = TncConnectionState.error;
    _notify();
  }

  /// Ends this controller's ownership of the test connection.
  ///
  /// Transport shutdown is deliberately separate from [disconnect]'s UI state
  /// transition: Flutter disposal cannot await, and no asynchronous completion
  /// is allowed to notify a disposed [ChangeNotifier].
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(service.disconnect());
    super.dispose();
  }
}
