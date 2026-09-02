import 'dart:async';

import 'package:flutter/foundation.dart';

import '../aprs/aprs_message_encoder.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_parser.dart';
import '../ax25/ax25_address.dart';
import '../ax25/ax25_decoder.dart';
import '../ax25/ax25_encoder.dart';
import '../ax25/ax25_frame.dart';
import '../domain/tnc_device.dart';
import '../kiss/kiss_decoder.dart';
import '../kiss/kiss_encoder.dart';
import '../kiss/kiss_frame.dart';
import '../openqsp_carriage/openqsp_aprs_carriage.dart';
import 'bluetooth_tnc_service.dart';

/// Transaction-level OpenQSP reliability shim for a KISS Bluetooth link.
final class BurstRepairBluetoothTncService implements BluetoothTncService {
  BurstRepairBluetoothTncService(
    this.delegate, {
    this.repairDelay = const Duration(seconds: 5),
    this.finalFragmentRepairDelay = const Duration(seconds: 2),
    this.repairRetryInterval = const Duration(seconds: 15),
    this.silentRetryTtl = const Duration(seconds: 65),
    this.cacheTtl = openQspAprsDefaultTtl,
    this.completedCacheTtl = const Duration(minutes: 10),
  }) {
    if (repairDelay <= Duration.zero ||
        finalFragmentRepairDelay <= Duration.zero ||
        repairRetryInterval <= Duration.zero ||
        silentRetryTtl <= Duration.zero ||
        cacheTtl <= Duration.zero ||
        completedCacheTtl <= Duration.zero) {
      throw ArgumentError(
        'repairDelay, finalFragmentRepairDelay, repairRetryInterval, '
        'silentRetryTtl, cacheTtl and completedCacheTtl must be positive',
      );
    }
    _incomingFrameSubscription = _incomingDecoder.frames.listen(_onIncomingFrame);
    _delegateBytesSubscription = delegate.incomingBytes.listen(_incomingDecoder.add);
  }

  final BluetoothTncService delegate;
  final Duration repairDelay;
  final Duration finalFragmentRepairDelay;
  final Duration repairRetryInterval;
  final Duration silentRetryTtl;
  final Duration cacheTtl;
  final Duration completedCacheTtl;

  static const _ax25Decoder = Ax25Decoder();
  static const _ax25Encoder = Ax25Encoder();
  static const _aprsParser = AprsParser();
  static const _messageEncoder = AprsMessageEncoder();
  static const _kissEncoder = KissEncoder();
  static const _ansiRed = '\x1B[31m';
  static const _ansiReset = '\x1B[0m';

  final KissDecoder _incomingDecoder = KissDecoder();
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast(sync: true);
  late final StreamSubscription<KissFrame> _incomingFrameSubscription;
  late final StreamSubscription<List<int>> _delegateBytesSubscription;

  final Map<String, _SentBurst> _sentBursts = {};
  final Map<String, _ReceivedBurst> _receivedBursts = {};
  final Map<String, DateTime> _completedReceived = {};
  final Map<String, Timer> _completedAckTimers = {};

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Stream<int> get unexpectedDisconnections => delegate.unexpectedDisconnections;

  @override
  int? get activeConnectionId => delegate.activeConnectionId;

  @override
  Future<List<TncDevice>> bondedDevices() => delegate.bondedDevices();

  @override
  Future<void> connect(TncDevice device) => delegate.connect(device);

  @override
  Future<void> disconnect() async {
    _clearReceiveState();
    _clearSentState();
    await delegate.disconnect();
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    _expireCaches(DateTime.now().toUtc());
    _observeOutgoing(data);
    await delegate.sendBytes(data);
  }

  void _observeOutgoing(List<int> data) {
    final frame = _decodeSingleKiss(data);
    if (frame == null || frame.port != 0 || frame.command != 0) return;
    try {
      final ax25 = _ax25Decoder.decode(frame.payload);
      final aprs = _aprsParser.parse(ax25);
      if (aprs is! AprsTextMessage ||
          !(aprs.text.startsWith('Q2') || aprs.text.startsWith('Q1:'))) {
        return;
      }
      final fragment = parseFragment(aprs.text);
      final now = DateTime.now().toUtc();
      var burst = _sentBursts[fragment.transactionId];
      if (burst == null || burst.total != fragment.total || fragment.index == 0) {
        burst?.retryTimer?.cancel();
        burst = _SentBurst(fragment.total, now);
        _sentBursts[fragment.transactionId] = burst;
      }
      burst.fragments[fragment.index] = List<int>.unmodifiable(data);
      burst.lastSeen = now;
      if (burst.fragments.length == burst.total) {
        _armSilentRetry(fragment.transactionId, burst);
      }
    } on Object {
      // Non-OpenQSP KISS traffic is transparent to the shim.
    }
  }

