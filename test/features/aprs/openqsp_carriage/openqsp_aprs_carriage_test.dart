import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/openqsp_carriage/openqsp_carriage.dart';

import '../../../fixtures/openqsp_aprs_carriage_vectors.dart';

void main() {
  final getCapabilities = Uint8List.fromList([1, 5, 0, 0]);
  final multiVector = openQspAprsCarriageVectors.last;
  final multiFrame = Uint8List.fromList(multiVector.frame);

  group('base36', () {
    test('encodes canonical values', () {
      expect(encodeBase36(0, 3), '000');
      expect(encodeBase36(35, 3), '00Z');
      expect(encodeBase36(36, 3), '010');
      expect(decodeBase36('00Z', 3), 35);
    });

    test('strictly rejects range, width, alphabet and lowercase errors', () {
      for (final callback in <void Function()>[
        () => encodeBase36(-1, 3),
        () => encodeBase36(36 * 36 * 36, 3),
        () => encodeBase36(0, 0),
        () => decodeBase36('00', 3),
        () => decodeBase36('00z', 3),
        () => decodeBase36('0-0', 3),
      ]) {
        expect(callback, throwsA(isA<OpenQspAprsInvalidBase36Exception>()));
      }
    });
  });

  group('frame text and Python vectors', () {
    test('GET_CAPABILITIES round trips', () {
      expect(encodeFrameText(getCapabilities), 'AQUAAA');
      expect(decodeFrameText('AQUAAA'), getCapabilities);
    });

    for (final vector in openQspAprsCarriageVectors) {
      test('${vector.name} matches canonical Python output', () {
        final frame = Uint8List.fromList(vector.frame);
        expect(encodeFrameText(frame), vector.encoded);
        expect(decodeFrameText(vector.encoded), frame);
        expect(
          fragmentFrame(frame, vector.transactionId).map((f) => f.body),
          vector.fragmentBodies,
        );
      });
    }

    test('rejects malformed text and decodable non-Core bytes', () {
      for (final text in ['', 'A', 'AA=', 'AA+_', 'AAAAA']) {
        expect(
          () => decodeFrameText(text),
          throwsA(isA<OpenQspAprsInvalidFrameException>()),
        );
      }
      expect(
        () => decodeFrameText('AAAA'),
        throwsA(isA<OpenQspAprsInvalidFrameException>()),
      );
    });
  });

  group('fragmentation and parsing', () {
    test('small frame produces the exact single fragment', () {
      final fragment = fragmentFrame(getCapabilities, '0AZ').single;
      expect(fragment.transactionId, '0AZ');
      expect(fragment.index, 0);
      expect(fragment.total, 1);
      expect(fragment.body, 'Q1:0AZ:00/01:AQUAAA');
    });

    test('multi-frame chunks are consecutive and bounded', () {
      final fragments = fragmentFrame(multiFrame, 'LNG');
      expect(fragments.length, 4);
      for (var index = 0; index < fragments.length; index++) {
        expect(fragments[index].index, index);
        expect(fragments[index].total, fragments.length);
        expect(fragments[index].transactionId, 'LNG');
        expect(fragments[index].data.length, lessThanOrEqualTo(48));
      }
    });

    test('parses plain and APRS message-ID suffix variants', () {
      final plain = parseFragment('Q1:ABC:00/01:AAAA');
      expect(plain.messageId, isNull);
      expect(plain.body, 'Q1:ABC:00/01:AAAA');
      final suffixed = parseFragment('Q1:ABC:00/01:AAAA{12A');
      expect(suffixed.data, 'AAAA');
      expect(suffixed.messageId, '12A');
      expect(suffixed.body, 'Q1:ABC:00/01:AAAA{12A');
    });

    test('rejects all non-canonical parser forms', () {
      final invalid = [
        'q1:ABC:00/01:AAAA',
        'Q1:abc:00/01:AAAA',
        'Q1:ABC:00/00:AAAA',
        'Q1:ABC:01/01:AAAA',
        'Q1:ABC:00/01:${'A' * 49}',
        'Q1:ABC:00/01:AAAA{',
        'Q1:ABC:00/01:AAAA{123456',
        'Q1:ABC:00/01:AAAA{abc',
        'Q1:ABC:00/01:AA+=',
      ];
      for (final body in invalid) {
        expect(
          () => parseFragment(body),
          throwsA(isA<OpenQspAprsInvalidFragmentException>()),
          reason: body,
        );
      }
    });

    test('rejects invalid transaction IDs and invalid Core frames', () {
      expect(
        () => fragmentFrame(getCapabilities, 'abc'),
        throwsA(isA<OpenQspAprsInvalidFragmentException>()),
      );
      expect(
        () => fragmentFrame(Uint8List.fromList([0, 0, 0, 0]), 'ABC'),
        throwsA(isA<OpenQspAprsInvalidFrameException>()),
      );
    });
  });

  group('reassembler', () {
    final start = DateTime.utc(2026);
    OpenQspAprsFragment changed(OpenQspAprsFragment fragment) =>
        OpenQspAprsFragment(
          transactionId: fragment.transactionId,
          index: fragment.index,
          total: fragment.total,
          data: '${fragment.data.substring(0, fragment.data.length - 1)}A',
        );

    test('reassembles out of order', () {
      final fragments = fragmentFrame(multiFrame, 'ABC');
      final reassembler = OpenQspAprsReassembler();
      expect(reassembler.add(peer: 'P1', fragment: fragments[2], now: start), isNull);
      expect(reassembler.add(peer: 'P1', fragment: fragments[0], now: start), isNull);
      expect(reassembler.add(peer: 'P1', fragment: fragments[3], now: start), isNull);
      expect(reassembler.add(peer: 'P1', fragment: fragments[1], now: start), multiFrame);
    });

    test('accepts identical duplicate', () {
      final fragments = fragmentFrame(multiFrame, 'ABC');
      final reassembler = OpenQspAprsReassembler();
      expect(reassembler.add(peer: 'P1', fragment: fragments[0], now: start), isNull);
      expect(reassembler.add(peer: 'P1', fragment: fragments[0], now: start), isNull);
    });

    test('conflicting duplicate removes assembly', () {
      final fragments = fragmentFrame(multiFrame, 'ABC');
      final reassembler = OpenQspAprsReassembler();
      reassembler.add(peer: 'P1', fragment: fragments[0], now: start);
      expect(
        () => reassembler.add(peer: 'P1', fragment: changed(fragments[0]), now: start),
        throwsA(isA<OpenQspAprsTransactionConflictException>()),
      );
      // A fresh assembly now accepts the original fragment again.
      expect(reassembler.add(peer: 'P1', fragment: fragments[0], now: start), isNull);
    });

    test('inconsistent total removes assembly', () {
      final fragments = fragmentFrame(multiFrame, 'ABC');
      final reassembler = OpenQspAprsReassembler();
      reassembler.add(peer: 'P1', fragment: fragments[0], now: start);
      final conflict = OpenQspAprsFragment(
        transactionId: 'ABC', index: 0, total: 3, data: fragments[0].data,
      );
      expect(
        () => reassembler.add(peer: 'P1', fragment: conflict, now: start),
        throwsA(isA<OpenQspAprsTransactionConflictException>()),
      );
      expect(reassembler.add(peer: 'P1', fragment: fragments[0], now: start), isNull);
    });

    test('isolates peers sharing a transaction ID', () {
      final fragments = fragmentFrame(multiFrame, 'ABC');
      final reassembler = OpenQspAprsReassembler();
      for (final fragment in fragments.take(3)) {
        expect(reassembler.add(peer: 'P1', fragment: fragment, now: start), isNull);
        expect(reassembler.add(peer: 'P2', fragment: fragment, now: start), isNull);
      }
      expect(reassembler.add(peer: 'P1', fragment: fragments[3], now: start), multiFrame);
      expect(reassembler.add(peer: 'P2', fragment: fragments[3], now: start), multiFrame);
    });

    test('expires partial assembly after TTL', () {
      final fragments = fragmentFrame(multiFrame, 'ABC');
      final reassembler = OpenQspAprsReassembler(ttl: const Duration(seconds: 120));
      reassembler.add(peer: 'P1', fragment: fragments[0], now: start);
      for (final fragment in fragments.skip(1)) {
        expect(
          reassembler.add(
            peer: 'P1', fragment: fragment,
            now: start.add(const Duration(seconds: 121)),
          ),
          isNull,
        );
      }
    });

    test('capacity evicts oldest active assembly', () {
      final fragments = fragmentFrame(multiFrame, 'ABC');
      final reassembler = OpenQspAprsReassembler(maxEntries: 2);
      reassembler.add(peer: 'OLD', fragment: fragments[0], now: start);
      reassembler.add(peer: 'KEEP', fragment: fragments[0], now: start.add(const Duration(seconds: 1)));
      reassembler.add(peer: 'NEW', fragment: fragments[0], now: start.add(const Duration(seconds: 2)));
      for (final fragment in fragments.skip(1)) {
        expect(
          reassembler.add(peer: 'OLD', fragment: fragment, now: start.add(const Duration(seconds: 3))),
          isNull,
        );
      }
    });
  });
}
