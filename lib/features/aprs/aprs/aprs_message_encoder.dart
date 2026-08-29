import 'dart:typed_data';

final class AprsMessageEncodeException implements Exception {
  const AprsMessageEncodeException(this.message);
  final String message;
}

/// Encodes the information field of a classic APRS text message.
final class AprsMessageEncoder {
  const AprsMessageEncoder();

  Uint8List encode({
    required String addressee,
    required String body,
    String? messageId,
  }) {
    if (!RegExp(r'^[A-Z0-9]{1,6}(?:-(?:[0-9]|1[0-5]))?$')
            .hasMatch(addressee) ||
        addressee.length > 9) {
      throw const AprsMessageEncodeException('invalid APRS addressee');
    }
    if (body.isEmpty ||
        body.length > 67 ||
        body.codeUnits.any((byte) => byte < 0x20 || byte > 0x7e) ||
        body.contains('{')) {
      throw const AprsMessageEncodeException('invalid APRS message body');
    }
    if (messageId != null &&
        !RegExp(r'^[A-Za-z0-9]{1,5}$').hasMatch(messageId)) {
      throw const AprsMessageEncodeException('invalid APRS message ID');
    }
    final text = ':${addressee.padRight(9)}:$body'
        '${messageId == null ? '' : '{$messageId'}';
    if (text.length > 78) {
      throw const AprsMessageEncodeException('APRS message is too long');
    }
    return Uint8List.fromList(text.codeUnits);
  }
}
