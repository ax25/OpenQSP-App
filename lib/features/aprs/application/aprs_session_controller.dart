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

enum AprsMessageReceiveState { hidden, receiving, failed, completed }

final class AprsSessionController extends ChangeNotifier {
  AprsSessionController({
    required this.tncController,
    this.slowResponseThreshold = const Duration(minutes: 1),
    this.receiveFailureDelay = const Duration(minutes: 1),
    this.receiveHideDelay = const Duration(minutes: 2),
    this.receiveCompletedVisibleDuration = const Duration(seconds: 5),
    this.receiveIndicatorDelay = const Duration(milliseconds: 300),
  }) {
    if (receiveFailureDelay <= Duration.zero ||
        receiveHideDelay <= receiveFailureDelay ||
        receiveCompletedVisibleDuration <= Duration.zero ||
        receiveIndicatorDelay <= Duration.zero) {
      throw ArgumentError(
        'receive delays must be positive and hide delay must exceed failure delay',
      );
    }
    tncController.addListener(_onTncChanged);
    _lastObservedFramesRx = tncController.openQspFramesRx;
    _lastObservedMessageFragmentsRx = tncController.openQspMessageFragmentsRx;
  }

  final TncSettingsController tncController;
  final Duration slowResponseThreshold;
  final Duration receiveFailureDelay;
  final Duration receiveHideDelay;
  final Duration receiveCompletedVisibleDuration;
  final Duration receiveIndicatorDelay;
  bool _active = false;
  bool _disposed = false;
  Timer? _ageTimer;
  Timer? _receiveIndicatorTimer;
  Timer? _receiveFailureTimer;
  Timer? _receiveHideTimer;
  Timer? _receiveCompletedTimer;
  AprsActivityState _activityState = AprsActivityState.idle;
  AprsMessageReceiveState _messageReceiveState = AprsMessageReceiveState.hidden;
  bool _receiveIndicatorVisible = false;
  String? _messageReceivePeer;
  int _lastObservedFramesRx = 0;
  int _lastObservedMessageFragmentsRx = 0;
  int _messageCursor = 0;
  DateTime? _capabilitiesCheckStartedAt;
  AprsSessionState? _responseHealthOverride;
  bool _receiveTimeoutSlow = false;
  int _serverCapabilities = 0;
  final List<OpenQspMessage> _recentMessages = [];
  static const int _recentMessageLimit = 64;

