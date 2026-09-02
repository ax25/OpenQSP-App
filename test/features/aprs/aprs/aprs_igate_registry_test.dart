import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_igate_registry.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_parser.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
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
      digipeaters: const [],
      control: 0x03,
      pid: 0xf0,
      information:
          '}OQSP>APOQSP,TCPIP*,qAC,EA3IK-6::EA3GNU-5 :Q1:ABC:00/01:AUYABQEAAAAP{00'
              .codeUnits,
    );

    final packet = const AprsParser().parse(frame);

    expect(packet, isNotNull);
    expect(registry.knownIgates, contains('EA3IK-6'));
  });

  test('forced selection exposes a one-station AX.25 path', () async {
    registry.observe('EA3IK-6');
    await registry.setForced('EA3IK-6');

    expect(registry.forcedIgate, 'EA3IK-6');
    expect(registry.forcedPath, hasLength(1));
    expect(registry.forcedPath.single.callsign, 'EA3IK');
    expect(registry.forcedPath.single.ssid, 6);
  });

  test('known iGates and forced selection survive reload', () async {
    registry.observe('EA3IK-6');
    await registry.setForced('EA3IK-6');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'tnc.aprs.knownIgates': <String>['EA3IK-6', 'EA3ABC-10'],
      'tnc.aprs.forcedIgate': 'EA3ABC-10',
    });
    await registry.resetForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tnc.aprs.knownIgates': <String>['EA3IK-6', 'EA3ABC-10'],
      'tnc.aprs.forcedIgate': 'EA3ABC-10',
    });
    await registry.load();

    expect(registry.knownIgates, const ['EA3ABC-10', 'EA3IK-6']);
    expect(registry.forcedIgate, 'EA3ABC-10');
  });
}
