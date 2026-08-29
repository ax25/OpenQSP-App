import '../ax25/ax25_frame.dart';
import 'aprs_packet.dart';

final class AprsParser {
  const AprsParser();

  /// Returns null only when [frame] is outside APRS's AX.25 UI/F0 envelope.
  AprsPacket? parse(Ax25Frame frame) {
    if (!frame.isUiFrame || frame.pid != 0xf0) return null;
    final bytes = frame.information;
    if (bytes.isEmpty) {
      return AprsInvalid(frame, reason: 'empty information');
    }
    if (bytes.first != 0x3a) {
      return AprsUnknown(
        frame,
        typeIdentifier: _printable(bytes.first)
            ? String.fromCharCode(bytes.first)
            : '.',
      );
    }
    // ':' + exactly nine addressee bytes + ':' + at least one body byte.
    if (bytes.length < 12) {
      return AprsInvalid(frame, reason: 'message is too short');
    }
    if (bytes[10] != 0x3a) {
      return AprsInvalid(frame, reason: 'missing message separator');
    }
    final addressBytes = bytes.sublist(1, 10);
    final bodyBytes = bytes.sublist(11);
    if (addressBytes.any((byte) => !_printable(byte)) ||
        bodyBytes.any((byte) => !_printable(byte))) {
      return AprsInvalid(frame, reason: 'message contains non-printable bytes');
    }
    final paddedAddressee = String.fromCharCodes(addressBytes);
    final addressee = paddedAddressee.replaceFirst(RegExp(r' +$'), '');
    if (addressee.isEmpty || addressee.contains(' ')) {
      return AprsInvalid(frame, reason: 'invalid addressee');
    }
    final body = String.fromCharCodes(bodyBytes);
    if (body.startsWith('ack')) {
      final id = body.substring(3);
      return _validId(id) && body == 'ack$id'
          ? AprsAck(frame, messageAddressee: addressee, messageId: id)
          : AprsInvalid(frame, reason: 'invalid ACK message ID');
    }
    if (body.startsWith('rej')) {
      final id = body.substring(3);
      return _validId(id) && body == 'rej$id'
          ? AprsReject(frame, messageAddressee: addressee, messageId: id)
          : AprsInvalid(frame, reason: 'invalid REJ message ID');
    }

    final marker = body.lastIndexOf('{');
    if (marker == -1) {
      return AprsTextMessage(frame, messageAddressee: addressee, text: body);
    }
    final id = body.substring(marker + 1);
    if (!_validId(id)) {
      return AprsInvalid(frame, reason: 'invalid message ID');
    }
    return AprsTextMessage(
      frame,
      messageAddressee: addressee,
      text: body.substring(0, marker),
      messageId: id,
    );
  }

  static bool _printable(int byte) => byte >= 0x20 && byte <= 0x7e;

  // APRS message numbers are one to five printable alphanumeric characters.
  static bool _validId(String value) =>
      RegExp(r'^[A-Za-z0-9]{1,5}$').hasMatch(value);
}
