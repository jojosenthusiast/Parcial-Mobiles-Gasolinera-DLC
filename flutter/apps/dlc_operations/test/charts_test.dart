import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/charts.dart';
import 'package:dlc_operations/haptics.dart';
import 'package:dlc_operations/tank_levels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: lightTheme,
  darkTheme: darkTheme,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

const levels = [
  FuelLevel(
    family: 'super',
    label: 'Súper',
    percent: 20,
    liters: 200,
    capacityLiters: 1000,
    tankCount: 1,
    unmeasuredTanks: 0,
  ),
  FuelLevel(
    family: 'regular',
    label: 'Regular',
    percent: 55,
    liters: 550,
    capacityLiters: 1000,
    tankCount: 1,
    unmeasuredTanks: 0,
  ),
  FuelLevel(
    family: 'diesel',
    label: 'Diésel',
    percent: 90,
    liters: 900,
    capacityLiters: 1000,
    tankCount: 2,
    unmeasuredTanks: 0,
  ),
];

void main() {
  group('summarizeTrend', () {
    test('empty series', () {
      final s = summarizeTrend(const []);
      expect(s.total, 0);
      expect(s.best, isNull);
    });
    test('total, average, best and worst', () {
      final s = summarizeTrend(const [
        TrendPoint('01/10', 10),
        TrendPoint('02/10', 40),
        TrendPoint('03/10', 20),
      ]);
      expect(s.total, 70);
      expect(s.average, closeTo(23.333, 0.001));
      expect(s.best!.label, '02/10');
      expect(s.worst!.label, '01/10');
    });
  });

  test('groupedNumber formats thousands and decimals', () {
    expect(groupedNumber(0), '0');
    expect(groupedNumber(999), '999');
    expect(groupedNumber(1234), '1,234');
    expect(groupedNumber(1234567.891, decimals: 2), '1,234,567.89');
    expect(groupedNumber(-12345), '-12,345');
  });

  group('TankLevelBars', () {
    testWidgets('shows label, percentage, status text and a CustomPaint', (
      tester,
    ) async {
      await tester.pumpWidget(host(const TankLevelBars(levels: levels)));
      await tester.pumpAndSettle();
      for (final text in ['Súper', 'Regular', 'Diésel']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('20 %'), findsOneWidget);
      expect(find.text('55 %'), findsOneWidget);
      expect(find.text('90 %'), findsOneWidget);
      expect(find.textContaining('Nivel crítico'), findsOneWidget);
      expect(find.textContaining('Nivel medio'), findsOneWidget);
      expect(find.textContaining('Nivel óptimo'), findsOneWidget);
      // One status icon per fuel (never colour alone).
      expect(find.byIcon(DlcStatus.critical.icon), findsOneWidget);
      expect(find.byIcon(DlcStatus.medium.icon), findsOneWidget);
      expect(find.byIcon(DlcStatus.optimal.icon), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('exposes one semantic summary', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const TankLevelBars(levels: levels)));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Súper: 20 %, nivel crítico')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('renders final width immediately when animations are off', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const TankLevelBars(levels: levels), disableAnimations: true),
      );
      await tester.pump(); // a single frame is enough
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<TankBarPainter>()
          .toList();
      expect(painters.map((p) => p.fraction), [0.2, 0.55, 0.9]);
    });

    testWidgets('empty list shows a text fallback', (tester) async {
      await tester.pumpWidget(host(const TankLevelBars(levels: [])));
      expect(find.text('Sin tanques configurados.'), findsOneWidget);
    });

    testWidgets('unmeasured fuel is labelled in words', (tester) async {
      await tester.pumpWidget(
        host(
          const TankLevelBars(
            levels: [
              FuelLevel(
                family: 'super',
                label: 'Súper',
                percent: null,
                liters: 0,
                capacityLiters: 1000,
                tankCount: 1,
                unmeasuredTanks: 1,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('— %'), findsOneWidget);
      expect(find.text('Sin medición'), findsOneWidget);
    });
  });

  group('TrendBarChart', () {
    const points = [
      TrendPoint('01/10', 100),
      TrendPoint('02/10', 250),
      TrendPoint('03/10', 175),
    ];

    testWidgets('shows caption and expandable text alternative', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TrendBarChart(
            title: 'Ventas por día (USD)',
            points: points,
            format: (v) => 'US\$ ${v.toStringAsFixed(0)}',
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(find.text('Ventas por día (USD)'), findsOneWidget);
      expect(find.textContaining('Total US\$ 525'), findsOneWidget);
      expect(find.textContaining('mejor día 02/10'), findsOneWidget);
      await tester.tap(find.text('Ver datos como texto'));
      await tester.pumpAndSettle();
      expect(find.text('US\$ 175'), findsOneWidget);
    });

    testWidgets('semantics label summarises the chart', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          TrendBarChart(
            title: 'Consumo',
            points: points,
            format: (v) => '${v.toStringAsFixed(0)} L',
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('Consumo. Total 525 L')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('empty series falls back to text', (tester) async {
      await tester.pumpWidget(
        host(
          TrendBarChart(title: 'Ventas', points: const [], format: (v) => '$v'),
        ),
      );
      expect(find.textContaining('Sin datos para Ventas'), findsOneWidget);
    });
  });

  group('Haptics', () {
    tearDown(() {
      Haptics.debugSupportedOverride = null;
      Haptics.debugListener = null;
    });

    test('is a silent no-op where haptics are unsupported', () async {
      final fired = <String>[];
      Haptics.debugSupportedOverride = false;
      Haptics.debugListener = fired.add;
      await Haptics.selection();
      await Haptics.error();
      await Haptics.critical();
      expect(fired, isEmpty);
    });

    test('maps each helper to its own kind when supported', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fired = <String>[];
      Haptics.debugSupportedOverride = true;
      Haptics.debugListener = fired.add;
      await Haptics.selection();
      await Haptics.success();
      await Haptics.error();
      await Haptics.critical();
      expect(fired, ['selection', 'success', 'error', 'critical']);
    });
  });
}
