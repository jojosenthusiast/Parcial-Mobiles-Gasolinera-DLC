import 'dart:convert';

import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/widgets.dart';

import 'format.dart';

/// Storage boundary for small per-device preferences (a protocol in Swift).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// Uses the employee session's secure storage (`operations.pref.<key>`).
class SessionKeyValueStore implements KeyValueStore {
  const SessionKeyValueStore(this.session);
  final EmployeeSession session;
  @override
  Future<String?> read(String key) => session.readPreference(key);
  @override
  Future<void> write(String key, String value) =>
      session.writePreference(key, value);
}

/// Volume unit and decimals chosen in Perfil > Configuración. Persisted per
/// device and exposed to every formatter through [DisplayPrefsScope].
class DisplayPrefsController extends ChangeNotifier {
  DisplayPrefsController({KeyValueStore? store})
    : _store = store ?? InMemoryKeyValueStore();

  final KeyValueStore _store;
  DisplayPrefs _prefs = DisplayPrefs.defaults;

  static const unitKey = 'volumeUnit';
  static const decimalsKey = 'decimals';

  DisplayPrefs get prefs => _prefs;

  Future<void> load() async {
    try {
      final unit = VolumeUnit.fromStorage(await _store.read(unitKey));
      final decimals = clampDecimals(
        int.tryParse(await _store.read(decimalsKey) ?? ''),
      );
      _prefs = DisplayPrefs(unit: unit, decimals: decimals);
    } catch (_) {
      _prefs = DisplayPrefs.defaults;
    }
    notifyListeners();
  }

  Future<void> setUnit(VolumeUnit unit) async {
    if (unit == _prefs.unit) return;
    _prefs = _prefs.copyWith(unit: unit);
    notifyListeners();
    try {
      await _store.write(unitKey, unit.storage);
    } catch (_) {
      // Best effort: the in-memory choice stands.
    }
  }

  Future<void> setDecimals(int decimals) async {
    final next = clampDecimals(decimals);
    if (next == _prefs.decimals) return;
    _prefs = _prefs.copyWith(decimals: next);
    notifyListeners();
    try {
      await _store.write(decimalsKey, '$next');
    } catch (_) {
      // Best effort.
    }
  }
}

/// Provides [DisplayPrefs] below the app; rebuilds dependants on change.
class DisplayPrefsScope extends InheritedNotifier<DisplayPrefsController> {
  const DisplayPrefsScope({
    required DisplayPrefsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static DisplayPrefsController? maybeControllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DisplayPrefsScope>()
          ?.notifier;
}

extension DisplayPrefsContext on BuildContext {
  /// Current formatting preferences (defaults when no scope is mounted).
  DisplayPrefs get prefs =>
      DisplayPrefsScope.maybeControllerOf(this)?.prefs ?? DisplayPrefs.defaults;
}

/// Free-form JSON helpers for per-user preference blobs.
String? encodeJson(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return null;
  }
}

Object? decodeJson(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}
