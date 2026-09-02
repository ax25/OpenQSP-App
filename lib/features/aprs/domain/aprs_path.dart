import '../ax25/ax25_address.dart';

enum AprsPathMode { direct, oneHop, twoHops }

extension AprsPathModeDetails on AprsPathMode {
  String get label => switch (this) {
    AprsPathMode.direct => 'Sin salto',
    AprsPathMode.oneHop => '1 salto',
    AprsPathMode.twoHops => '2 saltos',
  };

  String get pathLabel => switch (this) {
    AprsPathMode.direct => 'Directo',
    AprsPathMode.oneHop => 'WIDE1-1',
    AprsPathMode.twoHops => 'WIDE1-1,WIDE2-1',
  };

  List<Ax25Address> get digipeaters => switch (this) {
    AprsPathMode.direct => const [],
    AprsPathMode.oneHop => const [
      Ax25Address(
        callsign: 'WIDE1',
        ssid: 1,
        hasBeenRepeated: false,
        isLast: false,
      ),
    ],
    AprsPathMode.twoHops => const [
      Ax25Address(
        callsign: 'WIDE1',
        ssid: 1,
        hasBeenRepeated: false,
        isLast: false,
      ),
      Ax25Address(
        callsign: 'WIDE2',
        ssid: 1,
        hasBeenRepeated: false,
        isLast: false,
      ),
    ],
  };
}
