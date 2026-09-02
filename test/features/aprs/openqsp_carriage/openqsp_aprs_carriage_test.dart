import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/openqsp_carriage/openqsp_carriage.dart';

import '../../../fixtures/openqsp_aprs_carriage_vectors.dart';

void main() {
  final getCapabilities = Uint8List.fromList([1, 5, 0, 0]);
  final multiFrame = Uint8List.fromList(openQspAprsCarriageVectors.last.frame);

  group('base36 and Base91', () {
    test('base36 remains canonical', () {
      expect(encodeBase36(0, 3), '000');
      expect(encodeBase36(255, 3), '073');
      expect(decodeBase36('073', 3), 255);
    });

    test('Base91 round trips every byte and avoids APRS reserved chars', () {
      final bytes = Uint8List.fromList([for (var i = 0; i < 256; i++) i]);
      final encoded = encodeOpenQspBase91(bytes);
      expect(encoded, isNot(contains('{')));
      expect(encoded, isNot(contains('|')));
      expect(encoded, isNot(contains('~')));
      expect(decodeOpenQspBase91(encoded), bytes);
    });
  });

  group('legacy Q1 compatibility', () {
    test('Base64url vectors remain decodable and Q1 remains parseable', () {
      for (final vector in openQspAprsCarriageVectors) {
        final frame = Uint8List.fromList(vector.frame);
        expect(encodeFrameText(frame), vector.encoded);
        expect(decodeFrameText(vector.encoded), frame);
        expect(
          fragmentFrameV1(frame, vector.transactionId).map((f) => f.body),
          vector.fragmentBodies,
        );
        for (final body in vector.fragmentBodies) {
          expect(parseFragment(body).version, 1);
        }
      }
    });
  });

  group('Q2 fragmentation', () {
    test('default fragmentFrame emits Q2 without APRS message IDs', () {
      final fragment = fragmentFrame(getCapabilities, '0AZ').single;
      expect(fragment.version, 2);
      expect(fragment.transactionId, encodeBase36(decodeBase36('0AZ', 3) & 0xff, 3));
      expect(fragment.index, 0);
      expect(fragment.total, 1);
      expect(fragment.body, startsWith('Q2'));
      expect(fragment.body, isNot(contains('{')));
      expect(fragment.body.length, lessThanOrEqualTo(openQspAprsMaxBodyLength));
    });

    test('Q2 parser round trips raw fragment bytes', () {
      final fragments = fragmentFrameV2(multiFrame, '00A');
      for (final fragment in fragments) {
        final parsed = parseFragment(fragment.body);
        expect(parsed.version, 2);
        expect(parsed.transactionId, '00A');
        expect(parsed.index, fragment.index);
        expect(parsed.total, fragment.total);
        expect(parsed.rawData, fragment.rawData);
      }
    });

    test('50-byte chunks stay within the APRS 67-character body limit', () {
      final frame = Uint8List.fromList([
        1,
        1,
        0,
        55,
        ...List<int>.filled(55, 1),
      ]);
      // The synthetic bytes above are not a valid SEND_MESSAGE, so exercise the
      // real long canonical fixture instead.
      expect(frame.length, 59);
      final fragments = fragmentFrame(multiFrame, '001');
      expect(fragments, isNotEmpty);
      for (final fragment in fragments) {
        expect(fragment.body.length, lessThanOrEqualTo(67));
        expect(fragment.rawData!.length, lessThanOrEqualTo(50));
      }
    });

    test('rejects Q2 with native APRS message ID suffix', () {
      final body = fragmentFrame(getCapabilities, '001').single.body;
      expect(
        () => parseFragment('$body{12'),
        throwsA(isA<OpenQspAprsInvalidFragmentException>()),
      );
    });
  });

  group('Q2 reassembler', () {
    final start = DateTime.utc(2026);

    test('reassembles out of order', () {
      final fragments = fragmentFrameV2(multiFrame, '001');
      final reassembler = OpenQspAprsReassembler();
      Uint8List? completed;
      for (final fragment in fragments.reversed) {
        completed = reassembler.add(
          peer: 'OPENQSP',
          fragment: parseFragment(fragment.body),
          now: start,
        );
      }
      expect(completed, multiFrame);
    });

    test('accepts identical duplicate and rejects conflicting duplicate', () {
      final fragments = fragmentFrameV2(multiFrame, '002');
      final reassembler = OpenQspAprsReassembler();
      expect(
        reassembler.add(peer: 'OPENQSP', fragment: fragments.first, now: start),
        isNull,
      );
      expect(
        reassembler.add(peer: 'OPENQSP', fragment: fragments.first, now: start),
        isNull,
      );
      final raw = Uint8List.fromList(fragments.first.rawData!);
      raw[0] ^= 1;
      final conflict = OpenQspAprsFragment(
        transactionId: fragments.first.transactionId,
        index: fragments.first.index,
        total: fragments.first.total,
        data: '',
        version: 2,
        rawData: raw,
      );
      expect(
        () => reassembler.add(peer: 'OPENQSP', fragment: conflict, now: start),
        throwsA(isA<OpenQspAprsTransactionConflictException>()),
      );
    });
  });
}
