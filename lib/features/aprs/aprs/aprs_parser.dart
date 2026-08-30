import '../ax25/ax25_address.dart';
import '../ax25/ax25_frame.dart';
import 'aprs_packet.dart';

final class AprsParser {
  const AprsParser();

  /// Returns null only when [frame] is outside APRS's AX.25 UI/F0 envelope.
  AprsPacket? parse(Ax25Frame frame) =>
      _parseFrame(frame, allowThirdParty: true, igate: null);

  AprsPacket? _parseFrame(
    Ax25Frame frame, {
    required bool allowThirdParty,
    required Ax25Address? igate,
  }) {
    if (!frame.isUiFrame || frame.pid != 0xf0) return null;
    final bytes = frame.information;
    if (bytes.isEmpty) {
      return AprsInvalid(frame, igate: igate, reason: 'empty information');
    }
    if (bytes.first == 0x7d) {
      return allowThirdParty
          ? _parseThirdParty(frame, bytes.sublist(1))
          : AprsInvalid(
              frame,
              igate: igate,
              reason: 'nested third-party packet',
            );
    }
    if (bytes.first != 0x3a) {
      return AprsUnknown(
        frame,
        igate: igate,
        typeIdentifier: _printable(bytes.first)
            ? String.fromCharCode(bytes.first)
            : '.',
      );
    }
    // ':' + exactly nine addressee bytes + ':' + at least one body byte.
    if (bytes.length < 12) {
      return AprsInvalid(frame, igate: igate, reason: 'message is too short');
    }
    if (bytes[10] != 0x3a) {
      return AprsInvalid(
        frame,
        igate: igate,
        reason: 'missing message separator',
      );
    }
    final addressBytes = bytes.sublist(1, 10);
    final bodyBytes = bytes.sublist(11);
    if (addressBytes.any((byte) => !_printable(byte)) ||
        bodyBytes.any((byte) => !_printable(byte))) {
      return AprsInvalid(
        frame,
        igate: igate,
        reason: 'message contains non-printable bytes',
      );
    }
    final paddedAddressee = String.fromCharCodes(addressBytes);
    final addressee = paddedAddressee.replaceFirst(RegExp(r' +$'), '');
    if (addressee.isEmpty || addressee.contains(' ')) {
      return AprsInvalid(frame, igate: igate, reason: 'invalid addressee');
    }
    final body = String.fromCharCodes(bodyBytes);
    if (body.startsWith('ack')) {
      final id = body.substring(3);
      return _validId(id) && body == 'ack$id'
          ? AprsAck(
              frame,
              igate: igate,
              messageAddressee: addressee,
              messageId: id,
            )
          : AprsInvalid(
              frame,
              igate: igate,
              reason: 'invalid ACK message ID',
            );
    }
    if (body.startsWith('rej')) {
      final id = body.substring(3);
      return _validId(id) && body == 'rej$id'
          ? AprsReject(
              frame,
              igate: igate,
              messageAddressee: addressee,
              messageId: id,
            )
          : AprsInvalid(
              frame,
              igate: igate,
              reason: 'invalid REJ message ID',
            );
    }

    final marker = body.lastIndexOf('{');
    if (marker == -1) {
      return AprsTextMessage(
        frame,
        igate: igate,
        messageAddressee: addressee,
        text: body,
      );
    }
    final id = body.substring(marker + 1);
    if (!_validId(id)) {
      return AprsInvalid(frame, igate: igate, reason: 'invalid message ID');
    }
    return AprsTextMessage(
      frame,
      igate: igate,
      messageAddressee: addressee,
      text: body.substring(0, marker),
      messageId: id,
    );
  }

  AprsPacket _parseThirdParty(Ax25Frame outerFrame, List<int> bytes) {
    if (bytes.isEmpty ||
        bytes.length > 512 ||
        bytes.any((byte) => !_printable(byte))) {
      return AprsInvalid(outerFrame, reason: 'invalid third-party packet');
    }

    final text = String.fromCharCodes(bytes);
    final informationSeparator = text.indexOf(':');
    if (informationSeparator <= 0 || informationSeparator == text.length - 1) {
      return AprsInvalid(outerFrame, reason: 'invalid third-party packet');
    }

    final header = text.substring(0, informationSeparator);
    final information = text.substring(informationSeparator + 1);
    final sourceSeparator = header.indexOf('>');
    if (sourceSeparator <= 0 || sourceSeparator != header.lastIndexOf('>')) {
      return AprsInvalid(outerFrame, reason: 'invalid third-party header');
    }

    final sourceText = header.substring(0, sourceSeparator);
    final route = header.substring(sourceSeparator + 1);
    final routeParts = route.split(',');
    if (routeParts.isEmpty || routeParts.any((part) => part.isEmpty)) {
      return AprsInvalid(outerFrame, reason: 'invalid third-party route');
    }

    final source = _parseAddress(sourceText);
    final destination = _parseAddress(routeParts.first);
    if (source == null || destination == null) {
      return AprsInvalid(outerFrame, reason: 'invalid third-party address');
    }

    final logicalFrame = Ax25Frame(
      destination: destination,
      source: source,
      digipeaters: const [],
      control: 0x03,
      pid: 0xf0,
      information: information.codeUnits,
    );
    return _parseFrame(
          logicalFrame,
          allowThirdParty: false,
          igate: outerFrame.source,
        ) ??
        AprsInvalid(outerFrame, reason: 'invalid third-party payload');
  }

  static Ax25Address? _parseAddress(String value) {
    final match = RegExp(r'^([A-Z0-9]{1,6})(?:-([0-9]|1[0-5]))?$')
        .firstMatch(value.toUpperCase());
    if (match == null) return null;
    return Ax25Address(
      callsign: match.group(1)!,
      ssid: int.tryParse(match.group(2) ?? '') ?? 0,
      hasBeenRepeated: false,
      isLast: true,
    );
  }

  static bool _printable(int byte) => byte >= 0x20 && byte <= 0x7e;

  // APRS message numbers are one to five printable alphanumeric characters.
  static bool _validId(String value) =>
      RegExp(r'^[A-Za-z0-9]{1,5}$').hasMatch(value);
}
