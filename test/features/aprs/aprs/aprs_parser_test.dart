import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_packet.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_parser.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_frame.dart';

const destination = Ax25Address(
  callsign: 'APRS',
  ssid: 0,
  hasBeenRepeated: false,
  isLast: false,
);
const source = Ax25Address(
  callsign: 'EA3GNU',
  ssid: 5,
  hasBeenRepeated: false,
  isLast: true,
);

Ax25Frame frame(
  List<int> information, {
  int control = 0x03,
  int? pid = 0xf0,
  Ax25Address frameSource = source,
}) => Ax25Frame(
  destination: destination,
  source: frameSource,
  digipeaters: const [],
  control: control,
  pid: pid,
  information: information,
);

void main() {
  const parser = AprsParser();

  group('APRS messages', () {
    test('decodes OQSP message without message ID', () {
      final packet = parser.parse(frame(':OQSP     :HELLO'.codeUnits));
      expect(packet, isA<AprsTextMessage>());
      final message = packet! as AprsTextMessage;
      expect(message.addressee, 'OQSP');
      expect(message.text, 'HELLO');
      expect(message.messageId, isNull);
      expect(message.isForOpenQsp, isTrue);
      expect(message.igate, isNull);
      expect(message.frame.source.toString(), 'EA3GNU-5');
      expect(message.frame.information, ':OQSP     :HELLO'.codeUnits);
    });

    test('extracts an ID and trims the nine-character addressee', () {
      final oqsp = parser.parse(frame(':OQSP     :HELLO{12'.codeUnits));
      final other = parser.parse(frame(':EA3GNU   :TEST'.codeUnits));
      final oqspMessage = oqsp! as AprsTextMessage;
      expect(oqspMessage.text, 'HELLO');
      expect(oqspMessage.messageId, '12');
      expect((other! as AprsTextMessage).addressee, 'EA3GNU');
    });

    test('recognizes lowercase ACK and REJ with different IDs', () {
      final ack = parser.parse(frame(':OQSP     :ackA1'.codeUnits));
      final reject = parser.parse(frame(':OQSP     :rej12'.codeUnits));
      expect(ack, isA<AprsAck>());
      expect((ack! as AprsAck).messageId, 'A1');
      expect(reject, isA<AprsReject>());
      expect((reject! as AprsReject).messageId, '12');
    });
  });

  group('third-party traffic', () {
    test('unwraps an IGate packet and exposes the logical APRS source', () {
      const igate = Ax25Address(
        callsign: 'OQSPK',
        ssid: 1,
        hasBeenRepeated: false,
        isLast: true,
      );
      final packet = parser.parse(
        frame(
          '}OQSP>APOQSP,TCPIP*,qAC,OQSPK-1::EA3GNU-5 :Q1:ABC:00/01:AUYABQEAAAAP{00'
              .codeUnits,
          frameSource: igate,
        ),
      );

      expect(packet, isA<AprsTextMessage>());
      final message = packet! as AprsTextMessage;
      expect(message.frame.source.toString(), 'OQSP');
      expect(message.frame.destination.toString(), 'APOQSP');
      expect(message.igate.toString(), 'OQSPK-1');
      expect(message.addressee, 'EA3GNU-5');
      expect(message.text, 'Q1:ABC:00/01:AUYABQEAAAAP');
      expect(message.messageId, '00');
    });

    test('rejects malformed and nested third-party packets without throwing', () {
      for (final text in [
        '}',
        '}OQSPAPOQSP::EA3GNU   :HELLO',
        '}OQSP>APOQSP:',
        '}OQSP>APOQSP:}OQSP>APOQSP::EA3GNU   :HELLO',
      ]) {
        expect(parser.parse(frame(text.codeUnits)), isA<AprsInvalid>());
      }
    });
  });

  group('controlled malformed input', () {
    test('rejects empty, short, missing separator and non-printable messages', () {
      for (final information in <List<int>>[
        [],
        ':OQSP'.codeUnits,
        ':OQSP      HELLO'.codeUnits,
        [...':OQSP     :HE'.codeUnits, 0],
      ]) {
        expect(parser.parse(frame(information)), isA<AprsInvalid>());
      }
    });

    test('rejects empty or malformed message IDs, ACKs and REJs', () {
      for (final text in [
        ':OQSP     :HELLO{',
        ':OQSP     :HELLO{123456',
        ':OQSP     :ack',
        ':OQSP     :rej',
      ]) {
        expect(parser.parse(frame(text.codeUnits)), isA<AprsInvalid>());
      }
    });

    test('retains non-message APRS as unknown without interpreting it', () {
      final packet = parser.parse(frame('!4123.45N/00203.21E'.codeUnits));
      expect(packet, isA<AprsUnknown>());
      expect((packet! as AprsUnknown).typeIdentifier, '!');
    });

    test('ignores non-UI and non-F0 AX.25 frames', () {
      expect(parser.parse(frame('x'.codeUnits, control: 0x2f)), isNull);
      expect(parser.parse(frame('x'.codeUnits, pid: 0xcf)), isNull);
    });
  });
}
