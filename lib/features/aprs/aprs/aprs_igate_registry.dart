import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ax25/ax25_address.dart';

/// Learns iGates observed in APRS third-party traffic and stores the optional
/// iGate that should be used as the explicit AX.25 path for outgoing traffic.
class AprsIgateRegistry extends ChangeNotifier {
  AprsIgateRegistry._();

  static final AprsIgateRegistry instance = AprsIgateRegistry._();

  static const _knownIgatesKey = 'tnc.aprs.knownIgates';
  static const _forcedIgateKey = 'tnc.aprs.forcedIgate';

  final Set<String> _knownIgates = <String>{};
  String? _forcedIgate;
  Future<void>? _loading;
  bool _loaded = false;

  List<String> get knownIgates {
    final values = _knownIgates.toList()..sort();
    return List<String>.unmodifiable(values);
  }

  String? get forcedIgate => _forcedIgate;

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
    final preferences = await SharedPreferences.getInstance();
    final beforeKnown = Set<String>.from(_knownIgates);
    final beforeForced = _forcedIgate;

    for (final value in preferences.getStringList(_knownIgatesKey) ?? const []) {
      final normalized = _normalize(value);
      if (normalized != null) _knownIgates.add(normalized);
    }

    final storedForced = _normalize(preferences.getString(_forcedIgateKey));
    if (_forcedIgate == null && storedForced != null) {
      _forcedIgate = storedForced;
    }
    if (_forcedIgate case final forced?) _knownIgates.add(forced);

    _loaded = true;
    _loading = null;
    if (!setEquals(beforeKnown, _knownIgates) || beforeForced != _forcedIgate) {
      notifyListeners();
    }
  }

  /// Records an iGate immediately in memory and persists it in the background.
  void observe(String value) {
    final normalized = _normalize(value);
    if (normalized == null || !_knownIgates.add(normalized)) return;
    notifyListeners();
    unawaited(_mergeAndPersistKnown());
  }

  Future<void> _mergeAndPersistKnown() async {
    await load();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_knownIgatesKey, knownIgates);
  }

  Future<void> setForced(String? value) async {
    await load();
    final normalized = value == null ? null : _normalize(value);
    if (value != null && normalized == null) {
      throw ArgumentError.value(value, 'value', 'Invalid AX.25 iGate address');
    }
    if (_forcedIgate == normalized) return;

    _forcedIgate = normalized;
    if (normalized != null) _knownIgates.add(normalized);
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    if (normalized == null) {
      await preferences.remove(_forcedIgateKey);
    } else {
      await preferences.setString(_forcedIgateKey, normalized);
      await preferences.setStringList(_knownIgatesKey, knownIgates);
    }
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
  Future<void> resetForTesting() async {
    _knownIgates.clear();
    _forcedIgate = null;
    _loaded = false;
    _loading = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_knownIgatesKey);
    await preferences.remove(_forcedIgateKey);
    notifyListeners();
  }
}
