import 'dart:math' as math;

import 'package:dlc_customers/main.dart';
import 'package:dlc_customers/ui/account_page.dart';
import 'package:dlc_customers/ui/benefits_page.dart';
import 'package:dlc_customers/ui/branches_page.dart';
import 'package:dlc_customers/ui/format.dart';
import 'package:dlc_customers/ui/home_page.dart';
import 'package:dlc_customers/ui/settings.dart';
import 'package:dlc_customers/ui/tokens.dart';
import 'package:dlc_customers/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

const _loyalty = {
  'pointsBalance': 1250,
  'canRedeem': true,
  'availableValueUsd': '12.5',
  'redemptionUsdPerPoint': '0.01',
};

final _points = [
  {'type': 'earn', 'pointsDelta': 120, 'createdAt': '2026-10-01T10:00:00Z'},
  {'type': 'redeem', 'pointsDelta': -45, 'reason': 'Canje en caja'},
  {'type': 'mystery_type', 'pointsDelta': 3},
  {'type': 'expire', 'pointsDelta': -10},
];

final _rewards = [
  {'title': 'Café gratis', 'description': 'Un café mediano', 'pointsCost': 500},
  {'title': 'Lavado de auto', 'pointsCost': 2000},
  {'title': 'Tanque lleno de aire', 'pointsCost': '150.5'},
];

final _branches = [
  {
    'id': '1',
    'name': 'Sucursal Centro',
    'zone': 'San Salvador',
    'countryCode': 'SV',
  },
  {
    'id': '2',
    'name': 'Sucursal Zona 10',
    'zone': 'Ciudad de Guatemala',
    'countryCode': 'GT',
  },
  {'id': '3', 'name': 'Sucursal Norte', 'countryCode': 'XX'},
];

