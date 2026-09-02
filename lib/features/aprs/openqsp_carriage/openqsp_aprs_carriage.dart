import 'dart:convert';
import 'dart:typed_data';

import '../../../core/openqsp_protocol/openqsp_protocol.dart';

const int openQspAprsDataChunkSize = 48;
const int openQspAprsV2DataChunkSize = 50;
const int openQspAprsMaxFragments = 16;
const int openQspAprsMaxBodyLength = 67;
const Duration openQspAprsDefaultTtl = Duration(seconds: 120);
const int openQspAprsDefaultMaxEntries = 128;

const _base36Alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
final _base36Pattern = RegExp(r'^[0-9A-Z]+$');
final _frameTextPattern = RegExp(r'^[A-Za-z0-9_-]+$');
final _fragmentPattern = RegExp(
  r'^Q1:([0-9A-Z]{3}):([0-9A-Z]{2})/([0-9A-Z]{2}):([A-Za-z0-9_-]{1,48})(?:\{([0-9A-Z]{1,5}))?$',
);
final String _base91Alphabet = String.fromCharCodes([
  for (var value = 33; value < 127; value++)
    if (value != 123 && value != 124 && value != 126) value,
]);
final Map<int, int> _base91Decode = {
  for (var index = 0; index < _base91Alphabet.length; index++)
    _base91Alphabet.codeUnitAt(index): index,
};

sealed class OpenQspAprsCarriageException implements Exception {
  const OpenQspAprsCarriageException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class OpenQspAprsInvalidBase36Exception
    extends OpenQspAprsCarriageException {
  const OpenQspAprsInvalidBase36Exception(super.message);
}

final class OpenQspAprsInvalidFragmentException
    extends OpenQspAprsCarriageException {
  const OpenQspAprsInvalidFragmentException(super.message);
}

final class OpenQspAprsInvalidFrameException
    extends OpenQspAprsCarriageException {
  const OpenQspAprsInvalidFrameException(super.message);
}

final class OpenQspAprsTransactionConflictException
    extends OpenQspAprsCarriageException {
  const OpenQspAprsTransactionConflictException(super.message);
}

String encodeBase36(int value, int width) {
  if (width <= 0 || value < 0) {
    throw const OpenQspAprsInvalidBase36Exception(
      'value and width are outside the representable range',
    );
  }
  var remaining = value;
  final characters = <String>[];
  do {
    characters.add(_base36Alphabet[remaining % 36]);
    remaining ~/= 36;
  } while (remaining != 0);
  if (characters.length > width) {
    throw const OpenQspAprsInvalidBase36Exception(
      'value is too large for the requested width',
    );
  }
  return characters.reversed.join().padLeft(width, '0');
}

int decodeBase36(String text, int width) {
  if (width <= 0 || text.length != width || !_base36Pattern.hasMatch(text)) {
    throw const OpenQspAprsInvalidBase36Exception(
      'base36 text must have the exact width and use uppercase 0-9A-Z',
    );
  }
  var result = 0;
  for (final codeUnit in text.codeUnits) {
    final digit = codeUnit <= 57 ? codeUnit - 48 : codeUnit - 55;
    result = result * 36 + digit;
  }
  return result;
}

String encodeOpenQspBase91(List<int> data) {
  var value = 0;
  var bits = 0;
  final output = StringBuffer();
  for (final byte in data) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError.value(byte, 'data', 'must contain bytes');
    }
    value |= byte << bits;
    bits += 8;
    if (bits > 13) {
      var encoded = value & 8191;
      if (encoded > 88) {
        value >>= 13;
        bits -= 13;
      } else {
        encoded = value & 16383;
        value >>= 14;
        bits -= 14;
      }
      output.write(_base91Alphabet[encoded % 91]);
      output.write(_base91Alphabet[encoded ~/ 91]);
    }
  }
  if (bits != 0) {
    output.write(_base91Alphabet[value % 91]);
    if (bits > 7 || value > 90) output.write(_base91Alphabet[value ~/ 91]);
  }
  return output.toString();
}

Uint8List decodeOpenQspBase91(String text) {
  if (text.isEmpty) {
    throw const OpenQspAprsInvalidFragmentException('invalid Base91 text');
  }
  var value = -1;
  var accumulator = 0;
  var bits = 0;
  final output = <int>[];
  for (final codeUnit in text.codeUnits) {
    final decoded = _base91Decode[codeUnit];
    if (decoded == null) {
      throw const OpenQspAprsInvalidFragmentException(
        'invalid OpenQSP Base91 character',
      );
    }
    if (value < 0) {
      value = decoded;
      continue;
    }
    value += decoded * 91;
    accumulator |= value << bits;
    bits += (value & 8191) > 88 ? 13 : 14;
    while (bits >= 8) {
      output.add(accumulator & 0xff);
      accumulator >>= 8;
      bits -= 8;
    }
    value = -1;
  }
  if (value >= 0) {
    accumulator |= value << bits;
    bits += 7;
    while (bits >= 8) {
      output.add(accumulator & 0xff);
      accumulator >>= 8;
      bits -= 8;
    }
  }
  return Uint8List.fromList(output);
}

