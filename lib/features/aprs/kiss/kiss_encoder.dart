import 'dart:typed_data';

import 'kiss_frame.dart';

const kissFend = 0xc0;
const kissFesc = 0xdb;
const kissTfend = 0xdc;
const kissTfesc = 0xdd;

final class KissEncoder {
  const KissEncoder();

  Uint8List encode(KissFrame frame) {
    final result = BytesBuilder(copy: false)..addByte(kissFend);
    _addEscaped(result, frame.commandByte);
    for (final byte in frame.payload) {
      _addEscaped(result, byte);
    }
    result.addByte(kissFend);
    return result.takeBytes();
  }

  void _addEscaped(BytesBuilder target, int byte) {
    switch (byte) {
      case kissFend:
        target.add([kissFesc, kissTfend]);
        break;
      case kissFesc:
        target.add([kissFesc, kissTfesc]);
        break;
      default:
        target.addByte(byte);
    }
  }
}
