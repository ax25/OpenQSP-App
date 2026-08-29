/// One decoded seven-byte AX.25 address.
final class Ax25Address {
  const Ax25Address({
    required this.callsign,
    required this.ssid,
    required this.hasBeenRepeated,
    required this.isLast,
  });

  final String callsign;
  final int ssid;
  final bool hasBeenRepeated;
  final bool isLast;

  @override
  String toString() => ssid == 0 ? callsign : '$callsign-$ssid';

  String get pathText => '${toString()}${hasBeenRepeated ? '*' : ''}';
}
