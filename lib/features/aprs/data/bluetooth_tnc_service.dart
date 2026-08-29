import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/tnc_connection_state.dart';
import '../domain/tnc_device.dart';

class TncServiceException implements Exception {
  const TncServiceException(this.failure);
  final TncFailure failure;
}

abstract interface class BluetoothTncService {
  Stream<List<int>> get incomingBytes;
  Stream<int> get unexpectedDisconnections;
  int? get activeConnectionId;
  Future<List<TncDevice>> bondedDevices();
  Future<void> connect(TncDevice device);
  Future<void> disconnect();
  Future<void> sendBytes(List<int> data);
}

class AndroidBluetoothTncService implements BluetoothTncService {
  AndroidBluetoothTncService({
    MethodChannel? channel,
    EventChannel? events,
    EventChannel? connectionEvents,
  })
    : _channel = channel ?? const MethodChannel('app.openqsp/bluetooth_tnc'),
      _events = events ?? const EventChannel('app.openqsp/bluetooth_tnc/bytes'),
      _connectionEvents = connectionEvents ??
          const EventChannel('app.openqsp/bluetooth_tnc/connection_events');

  final MethodChannel _channel;
  final EventChannel _events;
  final EventChannel _connectionEvents;
  Stream<List<int>>? _incomingBytes;
  Stream<int>? _unexpectedDisconnections;
  int? _activeConnectionId;
  static const connectionTimeout = Duration(seconds: 12);

  @override
  Stream<List<int>> get incomingBytes => _incomingBytes ??= _events
      .receiveBroadcastStream()
      .map((value) {
        final bytes = List<int>.unmodifiable((value as List).cast<int>());
        assert(() {
          debugPrint('Bluetooth RX bytes: ${bytes.length}');
          return true;
        }());
        return bytes;
      });

  @override
  int? get activeConnectionId => _activeConnectionId;

  @override
  Stream<int> get unexpectedDisconnections =>
      _unexpectedDisconnections ??= _connectionEvents
          .receiveBroadcastStream()
          .map(
            (value) =>
                Map<Object?, Object?>.from(value! as Map)['connectionId']! as int,
          )
          .where((connectionId) => connectionId == _activeConnectionId);

  Future<void> _ensureAndroid() async {
    if (!Platform.isAndroid) {
      throw const TncServiceException(TncFailure.unavailable);
    }
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      if (granted != true) {
        throw const TncServiceException(TncFailure.permissionDenied);
      }
    } on PlatformException catch (error) {
      throw TncServiceException(_failure(error.code));
    }
  }

  @override
  Future<List<TncDevice>> bondedDevices() async {
    await _ensureAndroid();
    try {
      final values = await _channel.invokeListMethod<Object?>('bondedDevices');
      return (values ?? const []).map((value) {
        final map = Map<Object?, Object?>.from(value! as Map);
        return TncDevice(id: map['id']! as String, name: map['name']! as String);
      }).toList();
    } on PlatformException catch (error) {
      throw TncServiceException(_failure(error.code));
    }
  }

  @override
  Future<void> connect(TncDevice device) async {
    await _ensureAndroid();
    _activeConnectionId = null;
    try {
      _activeConnectionId = await _channel
          .invokeMethod<int>('connect', {'address': device.id})
          .timeout(connectionTimeout);
    } on TimeoutException {
      await disconnect();
      throw const TncServiceException(TncFailure.timeout);
    } on PlatformException catch (error) {
      throw TncServiceException(_failure(error.code));
    }
  }

  @override
  Future<void> disconnect() async {
    if (!Platform.isAndroid) return;
    // Clear first: closing the socket unblocks read(), but that is intentional.
    _activeConnectionId = null;
    try {
      await _channel.invokeMethod<void>('disconnect');
    } on PlatformException {
      // Disconnection is best-effort and never leaks platform errors to the UI.
    }
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    if (!Platform.isAndroid) {
      throw const TncServiceException(TncFailure.unavailable);
    }
    try {
      await _channel.invokeMethod<void>('write', {
        'bytes': Uint8List.fromList(data),
      });
      assert(() {
        debugPrint('Bluetooth TX bytes: ${data.length}');
        return true;
      }());
    } on PlatformException catch (error) {
      throw TncServiceException(_failure(error.code));
    }
  }

  TncFailure _failure(String code) => switch (code) {
    'unavailable' => TncFailure.unavailable,
    'disabled' => TncFailure.disabled,
    'permission_denied' => TncFailure.permissionDenied,
    'not_found' => TncFailure.deviceNotFound,
    'connection_failed' => TncFailure.connectionFailed,
    _ => TncFailure.unknown,
  };
}