  void _armSilentRetry(String transactionId, _SentBurst burst) {
    burst.retryTimer?.cancel();
    final now = DateTime.now().toUtc();
    if (now.difference(burst.createdAt) >= silentRetryTtl) {
      _sentBursts.remove(transactionId);
      return;
    }
    burst.retryTimer = Timer(
      repairRetryInterval,
      () => unawaited(_retrySilentBurst(transactionId, burst)),
    );
  }

  Future<void> _retrySilentBurst(String transactionId, _SentBurst burst) async {
    if (!identical(_sentBursts[transactionId], burst)) return;
    burst.retryTimer = null;
    final now = DateTime.now().toUtc();
    if (now.difference(burst.createdAt) >= silentRetryTtl) {
      _sentBursts.remove(transactionId);
      return;
    }
    _debugTx('TX retry complete burst (transaction $transactionId)');
    for (var index = 0; index < burst.total; index++) {
      final bytes = burst.fragments[index];
      if (bytes != null) await delegate.sendBytes(bytes);
    }
    burst.lastSeen = DateTime.now().toUtc();
    if (identical(_sentBursts[transactionId], burst)) {
      _armSilentRetry(transactionId, burst);
    }
  }

  KissFrame? _decodeSingleKiss(List<int> data) {
    final decoder = KissDecoder();
    KissFrame? result;
    final subscription = decoder.frames.listen((frame) => result ??= frame);
    decoder.add(data);
    unawaited(subscription.cancel());
    unawaited(decoder.close());
    return result;
  }

  void _onIncomingFrame(KissFrame frame) {
    if (frame.port == 0 && frame.command == 0) {
      try {
        final ax25 = _ax25Decoder.decode(frame.payload);
        final aprs = _aprsParser.parse(ax25);
        if (aprs is AprsTextMessage && _isFromOpenQsp(aprs)) {
          final storedTransaction = parseOpenQspStoredControl(aprs.text);
          if (storedTransaction != null) {
            _removeSentBurst(storedTransaction);
            _forwardCompactStored(aprs, storedTransaction);
            return;
          }
          final control = parseOpenQspBurstControl(aprs.text);
          if (control != null) {
            _handleControl(control);
            return;
          }
          if ((aprs.text.startsWith('Q2') || aprs.text.startsWith('Q1:')) &&
              _observeIncomingFragment(aprs)) {
            return;
          }
        }
      } on Object {
        // Malformed or unrelated traffic continues to the regular decoder.
      }
    }
    _incoming.add(_kissEncoder.encode(frame));
  }

  void _forwardCompactStored(
    AprsTextMessage message,
    String transactionId,
  ) {
    final transaction = decodeBase36(transactionId, 3);
    // Core STORED is 01 44 00 00. Build a one-fragment Q2 envelope for
    // downstream consumers. Preserve the logical third-party OpenQSP source
    // and destination rather than the outer RF/IGate AX.25 wrapper. This
    // synthetic frame never goes on RF.
    final syntheticBody =
        'Q2${encodeOpenQspBase91([transaction, 0x00, 0x01, 0x44, 0x00, 0x00])}';
    final information = _messageEncoder.encode(
      addressee: message.addressee,
      body: syntheticBody,
    );
    final syntheticAx25 = _ax25Encoder.encodeUi(
      destination: message.frame.destination,
      source: message.frame.source,
      information: information,
    );
    _incoming.add(
      _kissEncoder.encode(
        KissFrame(port: 0, command: 0, payload: syntheticAx25),
      ),
    );
  }

  static bool _isFromOpenQsp(AprsTextMessage message) =>
      message.frame.source.callsign == openQspAprsAddressee;

  static String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final millis = now.millisecond.toString().padLeft(3, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.$millis';
  }

