import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_connection_state.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';

class MemoryTncStorage implements BluetoothTncStorage {
  TncDevice? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<TncDevice?> read() async => value;
  @override
  Future<void> write(TncDevice device) async => value = device;
}

class FakeTncService implements BluetoothTncService {
  Object? error;
  bool connected = false;
  List<TncDevice> devices = const [];
  Future<void>? disconnectPending;
  int disconnectCalls = 0;

  @override
  Future<List<TncDevice>> bondedDevices() async {
    if (error case final Object value) throw value;
    return devices;
  }

  @override
  Future<void> connect(TncDevice device) async {
    if (error case final Object value) throw value;
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connected = false;
    final pending = disconnectPending;
    if (pending != null) await pending;
  }
}

void main() {
  const device = TncDevice(id: '00:11:22:33:44:55', name: 'Mobilinkd TNC4');
  late MemoryTncStorage storage;
  late FakeTncService service;
  late TncSettingsController controller;

  setUp(() {
    storage = MemoryTncStorage();
    service = FakeTncService();
    controller = TncSettingsController(storage: storage, service: service);
  });

  test('without a stored TNC initializes as not configured', () async {
    await controller.initialize();
    expect(controller.state, TncConnectionState.notConfigured);
    expect(controller.device, isNull);
  });

  test('selecting a TNC persists it', () async {
    await controller.initialize();
    await controller.select(device);
    expect(storage.value, device);
    expect(controller.state, TncConnectionState.configured);
  });

  test('a new controller restores the persisted TNC as configured', () async {
    storage.value = device;
    final restored = TncSettingsController(storage: storage, service: service);
    await restored.initialize();
    expect(restored.device, device);
    expect(restored.state, TncConnectionState.configured);
  });

  test('forgetting clears persistence and configuration', () async {
    storage.value = device;
    await controller.initialize();
    await controller.forget();
    expect(storage.value, isNull);
    expect(controller.device, isNull);
    expect(controller.state, TncConnectionState.notConfigured);
  });

  test('a successful fake connection is reflected and can disconnect', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    expect(controller.state, TncConnectionState.connected);
    expect(service.connected, isTrue);
    await controller.disconnect();
    expect(controller.state, TncConnectionState.configured);
  });

  test('a connection failure becomes controlled error state', () async {
    storage.value = device;
    service.error = const TncServiceException(TncFailure.connectionFailed);
    await controller.initialize();
    await controller.connect();
    expect(controller.state, TncConnectionState.error);
    expect(controller.failure, TncFailure.connectionFailed);
  });

  test('permission denial while listing is controlled and retryable', () async {
    service.error = const TncServiceException(TncFailure.permissionDenied);
    await controller.initialize();
    expect(await controller.loadDevices(), isNull);
    expect(controller.state, TncConnectionState.error);
    expect(controller.failure, TncFailure.permissionDenied);
  });

  test('dispose closes an active connection without later notifications', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final pendingDisconnect = Completer<void>();
    service.disconnectPending = pendingDisconnect.future;

    controller.dispose();

    expect(service.disconnectCalls, 1);
    expect(service.connected, isFalse);
    pendingDisconnect.complete();
    await pendingDisconnect.future;
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0);
  });
}
