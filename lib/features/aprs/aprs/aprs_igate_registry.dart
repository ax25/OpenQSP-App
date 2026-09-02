import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ax25/ax25_address.dart';

/// Learns concrete digipeaters observed on RF and stores the optional station
/// that should be used as the explicit AX.25 path for outgoing traffic.
class AprsIgateRegistry extends ChangeNotifier {
  AprsIgateRegistry._();

  static final AprsIgateRegistry instance = AprsIgateRegistry._();

  static const digipeaterTtl = Duration(minutes: 15);
  static const _knownIgatesKey = 'tnc.aprs.knownIgates';
  static const _forcedIgateKey = 'tnc.aprs.forcedIgate';
  static const _lastSeenKey = 'tnc.aprs.digipeaterLastSeen';

  final Set<String> _knownIgates = <String>{};
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};
  String? _forcedIgate;
  Future<void>? _loading;
  bool _loaded = false;
  Timer? _expiryTimer;

  List<String> get knownIgates {
    final values = _knownIgates.toList()..sort();
    return List<String>.unmodifiable(values);
  }

  String? get forcedIgate => _forcedIgate;

  bool get hasClearableDigipeaters =>
      _knownIgates.any((value) => value != _forcedIgate);

  List<Ax25Address> get forcedPath {
    final value = _forcedIgate;
    if (value == null) return const [];
    final address = _parseAddress(value);
    return address == null ? const [] : <Ax25Address>[address];
  }

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final beforeKnown = Set<String>.from(_knownIgates);
      final beforeForced = _forcedIgate;

      final storedLastSeen = _decodeLastSeen(
        preferences.getStringList(_lastSeenKey) ?? const [],
      );
      _lastSeen.addAll(storedLastSeen);

      // Legacy known entries without a timestamp are deliberately not restored:
      // there is no evidence that they were heard within the last 15 minutes.
      for (final value in preferences.getStringList(_knownIgatesKey) ?? const []) {
        final normalized = _normalize(value);
        if (normalized != null && _lastSeen.containsKey(normalized)) {
          _knownIgates.add(normalized);
        }
      }

      final storedForced = _normalize(preferences.getString(_forcedIgateKey));
      if (_forcedIgate == null && storedForced != null) {
        _forcedIgate = storedForced;
      }
      if (_forcedIgate case final forced?) _knownIgates.add(forced);

      _loaded = true;
      await _expireStale(DateTime.now().toUtc(), persist: false);
      _scheduleExpiry();
      await _persistKnown();

      if (!setEquals(beforeKnown, _knownIgates) || beforeForced != _forcedIgate) {
        notifyListeners();
      }
    } finally {
      _loading = null;
    }
  }

  /// Records a digipeater immediately in memory and refreshes its last-seen
  /// timestamp. Persistence is best-effort so APRS parsing remains usable in
  /// binding-free unit tests.
  void observe(String value) {
    final normalized = _normalize(value);
    if (normalized == null) return;

    final added = _knownIgates.add(normalized);
    _lastSeen[normalized] = DateTime.now().toUtc();
    if (added) notifyListeners();
    _scheduleExpiry();
    unawaited(_mergeAndPersistKnown());
  }

  Future<void> _mergeAndPersistKnown() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedLastSeen = _decodeLastSeen(
        preferences.getStringList(_lastSeenKey) ?? const [],
      );
      for (final entry in storedLastSeen.entries) {
        final current = _lastSeen[entry.key];
        if (current == null || entry.value.isAfter(current)) {
          _lastSeen[entry.key] = entry.value;
        }
      }
      await _persistKnown(preferences: preferences);
    } catch (_) {
      // SharedPreferences needs a Flutter services binding. APRS parsing also
      // runs in binding-free unit tests, where learning remains in-memory.
    }
  }

  Future<void> setForced(String? value) async {
    await load();
    final normalized = value == null ? null : _normalize(value);
    if (value != null && normalized == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Invalid AX.25 digipeater address',
      );
    }
    if (_forcedIgate == normalized) return;

    _forcedIgate = normalized;
    if (normalized != null) _knownIgates.add(normalized);
    await _expireStale(DateTime.now().toUtc(), persist: false);
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    if (normalized == null) {
      await preferences.remove(_forcedIgateKey);
    } else {
      await preferences.setString(_forcedIgateKey, normalized);
    }
    await _persistKnown(preferences: preferences);
    _scheduleExpiry();
  }

  /// Clears every learned digipeater except the currently forced station.
  Future<void> clearDiscovered() async {
    await load();
    final forced = _forcedIgate;
    final changed = _knownIgates.any((value) => value != forced);
    if (!changed) return;

    _knownIgates
      ..clear()
      ..addAll(forced == null ? const <String>[] : <String>[forced]);
    _lastSeen.removeWhere((key, _) => key != forced);
    notifyListeners();
    await _persistKnown();
    _scheduleExpiry();
  }

  Future<void> _expireStale(
    DateTime now, {
    bool persist = true,
  }) async {
    final forced = _forcedIgate;
    final expired = <String>[
      for (final value in _knownIgates)
        if (value != forced &&
            (_lastSeen[value] == null ||
                now.difference(_lastSeen[value]!) >= digipeaterTtl))
          value,
    ];
    if (expired.isEmpty) return;

    _knownIgates.removeAll(expired);
    for (final value in expired) {
      _lastSeen.remove(value);
    }
    notifyListeners();
    if (persist) await _persistKnown();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final now = DateTime.now().toUtc();
    DateTime? nextExpiry;
    for (final entry in _lastSeen.entries) {
      if (entry.key == _forcedIgate || !_knownIgates.contains(entry.key)) continue;
      final candidate = entry.value.add(digipeaterTtl);
      if (nextExpiry == null || candidate.isBefore(nextExpiry)) {
        nextExpiry = candidate;
      }
    }
    if (nextExpiry == null) return;

    final delay = nextExpiry.isAfter(now)
        ? nextExpiry.difference(now)
        : Duration.zero;
    _expiryTimer = Timer(delay, () async {
      await _expireStale(DateTime.now().toUtc());
      _scheduleExpiry();
    });
  }

  Future<void> _persistKnown({SharedPreferences? preferences}) async {
    try {
      final prefs = preferences ?? await SharedPreferences.getInstance();
      await prefs.setStringList(_knownIgatesKey, knownIgates);
      await prefs.setStringList(_lastSeenKey, _encodeLastSeen());
    } catch (_) {
      // See _mergeAndPersistKnown: persistence is best-effort during parsing.
    }
  }

  List<String> _encodeLastSeen() {
    final values = <String>[];
    for (final entry in _lastSeen.entries) {
      if (_knownIgates.contains(entry.key)) {
        values.add('${entry.key}|${entry.value.millisecondsSinceEpoch}');
      }
    }
    values.sort();
    return values;
  }

  static Map<String, DateTime> _decodeLastSeen(List<String> values) {
    final result = <String, DateTime>{};
    for (final value in values) {
      final separator = value.lastIndexOf('|');
      if (separator <= 0 || separator == value.length - 1) continue;
      final callsign = _normalize(value.substring(0, separator));
      final millis = int.tryParse(value.substring(separator + 1));
      if (callsign == null || millis == null) continue;
      result[callsign] = DateTime.fromMillisecondsSinceEpoch(
        millis,
        isUtc: true,
      );
    }
    return result;
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return null;
    final match = RegExp(r'^([A-Z0-9]{1,6})(?:-([0-9]|1[0-5]))?$')
        .firstMatch(normalized);
    return match == null ? null : normalized;
  }

  static Ax25Address? _parseAddress(String value) {
    final match = RegExp(r'^([A-Z0-9]{1,6})(?:-([0-9]|1[0-5]))?$')
        .firstMatch(value);
    if (match == null) return null;
    return Ax25Address(
      callsign: match.group(1)!,
      ssid: int.tryParse(match.group(2) ?? '') ?? 0,
      hasBeenRepeated: false,
      isLast: true,
    );
  }

  @visibleForTesting
  Future<void> expireNowForTesting(DateTime now) async {
    await load();
    await _expireStale(now.toUtc());
    _scheduleExpiry();
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _knownIgates.clear();
    _lastSeen.clear();
    _forcedIgate = null;
    _loaded = false;
    _loading = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_knownIgatesKey);
    await preferences.remove(_forcedIgateKey);
    await preferences.remove(_lastSeenKey);
    notifyListeners();
  }
}