  static void _debugTx(String message) {
    if (!kDebugMode) return;
    debugPrint('$_ansiRed${_timestamp()} $message$_ansiReset');
  }

  static void _debugBurst(String transactionId, {required bool duplicate}) {
    if (!kDebugMode) return;
    debugPrint(
      'OPENQSP | transaction $transactionId | '
      '${duplicate ? 'DUPLICATE' : 'complete'}',
    );
  }

  void _removeSentBurst(String transactionId) {
    _sentBursts.remove(transactionId)?.retryTimer?.cancel();
  }

  /// Stop reliability work for a request whose logical response proves that
  /// the server already received and processed the original Q2 transaction.
  /// Response frames may use a different transaction ID, so upper protocol
  /// layers need an explicit way to retire the request-side retry state.
  void completeOutboundTransaction(String transactionId) {
    _removeSentBurst(transactionId);
  }

  void _handleControl(OpenQspBurstControl control) {
    switch (control) {
      case OpenQspBurstAck(:final transactionId):
        _removeSentBurst(transactionId);
      case OpenQspBurstMissing(:final transactionId, :final missing):
        final burst = _sentBursts[transactionId];
        if (burst == null) return;
        // N2 is a valid response, so silence-based full-burst retry stops.
        // From here reliability is selective: resend only requested fragments.
        burst.retryTimer?.cancel();
        burst.retryTimer = null;
        for (final index in missing) {
          final bytes = burst.fragments[index];
          if (bytes != null) {
            _debugTx(
              'TX repair fragment ${index + 1}/${burst.total} '
              '(transaction $transactionId)',
            );
            unawaited(delegate.sendBytes(bytes));
          }
        }
    }
  }

  bool _observeIncomingFragment(AprsTextMessage message) {
    final now = DateTime.now().toUtc();
    _expireCaches(now);
    final fragment = parseFragment(message.text);
    final key = '${message.frame.source}|${fragment.transactionId}';
    final localIdentity = message.addressee;

    if (_completedReceived.containsKey(key)) {
      _debugBurst(fragment.transactionId, duplicate: true);
      if (!_completedAckTimers.containsKey(key)) {
        unawaited(
          _sendControl(localIdentity, encodeOpenQspBurstAck(fragment.transactionId)),
        );
      }
      // Keep the duplicate out of the burst state machine, but let the raw
      // APRS frame continue downstream so the traffic monitor can show the
      // exact IGate/APRS/RF path that caused this recovery ACK. The upper
      // OpenQSP decoder has its own completed-transaction cache, so this does
      // not re-deliver the message to application consumers.
      return false;
    }

    var burst = _receivedBursts[key];
    if (burst == null || burst.total != fragment.total) {
      burst = _ReceivedBurst(
        transactionId: fragment.transactionId,
        total: fragment.total,
        localIdentity: localIdentity,
        lastSeen: now,
      );
      _receivedBursts[key] = burst;
    }
    burst.received.add(fragment.index);
    burst.lastSeen = now;
    if (fragment.index == fragment.total - 1) {
      burst.finalFragmentSeen = true;
    }
    burst.timer?.cancel();

    if (burst.received.length == burst.total) {
      _receivedBursts.remove(key);
      _completedReceived[key] = now;
      _debugBurst(fragment.transactionId, duplicate: false);
      _completedAckTimers[key]?.cancel();
      _completedAckTimers[key] = Timer(finalFragmentRepairDelay, () {
        _completedAckTimers.remove(key);
        unawaited(
          _sendControl(localIdentity, encodeOpenQspBurstAck(fragment.transactionId)),
        );
      });
      return false;
    }

    final delay = burst.finalFragmentSeen
        ? finalFragmentRepairDelay
        : repairDelay;
    burst.timer = Timer(delay, () => _requestMissing(key));
    return false;
  }

  void _requestMissing(String key) {
    final burst = _receivedBursts[key];
    if (burst == null) return;
    burst.timer = null;
    final now = DateTime.now().toUtc();
    if (now.difference(burst.lastSeen) >= cacheTtl) {
      _receivedBursts.remove(key);
      return;
    }
    final missing = <int>{
      for (var index = 0; index < burst.total; index++)
        if (!burst.received.contains(index)) index,
    };
    if (missing.isEmpty) return;
    unawaited(
      _sendControl(
        burst.localIdentity,
        encodeOpenQspBurstMissing(burst.transactionId, missing),
      ),
    );
    burst.timer = Timer(repairRetryInterval, () => _requestMissing(key));
  }

