import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_decoder.dart';

List<int> address(
  String callsign, {
  int ssid = 0,
  bool last = false,
  bool repeated = false,
}) {
  final padded = callsign.padRight(6);
  return [
    ...padded.codeUnits.map((character) => character << 1),
    0x60 | (repeated ? 0x80 : 0) | (ssid << 1) | (last ? 1 : 0),
  ];
}

List<int> uiFrame({
  List<List<int>>? addresses,
  List<int> information = const [],
}) => [
  ...(addresses ?? [address('APN382'), address('EA3GNU', ssid: 5, last: true)])
      .expand((value) => value),
  0x03,
  0xf0,
  ...information,
];

void main() {
  const decoder = Ax25Decoder();

  group('address decode', () {
    test('decodes callsign, padding, SSID and extension bit', () {
      final plain = decoder.decodeAddress(address('EA3GNU'));
      final withSsid = decoder.decodeAddress(
        address('EA3GNU', ssid: 5, last: true),
      );

      expect(plain.callsign, 'EA3GNU');
      expect(plain.ssid, 0);
      expect(plain.toString(), 'EA3GNU');
      expect(plain.isLast, isFalse);
      expect(withSsid.toString(), 'EA3GNU-5');
      expect(withSsid.isLast, isTrue);
    });

    test('trims trailing spaces and preserves digipeater H bit', () {
      final digi = decoder.decodeAddress(
        address('WIDE1', ssid: 1, repeated: true),
      );
      expect(digi.callsign, 'WIDE1');
      expect(digi.hasBeenRepeated, isTrue);
      expect(digi.pathText, 'WIDE1-1*');
    });
  });

  group('frame decode', () {
    test('decodes destination and source with no digipeaters', () {
      final frame = decoder.decode(uiFrame());
      expect(frame.destination.toString(), 'APN382');
      expect(frame.source.toString(), 'EA3GNU-5');
      expect(frame.digipeaters, isEmpty);
    });

    test('decodes one digipeater', () {
      final frame = decoder.decode(
        uiFrame(
          addresses: [
            address('APN382'),
            address('EA3GNU', ssid: 5),
            address('WIDE1', ssid: 1, last: true, repeated: true),
          ],
        ),
      );
      expect(frame.digipeaters.single.pathText, 'WIDE1-1*');
    });

    test('decodes realistic APRS UI fixture with multiple digipeaters', () {
      // EA3XXX-9 > APN382 via WIDE1-1*,WIDE2-1
      final frame = decoder.decode(
        uiFrame(
          addresses: [
            address('APN382'),
            address('EA3XXX', ssid: 9),
            address('WIDE1', ssid: 1, repeated: true),
            address('WIDE2', ssid: 1, last: true),
          ],
          information: '!4123.45N/00203.21E'.codeUnits,
        ),
      );
      expect(frame.source.toString(), 'EA3XXX-9');
      expect(frame.destination.toString(), 'APN382');
      expect(frame.digipeaters.map((digi) => digi.pathText), [
        'WIDE1-1*',
        'WIDE2-1',
      ]);
      expect(frame.control, 0x03);
      expect(frame.pid, 0xf0);
      expect(frame.isUiFrame, isTrue);
      expect(frame.informationText, '!4123.45N/00203.21E');
    });

    test('accepts empty and arbitrary information safely', () {
      expect(decoder.decode(uiFrame()).information, isEmpty);
      final frame = decoder.decode(uiFrame(information: [0, 0xff, 0x41]));
      expect(frame.information, [0, 0xff, 0x41]);
      expect(frame.informationText, '..A');
    });

    test('retains a non-UI control without assuming a PID', () {
      final bytes = [
        ...address('APN382'),
        ...address('EA3GNU', last: true),
        0x2f,
        0xaa,
      ];
      final frame = decoder.decode(bytes);
      expect(frame.control, 0x2f);
      expect(frame.pid, isNull);
      expect(frame.information, [0xaa]);
    });
  });

  group('controlled corruption handling', () {
    test('rejects too-short and incomplete address fields', () {
      expect(() => decoder.decode([]), throwsA(isA<Ax25DecodeException>()));
      expect(
        () => decoder.decode([...address('APN382'), ...address('EA3GNU').take(6)]),
        throwsA(isA<Ax25DecodeException>()),
      );
    });

    test('rejects missing extension bit and excessive addresses', () {
      expect(
        () => decoder.decode([
          ...List.generate(10, (_) => address('WIDE1')).expand((a) => a),
          0x03,
          0xf0,
        ]),
        throwsA(isA<Ax25DecodeException>()),
      );
    });

    test('rejects missing control and missing UI PID', () {
      final fields = [...address('APN382'), ...address('EA3GNU', last: true)];
      expect(() => decoder.decode(fields), throwsA(isA<Ax25DecodeException>()));
      expect(
        () => decoder.decode([...fields, 0x03]),
        throwsA(isA<Ax25DecodeException>()),
      );
    });

    test('rejects invalid callsign bytes without leaking other errors', () {
      final corrupt = uiFrame()..[0] = 0xff;
      expect(() => decoder.decode(corrupt), throwsA(isA<Ax25DecodeException>()));
      for (final bytes in <List<int>>[
        [1],
        List.filled(30, 0xff),
        List.filled(100, 0),
      ]) {
        expect(() => decoder.decode(bytes), throwsA(isA<Ax25DecodeException>()));
      }
    });
  });
}
