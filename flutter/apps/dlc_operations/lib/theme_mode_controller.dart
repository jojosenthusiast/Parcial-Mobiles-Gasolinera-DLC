import 'package:flutter/material.dart';

/// Storage boundary for the theme preference (maps to a protocol in Swift).
abstract class ThemePreferenceStore {
  Future<String?> read();
  Future<void> write(String value);
}

class InMemoryThemePreferenceStore implements ThemePreferenceStore {
  String? _value;
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async => _value = value;
}

/// Adapts any async key/value pair of functions (e.g. the session's secure
/// storage) to [ThemePreferenceStore] without adding a dependency.
class CallbackThemePreferenceStore implements ThemePreferenceStore {
  const CallbackThemePreferenceStore({
    required Future<String?> Function() reader,
    required Future<void> Function(String value) writer,
  }) : _reader = reader,
       _writer = writer;
  final Future<String?> Function() _reader;
  final Future<void> Function(String value) _writer;
  @override
  Future<String?> read() => _reader();
  @override
  Future<void> write(String value) => _writer(value);
}

String themeModeToStorage(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

ThemeMode themeModeFromStorage(String? raw) => switch (raw) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

ThemeMode nextThemeMode(ThemeMode mode) => switch (mode) {
  ThemeMode.system => ThemeMode.light,
  ThemeMode.light => ThemeMode.dark,
  ThemeMode.dark => ThemeMode.system,
};

String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Claro',
  ThemeMode.dark => 'Oscuro',
  ThemeMode.system => 'Sistema',
};

IconData themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
  ThemeMode.system => Icons.brightness_auto_outlined,
};

class ThemeModeController extends ChangeNotifier {
  ThemeModeController({ThemePreferenceStore? store})
    : _store = store ?? InMemoryThemePreferenceStore();
  final ThemePreferenceStore _store;
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      _mode = themeModeFromStorage(await _store.read());
    } catch (_) {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> select(ThemeMode next) async {
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
    try {
      await _store.write(themeModeToStorage(next));
    } catch (_) {
      // Preference persistence is best effort; the in-memory choice stands.
    }
  }
}

/// Light / Dark / System selector for the account/settings screen.
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({required this.controller, super.key});
  final ThemeModeController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Apariencia',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in ThemeMode.values)
                ButtonSegment(
                  value: mode,
                  icon: Icon(themeModeIcon(mode)),
                  label: Text(themeModeLabel(mode)),
                ),
            ],
            selected: {controller.mode},
            onSelectionChanged: (s) => controller.select(s.first),
          ),
        ),
      ],
    ),
  );
}
