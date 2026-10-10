import 'dart:math' as math;

import 'package:dlc_customers/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color a, Color b) {
  final lighter = math.max(a.computeLuminance(), b.computeLuminance());
  final darker = math.min(a.computeLuminance(), b.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const promotion = {
    'title': 'Ahorro de prueba',
    'branchName': 'Sucursal Centro',
    'motive': 'Promoción de QA',
    'startsAt': '2026-10-01',
    'endsAt': '2026-10-31',
    'timeZone': 'America/Guatemala',
    'terms': {
      'applies': ['Gasolina regular'],
      'excludes': ['Diesel'],
    },
  };

  testWidgets('dark theme builds and uses the dark color scheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDlcTheme(Brightness.light),
        darkTheme: buildDlcTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const PromotionDetailPage(promotion: promotion),
      ),
    );

    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(Scaffold).first);
    final theme = Theme.of(context);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, isNot(_paperLight));
    expect(find.text('Sucursal: Sucursal Centro'), findsOneWidget);
  });

  testWidgets('body text keeps WCAG AA contrast in light and dark themes', (
    tester,
  ) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDlcTheme(Brightness.light),
          darkTheme: buildDlcTheme(Brightness.dark),
          themeMode: mode,
          home: const PromotionDetailPage(promotion: promotion),
        ),
      );

      final element = tester.element(find.text('Sucursal: Sucursal Centro'));
      final textColor = DefaultTextStyle.of(element).style.color!;
      final background = Theme.of(element).scaffoldBackgroundColor;
      expect(
        Theme.of(element).colorScheme.onSurface,
        textColor,
        reason: 'body text must come from the color scheme ($mode)',
      );
      expect(
        _contrastRatio(textColor, background),
        greaterThanOrEqualTo(4.5),
        reason: 'contrast too low in $mode',
      );
    }
  });
}

const _paperLight = Color(0xfff5f0e5);
