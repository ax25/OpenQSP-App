import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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
    final encoded = result.takeBytes();
    assert(() {
      debugPrint('KISS frame encoded: ${encoded.length} bytes');
      return true;
    }());
    return encoded;
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