String encodeFrameText(Uint8List frame) {
  _validateFrame(frame);
  return base64Url.encode(frame).replaceAll('=', '');
}

Uint8List decodeFrameText(String text) {
  if (text.isEmpty ||
      !_frameTextPattern.hasMatch(text) ||
      text.length % 4 == 1) {
    throw const OpenQspAprsInvalidFrameException(
      'invalid unpadded Base64url frame text',
    );
  }
  try {
    final padding = (4 - text.length % 4) % 4;
    final frame = Uint8List.fromList(
      base64Url.decode(text.padRight(text.length + padding, '=')),
    );
    _validateFrame(frame);
    return frame;
  } on OpenQspAprsCarriageException {
    rethrow;
  } on Object {
    throw const OpenQspAprsInvalidFrameException(
      'frame text does not contain a valid OpenQSP Core frame',
    );
  }
}

void _validateFrame(List<int> frame) {
  try {
    const OpenQspCodec().decode(frame);
  } on Object {
    throw const OpenQspAprsInvalidFrameException(
      'bytes are not one complete valid OpenQSP Core frame',
    );
  }
}

final class OpenQspAprsFragment {
  const OpenQspAprsFragment({
    required this.transactionId,
    required this.index,
    required this.total,
    required this.data,
    this.messageId,
    this.version = 1,
    this.rawData,
  });

  final String transactionId;
  final int index;
  final int total;
  final String data;
  final String? messageId;
  final int version;
  final Uint8List? rawData;

  String get body {
    if (version == 2) {
      final transaction = decodeBase36(transactionId, 3);
      if (transaction > 0xff || index < 0 || index >= total || total > 16) {
        throw const OpenQspAprsInvalidFragmentException(
          'Q2 fragment header is outside its allowed range',
        );
      }
      final raw = rawData;
      if (raw == null || raw.isEmpty) {
        throw const OpenQspAprsInvalidFragmentException(
          'Q2 fragment requires raw Core bytes',
        );
      }
      final descriptor = (index << 4) | (total - 1);
      final result = 'Q2${encodeOpenQspBase91([transaction, descriptor, ...raw])}';
      if (result.length > openQspAprsMaxBodyLength) {
        throw const OpenQspAprsInvalidFragmentException(
          'Q2 fragment exceeds APRS message body limit',
        );
      }
      return result;
    }
    return 'Q1:$transactionId:${encodeBase36(index, 2)}/${encodeBase36(total, 2)}:$data'
        '${messageId == null ? '' : '{$messageId'}';
  }
}

List<OpenQspAprsFragment> fragmentFrame(
  Uint8List frame,
  String transactionId,
) {
  decodeBase36(transactionId, 3);
  final text = encodeFrameText(frame);
  final total = (text.length + openQspAprsDataChunkSize - 1) ~/
      openQspAprsDataChunkSize;
  if (total > openQspAprsMaxFragments) {
    throw const OpenQspAprsInvalidFragmentException(
      'frame requires more than 16 APRS fragments',
    );
  }
  return [
    for (var index = 0; index < total; index++)
      OpenQspAprsFragment(
        transactionId: transactionId,
        index: index,
        total: total,
        data: text.substring(
          index * openQspAprsDataChunkSize,
          (index + 1) * openQspAprsDataChunkSize < text.length
              ? (index + 1) * openQspAprsDataChunkSize
              : text.length,
        ),
      ),
  ];
}

List<OpenQspAprsFragment> fragmentFrameV2(
  Uint8List frame,
  String transactionId,
) {
  final transaction = decodeBase36(transactionId, 3);
  if (transaction > 0xff) {
    throw const OpenQspAprsInvalidFragmentException(
      'Q2 transaction ID must fit in one byte',
    );
  }
  _validateFrame(frame);
  final total = (frame.length + openQspAprsV2DataChunkSize - 1) ~/
      openQspAprsV2DataChunkSize;
  if (total < 1 || total > openQspAprsMaxFragments) {
    throw const OpenQspAprsInvalidFragmentException(
      'frame requires more than 16 Q2 fragments',
    );
  }
  return [
    for (var index = 0; index < total; index++)
      OpenQspAprsFragment(
        transactionId: transactionId,
        index: index,
        total: total,
        data: '',
        version: 2,
        rawData: Uint8List.fromList(
          frame.sublist(
            index * openQspAprsV2DataChunkSize,
            ((index + 1) * openQspAprsV2DataChunkSize).clamp(0, frame.length),
          ),
        ),
      ),
  ];
}

OpenQspAprsFragment parseFragment(String body) {
  if (body.startsWith('Q2')) return _parseQ2(body);
  final match = _fragmentPattern.firstMatch(body);
  if (match == null) {
    throw const OpenQspAprsInvalidFragmentException(
      'fragment does not match a supported OpenQSP APRS format',
    );
  }
  final index = decodeBase36(match.group(2)!, 2);
  final total = decodeBase36(match.group(3)!, 2);
  if (total < 1 || total > openQspAprsMaxFragments || index >= total) {
    throw const OpenQspAprsInvalidFragmentException(
      'fragment index or total is outside its allowed range',
    );
  }
  return OpenQspAprsFragment(
    transactionId: match.group(1)!,
    index: index,
    total: total,
    data: match.group(4)!,
    messageId: match.group(5),
  );
}

OpenQspAprsFragment _parseQ2(String body) {
  if (body.contains('{') || body.length > openQspAprsMaxBodyLength) {
    throw const OpenQspAprsInvalidFragmentException(
      'Q2 fragments do not use APRS message IDs',
    );
  }
  final decoded = decodeOpenQspBase91(body.substring(2));
  if (decoded.length < 3) {
    throw const OpenQspAprsInvalidFragmentException('Q2 fragment is truncated');
  }
  final descriptor = decoded[1];
  final index = descriptor >> 4;
  final total = (descriptor & 0x0f) + 1;
  if (index >= total || decoded.length - 2 > openQspAprsV2DataChunkSize) {
    throw const OpenQspAprsInvalidFragmentException(
      'Q2 fragment is outside its allowed range',
    );
  }
  final raw = Uint8List.fromList(decoded.sublist(2));
  return OpenQspAprsFragment(
    transactionId: encodeBase36(decoded[0], 3),
    index: index,
    total: total,
    data: encodeOpenQspBase91(raw),
    version: 2,
    rawData: raw,
  );
}

final class OpenQspAprsReassembler {
  OpenQspAprsReassembler({
    this.ttl = openQspAprsDefaultTtl,
    this.maxEntries = openQspAprsDefaultMaxEntries,
  }) {
    if (ttl.isNegative || ttl == Duration.zero || maxEntries < 1) {
      throw ArgumentError('ttl and maxEntries must be positive');
    }
  }

