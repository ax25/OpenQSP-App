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

  tearDown(() async {
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

  test('known digipeaters and forced selection survive reload while fresh',
      () async {
    final now = DateTime.now().toUtc();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tnc.aprs.knownIgates': <String>['EB3EHJ-14', 'ED3YAB-14'],
      'tnc.aprs.forcedIgate': 'ED3YAB-14',
      'tnc.aprs.digipeaterLastSeen': <String>[
        'EB3EHJ-14|${now.millisecondsSinceEpoch}',
        'ED3YAB-14|${now.millisecondsSinceEpoch}',
      ],
    });
    await registry.load();

    expect(registry.knownIgates, const ['EB3EHJ-14', 'ED3YAB-14']);
    expect(registry.forcedIgate, 'ED3YAB-14');
  });

  test('digipeater expires after 15 minutes without reception', () async {
    registry.observe('EB3EHJ-14');
    final future = DateTime.now().toUtc().add(const Duration(minutes: 16));

    await registry.expireNowForTesting(future);

    expect(registry.knownIgates, isNot(contains('EB3EHJ-14')));
  });

  test('selected digipeater never expires', () async {
    registry.observe('ED3YAB-14');
    await registry.setForced('ED3YAB-14');
    final future = DateTime.now().toUtc().add(const Duration(hours: 1));

    await registry.expireNowForTesting(future);

    expect(registry.knownIgates, contains('ED3YAB-14'));
    expect(registry.forcedIgate, 'ED3YAB-14');
  });

  test('clear list preserves selected digipeater', () async {
    registry.observe('EB3EHJ-14');
    registry.observe('ED3YAB-14');
    await registry.setForced('ED3YAB-14');

    await registry.clearDiscovered();

    expect(registry.knownIgates, const ['ED3YAB-14']);
    expect(registry.forcedIgate, 'ED3YAB-14');
    expect(registry.hasClearableDigipeaters, isFalse);
  });
}
