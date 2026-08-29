import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_decoder.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';

void main() {
  test('UI frame round trips source, destination, path and information', () {
    const encoder = Ax25Encoder();
    final bytes = encoder.encodeUi(
      destination: const Ax25Address(callsign: 'OQSP', ssid: 0, hasBeenRepeated: false, isLast: false),
      source: const Ax25Address(callsign: 'EA3GNU', ssid: 5, hasBeenRepeated: false, isLast: false),
      digipeaters: const [Ax25Address(callsign: 'WIDE1', ssid: 1, hasBeenRepeated: true, isLast: true)],
      information: ':OQSP     :hello'.codeUnits,
    );
    final frame = const Ax25Decoder().decode(bytes);
    expect(frame.destination.toString(), 'OQSP');
    expect(frame.source.toString(), 'EA3GNU-5');
    expect(frame.digipeaters.single.pathText, 'WIDE1-1*');
    expect(frame.control, 0x03);
    expect(frame.pid, 0xf0);
    expect(frame.informationText, ':OQSP     :hello');
  });
}
