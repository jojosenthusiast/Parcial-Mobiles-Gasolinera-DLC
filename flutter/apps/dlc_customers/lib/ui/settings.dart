import 'package:flutter/material.dart';

import 'format.dart';

/// Per-customer display preferences. Kept in memory only: the app has no
/// local preference store yet, so choices reset when the app restarts.
class DlcSettings extends ChangeNotifier {
  DlcSettings({
    ThemeMode themeMode = ThemeMode.system,
    VolumeUnit volumeUnit = VolumeUnit.liter,
    int decimals = 2,
  }) : _themeMode = themeMode,
       _volumeUnit = volumeUnit,
       _decimals = decimals.clamp(0, 4);

  ThemeMode _themeMode;
  VolumeUnit _volumeUnit;
  int _decimals;

  ThemeMode get themeMode => _themeMode;
  VolumeUnit get volumeUnit => _volumeUnit;

  /// Decimals for money amounts (0-4, default 2).
  int get decimals => _decimals;

  set themeMode(ThemeMode value) {
    if (value == _themeMode) return;
    _themeMode = value;
    notifyListeners();
  }

  set volumeUnit(VolumeUnit value) {
    if (value == _volumeUnit) return;
    _volumeUnit = value;
    notifyListeners();
  }

  set decimals(int value) {
    final next = value.clamp(0, 4);
    if (next == _decimals) return;
    _decimals = next;
    notifyListeners();
  }

  /// Money formatted with the customer's decimals.
  String money(dynamic value, {String currency = 'USD'}) =>
      formatMoney(value, decimals: _decimals, currency: currency);
}

/// Makes [DlcSettings] available below the app root; widgets that read it
/// rebuild when a preference changes.
class SettingsScope extends InheritedNotifier<DlcSettings> {
  const SettingsScope({
    super.key,
    required DlcSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static final DlcSettings _fallback = DlcSettings();

  /// Settings in scope, or defaults when none is provided (isolated widgets).
  static DlcSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier ??
      _fallback;
}
