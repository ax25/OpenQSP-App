import 'dart:async';

import 'package:flutter/foundation.dart';

import '../aprs/aprs_message_encoder.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_parser.dart';
import '../ax25/ax25_address.dart';
import '../ax25/ax25_decoder.dart';
import '../ax25/ax25_encoder.dart';
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
    this.repairDelay = const Duration(seconds: 2),
    this.repairRetryInterval = const Duration(seconds: 31),
    this.cacheTtl = openQspAprsDefaultTtl,
    this.completedCacheTtl = const Duration(minutes: 10),
  }) {
    if (repairDelay <= Duration.zero ||
        repairRetryInterval <= Duration.zero ||
        cacheTtl <= Duration.zero ||
        completedCacheTtl <= Duration.zero) {
      throw ArgumentError(
        'repairDelay, repairRetryInterval, cacheTtl and completedCacheTtl '
        'must be positive',
      );
    }
    _incomingFrameSubscription = _incomingDecoder.frames.listen(_onIncomingFrame);
    _delegateBytesSubscription = delegate.incomingBytes.listen(_incomingDecoder.add);
  }

  final BluetoothTncService delegate;
  final Duration repairDelay;
  final Duration repairRetryInterval;
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
    _sentBursts.clear();
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
      if (aprs is! AprsTextMessage || !aprs.text.startsWith('Q1:')) return;
      final fragment = parseFragment(aprs.text);
      final now = DateTime.now().toUtc();
      var burst = _sentBursts[fragment.transactionId];
      if (burst == null || burst.total != fragment.total || fragment.index == 0) {
        burst = _SentBurst(fragment.total, now);
        _sentBursts[fragment.transactionId] = burst;
      }
      burst.fragments[fragment.index] = List<int>.unmodifiable(data);
      burst.lastSeen = now;
    } on Object {
      // Non-OpenQSP KISS traffic is transparent to the shim.
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
          final control = parseOpenQspBurstControl(aprs.text);
          if (control != null) {
            _handleControl(control);
            return;
          }
          if (aprs.text.startsWith('Q1:') && _observeIncomingFragment(aprs)) {
            return;
          }
        }
      } on Object {
        // Malformed or unrelated traffic continues to the regular decoder.
      }
    }
    _incoming.add(_kissEncoder.encode(frame));
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

  void _handleControl(OpenQspBurstControl control) {
    switch (control) {
      case OpenQspBurstAck(:final transactionId):
        _sentBursts.remove(transactionId);
      case OpenQspBurstMissing(:final transactionId, :final missing):
        final burst = _sentBursts[transactionId];
        if (burst == null) return;
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

  /// Returns true when the fragment belongs to a transaction already completed
  /// by this link and therefore must not be forwarded to the Core reassembler.
  bool _observeIncomingFragment(AprsTextMessage message) {
    final now = DateTime.now().toUtc();
    _expireCaches(now);
    final fragment = parseFragment(message.text);
    final key = '${message.frame.source}|${fragment.transactionId}';
    final localIdentity = message.addressee;

    if (_completedReceived.containsKey(key)) {
      _debugBurst(fragment.transactionId, duplicate: true);
      unawaited(
        _sendControl(localIdentity, encodeOpenQspBurstAck(fragment.transactionId)),
      );
      return true;
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
    burst.timer?.cancel();

    if (burst.received.length == burst.total) {
      _receivedBursts.remove(key);
      _completedReceived[key] = now;
      _debugBurst(fragment.transactionId, duplicate: false);
      unawaited(
        _sendControl(localIdentity, encodeOpenQspBurstAck(fragment.transactionId)),
      );
      return false;
    }

    // A newly received fragment gets the short repair grace period. If the
    // following Q1N is itself lost, retries use the much slower RF retry
    // interval instead of continuously transmitting every repairDelay.
    burst.timer = Timer(repairDelay, () => _requestMissing(key));
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
    _debugTx('TX $localIdentity -> $openQspAprsAddressee | OPENQSP | $body');
    await delegate.sendBytes(
      _kissEncoder.encode(KissFrame(port: 0, command: 0, payload: ax25)),
    );
  }

  static Ax25Address? _parseIdentity(String value) {
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

  void _expireCaches(DateTime now) {
    _sentBursts.removeWhere((_, burst) => now.difference(burst.lastSeen) >= cacheTtl);
    _completedReceived.removeWhere(
      (_, completed) => now.difference(completed) >= completedCacheTtl,
    );
    final expired = <String>[];
    for (final entry in _receivedBursts.entries) {
      if (now.difference(entry.value.lastSeen) >= cacheTtl) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _receivedBursts.remove(key)?.timer?.cancel();
    }
  }

  void _clearReceiveState() {
    for (final burst in _receivedBursts.values) {
      burst.timer?.cancel();
    }
    _receivedBursts.clear();
    _completedReceived.clear();
  }
}

sealed class OpenQspBurstControl {
  const OpenQspBurstControl(this.transactionId);
  final String transactionId;
}

final class OpenQspBurstAck extends OpenQspBurstControl {
  const OpenQspBurstAck(super.transactionId);
}

final class OpenQspBurstMissing extends OpenQspBurstControl {
  const OpenQspBurstMissing(super.transactionId, this.missing);
  final Set<int> missing;
}

OpenQspBurstControl? parseOpenQspBurstControl(String body) {
  final ack = RegExp(r'^Q1A:([0-9A-Z]{3})$').firstMatch(body);
  if (ack != null) return OpenQspBurstAck(ack.group(1)!);
  final nack = RegExp(r'^Q1N:([0-9A-Z]{3}):([0-9A-F]{4})$').firstMatch(body);
  if (nack == null) return null;
  final mask = int.parse(nack.group(2)!, radix: 16);
  if (mask == 0) return null;
  return OpenQspBurstMissing(nack.group(1)!, {
    for (var index = 0; index < 16; index++)
      if ((mask & (1 << index)) != 0) index,
  });
}

String encodeOpenQspBurstAck(String transactionId) {
  _validateTransactionId(transactionId);
  return 'Q1A:$transactionId';
}

String encodeOpenQspBurstMissing(String transactionId, Set<int> missing) {
  _validateTransactionId(transactionId);
  var mask = 0;
  for (final index in missing) {
    if (index < 0 || index >= openQspAprsMaxFragments) {
      throw ArgumentError.value(index, 'missing', 'fragment index out of range');
    }
    mask |= 1 << index;
  }
  if (mask == 0) {
    throw ArgumentError.value(missing, 'missing', 'must not be empty');
  }
  return 'Q1N:$transactionId:${mask.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

void _validateTransactionId(String value) {
  if (!RegExp(r'^[0-9A-Z]{3}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'transactionId',
      'must be 3 uppercase base36 characters',
    );
  }
}

final class _SentBurst {
  _SentBurst(this.total, this.lastSeen);
  final int total;
  DateTime lastSeen;
  final Map<int, List<int>> fragments = {};
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
  final Set<int> received = {};
  Timer? timer;
}
