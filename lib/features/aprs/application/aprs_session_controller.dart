import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/tnc_connection_state.dart';
import 'tnc_settings_controller.dart';

enum AprsSessionState { inactive, connecting, available, unavailable }

/// Owns the operational APRS mode independently from any presentation screen.
///
/// The underlying [TncSettingsController] remains the single owner of the
/// Bluetooth/KISS/APRS/OpenQSP pipeline. This controller only decides when that
/// pipeline should be active for the application.
final class AprsSessionController extends ChangeNotifier {
  AprsSessionController({required this.tncController}) {
    tncController.addListener(_onTncChanged);
  }

  final TncSettingsController tncController;
  bool _active = false;
  bool _disposed = false;

  bool get active => _active;

  AprsSessionState get state {
    if (!_active) return AprsSessionState.inactive;
    if (tncController.state == TncConnectionState.loading ||
        tncController.state == TncConnectionState.connecting ||
        tncController.openQspCheckState == OpenQspCheckState.waiting) {
      return AprsSessionState.connecting;
    }
    if (tncController.kissReady &&
        tncController.openQspCheckState == OpenQspCheckState.available) {
      return AprsSessionState.available;
    }
    return AprsSessionState.unavailable;
  }

  String get statusLabel => switch (state) {
    AprsSessionState.inactive => 'APRS inactive',
    AprsSessionState.connecting => 'Connecting APRS...',
    AprsSessionState.available => 'APRS Server Available',
    AprsSessionState.unavailable => 'APRS Server Unavailable',
  };

  Future<void> activate() async {
    _active = true;
    _notify();

    await tncController.initialize();
    if (!_active || _disposed || tncController.device == null) {
      _notify();
      return;
    }

    if (!tncController.kissReady) {
      await tncController.connect();
    }
    if (!_active || _disposed || !tncController.kissReady) {
      _notify();
      return;
    }

    await tncController.checkOpenQsp();
    _notify();
  }

  Future<void> retry() => activate();

  Future<void> deactivate() async {
    _active = false;
    _notify();
    await tncController.disconnect();
    _notify();
  }

  void _onTncChanged() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    tncController.removeListener(_onTncChanged);
    super.dispose();
  }
}
