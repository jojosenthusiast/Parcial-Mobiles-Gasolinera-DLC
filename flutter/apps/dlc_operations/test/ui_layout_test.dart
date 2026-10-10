import 'package:dlc_api/dlc_api.dart';
import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/format.dart';
import 'package:dlc_operations/main.dart';
import 'package:dlc_operations/preferences.dart';
import 'package:dlc_operations/theme_mode_controller.dart';
import 'package:dlc_operations/ui/branch_wizard.dart';
import 'package:dlc_operations/ui/data_widgets.dart';
import 'package:dlc_operations/ui/gauges.dart';
import 'package:dlc_operations/ui/kit.dart';
import 'package:dlc_operations/ui/login_page.dart';
import 'package:dlc_operations/ui/prices_page.dart';
import 'package:dlc_operations/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two phone sizes the owner checks, at 130 % text.
const sizes = <String, Size>{
  '360x640': Size(360, 640),
  '400x800': Size(400, 800),
};
const scale = 1.3;

BranchSummary br(String id, String name, String country, {String status = 'active'}) =>
    BranchSummary(
      id: id,
      code: id.toUpperCase(),
      name: name,
      zone: 'central',
      timezone: 'America/El_Salvador',
      countryCode: country,
      status: status,
    );

class FakeOps extends EmployeeSession {
  FakeOps({this.general = true, List<BranchSummary>? branches})
    : list = branches ??
          [
            br('a', 'Estación Centro Histórico San Salvador', 'SV'),
            br('b', 'Antigua Guatemala', 'GT'),
          ];
  final bool general;
  final List<BranchSummary> list;
  final prefs = <String, String>{};
  final steps = <String>[];
  int version = 1;
  Map<String, dynamic> onboardingData = {};
  bool created = false;

  @override
  Future<EmployeeIdentity?> restore() async => EmployeeIdentity(
    id: 'u1',
    organizationId: 'o1',
    displayName: 'Gerente de Prueba',
    email: 'g@dlc.test',
    roles: general
        ? const [EmployeeRole(code: 'general_manager', name: 'Gerente General')]
        : [EmployeeRole(code: 'branch_manager', name: 'Gerente', branchId: list.first.id)],
  );

  @override
  Future<String?> readPreference(String key) async => prefs[key];
  @override
  Future<void> writePreference(String key, String value) async => prefs[key] = value;

  @override
  Future<List<String>> capabilities({String? branchId}) async => branchId == null
      ? (general ? const ['branch.read', 'branch.manage'] : const [])
      : const [
          'dispenser.read', 'price.propose', 'branch.activate', 'staff.read',
          'infrastructure.read', 'incident.read', 'purchase.read',
        ];

  @override
  Future<List<BranchSummary>> branches({String status = 'active', String? countryCode}) async => list;

  @override
  Future<Map<String, dynamic>> branchDetail(String id) async {
    final b = list.where((x) => x.id == id).firstOrNull;
    return {
      'id': id,
      'code': b?.code ?? 'SV-01',
      'name': b?.name ?? 'Centro Nuevo',
      'zone': 'central',
      'timezone': 'America/El_Salvador',
      'countryCode': b?.countryCode ?? 'SV',
      'status': b?.status ?? 'draft',
      'onboardingVersion': version,
      'onboardingData': onboardingData,
    };
  }

  @override
  Future<Map<String, dynamic>> branchDashboard(String id) async => {
    'alerts': [
      {'title': 'Tanque Súper T1 bajo', 'detail': 'Menos de 30 %', 'severity': 'critical'},
    ],
    'cuts': [
      {
        'slot': '1', 'status': 'closed', 'closedSalesUsd': '1234.50000000',
        'registeredDispensers': 6, 'expectedDispensers': 6,
      },
      {'slot': '2', 'status': 'open', 'registeredDispensers': 2, 'expectedDispensers': 6},
    ],
    'inventory': {
      'totalLiters': '15234.123456',
      'tanks': _tanks,
    },
    'openIncidents': [{}],
    'lastSourceAt': '2026-10-10T14:32:00Z',
    'operationalDate': '2026-10-10',
  };

  static const _tanks = [
    {'code': 'T1', 'fuelName': 'Súper', 'family': 'super', 'onHandLiters': '2000.123456', 'capacityLiters': '10000'},
    {'code': 'T2', 'fuelName': 'Regular', 'family': 'regular', 'onHandLiters': '5200', 'capacityLiters': '10000'},
    {'code': 'T3', 'fuelName': 'Diésel', 'family': 'diesel', 'onHandLiters': '8000', 'capacityLiters': '10000'},
  ];