  final Duration ttl;
  final int maxEntries;
  final Map<_AssemblyKey, _Assembly> _assemblies = {};

  Uint8List? add({
    required String peer,
    required OpenQspAprsFragment fragment,
    required DateTime now,
  }) {
    _discardExpired(now);
    final key = _AssemblyKey(peer, fragment.transactionId);
    var assembly = _assemblies[key];
    if (assembly == null) {
      if (_assemblies.length >= maxEntries) {
        final oldest = _assemblies.entries.reduce(
          (a, b) => a.value.lastUpdated.isAfter(b.value.lastUpdated) ? b : a,
        );
        _assemblies.remove(oldest.key);
      }
      assembly = _Assembly(fragment.total, fragment.version, now);
      _assemblies[key] = assembly;
    } else if (assembly.total != fragment.total ||
        assembly.version != fragment.version) {
      _assemblies.remove(key);
      throw const OpenQspAprsTransactionConflictException(
        'fragment profile or total differs within the transaction',
      );
    }

    final part = fragment.version == 2 ? fragment.rawData! : fragment.data;
    final existing = assembly.parts[fragment.index];
    if (existing != null && !_partsEqual(existing, part)) {
      _assemblies.remove(key);
      throw const OpenQspAprsTransactionConflictException(
        'fragment index contains conflicting data',
      );
    }
    assembly.parts[fragment.index] = part;
    assembly.lastUpdated = now;
    if (assembly.parts.length != assembly.total) return null;

    _assemblies.remove(key);
    if (assembly.version == 2) {
      final bytes = <int>[];
      for (var index = 0; index < assembly.total; index++) {
        bytes.addAll(assembly.parts[index]! as Uint8List);
      }
      final frame = Uint8List.fromList(bytes);
      _validateFrame(frame);
      return frame;
    }
    return decodeFrameText([
      for (var index = 0; index < assembly.total; index++)
        assembly.parts[index]! as String,
    ].join());
  }

  static bool _partsEqual(Object a, Object b) {
    if (a is String && b is String) return a == b;
    if (a is Uint8List && b is Uint8List) {
      if (a.length != b.length) return false;
      for (var index = 0; index < a.length; index++) {
        if (a[index] != b[index]) return false;
      }
      return true;
    }
    return false;
  }

  void _discardExpired(DateTime now) {
    _assemblies.removeWhere(
      (_, assembly) => now.difference(assembly.lastUpdated) >= ttl,
    );
  }
}

final class _AssemblyKey {
  const _AssemblyKey(this.peer, this.transactionId);
  final String peer;
  final String transactionId;

  @override
  bool operator ==(Object other) =>
      other is _AssemblyKey &&
      peer == other.peer &&
      transactionId == other.transactionId;

  @override
  int get hashCode => Object.hash(peer, transactionId);
}

final class _Assembly {
  _Assembly(this.total, this.version, this.lastUpdated);
  final int total;
  final int version;
  DateTime lastUpdated;
  final Map<int, Object> parts = {};
}
