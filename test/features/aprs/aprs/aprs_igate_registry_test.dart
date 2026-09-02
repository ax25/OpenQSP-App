import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_igate_registry.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_parser.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_decoder.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final registry = AprsIgateRegistry.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await registry.resetForTesting();
  });

  test('starts with no forced iGate', () {
    expect(registry.knownIgates, isEmpty);
    expect(registry.forcedIgate, isNull);
    expect(registry.forcedPath, isEmpty);
  });

  test('learns iGate from valid third-party APRS traffic', () {
    final frame = Ax25Frame(
      destination: const Ax25Address(
        callsign: 'APLRG1',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: const Ax25Address(
        callsign: 'EA3IK',
        ssid: 6,
        hasBeenRepeated: false,
        isLast: true,
      ),
      control: 0x03,
      pid: 0xf0,
      information: '}OQSP>APOQSP,TCPIP*::EA3GNU  :hello'.codeUnits,
    );

    final packet = const AprsParser().parse(frame);

    expect(packet, isNotNull);
    expect(registry.knownIgates, contains('EA3IK-6'));
  });

  test('forced iGate becomes the default outgoing AX.25 path', () async {
    registry.observe('EA3IK-6');
    await registry.setForced('EA3IK-6');

    final encoded = const Ax25Encoder().encodeUi(
      destination: const Ax25Address(
        callsign: 'APOQSP',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: const Ax25Address(
        callsign: 'EA3GNU',
        ssid: 5,
        hasBeenRepeated: false,
        isLast: true,
      ),
      information: ':OQSP     :test'.codeUnits,
    );
    final decoded = const Ax25Decoder().decode(encoded);

    expect(decoded.digipeaters, hasLength(1));
    expect(decoded.digipeaters.single.callsign, 'EA3IK');
    expect(decoded.digipeaters.single.ssid, 6);
  });

  test('explicit path still overrides forced iGate', () async {
    registry.observe('EA3IK-6');
    await registry.setForced('EA3IK-6');

    final encoded = const Ax25Encoder().encodeUi(
      destination: const Ax25Address(
        callsign: 'APOQSP',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: const Ax25Address(
        callsign: 'EA3GNU',
        ssid: 5,
        hasBeenRepeated: false,
        isLast: true,
      ),
      digipeaters: const [
        Ax25Address(
          callsign: 'WIDE1',
          ssid: 1,
          hasBeenRepeated: false,
          isLast: true,
        ),
      ],
      information: ':OQSP     :test'.codeUnits,
    );
    final decoded = const Ax25Decoder().decode(encoded);

    expect(decoded.digipeaters, hasLength(1));
    expect(decoded.digipeaters.single.callsign, 'WIDE1');
    expect(decoded.digipeaters.single.ssid, 1);
  });
}