final _quote = {
  'id': 'q1',
  'branchName': 'Sucursal con un nombre bastante largo para probar',
  'points': 800,
  'amountUsd': '8',
  'saleTotalUsd': '45.9',
  'status': 'pending',
};

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1.3,
  DlcSettings? settings,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SettingsScope(
      settings: settings ?? DlcSettings(),
      child: MaterialApp(
        theme: buildDlcTheme(brightness),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: app!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Widget _home({
  List<Map<String, dynamic>>? points,
  bool animate = true,
  List<Map<String, dynamic>> quotes = const [],
}) => HomePage(
  profile: const {'fullName': 'María Fernanda López'},
  loyalty: _loyalty,
  rewards: _rewards,
  points: points ?? _points,
  branches: _branches,
  quotes: quotes,
  busy: false,
  animateBalance: animate,
  onBalanceCounted: () {},
  onDecideQuote: (_, _) {},
  onSeeBranches: () {},
  onSeeRewards: () {},
  onSeeHistory: () {},
);

Widget _benefits() => BenefitsPage(
  balance: 1250,
  rewards: _rewards,
  promotions: const [
    {
      'title': 'Ahorro de fin de mes con un título extenso',
      'kind': 'unit_discount',
      'value': '0.05',
      'valueUnit': 'liter',
      'motive': 'Promoción de prueba',
    },
  ],
  campaigns: const [
    {'title': 'Novedad', 'body': 'Texto de la novedad'},
  ],
  services: const [
    {'description': 'Aire para llantas', 'branchName': 'Centro', 'priceUsd': 1},
  ],
  branches: _branches,
  selectedBranchId: null,
  promotionsLoading: false,
  onSelectBranch: (_) {},
  onOpenPromotion: (_) {},
);

void main() {
  setUp(Reveal.reset);

  group('number formatting', () {
    test('two decimals and thousands separator', () {
      expect(formatNumber(1234.5), '1,234.50');
      expect(formatNumber(1234567.891), '1,234,567.89');
      expect(formatNumber(0), '0.00');
      expect(formatNumber(-0.001), '0.00');
      expect(formatNumber(-1234.5), '-1,234.50');
      expect(formatNumber(1234.5, decimals: 0), '1,235');
    });

    test('points and money', () {
      expect(formatPoints(12500), '12,500');
      expect(formatPoints(null), '0');
      expect(formatPoints('1250.4'), '1,250');
      expect(formatMoney('3.5'), 'USD 3.50');
      expect(formatMoney(null), '—');
      expect(
        formatMoney(1234.5, decimals: 3, currency: 'GTQ'),
        'GTQ 1,234.500',
      );
      expect(formatSignedPoints(120), '+120');
      expect(formatSignedPoints(-45), '−45');
    });

    test('volume unit conversion', () {
      expect(pricePerUnit(1, 'liter', VolumeUnit.liter), 1);
      expect(
        pricePerUnit(1, 'us_gallon', VolumeUnit.liter),
        closeTo(0.264, 0.001),
      );
      expect(
        pricePerUnit(1, 'liter', VolumeUnit.gallon),
        closeTo(3.785, 0.001),
      );
    });
  });

  group('Spanish labels with fallback', () {
    test('every ledger type has a Spanish label and an icon', () {
      const types = [
        'earn',
        'reserve',
        'redeem',
        'release',
        'expire',
        'reverse',
        'adjust',
      ];
      final labels = {for (final t in types) pointEventLabel(t)};
      expect(labels.length, types.length);
      for (final label in labels) {
        expect(RegExp(r'^[A-ZÁÉÍÓÚ]').hasMatch(label), isTrue);
      }
      expect(pointEventLabel('earn'), 'Puntos ganados');
    });

    test('unknown enums never leak raw keys or throw', () {
      expect(pointEventLabel('weird_new_type'), 'Weird new type');
      expect(pointEventLabel(null), '—');
      expect(quoteStatusLabel('pending'), 'Pendiente');
      expect(quoteStatusLabel('confirmed'), 'Confirmada');
      expect(quoteStatusLabel('some_state'), 'Some state');
      expect(countryName('sv'), 'El Salvador');
      expect(countryName('ZZ'), 'ZZ');
      expect(countryName(null), 'Sin país');
      expect(promotionKindLabel('x'), 'Promoción informativa');
    });

    test('next reward picks the closest unreached cost', () {
      final rewards = [
        {'pointsCost': 2000},
        {'pointsCost': 500},
        {'pointsCost': null},
      ];
      expect(nextReward(rewards, 100)!.reward['pointsCost'], 500);
      expect(nextReward(rewards, 600)!.reward['pointsCost'], 2000);
      final done = nextReward(rewards, 5000)!;
      expect(done.reachable, isTrue);
      expect(nextReward(const [], 10), isNull);
    });
  });

  group('palette keeps WCAG AA', () {
    for (final brightness in Brightness.values) {
      test('text pairs in $brightness', () {
        final theme = buildDlcTheme(brightness);
        final scheme = theme.colorScheme;
        final tokens = brightness == Brightness.dark
            ? DlcColors.dark
            : DlcColors.light;
        void aa(Color fg, Color bg, String name, [double min = 4.5]) =>
            expect(_contrast(fg, bg), greaterThanOrEqualTo(min), reason: name);
        aa(scheme.onSurface, tokens.paper, 'body on paper');
        aa(scheme.onSurface, tokens.card, 'body on card');
        aa(scheme.onSurfaceVariant, tokens.card, 'secondary on card');
        aa(scheme.onSurfaceVariant, tokens.paper, 'secondary on paper');
        aa(scheme.onPrimary, scheme.primary, 'button label');
        aa(scheme.primary, tokens.card, 'link on card');
        aa(scheme.onPrimaryContainer, scheme.primaryContainer, 'container');
        aa(scheme.onError, scheme.error, 'error button');
        for (final (name, tone) in [
          ('ok', tokens.ok),
          ('warn', tokens.warn),
          ('crit', tokens.crit),
          ('info', tokens.info),
        ]) {
          aa(tone.fg, tone.bg, name);
        }
        for (var i = 0; i < tokens.accents.length; i++) {
          final tone = tokens.accents[i];
          aa(tone.fg, tone.bg, 'accent $i text');
          aa(tone.bar!, tone.bg, 'accent $i bar', 3);
        }
      });
    }

    test('hero text on every gradient stop', () {
      for (final stop in DlcBrand.heroGradient.colors) {
        expect(_contrast(DlcBrand.ink, stop), greaterThanOrEqualTo(6.5));
        expect(
          _contrast(const Color(0xFF3B2A1F), stop),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('filled action button with white text', () {
      expect(
        _contrast(Colors.white, DlcBrand.action),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('layout at 360x640 and text scale 1.3', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('Inicio ($mode)', (tester) async {
        await _pump(tester, _home(), brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('Hola, María'), findsOneWidget);
        expect(find.text('1,250'), findsOneWidget);
        expect(find.text('USD 12.50'), findsOneWidget);
        // Scroll through the secondary cards: none may overflow.
        for (var i = 0; i < 4; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('Beneficios ($mode)', (tester) async {
        await _pump(tester, _benefits(), brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('Café gratis'), findsOneWidget);
      });

      testWidgets('Sucursales ($mode)', (tester) async {
        await _pump(
          tester,
          BranchesPage(
            branches: _branches,
            search: TextEditingController(),
            onSearchChanged: () {},
          ),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('El Salvador'), findsWidgets);
        expect(find.textContaining('Guatemala'), findsWidgets);
      });

      testWidgets('Mi código ($mode)', (tester) async {
        await _pump(
          tester,
          const QrPage(qr: {'code': 'DLC-1234567890', 'message': 'Listo'}),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Perfil ($mode)', (tester) async {
        await _pump(
          tester,
          AccountPage(
            profile: const {
              'fullName': 'María Fernanda López',
              'createdAt': '2026-01-05T00:00:00Z',
            },
            email: 'maria.fernanda.lopez.con.correo.largo@ejemplo.com',
            busy: false,
            onSignOut: () {},
          ),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Configuración'), findsOneWidget);
      });
    }

    testWidgets('sign-in screen', (tester) async {
      await _pump(
        tester,
        AuthScreen(busy: false, onAction: (_) async => true, onChanged: () {}),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Iniciar sesión'), findsOneWidget);
    });

    testWidgets('error state, banner and skeletons', (tester) async {
      await _pump(
        tester,
        Column(
          children: [
            ErrorBanner(
              error: const UiError('No se pudo conectar con DLC.'),
              onRetry: () {},
              staleSince: DateTime(2026, 10, 10, 14, 32),
            ),
            const Expanded(child: HomeSkeleton()),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Mostrando datos de las 14:32'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('history page', (tester) async {
      await _pump(tester, HistoryPage(points: _points));
      expect(tester.takeException(), isNull);
    });
  });

  group('behaviour', () {
    testWidgets('payment request keeps one filled primary action', (
      tester,
    ) async {
      final decided = <bool>[];
      await _pump(
        tester,
        PaymentRequestCard(
          quote: _quote,
          busy: false,
          onDecide: (_, confirm) => decided.add(confirm),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.ensureVisible(find.text('Confirmar pago'));
      await tester.tap(find.text('Confirmar pago'));
      await tester.ensureVisible(find.text('Rechazar'));
      await tester.tap(find.text('Rechazar'));
      expect(decided, [true, false]);
    });

    testWidgets('empty states show icon and a useful sentence', (tester) async {
      await _pump(tester, _home(points: const []));
      await tester.scrollUntilVisible(
        find.textContaining('Tu historial aparecerá aquí'),
        200,
      );
      expect(
        find.textContaining('Tu historial aparecerá aquí'),
        findsOneWidget,
      );
      expect(find.byType(EmptyState), findsWidgets);
    });

    testWidgets('history rows use Spanish labels', (tester) async {
      await _pump(tester, HistoryPage(points: _points));
      expect(find.text('Puntos ganados'), findsOneWidget);
      expect(find.text('Canje de puntos'), findsOneWidget);
      expect(find.text('Mystery type'), findsOneWidget);
      expect(find.text('Puntos vencidos'), findsOneWidget);
      expect(find.text('mystery_type'), findsNothing);
    });

    testWidgets('balance counts up once; reduced motion shows it at once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final done = <int>[];
      await tester.pumpWidget(
        SettingsScope(
          settings: DlcSettings(),
          child: MaterialApp(
            theme: buildDlcTheme(Brightness.light),
            home: Scaffold(
              body: CountUp(
                value: 1250,
                style: const TextStyle(fontSize: 40),
                onDone: () => done.add(1),
              ),
            ),
          ),
        ),
      );
      expect(find.text('0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      final mid = (tester.widget<Text>(find.byType(Text)).data!);
      expect(mid, isNot('0'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('1,250'), findsOneWidget);
      expect(done, [1]);

      await _pump(
        tester,
        const CountUp(value: 4321, style: TextStyle(fontSize: 40)),
        disableAnimations: true,
      );
      expect(find.text('4,321'), findsOneWidget);
    });

    testWidgets('settings page changes theme, unit and decimals', (
      tester,
    ) async {
      final settings = DlcSettings();
      await _pump(
        tester,
        AccountPage(
          profile: const {'fullName': 'Ana'},
          email: 'ana@dlc.com',
          busy: false,
          onSignOut: () {},
        ),
        settings: settings,
        scale: 1,
      );
      await tester.ensureVisible(find.text('Oscuro'));
      await tester.tap(find.text('Oscuro'));
      await tester.pump();
      expect(settings.themeMode, ThemeMode.dark);
      await tester.ensureVisible(find.text('Galones'));
      await tester.tap(find.text('Galones'));
      await tester.pump();
      expect(settings.volumeUnit, VolumeUnit.gallon);
      await tester.ensureVisible(find.text('4'));
      await tester.tap(find.text('4'));
      await tester.pump();
      expect(settings.decimals, 4);
      expect(find.text('Ejemplo: USD 1,234.5000'), findsOneWidget);
    });

    testWidgets('sign out is reachable from the profile page', (tester) async {
      var out = 0;
      await _pump(
        tester,
        AccountPage(
          profile: const {'fullName': 'Ana'},
          email: 'ana@dlc.com',
          busy: false,
          onSignOut: () => out++,
        ),
        scale: 1,
      );
      await tester.scrollUntilVisible(find.text('Cerrar sesión'), 200);
      await tester.tap(find.text('Cerrar sesión'));
      expect(out, 1);
    });

    testWidgets('error state offers Reintentar', (tester) async {
      var retries = 0;
      await _pump(
        tester,
        ErrorState(
          error: const UiError('Sin conexión.', reference: 'abc-123'),
          onRetry: () => retries++,
        ),
      );
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);
      expect(find.textContaining('abc-123'), findsNothing);
      await tester.tap(find.text('Ver detalle técnico'));
      await tester.pump();
      expect(find.textContaining('abc-123'), findsOneWidget);
    });
  });
}
