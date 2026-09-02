import 'dart:typed_data';

import 'ax25_address.dart';

final class Ax25EncodeException implements Exception {
  const Ax25EncodeException(this.message);
  final String message;
}

/// Encodes an AX.25 UI frame as expected by KISS (without flags or FCS).
final class Ax25Encoder {
  const Ax25Encoder();

  Uint8List encodeUi({
    required Ax25Address destination,
    required Ax25Address source,
    List<Ax25Address> digipeaters = const [],
    required List<int> information,
  }) {
    final addresses = [destination, source, ...digipeaters];
    final result = <int>[];
    for (var index = 0; index < addresses.length; index++) {
      result.addAll(_address(addresses[index], index == addresses.length - 1));
    }
    if (information.any((byte) => byte < 0 || byte > 255)) {
      throw const Ax25EncodeException('information contains a non-byte value');
    }
    result.addAll([0x03, 0xf0, ...information]);
    return Uint8List.fromList(result);
  }

  List<int> _address(Ax25Address address, bool last) {
    final call = address.callsign.toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{1,6}$').hasMatch(call) ||
        address.ssid < 0 ||
        address.ssid > 15) {
      throw const Ax25EncodeException('invalid AX.25 address');
    }
    return [
      ...call.padRight(6).codeUnits.map((byte) => byte << 1),
      0x60 |
          (address.hasBeenRepeated ? 0x80 : 0) |
          (address.ssid << 1) |
          (last ? 1 : 0),
    ];
  }
}
