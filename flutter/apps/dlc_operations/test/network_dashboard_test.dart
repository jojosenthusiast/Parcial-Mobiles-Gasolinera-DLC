import 'package:dlc_api/dlc_api.dart';
import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/live_form.dart';
import 'package:dlc_operations/network_dashboard_page.dart';
import 'package:dlc_operations/network_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row(String id, String name, {String? country}) => {
  'id': id,
  'name': name,
  'code': id.toUpperCase(),
  if (country != null) 'countryCode': country,
  'inventoryRisk': id == 'b' ? 'critical' : 'normal',
  'closedCuts': 2,
  'expectedCuts': 4,
  'products': [
    {'soldLiters': '100.5', 'salesUsd': '300'},
    {'soldLiters': '50', 'salesUsd': '150.25'},
  ],
  'tanks': [
    {
      'family': 'super',
      'fuelName': 'Súper',
      'onHandLiters': '250',
      'capacityLiters': '1000',
    },
  ],
};

class FakeSession extends EmployeeSession {
  final calls = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> networkDashboard({
    int days = 7,
    String? branchId,
    String? countryCode,
  }) async {
    calls.add({'days': days, 'branchId': branchId, 'countryCode': countryCode});
    return {
      'periodDays': days,
      'branches': [
        row('a', 'Centro'),
        row('b', 'Antigua'),
      ],
      'dailySeries': [
        {'date': '2026-10-01', 'salesUsd': '100', 'soldLiters': '40', 'closedCuts': 2},
        {'date': '2026-10-02', 'salesUsd': '200', 'soldLiters': '80', 'closedCuts': 2},
      ],
      'countries': [
        {'countryCode': 'SV', 'branchCount': 1},
        {'countryCode': 'GT', 'branchCount': 1},
      ],
      'permissions': {'sales': true, 'inventory': true},
    };
  }
}

BranchSummary branch(String id, String name, String country) => BranchSummary(
  id: id,
  code: id.toUpperCase(),
  name: name,
  zone: 'central',
  timezone: 'America/El_Salvador',
  countryCode: country,
);

void main() {
  group('NetworkDashboardData.parse', () {
    test('tolerates a response without countries or countryCode', () {
      final data = NetworkDashboardData.parse({
        'branches': [row('a', 'Centro')],
      });
      expect(data.countries, isEmpty);
      expect(data.rows.single.countryCode, 'SV');
      expect(data.periodDays, 7);
      expect(data.canSales, isFalse);
    });

    test('country comes from the row, then from the lookup, then SV', () {
      final data = NetworkDashboardData.parse(
        {
          'branches': [
            row('a', 'A', country: 'gt'),
            row('b', 'B'),
            row('c', 'C'),
          ],
        },
        countryByBranchId: {'b': 'HN'},
      );
      expect(data.rows.map((r) => r.countryCode), ['GT', 'HN', 'SV']);
    });

    test('visibleRows filters locally and sums cuts and fuel levels', () {
      final data = NetworkDashboardData.parse({
        'branches': [
          row('a', 'A', country: 'SV'),
          row('b', 'B', country: 'GT'),
        ],
        'countries': [
          {'countryCode': 'SV', 'branchCount': 1},
        ],
      });
      expect(data.visibleRows().length, 2);
      final gt = data.visibleRows(countryCode: 'gt');
      expect(gt.single.id, 'b');
      expect(data.closedCutsOf(gt), 2);
      expect(data.expectedCutsOf(data.rows), 8);
      expect(gt.single.soldLiters, closeTo(150.5, 0.001));
      expect(gt.single.salesUsd, closeTo(450.25, 0.001));
      expect(data.fuelLevelsOf(data.rows).single.percent, 25);
    });
  });

  group('helpers', () {
    test('inventory risk text and status are never colour-only', () {
      expect(inventoryRiskStatus('critical'), DlcStatus.critical);
      expect(inventoryRiskStatus('warning'), DlcStatus.medium);
      expect(inventoryRiskStatus('normal'), DlcStatus.optimal);
      expect(inventoryRiskStatus('unknown'), DlcStatus.info);
      expect(inventoryRiskText('critical'), 'Inventario crítico');
      expect(inventoryRiskText('other'), 'Inventario sin datos');
    });
    test('shortDay and money formatting', () {
      expect(shortDay('2026-10-08'), '08/10');
      expect(shortDay('bad'), 'bad');
      expect(formatUsd(1234.5), 'US\$ 1,234.50');
      expect(formatLiters(1500), '1,500 L');
    });
  });

  group('NetworkDashboardPage', () {
    final branches = [
      branch('a', 'Centro', 'SV'),
      branch('b', 'Antigua', 'GT'),
    ];

    Future<FakeSession> pump(WidgetTester tester) async {
      final session = FakeSession();
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: NetworkDashboardPage(api: session, branches: branches),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('loads once and shows indicators and charts', (tester) async {
      final session = await pump(tester);
      expect(session.calls, [
        {'days': 7, 'branchId': null, 'countryCode': null},
      ]);
      expect(find.text('Nivel de combustible'), findsOneWidget);
      expect(find.text('Súper'), findsOneWidget);
      expect(find.text('Tendencia de ventas'), findsOneWidget);
      expect(find.text('Inventario crítico'), findsOneWidget);
      expect(find.text('Todos los países'), findsOneWidget);
    });

    testWidgets('choosing a country refetches with countryCode and '
        'resets an incompatible branch', (tester) async {
      final session = await pump(tester);

      // Pick the Guatemala branch first.
      await tester.tap(find.text('Todas las sucursales'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Antigua · GT').last);
      await tester.pumpAndSettle();
      expect(session.calls.last['branchId'], 'b');

      // Switch to El Salvador: the GT branch is incompatible and is reset.
      await tester.tap(find.text('Todos los países'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('El Salvador').last);
      await tester.pumpAndSettle();
      expect(session.calls.last, {
        'days': 7,
        'branchId': null,
        'countryCode': 'SV',
      });
      expect(find.text('Todas las sucursales'), findsOneWidget);
    });
  });

  group('LiveTextField / ValidatedFormDialog', () {
    testWidgets('shows the message as soon as the user types and gates submit', (
      tester,
    ) async {
      final controller = TextEditingController();
      var submitted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValidatedFormDialog(
              title: 'Lectura',
              submitLabel: 'Guardar',
              isValid: () =>
                  double.tryParse(controller.text) != null &&
                  double.parse(controller.text) >= 100,
              onSubmit: () => submitted++,
              contentBuilder: (context, changed) => LiveTextField(
                controller: controller,
                label: 'Final',
                validator: (v) => (double.tryParse(v ?? '') ?? 0) >= 100
                    ? null
                    : 'La lectura final no puede ser menor que la inicial.',
                onChanged: changed,
              ),
              ),
          ),
        ),
      );
      FilledButton button() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button().onPressed, isNull);
      expect(find.textContaining('no puede ser menor'), findsNothing);

      await tester.enterText(find.byType(TextFormField), '50');
      await tester.pump();
      expect(find.textContaining('no puede ser menor'), findsOneWidget);
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextFormField), '150');
      await tester.pump();
      expect(find.textContaining('no puede ser menor'), findsNothing);
      expect(button().onPressed, isNotNull);
      await tester.tap(find.byType(FilledButton));
      expect(submitted, 1);
    });
  });
}
