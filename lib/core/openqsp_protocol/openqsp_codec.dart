import 'dart:convert';
import 'dart:typed_data';

import 'openqsp_constants.dart';
import 'openqsp_error_code.dart';
import 'openqsp_models.dart';
import 'openqsp_operation.dart';
import 'openqsp_protocol_exception.dart';

final class OpenQspCodec {
  const OpenQspCodec();

  Uint8List encode(OpenQspFrameObject object, {bool unsolicited = false}) {
    final operation = _operationFor(object);
    if (unsolicited && !_allowsUnsolicited(operation)) {
      throw const OpenQspInvalidFieldException('UNSOLICITED is invalid for this operation');
    }
    final writer = _Writer();
    switch (object) {
      case OpenQspSendMessage(:final createdAt, :final recipient, :final body):
        writer.u32(createdAt, 'created_at', nonZero: true);
        writer.callsign(recipient, 'recipient'); writer.text(body, 'body', 1, 208);
      case OpenQspGetNewMessages(:final since, :final max) || OpenQspGetNewBulletins(:final since, :final max):
        writer.u32(since, 'since'); writer.rangedU8(max, 'max', 1, 20);
      case OpenQspGetBulletin(:final sequence): writer.u32(sequence, 'sequence', nonZero: true);
      case OpenQspGetCapabilities() || OpenQspStored(): break;
      case OpenQspMessage(:final sequence, :final createdAt, :final author, :final recipient, :final body):
        writer.u32(sequence, 'sequence', nonZero: true); writer.u32(createdAt, 'created_at', nonZero: true);
        writer.callsign(author, 'author'); writer.callsign(recipient, 'recipient'); writer.text(body, 'body', 1, 208);
      case OpenQspBulletinHeader(:final sequence, :final createdAt, :final author, :final title):
        writer.u32(sequence, 'sequence', nonZero: true); writer.u32(createdAt, 'created_at', nonZero: true);
        writer.callsign(author, 'author'); writer.text(title, 'title', 1, 64);
      case OpenQspBulletin(:final sequence, :final createdAt, :final author, :final title, :final body):
        writer.u32(sequence, 'sequence', nonZero: true); writer.u32(createdAt, 'created_at', nonZero: true);
        writer.callsign(author, 'author'); writer.text(title, 'title', 1, 64); writer.text(body, 'body', 1, 164);
      case OpenQspEnd(:final requestOperation, :final returnedCount, :final nextSince, :final hasMore):
        if (!_isRetrieval(requestOperation)) throw const OpenQspInvalidFieldException('END request_operation is invalid');
        writer.u8(requestOperation.code, 'request_operation'); writer.u8(returnedCount, 'returned_count');
        writer.u32(nextSince, 'next_since'); writer.u8(hasMore ? 1 : 0, 'has_more');
      case OpenQspError(:final requestOperation, :final errorCode, :final detail):
        writer.u8(requestOperation, 'request_operation'); writer.u8(errorCode.code, 'error_code'); writer.text(detail, 'detail', 0, 64);
      case OpenQspCapabilities(:final protocolVersion, :final capabilities):
        writer.u8(protocolVersion, 'protocol_version'); writer.u32(capabilities, 'capabilities');
    }
    if (writer.length > openQspMaxPayloadLength) throw const OpenQspFrameTooLargeException('payload exceeds 255 bytes');
    return Uint8List.fromList([openQspVersion, operation.code, unsolicited ? openQspFlagUnsolicited : 0, writer.length, ...writer.bytes]);
  }