  Future<void> _sendControl(String localIdentity, String body) async {
    final source = _parseIdentity(localIdentity);
    if (source == null) return;
    final information = _messageEncoder.encode(
      addressee: openQspAprsAddressee,
      body: body,
    );
    final ax25 = _ax25Encoder.encodeUi(
      destination: const Ax25Address(
        callsign: 'APOQSP',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: source,
      information: information,
    );
    final storedTransaction = parseOpenQspStoredControl(body);
    final control = parseOpenQspBurstControl(body);
    final detail = storedTransaction != null
        ? 'STORED | txn=$storedTransaction'
        : switch (control) {
            OpenQspBurstAck(:final transactionId) => 'ACK | txn=$transactionId',
            OpenQspBurstMissing(:final transactionId, :final missing) =>
              'NACK | txn=$transactionId | missing=${missing.map((index) => index + 1).join(',')}',
            null => body,
          };
    _debugTx('TX $localIdentity -> $openQspAprsAddressee | OPENQSP | $detail');
    await delegate.sendBytes(
      _kissEncoder.encode(KissFrame(port: 0, command: 0, payload: ax25)),
    );
  }

  void _expireCaches(DateTime now) {
    final expiredSent = <String>[];
    for (final entry in _sentBursts.entries) {
      if (now.difference(entry.value.createdAt) >= silentRetryTtl) {
        entry.value.retryTimer?.cancel();
        expiredSent.add(entry.key);
      }
    }
    for (final key in expiredSent) {
      _sentBursts.remove(key);
    }
    final expiredReceived = <String>[];
    for (final entry in _receivedBursts.entries) {
      if (now.difference(entry.value.lastSeen) >= cacheTtl) {
        entry.value.timer?.cancel();
        expiredReceived.add(entry.key);
      }
    }
    for (final key in expiredReceived) {
      _receivedBursts.remove(key);
    }
    final expiredCompleted = <String>[];
    for (final entry in _completedReceived.entries) {
      if (now.difference(entry.value) >= completedCacheTtl) {
        expiredCompleted.add(entry.key);
      }
    }
    for (final key in expiredCompleted) {
      _completedReceived.remove(key);
      _completedAckTimers.remove(key)?.cancel();
    }
  }

  void _clearSentState() {
    for (final burst in _sentBursts.values) {
      burst.retryTimer?.cancel();
    }
    _sentBursts.clear();
  }

  void _clearReceiveState() {
    for (final burst in _receivedBursts.values) {
      burst.timer?.cancel();
    }
    for (final timer in _completedAckTimers.values) {
      timer.cancel();
    }
    _receivedBursts.clear();
    _completedReceived.clear();
    _completedAckTimers.clear();
  }

  Ax25Address? _parseIdentity(String value) {
    final match = RegExp(r'^([A-Z0-9]{1,6})(?:-(\d{1,2}))?$').firstMatch(value);
    if (match == null) return null;
    final ssid = int.tryParse(match.group(2) ?? '0');
    if (ssid == null || ssid < 0 || ssid > 15) return null;
    return Ax25Address(
      callsign: match.group(1)!,
      ssid: ssid,
      hasBeenRepeated: false,
      isLast: true,
    );
  }

  @override
  Future<void> close() async {
    _clearReceiveState();
    _clearSentState();
    await _incomingFrameSubscription.cancel();
    await _delegateBytesSubscription.cancel();
    await _incoming.close();
    await _incomingDecoder.close();
  }
}

final class _SentBurst {
  _SentBurst(this.total, DateTime now)
      : createdAt = now,
        lastSeen = now;

  final int total;
  final DateTime createdAt;
  DateTime lastSeen;
  final Map<int, List<int>> fragments = {};
  Timer? retryTimer;
}

final class _ReceivedBurst {
  _ReceivedBurst({
    required this.transactionId,
    required this.total,
    required this.localIdentity,
    required this.lastSeen,
  });

  final String transactionId;
  final int total;
  final String localIdentity;
  DateTime lastSeen;
  bool finalFragmentSeen = false;
  final Set<int> received = {};
  Timer? timer;
}