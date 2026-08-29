import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ax25/ax25_decoder.dart';
import '../ax25/ax25_frame.dart';
import '../data/bluetooth_tnc_service.dart';
import '../data/bluetooth_tnc_storage.dart';
import '../domain/tnc_connection_state.dart';
import '../domain/tnc_device.dart';
import '../kiss/kiss_encoder.dart';
import '../kiss/kiss_frame.dart';
import '../kiss/kiss_transport.dart';

class TncSettingsController extends ChangeNotifier {
  TncSettingsController({required this.storage, required this.service}) {
    _kissTransport = KissTransport(service);
    _byteSubscription = service.incomingBytes.listen((bytes) {
      rxBytes += bytes.length;
      _notify();
    });
    _frameSubscription = _kissTransport.frames.listen((frame) {
      rxKissFrames++;
      _activity.insert(0, 'RX  ${_hex(const KissEncoder().encode(frame))}');
      if (_activity.length > 10) _activity.removeLast();
      if (frame.port == 0 && frame.command == 0) _decodeAx25(frame.payload);
      _notify();
    });
    _connectionLossSubscription = service.unexpectedDisconnections.listen((id) {
      if (id != service.activeConnectionId ||
          state != TncConnectionState.connected) {
        return;
      }
      _setError(TncFailure.connectionFailed);
    });
  }

  final BluetoothTncStorage storage;
  final BluetoothTncService service;
  TncConnectionState state = TncConnectionState.loading;
  TncDevice? device;
  TncFailure? failure;
  bool _disposed = false;
  late final KissTransport _kissTransport;
  late final StreamSubscription<List<int>> _byteSubscription;
  late final StreamSubscription<KissFrame> _frameSubscription;
  late final StreamSubscription<int> _connectionLossSubscription;
  int rxBytes = 0;
  int rxKissFrames = 0;
  int txKissFrames = 0;
  final List<String> _activity = [];
  final List<String> _ax25Activity = [];
  static const Ax25Decoder _ax25Decoder = Ax25Decoder();
  int rxAx25Frames = 0;
  int ax25DecodeErrors = 0;

  List<String> get kissActivity => List.unmodifiable(_activity);
  List<String> get ax25Activity => List.unmodifiable(_ax25Activity);
  bool get kissReady => state == TncConnectionState.connected;

  static String _hex(Iterable<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  void _decodeAx25(List<int> payload) {
    try {
      final frame = _ax25Decoder.decode(payload);
      rxAx25Frames++;
      _ax25Activity.insert(0, _describeAx25(frame));
      if (_ax25Activity.length > 10) _ax25Activity.removeLast();
      if (kDebugMode) {
        debugPrint(
          'AX.25 frame decoded: ${frame.source} > ${frame.destination}',
        );
      }
    } on Ax25DecodeException catch (error) {
      ax25DecodeErrors++;
      if (kDebugMode) debugPrint('AX.25 decode error: ${error.message}');
    }
  }

  static String _describeAx25(Ax25Frame frame) {
    final via = frame.digipeaters.isEmpty
        ? '-'
        : frame.digipeaters.map((address) => address.pathText).join(',');
    final pid = frame.pid == null
        ? '-'
        : frame.pid!.toRadixString(16).padLeft(2, '0').toUpperCase();
    final control = frame.control
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return 'SRC: ${frame.source}  DST: ${frame.destination}\n'
        'VIA: $via  CTRL: $control  PID: $pid\n'
        'INFO: ${frame.informationText}';
  }

  Future<void> sendKiss(KissFrame frame) async {
    await _kissTransport.send(frame);
    txKissFrames++;
    _activity.insert(0, 'TX  ${_hex(const KissEncoder().encode(frame))}');
    if (_activity.length > 10) _activity.removeLast();
    _notify();
  }

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
    unawaited(_byteSubscription.cancel());
    unawaited(_frameSubscription.cancel());
    unawaited(_connectionLossSubscription.cancel());
    unawaited(_kissTransport.close());
    unawaited(service.disconnect());
    super.dispose();
  }
}