  OpenQspDecodedFrame decode(List<int> bytes) {
    if (bytes.length > openQspMaxFrameLength) throw const OpenQspFrameTooLargeException('frame exceeds 259 bytes');
    if (bytes.length < openQspHeaderLength) throw const OpenQspPayloadLengthException('truncated frame header');
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) throw const OpenQspInvalidFieldException('frame contains a non-byte value');
    }
    if (bytes[0] != openQspVersion) throw OpenQspUnsupportedVersionException('unsupported version ${bytes[0]}');
    final operation = OpenQspOperation.fromCode(bytes[1]);
    if (operation == null) throw OpenQspUnknownOperationException('unknown operation ${bytes[1]}');
    final flags = bytes[2];
    if (flags & ~openQspFlagUnsolicited != 0) throw const OpenQspInvalidFieldException('unknown flag bit');
    if (flags & openQspFlagUnsolicited != 0 && !_allowsUnsolicited(operation)) {
      throw const OpenQspInvalidFieldException('UNSOLICITED is invalid for this operation');
    }
    final declared = bytes[3];
    final actual = bytes.length - openQspHeaderLength;
    if (declared != actual) throw OpenQspPayloadLengthException('declared payload $declared, actual $actual');
    final reader = _Reader(bytes.sublist(4));
    final object = _decodePayload(operation, reader);
    if (!reader.done) throw const OpenQspPayloadLengthException('payload contains trailing bytes');
    return OpenQspDecodedFrame(version: bytes[0], operation: operation, flags: flags, object: object);
  }

  OpenQspFrameObject _decodePayload(OpenQspOperation operation, _Reader r) {
    switch (operation) {
      case OpenQspOperation.sendMessage:
        return OpenQspSendMessage(createdAt: r.u32('created_at', nonZero: true), recipient: r.callsign('recipient'), body: r.text('body', 1, 208));
      case OpenQspOperation.getNewMessages:
        return OpenQspGetNewMessages(since: r.u32('since'), max: r.rangedU8('max', 1, 20));
      case OpenQspOperation.getNewBulletins:
        return OpenQspGetNewBulletins(since: r.u32('since'), max: r.rangedU8('max', 1, 20));
      case OpenQspOperation.getBulletin: return OpenQspGetBulletin(r.u32('sequence', nonZero: true));
      case OpenQspOperation.getCapabilities: return const OpenQspGetCapabilities();
      case OpenQspOperation.message:
        return OpenQspMessage(sequence: r.u32('sequence', nonZero: true), createdAt: r.u32('created_at', nonZero: true), author: r.callsign('author'), recipient: r.callsign('recipient'), body: r.text('body', 1, 208));
      case OpenQspOperation.bulletinHeader:
        return OpenQspBulletinHeader(sequence: r.u32('sequence', nonZero: true), createdAt: r.u32('created_at', nonZero: true), author: r.callsign('author'), title: r.text('title', 1, 64));
      case OpenQspOperation.bulletin:
        return OpenQspBulletin(sequence: r.u32('sequence', nonZero: true), createdAt: r.u32('created_at', nonZero: true), author: r.callsign('author'), title: r.text('title', 1, 64), body: r.text('body', 1, 164));
      case OpenQspOperation.end:
        final request = OpenQspOperation.fromCode(r.u8('request_operation'));
        if (request == null || !_isRetrieval(request)) throw const OpenQspInvalidFieldException('END request_operation is invalid');
        final count = r.u8('returned_count'); final next = r.u32('next_since'); final more = r.u8('has_more');
        if (more > 1) throw const OpenQspInvalidFieldException('has_more must be 0 or 1');
        return OpenQspEnd(requestOperation: request, returnedCount: count, nextSince: next, hasMore: more == 1);
      case OpenQspOperation.stored: return const OpenQspStored();
      case OpenQspOperation.error:
        final request = r.u8('request_operation'); final code = OpenQspErrorCode.fromCode(r.u8('error_code'));
        if (code == null) throw const OpenQspInvalidFieldException('unknown ERROR code');
        return OpenQspError(requestOperation: request, errorCode: code, detail: r.text('detail', 0, 64));
      case OpenQspOperation.capabilities:
        return OpenQspCapabilities(protocolVersion: r.u8('protocol_version'), capabilities: r.u32('capabilities'));
    }
  }
}

bool _allowsUnsolicited(OpenQspOperation op) => op == OpenQspOperation.message || op == OpenQspOperation.bulletinHeader;
bool _isRetrieval(OpenQspOperation op) => op == OpenQspOperation.getNewMessages || op == OpenQspOperation.getNewBulletins;

