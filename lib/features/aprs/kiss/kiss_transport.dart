import 'dart:async';

import '../data/bluetooth_tnc_service.dart';
import 'kiss_decoder.dart';
import 'kiss_encoder.dart';
import 'kiss_frame.dart';

/// Bridges the byte-only Bluetooth service to KISS, without interpreting data.
final class KissTransport {
  KissTransport(this._bluetooth, {KissEncoder encoder = const KissEncoder()})
    : _encoder = encoder {
    _bytesSubscription = _bluetooth.incomingBytes.listen(_decoder.add);
  }

  final BluetoothTncService _bluetooth;
  final KissEncoder _encoder;
  final KissDecoder _decoder = KissDecoder();
  late final StreamSubscription<List<int>> _bytesSubscription;

  Stream<KissFrame> get frames => _decoder.frames;

  Future<void> send(KissFrame frame) =>
      _bluetooth.sendBytes(_encoder.encode(frame));

  Future<void> close() async {
    await _bytesSubscription.cancel();
    await _decoder.close();
  }
}