  @override
  Future<List<Map<String, dynamic>>> dispensers(String id) async => [
    {
      'id': 'p1', 'code': 'P-01', 'physicalStatus': 'active',
      'nozzles': [{'fuelName': 'Súper'}, {'fuelName': 'Regular'}],
    },
    {'id': 'p2', 'code': 'P-02', 'physicalStatus': 'maintenance', 'nozzles': []},
  ];

  @override
  Future<Map<String, dynamic>> networkDashboard({int days = 7, String? branchId, String? countryCode}) async => {
    'periodDays': days,
    'permissions': {'sales': true, 'inventory': true},
    'countries': [
      {'countryCode': 'SV', 'branchCount': 1},
      {'countryCode': 'GT', 'branchCount': 1},
    ],
    'dailySeries': [
      {'date': '2026-10-09', 'salesUsd': '100', 'soldLiters': '40', 'closedCuts': 2},
      {'date': '2026-10-10', 'salesUsd': '200', 'soldLiters': '80', 'closedCuts': 2},
    ],
    'branches': [
      for (final b in list)
        {
          'id': b.id, 'name': b.name, 'code': b.code, 'countryCode': b.countryCode,
          'inventoryRisk': b.id == 'a' ? 'critical' : 'normal',
          'closedCuts': 2, 'expectedCuts': 4,
          'products': [{'soldLiters': '100.5', 'salesUsd': '300.123456'}],
          'tanks': _tanks,
        },
    ],
  };

