import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/message_models.dart';

abstract interface class LocalMessagesStore {
  Future<List<InternetMessage>> messages(String callsign);

  Future<void> upsert(String callsign, InternetMessage message);

  Future<void> upsertAll(String callsign, Iterable<InternetMessage> messages);

  Future<String?> cursor(String callsign, String transport);

  Future<void> setCursor(String callsign, String transport, String value);
}

/// Cross-platform persistent message cache backed by the preferences plugin.
///
/// The storage interface deliberately hides this implementation detail so a
/// database-backed store can replace it later without changing controllers or
/// transports. Writes are serialized to avoid losing concurrent websocket/APRS
/// updates.
final class PreferencesLocalMessagesStore implements LocalMessagesStore {
  PreferencesLocalMessagesStore({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;
  Future<void> _writeTail = Future<void>.value();

  static const _messagesPrefix = 'openqsp.messages.v1.';
  static const _cursorsPrefix = 'openqsp.message-cursors.v1.';

  @override
  Future<List<InternetMessage>> messages(String callsign) async {
    await _writeTail;
    final preferences = await _preferences;
    return _decodeMessages(preferences.getString(_messagesKey(callsign)));
  }

  @override
  Future<void> upsert(String callsign, InternetMessage message) =>
      upsertAll(callsign, [message]);

  @override
  Future<void> upsertAll(
    String callsign,
    Iterable<InternetMessage> messages,
  ) {
    final additions = List<InternetMessage>.of(messages);
    if (additions.isEmpty) return _writeTail;
    return _enqueue(() async {
      final preferences = await _preferences;
      final normalizedCallsign = _normalize(callsign);
      final stored = _decodeMessages(
        preferences.getString(_messagesKey(normalizedCallsign)),
      );
      for (final message in additions) {
        _upsertOne(stored, message);
      }
      stored.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await preferences.setString(
        _messagesKey(normalizedCallsign),
        jsonEncode(stored.map(_encodeMessage).toList()),
      );

      // The APRS Core cursor is the recipient mailbox sequence and is encoded
      // in the canonical message id. If an incoming message arrived first over
      // Internet, advance the APRS cursor too so switching transports does not
      // redownload that already-cached mailbox history.
      var inferredAprs = 0;
      for (final message in stored) {
        if (_normalize(message.to) != normalizedCallsign) continue;
        final sequence = _canonicalMailboxSequence(message.id, normalizedCallsign);
        if (sequence != null && sequence > inferredAprs) inferredAprs = sequence;
      }
      if (inferredAprs > 0) {
        final cursors = _decodeCursors(
          preferences.getString(_cursorsKey(normalizedCallsign)),
        );
        final current = int.tryParse(cursors['aprs'] ?? '') ?? 0;
        if (inferredAprs > current) {
          cursors['aprs'] = '$inferredAprs';
          await preferences.setString(
            _cursorsKey(normalizedCallsign),
            jsonEncode(cursors),
          );
        }
      }
    });
  }

  @override
  Future<String?> cursor(String callsign, String transport) async {
    await _writeTail;
    final preferences = await _preferences;
    final cursors = _decodeCursors(
      preferences.getString(_cursorsKey(callsign)),
    );
    return cursors[transport];
  }

  @override
  Future<void> setCursor(
    String callsign,
    String transport,
    String value,
  ) => _enqueue(() async {
    final preferences = await _preferences;
    final cursors = _decodeCursors(
      preferences.getString(_cursorsKey(callsign)),
    );
    cursors[transport] = value;
    await preferences.setString(_cursorsKey(callsign), jsonEncode(cursors));
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        await operation();
        result.complete();
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  static String _normalize(String value) => value.trim().toUpperCase();

  static String _messagesKey(String callsign) =>
      '$_messagesPrefix${_normalize(callsign)}';

  static String _cursorsKey(String callsign) =>
      '$_cursorsPrefix${_normalize(callsign)}';

  static List<InternetMessage> _decodeMessages(String? encoded) {
    if (encoded == null || encoded.isEmpty) return <InternetMessage>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <InternetMessage>[];
      return decoded
          .whereType<Map>()
          .map(
            (value) =>
                InternetMessage.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList();
    } on Object {
      // A corrupt local cache must never prevent the user from synchronizing it
      // again from the authoritative server.
      return <InternetMessage>[];
    }
  }

  static Map<String, String> _decodeCursors(String? encoded) {
    if (encoded == null || encoded.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } on Object {
      return <String, String>{};
    }
  }

  static Map<String, Object?> _encodeMessage(InternetMessage message) => {
    'id': message.id,
    'from': message.from,
    'to': message.to,
    'body': message.body,
    'created_at': message.createdAt.toUtc().toIso8601String(),
    'delivery_status': message.deliveryStatus.name,
    'delivered_at': message.deliveredAt?.toUtc().toIso8601String(),
  };

  static int? _canonicalMailboxSequence(String id, String recipient) {
    if (id.startsWith('aprs-local-')) return null;
    try {
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(id)),
      );
      final separator = decoded.lastIndexOf(':');
      if (separator <= 0) return null;
      if (_normalize(decoded.substring(0, separator)) != recipient) return null;
      final sequence = int.tryParse(decoded.substring(separator + 1));
      if (sequence == null || sequence <= 0 || sequence > 0xffffffff) return null;
      return sequence;
    } on Object {
      return null;
    }
  }

  static void _upsertOne(
    List<InternetMessage> messages,
    InternetMessage incoming,
  ) {
    var index = messages.indexWhere((message) => message.id == incoming.id);
    if (index < 0 && !incoming.id.startsWith('aprs-local-')) {
      index = messages.indexWhere(
        (message) =>
            message.id.startsWith('aprs-local-') &&
            _sameLogicalMessage(message, incoming),
      );
    }
    if (index < 0) {
      messages.add(incoming);
      return;
    }
    final current = messages[index];
    if (_statusRank(incoming.deliveryStatus) >=
        _statusRank(current.deliveryStatus)) {
      messages[index] = incoming;
    }
  }

  static bool _sameLogicalMessage(
    InternetMessage first,
    InternetMessage second,
  ) =>
      first.from == second.from &&
      first.to == second.to &&
      first.body == second.body &&
      first.createdAt.millisecondsSinceEpoch ~/ 1000 ==
          second.createdAt.millisecondsSinceEpoch ~/ 1000;

  static int _statusRank(MessageDeliveryStatus status) => switch (status) {
    MessageDeliveryStatus.stored => 0,
    MessageDeliveryStatus.delivered => 1,
    MessageDeliveryStatus.read => 2,
  };
}
