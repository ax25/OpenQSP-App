import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/openqsp_protocol/openqsp_models.dart';
import '../../../core/openqsp_protocol/openqsp_operation.dart';
import '../domain/tnc_connection_state.dart';
import 'tnc_settings_controller.dart';

enum AprsSessionState {
  inactive,
  connecting,
  available,
  slow,
  notResponding,
  unavailable,
}

enum AprsActivityState {
  idle,
  askingForNewMessages,
  gettingNewMessages,
  newMessageReceived,
  noNewMessages,
}

/// Owns the operational APRS mode independently from any presentation screen.
///
/// The underlying [TncSettingsController] remains the single owner of the
/// Bluetooth/KISS/APRS/OpenQSP pipeline. This controller only decides when that
/// pipeline should be active for the application.
final class AprsSessionController extends ChangeNotifier {
  AprsSessionController({
    required this.tncController,
    this.slowResponseThreshold = const Duration(minutes: 1),
  }) {
    tncController.addListener(_onTncChanged);
    _lastObservedFramesRx = tncController.openQspFramesRx;
  }

  final TncSettingsController tncController;
  final Duration slowResponseThreshold;
  bool _active = false;
  bool _disposed = false;
  Timer? _ageTimer;
  AprsActivityState _activityState = AprsActivityState.idle;
  int _lastObservedFramesRx = 0;
  DateTime? _capabilitiesCheckStartedAt;
  AprsSessionState? _responseHealthOverride;

  bool get active => _active;
  AprsActivityState get activityState => _activityState;
  String? get lastIgate => tncController.lastOpenQspIgate;
  DateTime? get lastServerRx => tncController.lastValidOpenQspRx;
  bool get serverReachable =>
      state == AprsSessionState.available || state == AprsSessionState.slow;

  AprsSessionState get state {
    if (!_active) return AprsSessionState.inactive;
    if (tncController.state == TncConnectionState.loading ||
        tncController.state == TncConnectionState.connecting ||
        tncController.openQspCheckState == OpenQspCheckState.waiting) {
      return AprsSessionState.connecting;
    }
    if (!tncController.kissReady ||
        tncController.openQspCheckState == OpenQspCheckState.error) {
      return AprsSessionState.unavailable;
    }
    final override = _responseHealthOverride;
    if (override != null) return override;
    if (tncController.openQspCheckState == OpenQspCheckState.available) {
      return AprsSessionState.available;
    }
    if (tncController.openQspCheckState == OpenQspCheckState.noResponse) {
      return AprsSessionState.notResponding;
    }
    return AprsSessionState.unavailable;
  }

  String get statusLabel => switch (state) {
    AprsSessionState.inactive => 'APRS inactive',
    AprsSessionState.connecting =>
      tncController.openQspCheckState == OpenQspCheckState.waiting
          ? 'Connecting APRS... ${tncController.openQspCheckRemainingSeconds}s'
          : 'Connecting APRS...',
    AprsSessionState.available => 'APRS Server Available',
    AprsSessionState.slow => 'APRS Server Connection Slow',
    AprsSessionState.notResponding => 'APRS Server Not Responding',
    AprsSessionState.unavailable => 'APRS Server Unavailable',
  };

  String get activityLabel => switch (_activityState) {
    AprsActivityState.idle => 'Idle',
    AprsActivityState.askingForNewMessages => 'Asking for new messages',
    AprsActivityState.gettingNewMessages => 'Getting new messages',
    AprsActivityState.newMessageReceived => 'New message received',
    AprsActivityState.noNewMessages => 'No new messages',
  };

  String get lastServerRxAgeLabel {
    final value = lastServerRx;
    if (value == null) return '--';
    final age = DateTime.now().toUtc().difference(value);
    if (age.inSeconds < 60) return '${age.inSeconds}s';
    final minutes = age.inMinutes;
    final seconds = age.inSeconds.remainder(60);
    return '${minutes}m ${seconds}s';
  }

  String get detailLabel {
    final age = lastServerRx == null ? '--' : '${lastServerRxAgeLabel} ago';
    return 'IGate ${lastIgate ?? '--'} · $activityLabel · RX $age';
  }

  void setActivity(AprsActivityState value) {
    if (_activityState == value) return;
    _activityState = value;
    _notify();
  }

  void _startAgeTimer() {
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
  }

  void _stopAgeTimer() {
    _ageTimer?.cancel();
    _ageTimer = null;
  }

  Future<void> activate() async {
    _active = true;
    _activityState = AprsActivityState.idle;
    _responseHealthOverride = null;
    _capabilitiesCheckStartedAt = null;
    _lastObservedFramesRx = tncController.openQspFramesRx;
    _startAgeTimer();
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

    _capabilitiesCheckStartedAt = DateTime.now().toUtc();
    await tncController.checkOpenQsp();
    _notify();
  }

  Future<void> retry() => activate();

  Future<void> deactivate() async {
    _active = false;
    _activityState = AprsActivityState.idle;
    _responseHealthOverride = null;
    _capabilitiesCheckStartedAt = null;
    _lastObservedFramesRx = tncController.openQspFramesRx;
    _stopAgeTimer();
    _notify();
    await tncController.disconnect();
    _notify();
  }

  void _onTncChanged() {
    final framesRx = tncController.openQspFramesRx;
    final object = tncController.lastOpenQspObject;
    if (object != null && framesRx != _lastObservedFramesRx) {
      _lastObservedFramesRx = framesRx;
      _observeServerResponse(object);
      switch (object) {
        case OpenQspMessage():
          _activityState = AprsActivityState.newMessageReceived;
        case OpenQspEnd(:final requestOperation, :final returnedCount)
            when requestOperation == OpenQspOperation.getNewMessages:
          _activityState = returnedCount == 0
              ? AprsActivityState.noNewMessages
              : AprsActivityState.newMessageReceived;
        default:
          break;
      }
    }
    _notify();
  }

  void _observeServerResponse(OpenQspFrameObject object) {
    if (!_active) return;
    final current = state;
    if (object is OpenQspCapabilities) {
      final startedAt = _capabilitiesCheckStartedAt;
      final elapsed = startedAt == null
          ? null
          : DateTime.now().toUtc().difference(startedAt);
      _responseHealthOverride = elapsed != null &&
              elapsed >= slowResponseThreshold
          ? AprsSessionState.slow
          : AprsSessionState.available;
      return;
    }
    if (current == AprsSessionState.notResponding) {
      // A complete, valid OpenQSP frame proves the server is reachable even if
      // the original capability check timed out. The request that produced
      // this frame may have been delayed in the APRS/IGate path, so recover as
      // slow rather than discarding the late response.
      _responseHealthOverride = AprsSessionState.slow;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopAgeTimer();
    tncController.removeListener(_onTncChanged);
    super.dispose();
  }
}
