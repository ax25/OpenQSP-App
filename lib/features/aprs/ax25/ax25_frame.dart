import 'dart:typed_data';

import 'ax25_address.dart';

/// A received AX.25 frame whose information remains available byte-for-byte,
/// including when a higher layer interprets it as APRS.
final class Ax25Frame {
  Ax25Frame({
    required this.destination,
    required this.source,
    required List<Ax25Address> digipeaters,
    required this.control,
    required this.pid,
    required List<int> information,
  }) : digipeaters = List.unmodifiable(digipeaters),
       information = Uint8List.fromList(information);

  final Ax25Address destination;
  final Ax25Address source;
  final List<Ax25Address> digipeaters;
  final int control;
  final int? pid;
  final Uint8List information;

  bool get isUiFrame => control == 0x03;

  /// ASCII-safe diagnostic rendering; arbitrary RF bytes never cause a codec
  /// exception and non-printable bytes are represented by dots.
  String get informationText => String.fromCharCodes(
    information.map((byte) => byte >= 0x20 && byte <= 0x7e ? byte : 0x2e),
  );
}
