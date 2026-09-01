import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ConversationVisibilityStore {
  Future<Map<String, Set<String>>> hiddenMessageIds(String callsign);
  Future<void> hideMessages(
    String callsign,
    String peer,
    Iterable<String> messageIds,
  );
}

final class PreferencesConversationVisibilityStore
    implements ConversationVisibilityStore {
  PreferencesConversationVisibilityStore({Future<SharedPreferences>? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;
  Future<void> _writeTail = Future<void>.value();

  static const _prefix = 'openqsp.conversation-hidden-messages.v1.';

  @override
  Future<Map<String, Set<String>>> hiddenMessageIds(String callsign) async {
    await _writeTail;
    final preferences = await _preferences;
    return _decode(preferences.getString(_key(callsign)));
  }

  @override
  Future<void> hideMessages(
    String callsign,
    String peer,
    Iterable<String> messageIds,
  ) {
    final ids = messageIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return _writeTail;
    final completer = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        final preferences = await _preferences;
        final current = _decode(preferences.getString(_key(callsign)));
        current.putIfAbsent(_normalize(peer), () => <String>{}).addAll(ids);
        await preferences.setString(
          _key(callsign),
          jsonEncode(
            current.map((key, value) => MapEntry(key, value.toList()..sort())),
          ),
        );
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Map<String, Set<String>> _decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return <String, Set<String>>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, Set<String>>{};
      final result = <String, Set<String>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! List) continue;
        result[_normalize(entry.key.toString())] = value
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
      }
      return result;
    } on Object {
      return <String, Set<String>>{};
    }
  }

  static String _normalize(String value) => value.trim().toUpperCase();
  static String _key(String callsign) => '$_prefix${_normalize(callsign)}';
}

final class MemoryConversationVisibilityStore implements ConversationVisibilityStore {
  final Map<String, Map<String, Set<String>>> _values = {};

  @override
  Future<Map<String, Set<String>>> hiddenMessageIds(String callsign) async {
    final stored = _values[_normalize(callsign)] ?? const {};
    return stored.map((key, value) => MapEntry(key, Set<String>.of(value)));
  }

  @override
  Future<void> hideMessages(
    String callsign,
    String peer,
    Iterable<String> messageIds,
  ) async {
    final owner = _values.putIfAbsent(_normalize(callsign), () => {});
    owner
        .putIfAbsent(_normalize(peer), () => <String>{})
        .addAll(messageIds.where((id) => id.isNotEmpty));
  }

  static String _normalize(String value) => value.trim().toUpperCase();
}
