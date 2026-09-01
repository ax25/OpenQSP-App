import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ConversationVisibilityStore {
  Future<Map<String, DateTime>> cutoffs(String callsign);
  Future<void> setCutoff(String callsign, String peer, DateTime cutoff);
}

final class PreferencesConversationVisibilityStore
    implements ConversationVisibilityStore {
  PreferencesConversationVisibilityStore({Future<SharedPreferences>? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;
  Future<void> _writeTail = Future<void>.value();

  static const _prefix = 'openqsp.conversation-clear-cutoffs.v1.';

  @override
  Future<Map<String, DateTime>> cutoffs(String callsign) async {
    await _writeTail;
    final preferences = await _preferences;
    final encoded = preferences.getString(_key(callsign));
    if (encoded == null || encoded.isEmpty) return <String, DateTime>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, DateTime>{};
      final result = <String, DateTime>{};
      for (final entry in decoded.entries) {
        final value = DateTime.tryParse(entry.value.toString());
        if (value != null) result[_normalize(entry.key.toString())] = value.toUtc();
      }
      return result;
    } on Object {
      return <String, DateTime>{};
    }
  }

  @override
  Future<void> setCutoff(String callsign, String peer, DateTime cutoff) {
    final completer = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        final preferences = await _preferences;
        final current = await cutoffs(callsign);
        final normalizedPeer = _normalize(peer);
        final existing = current[normalizedPeer];
        final next = cutoff.toUtc();
        if (existing == null || next.isAfter(existing)) {
          current[normalizedPeer] = next;
          await preferences.setString(
            _key(callsign),
            jsonEncode(
              current.map(
                (key, value) => MapEntry(key, value.toUtc().toIso8601String()),
              ),
            ),
          );
        }
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static String _normalize(String value) => value.trim().toUpperCase();
  static String _key(String callsign) => '$_prefix${_normalize(callsign)}';
}

final class MemoryConversationVisibilityStore implements ConversationVisibilityStore {
  final Map<String, Map<String, DateTime>> _values = {};

  @override
  Future<Map<String, DateTime>> cutoffs(String callsign) async =>
      Map<String, DateTime>.of(_values[_normalize(callsign)] ?? const {});

  @override
  Future<void> setCutoff(String callsign, String peer, DateTime cutoff) async {
    final owner = _values.putIfAbsent(_normalize(callsign), () => {});
    final normalizedPeer = _normalize(peer);
    final next = cutoff.toUtc();
    final existing = owner[normalizedPeer];
    if (existing == null || next.isAfter(existing)) owner[normalizedPeer] = next;
  }

  static String _normalize(String value) => value.trim().toUpperCase();
}