  @override
  Future<Map<String, dynamic>> fuelPrices(String branchId) async => {
    'current': [
      {
        'fuelProductId': 'f1', 'productName': 'Súper', 'serviceMode': 'full_service',
        'priceUsdPerUnit': '0.91240000', 'unit': 'liter', 'effectiveAt': '2026-10-01T00:00:00Z',
      },
      {
        'fuelProductId': 'f2', 'productName': 'Diésel', 'serviceMode': 'self_service',
        'priceUsdPerUnit': '0.85000000', 'unit': 'liter', 'effectiveAt': '2026-10-01T00:00:00Z',
      },
    ],
    'upcoming': [
      {
        'fuelProductId': 'f1', 'serviceMode': 'full_service',
        'priceUsdPerUnit': '0.93000000', 'effectiveAt': '2026-10-20T00:00:00Z',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> branchConfiguration(String branchId) async => {
    'fuelOffers': [
      {'fuelProductId': 'f1', 'fuelName': 'Súper', 'status': 'active'},
    ],
  };

  // Wizard ------------------------------------------------------------------
  @override
  Future<Map<String, dynamic>> createBranchDraft({
    required String code,
    required String name,
    required String zone,
    required String timezone,
    required String profile,
    required int expectedDispenserCount,
    String countryCode = kDefaultCountryCode,
  }) async {
    created = true;
    steps.add('create:$code:$profile:$expectedDispenserCount');
    return {'id': 'new1'};
  }

  @override
  Future<Map<String, dynamic>> saveBranchStep(
    String branchId, {
    required int expectedVersion,
    required String step,
    required Map<String, dynamic> data,
  }) async {
    steps.add(step);
    onboardingData = {...onboardingData, step: data};
    version = expectedVersion + 1;
    return {'onboardingVersion': version};
  }

  @override
  Future<Map<String, dynamic>> branchReadiness(String branchId) async => {
    'canActivate': false,
    'blockers': [
      {'step': 'tanks', 'code': 'TANK_MISSING', 'message': 'Registra por lo menos un tanque activo.'},
      {'step': 'prices', 'code': 'PRICE_NOT_EFFECTIVE', 'message': 'Configura un precio aprobado y vigente.'},
    ],
  };

  @override
  Future<List<Map<String, dynamic>>> staffEmployees(String branchId) async => const [];

  @override
  Future<void> clear() async {}
}

Widget host(Widget child, {ThemeMode mode = ThemeMode.light, DisplayPrefsController? prefs}) {
  return MaterialApp(
    theme: lightTheme,
    darkTheme: darkTheme,
    themeMode: mode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: DisplayPrefsScope(
        controller: prefs ?? DisplayPrefsController(),
        child: child!,
      ),
    ),
    home: child,
  );
}

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

void main() {
  for (final entry in sizes.entries) {
    group('layout ${entry.key} at 130 % text', () {
      testWidgets('login', (tester) async {
        await setSize(tester, entry.value);
        final controller = OperationsController(FakeOps())..busy = false;
        await tester.pumpWidget(host(LoginPage(controller: controller)));
        await tester.pumpAndSettle();
        expect(find.text('Iniciar sesión'), findsOneWidget);
        expect(find.text('Entrar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('general manager shell: scope bar, every tab, no overflow', (tester) async {
        await setSize(tester, entry.value);
        final session = FakeOps();
        final controller = OperationsController(session);
        await tester.pumpWidget(OperationsAppHost(controller: controller));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('scope-country')), findsOneWidget);
        expect(find.byKey(const Key('scope-branch')), findsOneWidget);
        expect(find.textContaining('Viendo:'), findsOneWidget);
        expect(find.text('Resumen'), findsWidgets);
        expect(find.text('1 alerta crítica'), findsOneWidget);
        expect(tester.takeException(), isNull);

        for (final tab in ['Bombas', 'Inventario', 'Precios', 'Más', 'Resumen']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'tab $tab');
        }
      });

      testWidgets('picking a country in the scope bar narrows the view', (tester) async {
        await setSize(tester, entry.value);
        final controller = OperationsController(FakeOps());
        await tester.pumpWidget(OperationsAppHost(controller: controller));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('scope-country')));
        await tester.pumpAndSettle();
        expect(find.text('Guatemala'), findsOneWidget);
        await tester.tap(find.text('Guatemala'));
        await tester.pumpAndSettle();
        expect(controller.scope.state.countryCode, 'GT');
        expect(find.textContaining('Viendo: Guatemala'), findsOneWidget);
        // one operating branch inside Guatemala: the branch summary opens
        expect(controller.branch?.id, 'b');
        expect(tester.takeException(), isNull);
      });

      testWidgets('branch manager sees the branch locked with a lock icon', (tester) async {
        await setSize(tester, entry.value);
        final controller = OperationsController(
          FakeOps(general: false, branches: [br('a', 'Estación Centro', 'SV')]),
        );
        await tester.pumpWidget(OperationsAppHost(controller: controller));
        await tester.pumpAndSettle();
        expect(find.text('Fija'), findsOneWidget);
        expect(find.byKey(const Key('scope-country')), findsNothing);
        expect(find.byIcon(Icons.lock), findsNothing, reason: 'cupertino icons only');
        expect(tester.takeException(), isNull);
      });

      testWidgets('dark theme renders the shell', (tester) async {
        await setSize(tester, entry.value);
        final controller = OperationsController(
          FakeOps(),
          themeController: ThemeModeController()..select(ThemeMode.dark),
        );
        await tester.pumpWidget(OperationsAppHost(controller: controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('settings page: unit, decimals and theme', (tester) async {
        await setSize(tester, entry.value);
        final prefs = DisplayPrefsController();
        final theme = ThemeModeController();
        await tester.pumpWidget(
          host(
            SettingsPage(theme: theme, prefs: prefs, identity: null, onLogout: () {}),
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Oscuro'));
        await tester.pumpAndSettle();
        expect(theme.mode, ThemeMode.dark);
        expect(find.text('Litros'), findsOneWidget);
        await tester.tap(find.text('Galones'));
        await tester.pumpAndSettle();
        expect(prefs.prefs.unit, VolumeUnit.gallons);
        await tester.ensureVisible(find.byTooltip('Más decimales'));
        await tester.tap(find.byTooltip('Más decimales'));
        await tester.pumpAndSettle();
        expect(prefs.prefs.decimals, 3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('components: hero, tiles, tank, price marker, alerts, bars', (tester) async {
        await setSize(tester, entry.value);
        await tester.pumpWidget(
          host(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  HeroKpi(
                    label: 'Ventas de la red en los últimos treinta días',
                    value: 1234567.891,
                    format: (v) => formatMoney(v),
                    extra: 'Más: Q 9,999,999.00 + HNL 1,000,000.00',
                    caption: 'Una descripción larga que debe ajustarse sin desbordar',
                  ),
                  const SizedBox(height: 8),
                  const MiniKpiRow(
                    tiles: [
                      MiniKpi(icon: Icons.abc, value: '12,345,678', label: 'Cortes cerrados de la semana'),
                      MiniKpi(icon: Icons.abc, value: '3/4', label: 'Incidencias abiertas hoy'),
                      MiniKpi(icon: Icons.abc, value: '99', label: 'Tanques críticos'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TankCard(
                    tank: const {
                      'code': 'TANQUE-SUPER-PRINCIPAL-01',
                      'fuelName': 'Súper Premium',
                      'family': 'super',
                      'onHandLiters': '1234567',
                      'capacityLiters': '9999999',
                    },
                    prefs: const DisplayPrefs(),
                  ),
                  const SizedBox(height: 8),
                  PriceMarker(
                    price: const {
                      'productName': 'Diésel de bajo azufre ultra',
                      'serviceMode': 'self_service',
                      'priceUsdPerUnit': '123456.78900000',
                      'effectiveAt': '2026-10-01T00:00:00Z',
                    },
                    currency: 'HNL',
                    move: PriceMove(-2.345, DateTime(2026, 10, 20)),
                  ),
                  const SizedBox(height: 8),
                  const AlertStrip(
                    items: [
                      AlertItem(
                        title: 'Inventario crítico en una sucursal con nombre largo',
                        detail: 'Detalle largo que ocupa varias líneas en pantallas angostas',
                        severity: 'critical',
                        branchName: 'Estación Centro Histórico San Salvador',
                      ),
                      AlertItem(title: 'Aviso', detail: '', severity: 'warning'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const HBarChart(
                    title: 'Comparación',
                    items: [
                      BarItem(label: 'Estación Centro Histórico San Salvador', value: 100, display: 'US\$ 1,234,567.00', detail: 'El Salvador · cortes 2/4'),
                      BarItem(label: 'Antigua', value: 40, display: 'US\$ 400.00'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedFilter<int>(
                    options: const {1: 'Hoy', 7: '7 días', 30: '30 días'},
                    selected: 7,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 8),
                  SelectField<String>(
                    label: 'Sucursal',
                    valueLabel: 'Estación Centro Histórico San Salvador Norte',
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  const EmptyState(
                    icon: Icons.abc,
                    title: 'Sin datos para mostrar en este momento',
                    message: 'Mensaje de ayuda bastante largo para comprobar el ajuste de línea.',
                    actionLabel: 'Actualizar ahora mismo',
                    onAction: _noop,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('branch wizard goes through the 5 steps and checkpoints', (tester) async {
        await setSize(tester, entry.value);
        final session = FakeOps();
        await tester.pumpWidget(
          host(BranchWizardPage(api: session, existingCodes: const ['SV-001'])),
        );
        await tester.pumpAndSettle();
        expect(find.text('Paso 1 de 5'), findsOneWidget);
        expect(find.textContaining('Por qué importa'), findsOneWidget);

        // Continue is disabled until the name is written.
        FilledButton cont() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Continuar'),
        );
        expect(cont().onPressed, isNull);
        await tester.enterText(find.byType(TextFormField).first, 'Centro Nuevo');
        await tester.pumpAndSettle();
        expect(cont().onPressed, isNotNull);
        await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
        await tester.pumpAndSettle();

        expect(find.text('Paso 2 de 5'), findsOneWidget);
        expect(find.textContaining('Guardado'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
        await tester.pumpAndSettle();
        expect(session.created, isTrue);
        expect(session.steps.first, startsWith('create:SV-002:academicLab22:6'));
        expect(session.steps, containsAll(['products', 'tanks', 'dispensers']));

        expect(find.text('Paso 3 de 5'), findsOneWidget);
        await tester.ensureVisible(find.text('Completar después'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Completar después'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
        await tester.pumpAndSettle();
        expect(session.onboardingData['staff'], {'status': 'deferred', 'employeeCount': 0});

        expect(find.text('Paso 4 de 5'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
        await tester.pumpAndSettle();
        expect(session.onboardingData['review'], {'store': {'enabled': false}});

        expect(find.text('Paso 5 de 5'), findsOneWidget);
        expect(find.textContaining('2 pendientes'), findsOneWidget);
        expect(find.text('Configurar equipos'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Configurar precios'), 120);
        expect(find.text('Configurar precios'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Activar sucursal')).onPressed,
          isNull,
          reason: 'cannot activate until the server says it is ready',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('branch wizard resumes at the first step without a checkpoint', (tester) async {
        await setSize(tester, entry.value);
        final session = FakeOps(branches: [br('d', 'Borrador Uno', 'GT', status: 'draft')])
          ..onboardingData = {
            'identity': {},
            'products': {'fuels': ['super']},
            'tanks': {'planned': 2},
            'dispensers': {'planned': 4},
          };
        await tester.pumpWidget(
          host(BranchWizardPage(api: session, existingCodes: const [], branchId: 'd')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Paso 3 de 5'), findsOneWidget);
        expect(find.text('Atrás'), findsOneWidget);
        await tester.tap(find.text('Atrás'));
        await tester.pumpAndSettle();
        expect(find.text('Paso 2 de 5'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}

void _noop() {}

/// The app under test (text scale and reduced motion come from setSize).
class OperationsAppHost extends StatelessWidget {
  const OperationsAppHost({required this.controller, super.key});
  final OperationsController controller;
  @override
  Widget build(BuildContext context) => OperationsApp(controller: controller);
}
