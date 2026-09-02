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

  test('starts with no forced digipeater', () {
    expect(registry.knownIgates, isEmpty);
    expect(registry.forcedIgate, isNull);
    expect(registry.forcedPath, isEmpty);
  });

  test('learns concrete repeated digipeaters and ignores WIDE aliases', () {
    final frame = Ax25Frame(
      destination: const Ax25Address(
        callsign: 'OQSP',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: const Ax25Address(
        callsign: 'EA3GNU',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      digipeaters: const [
        Ax25Address(
          callsign: 'EB3EHJ',
          ssid: 14,
          hasBeenRepeated: true,
          isLast: false,
        ),
        Ax25Address(
          callsign: 'WIDE1',
          ssid: 0,
          hasBeenRepeated: true,
          isLast: true,
        ),
      ],
      control: 0x03,
      pid: 0xf0,
      information: ':OQSP     :Q2:069:00/05:AAAA'.codeUnits,
    );

    final packet = const AprsParser().parse(frame);

    expect(packet, isNotNull);
    expect(registry.knownIgates, contains('EB3EHJ-14'));
    expect(registry.knownIgates, isNot(contains('WIDE1')));
  });

  test('forced selection exposes a one-station AX.25 path', () async {
    registry.observe('ED3YAB-14');
    await registry.setForced('ED3YAB-14');

    expect(registry.forcedIgate, 'ED3YAB-14');
    expect(registry.forcedPath, hasLength(1));
    expect(registry.forcedPath.single.callsign, 'ED3YAB');
    expect(registry.forcedPath.single.ssid, 14);
  });

  test('known digipeaters and forced selection survive reload', () async {
    registry.observe('EB3EHJ-14');
    await registry.setForced('EB3EHJ-14');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'tnc.aprs.knownIgates': <String>['EB3EHJ-14', 'ED3YAB-14'],
      'tnc.aprs.forcedIgate': 'ED3YAB-14',
    });
    await registry.resetForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tnc.aprs.knownIgates': <String>['EB3EHJ-14', 'ED3YAB-14'],
      'tnc.aprs.forcedIgate': 'ED3YAB-14',
    });
    await registry.load();

    expect(registry.knownIgates, const ['EB3EHJ-14', 'ED3YAB-14']);
    expect(registry.forcedIgate, 'ED3YAB-14');
  });
}
