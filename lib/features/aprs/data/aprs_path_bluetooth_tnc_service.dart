import '../aprs/aprs_packet.dart';
import '../aprs/aprs_parser.dart';
import '../ax25/ax25_decoder.dart';
import '../ax25/ax25_encoder.dart';
import '../domain/tnc_device.dart';
import '../kiss/kiss_decoder.dart';
import '../kiss/kiss_encoder.dart';
import '../kiss/kiss_frame.dart';
import 'aprs_path_storage.dart';
import 'bluetooth_tnc_service.dart';

/// Rewrites outbound OpenQSP APRS UI frames with the configured RF path.
/// All unrelated KISS traffic is passed through unchanged.
final class AprsPathBluetoothTncService implements BluetoothTncService {
  AprsPathBluetoothTncService(
    this.delegate, {
    AprsPathStorage? storage,
  }) : storage = storage ?? PreferencesAprsPathStorage();

  final BluetoothTncService delegate;
  final AprsPathStorage storage;

  static const _kissEncoder = KissEncoder();
  static const _ax25Decoder = Ax25Decoder();
  static const _ax25Encoder = Ax25Encoder();
  static const _aprsParser = AprsParser();

  @override
  Stream<List<int>> get incomingBytes => delegate.incomingBytes;

  @override
  Stream<int> get unexpectedDisconnections => delegate.unexpectedDisconnections;

  @override
  int? get activeConnectionId => delegate.activeConnectionId;

  @override
  Future<List<TncDevice>> bondedDevices() => delegate.bondedDevices();

  @override
  Future<void> connect(TncDevice device) => delegate.connect(device);

  @override
  Future<void> disconnect() => delegate.disconnect();

  @override
  Future<void> sendBytes(List<int> data) async {
    final rewritten = await _rewriteOpenQspPath(data);
    await delegate.sendBytes(rewritten);
  }

  Future<List<int>> _rewriteOpenQspPath(List<int> data) async {
    final kiss = _decodeSingleKiss(data);
    if (kiss == null || kiss.port != 0 || kiss.command != 0) return data;

    try {
      final ax25 = _ax25Decoder.decode(kiss.payload);
      final aprs = _aprsParser.parse(ax25);
      if (aprs is! AprsTextMessage || !aprs.isForOpenQsp) return data;

      final mode = await storage.read();
      final payload = _ax25Encoder.encodeUi(
        destination: ax25.destination,
        source: ax25.source,
        digipeaters: mode.digipeaters,
        information: ax25.information,
      );
      return _kissEncoder.encode(
        KissFrame(port: kiss.port, command: kiss.command, payload: payload),
      );
    } on Object {
      return data;
    }
  }

  KissFrame? _decodeSingleKiss(List<int> data) {
    final decoder = KissDecoder();
    KissFrame? result;
    final subscription = decoder.frames.listen((frame) => result ??= frame);
    decoder.add(data);
    subscription.cancel();
    decoder.close();
    return result;
  }
}