  bool get active => _active;
  AprsActivityState get activityState => _activityState;
  AprsMessageReceiveState get messageReceiveState => _messageReceiveState;
  String? get messageReceivePeer => _messageReceivePeer;
  bool get hasMessageReceiveIndicator =>
      _messageReceiveState != AprsMessageReceiveState.hidden;
  bool get showMessageReceiveIndicator =>
      _messageReceiveState != AprsMessageReceiveState.hidden &&
      (_messageReceiveState != AprsMessageReceiveState.receiving ||
          _receiveIndicatorVisible);
  String? get lastIgate => tncController.lastOpenQspIgate;
  DateTime? get lastServerRx => tncController.lastValidOpenQspRx;
  bool get serverReachable =>
      state == AprsSessionState.available || state == AprsSessionState.slow;
  int get serverCapabilities => _serverCapabilities;
  bool get supportsAprsCommitAck => false;
  List<OpenQspMessage> get recentMessages => List.unmodifiable(_recentMessages);

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
    AprsSessionState.slow => 'APRS Connection Slow',
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
    if (value == AprsActivityState.noNewMessages) {
      _clearReceiveState();
    }
    _notify();
  }

  void setMessageCursor(int value) {
    if (value < 0 || value > 0xffffffff || value <= _messageCursor) return;
    _messageCursor = value;
    if (tncController.lastOpenQspMessageFragmentSequence case final sequence?
        when sequence <= _messageCursor) {
      _finishNonMessageFrame();
    }
  }

  void _startAgeTimer() {
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
  }

  void _stopAgeTimer() {
    _ageTimer?.cancel();
    _ageTimer = null;
  }

  void _cancelReceiveTimers() {
    _receiveIndicatorTimer?.cancel();
    _receiveIndicatorTimer = null;
    _receiveFailureTimer?.cancel();
    _receiveFailureTimer = null;
    _receiveHideTimer?.cancel();
    _receiveHideTimer = null;
    _receiveCompletedTimer?.cancel();
    _receiveCompletedTimer = null;
  }

  void _clearReceiveState() {
    _cancelReceiveTimers();
    _messageReceiveState = AprsMessageReceiveState.hidden;
    _receiveIndicatorVisible = false;
    _messageReceivePeer = null;
    _receiveTimeoutSlow = false;
  }

  void _observeFragmentActivity() {
    if (!_active) return;
    if (_messageReceiveState == AprsMessageReceiveState.completed) return;

    _receiveCompletedTimer?.cancel();
    _receiveCompletedTimer = null;
    _messageReceivePeer = null;

    if (_receiveTimeoutSlow) {
      _receiveTimeoutSlow = false;
      _responseHealthOverride = AprsSessionState.available;
    }

    if (_messageReceiveState != AprsMessageReceiveState.receiving) {
      _messageReceiveState = AprsMessageReceiveState.receiving;
      _receiveIndicatorVisible = false;
      _receiveIndicatorTimer?.cancel();
      _receiveIndicatorTimer = Timer(receiveIndicatorDelay, () {
        _receiveIndicatorTimer = null;
        if (!_active || _disposed ||
            _messageReceiveState != AprsMessageReceiveState.receiving) {
          return;
        }
        _receiveIndicatorVisible = true;
        _notify();
      });
    }

    _receiveFailureTimer?.cancel();
    _receiveHideTimer?.cancel();
    _receiveFailureTimer = Timer(receiveFailureDelay, () {
      if (!_active || _disposed) return;
      _receiveIndicatorTimer?.cancel();
      _receiveIndicatorTimer = null;
      _messageReceiveState = AprsMessageReceiveState.failed;
      _receiveIndicatorVisible = true;
      _notify();
    });
    _receiveHideTimer = Timer(receiveHideDelay, () {
      if (!_active || _disposed) return;
      _receiveIndicatorTimer?.cancel();
      _receiveIndicatorTimer = null;
      _messageReceiveState = AprsMessageReceiveState.hidden;
      _receiveIndicatorVisible = false;
      _messageReceivePeer = null;
      _receiveTimeoutSlow = true;
      _responseHealthOverride = AprsSessionState.slow;
      _notify();
    });
  }

  void _completeMessageReceive(OpenQspMessage message) {
    _receiveIndicatorTimer?.cancel();
    _receiveIndicatorTimer = null;
    _receiveFailureTimer?.cancel();
    _receiveFailureTimer = null;
    _receiveHideTimer?.cancel();
    _receiveHideTimer = null;
    _receiveCompletedTimer?.cancel();
    _messageReceiveState = AprsMessageReceiveState.completed;
    _receiveIndicatorVisible = true;
    _messageReceivePeer = message.author;
    _receiveCompletedTimer = Timer(receiveCompletedVisibleDuration, () {
      if (_disposed) return;
      _messageReceiveState = AprsMessageReceiveState.hidden;
      _receiveIndicatorVisible = false;
      _messageReceivePeer = null;
      _receiveCompletedTimer = null;
      _notify();
    });
  }

  void _finishNonMessageFrame() {
    if (_messageReceiveState != AprsMessageReceiveState.receiving &&
        _messageReceiveState != AprsMessageReceiveState.failed) {
      return;
    }
    _receiveIndicatorTimer?.cancel();
    _receiveIndicatorTimer = null;
    _receiveFailureTimer?.cancel();
    _receiveFailureTimer = null;
    _receiveHideTimer?.cancel();
    _receiveHideTimer = null;
    _messageReceiveState = AprsMessageReceiveState.hidden;
    _receiveIndicatorVisible = false;
    _messageReceivePeer = null;
  }

  Future<void> activate() async {
    _active = true;
    _activityState = AprsActivityState.idle;
    _clearReceiveState();
    _responseHealthOverride = null;
    _serverCapabilities = 0;
    _capabilitiesCheckStartedAt = null;
    _lastObservedFramesRx = tncController.openQspFramesRx;
    _lastObservedMessageFragmentsRx = tncController.openQspMessageFragmentsRx;
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
    _clearReceiveState();
    _responseHealthOverride = null;
    _serverCapabilities = 0;
    _capabilitiesCheckStartedAt = null;
    _lastObservedFramesRx = tncController.openQspFramesRx;
    _lastObservedMessageFragmentsRx = tncController.openQspMessageFragmentsRx;
    _messageCursor = 0;
    _recentMessages.clear();
    _stopAgeTimer();
    _notify();
    await tncController.disconnect();
    _notify();
  }

  bool _rememberMessage(OpenQspMessage message) {
    final duplicate = _recentMessages.any(
      (existing) =>
          existing.recipient == message.recipient &&
          existing.sequence == message.sequence,
    );
    if (duplicate) return false;
    _recentMessages.add(message);
    if (_recentMessages.length > _recentMessageLimit) {
      _recentMessages.removeAt(0);
    }
    return true;
  }

  void _onTncChanged() {
    final messageFragmentsRx = tncController.openQspMessageFragmentsRx;
    if (messageFragmentsRx != _lastObservedMessageFragmentsRx) {
      _lastObservedMessageFragmentsRx = messageFragmentsRx;
      final sequence = tncController.lastOpenQspMessageFragmentSequence;
      if (sequence != null && sequence > _messageCursor) {
        _observeFragmentActivity();
      }
    }

    final framesRx = tncController.openQspFramesRx;
    final object = tncController.lastOpenQspObject;
    if (object != null && framesRx != _lastObservedFramesRx) {
      _lastObservedFramesRx = framesRx;
      _observeServerResponse(object);
      switch (object) {
        case OpenQspMessage(:final sequence):
          final isNew = sequence > _messageCursor && _rememberMessage(object);
          if (sequence > _messageCursor) _messageCursor = sequence;
          if (isNew) {
            _activityState = AprsActivityState.newMessageReceived;
            _completeMessageReceive(object);
          } else {
            _finishNonMessageFrame();
          }
        case OpenQspEnd(:final requestOperation, :final returnedCount)
            when requestOperation == OpenQspOperation.getNewMessages:
          _activityState = returnedCount == 0
              ? AprsActivityState.noNewMessages
              : AprsActivityState.newMessageReceived;
          _finishNonMessageFrame();
        default:
          _finishNonMessageFrame();
      }
    }
    _notify();
  }

  void _observeServerResponse(OpenQspFrameObject object) {
    if (!_active) return;
    final current = state;
    if (object is OpenQspCapabilities) {
      _serverCapabilities = object.capabilities;
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
    _clearReceiveState();
    _stopAgeTimer();
    tncController.removeListener(_onTncChanged);
    super.dispose();
  }
}
