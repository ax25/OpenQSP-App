import 'dart:async';

import 'kiss_encoder.dart';
import 'kiss_frame.dart';

/// Incrementally reconstructs KISS frames from arbitrary byte chunks.
final class KissDecoder {
  KissDecoder({this.maximumFrameLength = 65536})
    : assert(maximumFrameLength > 0);

  /// Maximum unescaped command-and-payload length retained without a FEND.
  /// Corrupt oversized frames are discarded until a fresh delimiter arrives.
  final int maximumFrameLength;
  final _frames = StreamController<KissFrame>.broadcast(sync: true);
  final List<int> _buffer = [];
  bool _insideFrame = false;
  bool _escaped = false;
  bool _closed = false;

  Stream<KissFrame> get frames => _frames.stream;

  void add(Iterable<int> bytes) {
    if (_closed) return;
    for (final rawByte in bytes) {
      final byte = rawByte & 0xff;
      if (!_insideFrame) {
        if (byte == kissFend) {
          _insideFrame = true;
          _buffer.clear();
          _escaped = false;
        }
        continue;
      }
      if (byte == kissFend) {
        if (_buffer.isNotEmpty) _emitFrame();
        _buffer.clear();
        _escaped = false;
        continue;
      }
      if (_escaped) {
        if (byte == kissTfend) {
          _buffer.add(kissFend);
        } else if (byte == kissTfesc) {
          _buffer.add(kissFesc);
        } else {
          // Recover deterministically: retain the unknown escaped byte.
          _buffer.add(byte);
        }
        _escaped = false;
      } else if (byte == kissFesc) {
        _escaped = true;
      } else {
        _buffer.add(byte);
      }
      if (_buffer.length > maximumFrameLength) {
        _buffer.clear();
        _insideFrame = false;
        _escaped = false;
      }
    }
  }

  void _emitFrame() {
    final frame = KissFrame.fromCommandByte(
      _buffer.first,
      _buffer.skip(1).toList(),
    );
    _frames.add(frame);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _buffer.clear();
    await _frames.close();
  }
}
