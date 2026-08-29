import 'ax25_address.dart';
import 'ax25_frame.dart';

final class Ax25DecodeException implements Exception {
  const Ax25DecodeException(this.message);
  final String message;

  @override
  String toString() => 'Ax25DecodeException: $message';
}

/// Decodes the AX.25 bytes carried by a KISS data command.
///
/// KISS transfers the AX.25 frame between host and TNC without HDLC flags or
/// FCS. Consequently every byte after control/PID is information; this decoder
/// intentionally neither removes nor calculates a CRC.
final class Ax25Decoder {
  const Ax25Decoder({this.maximumAddresses = 10});

  final int maximumAddresses;

  Ax25Frame decode(List<int> bytes) {
    if (bytes.length < 14) {
      throw const Ax25DecodeException('Frame is too short for two addresses');
    }

    final addresses = <Ax25Address>[];
    var offset = 0;
    while (true) {
      if (addresses.length == maximumAddresses) {
        throw Ax25DecodeException(
          'Address field exceeds the limit of $maximumAddresses',
        );
      }
      if (offset + 7 > bytes.length) {
        throw const Ax25DecodeException('Incomplete address field');
      }
      final address = decodeAddress(bytes.sublist(offset, offset + 7));
      addresses.add(address);
      offset += 7;
      if (address.isLast) break;
    }
    if (addresses.length < 2) {
      throw const Ax25DecodeException('Destination and source are required');
    }
    if (offset >= bytes.length) {
      throw const Ax25DecodeException('Missing control byte');
    }

    final control = bytes[offset++] & 0xff;
    int? pid;
    // This RX-only first version extracts PID for the APRS UI frame type. Other
    // controls are retained without guessing their complete AX.25 semantics.
    if (control == 0x03) {
      if (offset >= bytes.length) {
        throw const Ax25DecodeException('UI frame is missing its PID');
      }
      pid = bytes[offset++] & 0xff;
    }

    return Ax25Frame(
      destination: addresses[0],
      source: addresses[1],
      digipeaters: addresses.skip(2).toList(),
      control: control,
      pid: pid,
      information: bytes.skip(offset).map((byte) => byte & 0xff).toList(),
    );
  }

  Ax25Address decodeAddress(List<int> bytes) {
    if (bytes.length != 7) {
      throw const Ax25DecodeException('An address must contain seven bytes');
    }
    final decoded = <int>[];
    var paddingStarted = false;
    for (var index = 0; index < 6; index++) {
      final encoded = bytes[index];
      if (encoded < 0 || encoded > 0xff || encoded.isOdd) {
        throw const Ax25DecodeException('Invalid shifted callsign byte');
      }
      final character = encoded >> 1;
      if (character == 0x20) {
        paddingStarted = true;
        continue;
      }
      final valid = character >= 0x30 && character <= 0x39 ||
          character >= 0x41 && character <= 0x5a;
      if (!valid || paddingStarted) {
        throw const Ax25DecodeException('Invalid callsign character or padding');
      }
      decoded.add(character);
    }
    if (decoded.isEmpty) {
      throw const Ax25DecodeException('Callsign cannot be empty');
    }
    final flags = bytes[6];
    if (flags < 0 || flags > 0xff) {
      throw const Ax25DecodeException('Invalid SSID byte');
    }
    return Ax25Address(
      callsign: String.fromCharCodes(decoded),
      ssid: (flags >> 1) & 0x0f,
      hasBeenRepeated: flags & 0x80 != 0,
      isLast: flags & 0x01 != 0,
    );
  }
}
