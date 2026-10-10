import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DlcColors', () {
    test('light and dark themes expose their own palette', () {
      expect(lightTheme.brightness, Brightness.light);
      expect(darkTheme.brightness, Brightness.dark);
      expect(lightTheme.extension<DlcColors>(), DlcColors.light);
      expect(darkTheme.extension<DlcColors>(), DlcColors.dark);
      expect(DlcColors.light.surface, isNot(DlcColors.dark.surface));
    });

    for (final entry in {
      'light': DlcColors.light,
      'dark': DlcColors.dark,
    }.entries) {
      test('${entry.key} status colours meet AA contrast', () {
        final c = entry.value;
        for (final status in DlcStatus.values) {
          expect(
            contrastRatio(c.foreground(status), c.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$status on surface',
          );
          expect(
            contrastRatio(c.foreground(status), c.container(status)),
            greaterThanOrEqualTo(4.5),
            reason: '$status on its container',
          );
        }
        expect(contrastRatio(c.muted, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.ink, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.brand, c.surface), greaterThanOrEqualTo(4.5));
      });
    }

    test('every status has a label and an icon (never colour alone)', () {
      for (final status in DlcStatus.values) {
        expect(status.label, isNotEmpty);
        expect(status.icon, isA<IconData>());
      }
    });

    test('lerp blends between palettes', () {
      final mid = DlcColors.light.lerp(DlcColors.dark, 0.5);
      expect(mid.surface, Color.lerp(DlcColors.light.surface, DlcColors.dark.surface, 0.5));
    });

    testWidgets('context.dlc follows ThemeMode', (tester) async {
      DlcColors? seen;
      Widget app(ThemeMode mode) => MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: mode,
        home: Builder(
          builder: (context) {
            seen = context.dlc;
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(app(ThemeMode.dark));
      expect(seen, DlcColors.dark);
      await tester.pumpWidget(app(ThemeMode.light));
      await tester.pump(const Duration(seconds: 1));
      expect(seen, DlcColors.light);
    });

    testWidgets('context.dlc falls back without the extension', (tester) async {
      DlcColors? seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              seen = context.dlc;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, DlcColors.dark);
    });
  });

  group('ThemeModeController', () {
    test('defaults to system and round-trips storage values', () {
      expect(ThemeModeController().mode, ThemeMode.system);
      for (final mode in ThemeMode.values) {
        expect(themeModeFromStorage(themeModeToStorage(mode)), mode);
      }
      expect(themeModeFromStorage('garbage'), ThemeMode.system);
      expect(themeModeFromStorage(null), ThemeMode.system);
    });

    test('persists the selection and restores it', () async {
      final store = InMemoryThemePreferenceStore();
      final first = ThemeModeController(store: store);
      await first.select(ThemeMode.dark);
      expect(first.mode, ThemeMode.dark);
      final second = ThemeModeController(store: store);
      await second.load();
      expect(second.mode, ThemeMode.dark);
    });

    test('keeps the in-memory choice when storage fails', () async {
      final controller = ThemeModeController(
        store: CallbackThemePreferenceStore(
          reader: () async => throw StateError('no storage'),
          writer: (_) async => throw StateError('no storage'),
        ),
      );
      await controller.load();
      expect(controller.mode, ThemeMode.system);
      await controller.select(ThemeMode.light);
      expect(controller.mode, ThemeMode.light);
    });

    test('nextThemeMode cycles through all modes', () {
      var mode = ThemeMode.system;
      final seen = <ThemeMode>{};
      for (var i = 0; i < 3; i++) {
        seen.add(mode);
        mode = nextThemeMode(mode);
      }
      expect(seen, ThemeMode.values.toSet());
      expect(mode, ThemeMode.system);
    });

    testWidgets('selector switches the mode', (tester) async {
      final controller = ThemeModeController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ThemeModeSelector(controller: controller)),
        ),
      );
      await tester.tap(find.text('Oscuro'));
      await tester.pump();
      expect(controller.mode, ThemeMode.dark);
    });
  });
}
