import 'dart:convert';
import 'dart:typed_data';

import '../../../core/openqsp_protocol/openqsp_protocol.dart';

const int openQspAprsDataChunkSize = 48;
const int openQspAprsMaxFragments = 16;
const Duration openQspAprsDefaultTtl = Duration(seconds: 120);
const int openQspAprsDefaultMaxEntries = 128;

const _base36Alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
final _base36Pattern = RegExp(r'^[0-9A-Z]+$');
final _frameTextPattern = RegExp(r'^[A-Za-z0-9_-]+$');
final _fragmentPattern = RegExp(
  r'^Q1:([0-9A-Z]{3}):([0-9A-Z]{2})/([0-9A-Z]{2}):([A-Za-z0-9_-]{1,48})(?:\{([0-9A-Z]{1,5}))?$',
);

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
    final frame = Uint8List.fromList(base64Url.decode(text.padRight(text.length + padding, '=')));
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
  });

  final String transactionId;
  final int index;
  final int total;
  final String data;
  final String? messageId;

  String get body =>
      'Q1:$transactionId:${encodeBase36(index, 2)}/${encodeBase36(total, 2)}:$data'
      '${messageId == null ? '' : '{$messageId'}';
}

List<OpenQspAprsFragment> fragmentFrame(
  Uint8List frame,
  String transactionId,
) {
  try {
    decodeBase36(transactionId, 3);
  } on OpenQspAprsInvalidBase36Exception {
    throw const OpenQspAprsInvalidFragmentException(
      'transaction ID must be three uppercase base36 characters',
    );
  }
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

OpenQspAprsFragment parseFragment(String body) {
  final match = _fragmentPattern.firstMatch(body);
  if (match == null) {
    throw const OpenQspAprsInvalidFragmentException(
      'fragment does not match the canonical Q1 format',
    );
  }
  try {
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
  } on OpenQspAprsCarriageException {
    rethrow;
  } on Object {
    throw const OpenQspAprsInvalidFragmentException('invalid Q1 fragment');
  }
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
      assembly = _Assembly(fragment.total, now);
      _assemblies[key] = assembly;
    } else if (assembly.total != fragment.total) {
      _assemblies.remove(key);
      throw const OpenQspAprsTransactionConflictException(
        'fragment total differs within the transaction',
      );
    }

    final existing = assembly.parts[fragment.index];
    if (existing != null && existing != fragment.data) {
      _assemblies.remove(key);
      throw const OpenQspAprsTransactionConflictException(
        'fragment index contains conflicting data',
      );
    }
    assembly.parts[fragment.index] = fragment.data;
    assembly.lastUpdated = now;
    if (assembly.parts.length != assembly.total) return null;

    _assemblies.remove(key);
    return decodeFrameText([
      for (var index = 0; index < assembly.total; index++)
        assembly.parts[index]!,
    ].join());
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
  _Assembly(this.total, this.lastUpdated);
  final int total;
  DateTime lastUpdated;
  final Map<int, String> parts = {};
}