OpenQspOperation _operationFor(OpenQspFrameObject object) => switch (object) {
  OpenQspSendMessage() => OpenQspOperation.sendMessage, OpenQspGetNewMessages() => OpenQspOperation.getNewMessages,
  OpenQspGetNewBulletins() => OpenQspOperation.getNewBulletins, OpenQspGetBulletin() => OpenQspOperation.getBulletin,
  OpenQspGetCapabilities() => OpenQspOperation.getCapabilities, OpenQspMessage() => OpenQspOperation.message,
  OpenQspBulletinHeader() => OpenQspOperation.bulletinHeader, OpenQspBulletin() => OpenQspOperation.bulletin,
  OpenQspEnd() => OpenQspOperation.end, OpenQspStored() => OpenQspOperation.stored,
  OpenQspError() => OpenQspOperation.error, OpenQspCapabilities() => OpenQspOperation.capabilities,
};

final class _Writer {
  final List<int> bytes = []; int get length => bytes.length;
  void u8(int value, String name) { if (value < 0 || value > 255) throw OpenQspInvalidFieldException('$name is outside u8'); bytes.add(value); }
  void rangedU8(int value, String name, int min, int max) { if (value < min || value > max) throw OpenQspInvalidFieldException('$name is outside $min..$max'); bytes.add(value); }
  void u32(int value, String name, {bool nonZero = false}) {
    if (value < 0 || value > 0xffffffff || nonZero && value == 0) throw OpenQspInvalidFieldException('$name is outside its allowed u32 range');
    bytes.addAll([(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]);
  }
  void callsign(String value, String name) {
    final encoded = utf8.encode(value);
    if (encoded.length < 3 || encoded.length > 12 || !RegExp(r'^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]+$').hasMatch(value)) throw OpenQspInvalidFieldException('$name is not a normalized OpenQSP callsign');
    u8(encoded.length, '${name}_length'); bytes.addAll(encoded);
  }
  void text(String value, String name, int min, int max) {
    final encoded = utf8.encode(value);
    if (encoded.length < min || encoded.length > max || encoded.contains(0)) throw OpenQspInvalidFieldException('$name has invalid encoded length or contains NUL');
    u8(encoded.length, '${name}_length'); bytes.addAll(encoded);
  }
}

final class _Reader {
  _Reader(this.bytes); final List<int> bytes; int offset = 0; bool get done => offset == bytes.length;
  int u8(String name) { if (offset >= bytes.length) throw OpenQspPayloadLengthException('truncated $name'); return bytes[offset++]; }
  int rangedU8(String name, int min, int max) { final value = u8(name); if (value < min || value > max) throw OpenQspInvalidFieldException('$name is outside $min..$max'); return value; }
  int u32(String name, {bool nonZero = false}) {
    if (bytes.length - offset < 4) throw OpenQspPayloadLengthException('truncated $name');
    final value = bytes[offset] * 0x1000000 + bytes[offset + 1] * 0x10000 + bytes[offset + 2] * 0x100 + bytes[offset + 3]; offset += 4;
    if (nonZero && value == 0) throw OpenQspInvalidFieldException('$name must be non-zero'); return value;
  }
  List<int> _field(String name) { final length = u8('${name}_length'); if (length > bytes.length - offset) throw OpenQspPayloadLengthException('truncated $name'); final value = bytes.sublist(offset, offset + length); offset += length; return value; }
  String text(String name, int min, int max) {
    final value = _field(name); if (value.length < min || value.length > max || value.contains(0)) throw OpenQspInvalidFieldException('$name has invalid encoded length or contains NUL');
    try { return utf8.decode(value, allowMalformed: false); } on FormatException { throw OpenQspInvalidFieldException('$name is not valid UTF-8'); }
  }
  String callsign(String name) {
    final value = _field(name);
    if (value.length < 3 || value.length > 12 || value.any((b) => b > 0x7f)) throw OpenQspInvalidFieldException('$name is not a normalized OpenQSP callsign');
    final decoded = String.fromCharCodes(value);
    if (!RegExp(r'^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]+$').hasMatch(decoded)) throw OpenQspInvalidFieldException('$name is not a normalized OpenQSP callsign'); return decoded;
  }
}
