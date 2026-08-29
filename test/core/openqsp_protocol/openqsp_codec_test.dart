import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_protocol.dart';

import '../../fixtures/openqsp_protocol_vectors.dart';

void main() {
  const codec = OpenQspCodec();
  group('canonical and cross-language vectors', () {
    for (final vector in openQspProtocolVectors) {
      test(vector.object.runtimeType.toString(), () {
        expect(codec.encode(vector.object), vector.bytes);
        final decoded = codec.decode(vector.bytes);
        expect(decoded.object.runtimeType, vector.object.runtimeType);
        expect(codec.encode(decoded.object), vector.bytes);
      });
    }
  });

  test('MESSAGE byte layout and round trip', () {
    const object = OpenQspMessage(sequence: 1, createdAt: 2, author: 'EA3ABC', recipient: 'EA3GNU', body: 'TEST');
    final expected = [1, 0x40, 0, 0x1b, 0,0,0,1, 0,0,0,2, 6, ...'EA3ABC'.codeUnits, 6, ...'EA3GNU'.codeUnits, 4, ...'TEST'.codeUnits];
    expect(codec.encode(object), expected);
    final decoded = codec.decode(expected).object as OpenQspMessage;
    expect((decoded.sequence, decoded.createdAt, decoded.author, decoded.recipient, decoded.body), (1, 2, 'EA3ABC', 'EA3GNU', 'TEST'));
  });

  test('all remaining objects round trip', () {
    final objects = <OpenQspFrameObject>[
      const OpenQspGetNewBulletins(since: 4, max: 1), const OpenQspGetBulletin(9),
      const OpenQspBulletinHeader(sequence: 1, createdAt: 2, author: 'EA3ABC', title: 'News'),
      const OpenQspBulletin(sequence: 1, createdAt: 2, author: 'EA3ABC', title: 'News', body: 'Body'),
      const OpenQspEnd(requestOperation: OpenQspOperation.getNewMessages, returnedCount: 2, nextSince: 10, hasMore: true),
      const OpenQspError(requestOperation: 1, errorCode: OpenQspErrorCode.invalidField),
      const OpenQspError(requestOperation: 1, errorCode: OpenQspErrorCode.rejected, detail: 'No'),
    ];
    for (final object in objects) {
      final bytes = codec.encode(object); expect(codec.encode(codec.decode(bytes).object), bytes);
    }
  });

  test('END exact bytes', () {
    expect(codec.encode(const OpenQspEnd(requestOperation: OpenQspOperation.getNewMessages, returnedCount: 2, nextSince: 10, hasMore: true)), [1, 0x43, 0, 7, 2, 2, 0, 0, 0, 10, 1]);
  });

  test('metadata and allowed unsolicited', () {
    const message = OpenQspMessage(sequence: 1, createdAt: 2, author: 'EA3ABC', recipient: 'EA3GNU', body: 'x');
    final frame = codec.decode(codec.encode(message, unsolicited: true));
    expect((frame.version, frame.operation, frame.flags, frame.unsolicited), (1, OpenQspOperation.message, 1, true));
    expect(() => codec.encode(const OpenQspStored(), unsolicited: true), throwsA(isA<OpenQspInvalidFieldException>()));
  });

  group('CAPABILITIES protocol_version', () {
    test('rejects zero while encoding', () {
      expect(
        () => codec.encode(const OpenQspCapabilities(protocolVersion: 0, capabilities: 0x0f)),
        throwsA(isA<OpenQspInvalidFieldException>()),
      );
    });

    test('rejects zero while decoding', () {
      expect(
        () => codec.decode([0x01, 0x46, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x0f]),
        throwsA(isA<OpenQspInvalidFieldException>()),
      );
    });

    test('accepts the canonical protocol version', () {
      final decoded = codec.decode([0x01, 0x46, 0x00, 0x05, 0x01, 0x00, 0x00, 0x00, 0x0f]);
      final capabilities = decoded.object as OpenQspCapabilities;

      expect(capabilities.protocolVersion, 1);
      expect(capabilities.capabilities, 0x0f);
      expect(codec.encode(capabilities), [0x01, 0x46, 0x00, 0x05, 0x01, 0x00, 0x00, 0x00, 0x0f]);
    });
  });

  group('malformed traffic is controlled', () {
    void invalid(List<int> bytes, [Matcher? matcher]) => expect(() => codec.decode(bytes), throwsA(matcher ?? isA<OpenQspProtocolException>()));
    test('empty/header truncated', () { invalid([]); invalid([1, 2, 0]); });
    test('payload truncated/trailing/length mismatch', () { invalid([1, 5, 0, 1]); invalid([1, 5, 0, 0, 0]); invalid([1, 2, 0, 5, 0, 0]); });
    test('version, operation and flags', () { invalid([2, 5, 0, 0], isA<OpenQspUnsupportedVersionException>()); invalid([1, 0xff, 0, 0], isA<OpenQspUnknownOperationException>()); invalid([1, 5, 2, 0]); invalid([1, 5, 1, 0]); });
    test('invalid utf8 and NUL', () { invalid([1, 1, 0, 13, 0,0,0,1, 6,...'EA3GNU'.codeUnits, 1, 0xff]); invalid([1, 1, 0, 13, 0,0,0,1, 6,...'EA3GNU'.codeUnits, 1, 0]); });
    test('invalid callsign', () { invalid([1, 1, 0, 10, 0,0,0,1, 2, ...'E3'.codeUnits, 2, ...'HI'.codeUnits]); });
    test('zero nonzero u32', () { invalid([1, 4, 0, 4, 0,0,0,0]); });
    test('retrieval max bounds', () { invalid([1,2,0,5,0,0,0,0,0]); invalid([1,2,0,5,0,0,0,0,21]); });
    test('unknown ERROR code', () { invalid([1,0x45,0,3,1,0xff,0]); });
    test('invalid END operation/boolean', () { invalid([1,0x43,0,7,1,0,0,0,0,0,0]); invalid([1,0x43,0,7,2,0,0,0,0,0,2]); });
    test('oversize and non-byte values', () { invalid(List.filled(260, 0)); invalid([1,5,0,0,256]); });
  });

  test('encode validates byte limits, callsigns and integer ranges', () {
    expect(() => codec.encode(const OpenQspSendMessage(createdAt: 0, recipient: 'EA3GNU', body: 'x')), throwsA(isA<OpenQspInvalidFieldException>()));
    expect(() => codec.encode(OpenQspSendMessage(createdAt: 1, recipient: 'ea3gnu', body: List.filled(209, 'x').join())), throwsA(isA<OpenQspInvalidFieldException>()));
    expect(() => codec.encode(const OpenQspSendMessage(createdAt: 1, recipient: 'EA3GNU', body: '\u0000')), throwsA(isA<OpenQspInvalidFieldException>()));
    expect(() => codec.encode(const OpenQspGetNewMessages(since: 0, max: 21)), throwsA(isA<OpenQspInvalidFieldException>()));
  });
}
