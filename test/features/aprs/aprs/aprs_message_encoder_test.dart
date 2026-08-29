import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_message_encoder.dart';

void main() {
  const encoder = AprsMessageEncoder();

  test('pads OQSP and encodes a Q1 body', () {
    expect(
      String.fromCharCodes(encoder.encode(addressee: 'OQSP', body: 'Q1:ABC:00/01:AQUAAA')),
      ':OQSP     :Q1:ABC:00/01:AQUAAA',
    );
  });

  test('accepts callsign addressees with and without SSID', () {
    expect(
      String.fromCharCodes(encoder.encode(addressee: 'EA3GNU', body: 'hello')),
      ':EA3GNU   :hello',
    );
    expect(
      String.fromCharCodes(
        encoder.encode(addressee: 'EA3GNU-5', body: 'hello'),
      ),
      ':EA3GNU-5 :hello',
    );
  });

  test('appends one optional APRS message ID', () {
    expect(
      String.fromCharCodes(encoder.encode(addressee: 'OQSP', body: 'Q1:ABC:00/01:AQUAAA', messageId: '12')),
      ':OQSP     :Q1:ABC:00/01:AQUAAA{12',
    );
  });

  test('rejects invalid fields', () {
    expect(() => encoder.encode(addressee: 'TOO-LONG-ID', body: 'x'), throwsA(isA<AprsMessageEncodeException>()));
    expect(() => encoder.encode(addressee: 'OQSP', body: 'x\n'), throwsA(isA<AprsMessageEncodeException>()));
    expect(() => encoder.encode(addressee: 'OQSP', body: 'x', messageId: '!'), throwsA(isA<AprsMessageEncodeException>()));
    for (final invalid in ['EA-16', 'EA--1', 'EA 1', '-5']) {
      expect(() => encoder.encode(addressee: invalid, body: 'x'), throwsA(isA<AprsMessageEncodeException>()));
    }
  });
}
