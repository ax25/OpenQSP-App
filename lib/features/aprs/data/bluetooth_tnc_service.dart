import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/tnc_connection_state.dart';
import '../domain/tnc_device.dart';

class TncServiceException implements Exception {
  const TncServiceException(this.failure);
  final TncFailure failure;
}

abstract interface class BluetoothTncService {
  Future<List<TncDevice>> bondedDevices();
  Future<void> connect(TncDevice device);
  Future<void> disconnect();
}

class AndroidBluetoothTncService implements BluetoothTncService {
  AndroidBluetoothTncService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.openqsp/bluetooth_tnc');

  final MethodChannel _channel;
  static const connectionTimeout = Duration(seconds: 12);

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
    try {
      await _channel
          .invokeMethod<void>('connect', {'address': device.id})
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
    try {
      await _channel.invokeMethod<void>('disconnect');
    } on PlatformException {
      // Disconnection is best-effort and never leaks platform errors to the UI.
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
