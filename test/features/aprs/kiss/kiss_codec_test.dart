import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_decoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';

void main() {
  const encoder = KissEncoder();

  group('KissEncoder', () {
    test('encodes a normal payload', () {
      expect(
        encoder.encode(KissFrame(port: 0, command: 0, payload: [1, 2, 3])),
        [0xc0, 0x00, 0x01, 0x02, 0x03, 0xc0],
      );
    });

    test('escapes FEND', () {
      expect(
        encoder.encode(KissFrame(port: 0, command: 0, payload: [1, 0xc0, 2])),
        [0xc0, 0, 1, 0xdb, 0xdc, 2, 0xc0],
      );
    });

    test('escapes FESC', () {
      expect(
        encoder.encode(KissFrame(port: 0, command: 0, payload: [1, 0xdb, 2])),
        [0xc0, 0, 1, 0xdb, 0xdd, 2, 0xc0],
      );
    });

    test('escapes both special characters', () {
      expect(
        encoder.encode(KissFrame(port: 0, command: 0, payload: [0xc0, 0xdb])),
        [0xc0, 0, 0xdb, 0xdc, 0xdb, 0xdd, 0xc0],
      );
    });
  });

  group('KissDecoder', () {
    late KissDecoder decoder;
    late List<KissFrame> frames;

    setUp(() {
      decoder = KissDecoder();
      frames = [];
      decoder.frames.listen(frames.add);
    });

    tearDown(() => decoder.close());

    test('decodes a normal frame', () {
      decoder.add([0xc0, 0, 1, 2, 3, 0xc0]);
      expect(frames.single.payload, [1, 2, 3]);
    });

    test('accepts a frame byte by byte', () {
      for (final byte in [0xc0, 0, 1, 2, 0xc0]) {
        decoder.add([byte]);
      }
      expect(frames.single.payload, [1, 2]);
    });

    test('accepts arbitrary chunks', () {
      decoder.add([0xc0, 0]);
      decoder.add([1, 2]);
      decoder.add([3, 0xc0]);
      expect(frames.single.payload, [1, 2, 3]);
    });

    test('emits multiple frames from one chunk', () {
      decoder.add([0xc0, 0, 1, 0xc0, 0, 2, 0xc0]);
      expect(frames.map((frame) => frame.payload.single), [1, 2]);
    });

    test('ignores repeated delimiters and empty frames', () {
      decoder.add([0xc0, 0xc0, 0xc0, 0, 1, 0xc0, 0xc0]);
      expect(frames.single.payload, [1]);
    });

    test('unescapes FEND and FESC', () {
      decoder.add([0xc0, 0, 0xdb, 0xdc, 0xdb, 0xdd, 0xc0]);
      expect(frames.single.payload, [0xc0, 0xdb]);
    });

    test('recovers from an invalid escape without throwing', () {
      expect(
        () => decoder.add([0xc0, 0, 0xdb, 0xaa, 0xc0]),
        returnsNormally,
      );
      expect(frames.single.payload, [0xaa]);
    });

    test('ignores garbage before the first FEND', () {
      decoder.add([1, 2, 3, 0xc0, 0, 4, 0xc0]);
      expect(frames.single.payload, [4]);
    });

    test('extracts the port and command nibbles', () {
      decoder.add([0xc0, 0x32, 9, 0xc0]);
      expect(frames.single.port, 3);
      expect(frames.single.command, 2);
      expect(frames.single.commandByte, 0x32);
    });

    test('close prevents later input and closes the stream', () async {
      final done = Completer<void>();
      decoder.frames.listen(null, onDone: done.complete);
      await decoder.close();
      decoder.add([0xc0, 0, 1, 0xc0]);
      await done.future;
      expect(frames, isEmpty);
    });

    test('discards an unterminated frame that exceeds the size limit', () async {
      final limitedDecoder = KissDecoder(maximumFrameLength: 4);
      final limitedFrames = <KissFrame>[];
      limitedDecoder.frames.listen(limitedFrames.add);

      limitedDecoder.add([0xc0, 0, 1, 2, 3, 4, 5, 0xc0]);
      limitedDecoder.add([0, 9, 0xc0]);

      expect(limitedFrames.single.payload, [9]);
      await limitedDecoder.close();
    });
  });
}
