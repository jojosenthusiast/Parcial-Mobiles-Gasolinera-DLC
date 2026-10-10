import 'package:dlc_api/dlc_api.dart';
import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/branch_status.dart';
import 'package:dlc_operations/main.dart';
import 'package:dlc_operations/network_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BranchSummary branch(String id, String status, {String? name}) => BranchSummary(
  id: id,
  code: id.toUpperCase(),
  name: name ?? 'Sucursal $id',
  zone: 'central',
  timezone: 'America/El_Salvador',
  status: status,
);

class FakeSession extends EmployeeSession {
  FakeSession({
    required this.roles,
    required this.globalPermissions,
    required this.branchList,
    this.dashboardError,
    this.onDashboardError,
  });
  final List<EmployeeRole> roles;
  final List<String> globalPermissions;
  List<BranchSummary> branchList;
  DlcApiException? dashboardError;
  void Function()? onDashboardError;
  final calls = <String>[];

  @override
  Future<EmployeeIdentity?> restore() async => EmployeeIdentity(
    id: 'u1',
    organizationId: 'o1',
    displayName: 'Gerente',
    email: 'g@dlc.test',
    roles: roles,
  );

  @override
  Future<List<String>> capabilities({String? branchId}) async {
    calls.add('capabilities:${branchId ?? 'global'}');
    return branchId == null ? globalPermissions : const ['dispenser.read'];
  }

  @override
  Future<List<BranchSummary>> branches({
    String status = 'active',
    String? countryCode,
  }) async {
    calls.add('branches:$status');
    return branchList;
  }

  @override
  Future<Map<String, dynamic>> branchDetail(String id) async {
    calls.add('branchDetail:$id');
    final b = branchList.firstWhere((x) => x.id == id);
    return {
      'id': b.id,
      'code': b.code,
      'name': b.name,
      'zone': b.zone,
      'timezone': b.timezone,
      'status': b.status,
    };
  }

  @override
  Future<Map<String, dynamic>> branchDashboard(String id) async {
    calls.add('dashboard:$id');
    if (dashboardError != null) {
      onDashboardError?.call();
      throw dashboardError!;
    }
    return {'inventory': {'tanks': []}, 'cuts': []};
  }

  @override
  Future<List<Map<String, dynamic>>> dispensers(String id) async {
    calls.add('dispensers:$id');
    return const [];
  }

  @override
  Future<Map<String, dynamic>> networkDashboard({
    int days = 7,
    String? branchId,
    String? countryCode,
  }) async {
    calls.add('network');
    return {'branches': [], 'dailySeries': [], 'countries': []};
  }

  @override
  Future<void> clear() async {}
}

const general = [EmployeeRole(code: 'general_manager', name: 'General')];
const scopeError = DlcApiException(
  'Sucursal fuera de tu ámbito.',
  code: 'NOT_FOUND',
  statusCode: 404,
  correlationId: 'ref-404',
);

Future<OperationsController> started(FakeSession session) async {
  final controller = OperationsController(session);
  await controller.start();
  return controller;
}

void main() {
  group('helpers', () {
    test('pickDefaultBranch prefers an active branch and never a draft', () {
      final list = [branch('d', 'draft'), branch('a', 'active')];
      expect(pickDefaultBranch(list)?.id, 'a');
      expect(pickDefaultBranch(list, assignedIds: ['a'])?.id, 'a');
      expect(pickDefaultBranch(list, assignedIds: ['d'])?.id, 'a');
      expect(
        pickDefaultBranch([branch('a', 'active'), branch('b', 'active')]),
        isNull,
        reason: 'several active branches: the user chooses',
      );
      expect(pickDefaultBranch([branch('d', 'draft')]), isNull);
      expect(pickDefaultBranch(const []), isNull);
    });

    test('isBranchScopeError only matches the 404 scope message', () {
      expect(isBranchScopeError(scopeError), isTrue);
      expect(
        isBranchScopeError(
          const DlcApiException('Sucursal activa fuera de tu ambito.', statusCode: 404),
        ),
        isTrue,
      );
      expect(
        isBranchScopeError(
          const DlcApiException('Corte fuera de tu sucursal.', statusCode: 404),
        ),
        isFalse,
      );
      expect(
        isBranchScopeError(
          const DlcApiException('Sucursal fuera de tu ámbito.', statusCode: 500),
        ),
        isFalse,
      );
      expect(isBranchScopeError(StateError('x')), isFalse);
    });

    test('messages and technical details', () {
      expect(
        branchNotReadyMessage('draft'),
        'Esta sucursal está en preparación (borrador). Completa la preparación operativa y actívala para ver su operación.',
      );
      expect(branchStatusLabel('draft'), 'Borrador');
      expect(technicalDetails(scopeError), 'Código NOT_FOUND · HTTP 404 · Ref. ref-404');
      expect(technicalDetails(const DlcApiException('x')), isNull);
    });
  });

  group('OperationsController', () {
    test('selects the ACTIVE branch by default and never loads the draft', () async {
      final session = FakeSession(
        roles: general,
        globalPermissions: const ['branch.read', 'branch.manage'],
        branchList: [branch('d', 'draft'), branch('a', 'active')],
      );
      final c = await started(session);

      expect(session.calls, contains('branches:'), reason: 'all statuses requested');
      expect(c.branch?.id, 'a');
      expect(c.branchNotReady, isFalse);
      expect(session.calls, contains('dashboard:a'));
      expect(session.calls.where((x) => x.endsWith(':d')), isEmpty);
    });

    test('with zero active branches nothing is selected and no metrics are requested', () async {
      final session = FakeSession(
        roles: general,
        globalPermissions: const ['branch.read', 'branch.manage'],
        branchList: [branch('d', 'draft')],
      );
      final c = await started(session);

      expect(c.branch, isNull);
      expect(c.activeBranchList, isEmpty);
      expect(c.error, isNull);
      expect(session.calls.where((x) => x.startsWith('dashboard')), isEmpty);
    });

    test('picking a draft branch skips every branch-scoped endpoint', () async {
      final session = FakeSession(
        roles: general,
        globalPermissions: const ['branch.read', 'branch.manage'],
        branchList: [branch('d', 'draft'), branch('e', 'draft')],
      );
      final c = await started(session);
      session.calls.clear();

      await c.selectBranch(c.branches.first);

      expect(c.branch?.id, 'd');
      expect(c.branchNotReady, isTrue);
      expect(c.error, isNull);
      expect(session.calls, isEmpty);
    });

    test('branch-scoped manager with a draft branch gets the explanation, not an error', () async {
      final session = FakeSession(
        roles: const [EmployeeRole(code: 'branch_manager', name: 'Gerente', branchId: 'd')],
        globalPermissions: const [],
        branchList: [branch('d', 'draft')],
      );
      final c = await started(session);

      expect(c.branch?.id, 'd');
      expect(c.branchNotReady, isTrue);
      expect(c.canManageBranches, isFalse);
      expect(c.error, isNull);
      expect(session.calls.where((x) => x.startsWith('dashboard') || x.startsWith('dispensers')), isEmpty);
    });

    test('a 404 scope error for a selected branch maps to the friendly state', () async {
      late FakeSession session;
      session = FakeSession(
        roles: general,
        globalPermissions: const ['branch.read'],
        branchList: [branch('a', 'active')],
        dashboardError: scopeError,
        onDashboardError: () => session.branchList = [branch('a', 'draft')],
      );
      final c = await started(session);

      expect(c.branchUnavailable, isTrue);
      expect(c.branchNotReady, isTrue);
      expect(c.error, isNull, reason: 'no raw NOT_FOUND text');
      expect(c.errorDetails, isNull);
      expect(c.branch?.status, 'draft', reason: 'status refreshed from the list');
    });

    test('genuine errors keep message and Ref in errorDetails', () async {
      final session = FakeSession(
        roles: general,
        globalPermissions: const ['branch.read'],
        branchList: [branch('a', 'active')],
        dashboardError: const DlcApiException(
          'Error interno.',
          code: 'INTERNAL',
          statusCode: 500,
          correlationId: 'abc-123',
        ),
      );
      final c = await started(session);

      expect(c.branchNotReady, isFalse);
      expect(c.error, 'Error interno.');
      expect(c.errorDetails, contains('Ref. abc-123'));
    });

    test('refresh picks up an activated branch', () async {
      final session = FakeSession(
        roles: const [EmployeeRole(code: 'branch_manager', name: 'Gerente', branchId: 'd')],
        globalPermissions: const [],
        branchList: [branch('d', 'draft')],
      );
      final c = await started(session);
      expect(c.branchNotReady, isTrue);

      session.branchList = [branch('d', 'active')];
      await c.refresh();

      expect(c.branchNotReady, isFalse);
      expect(session.calls, contains('dashboard:d'));
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(theme: lightTheme, home: Scaffold(body: SingleChildScrollView(child: child))),
    );

    testWidgets('BranchNotReadyPanel: message, badge and button for managers', (tester) async {
      var opened = 0;
      await pump(
        tester,
        BranchNotReadyPanel(
          branch: branch('d', 'draft', name: 'Centro'),
          canManage: true,
          onOpenOnboarding: () => opened++,
        ),
      );

      expect(find.textContaining('Esta sucursal está en preparación (borrador)'), findsOneWidget);
      expect(find.byKey(const Key('branch-status-badge')), findsOneWidget);
      expect(find.text('Borrador'), findsOneWidget);
      expect(find.textContaining('NOT_FOUND'), findsNothing);
      await tester.tap(find.byKey(const Key('open-onboarding')));
      expect(opened, 1);
    });

    testWidgets('BranchNotReadyPanel: users without permission only see the explanation', (tester) async {
      await pump(
        tester,
        BranchNotReadyPanel(branch: branch('d', 'draft'), canManage: false, onOpenOnboarding: () {}),
      );

      expect(find.textContaining('en preparación'), findsOneWidget);
      expect(find.byKey(const Key('open-onboarding')), findsNothing);
      expect(find.textContaining('Gerente General'), findsOneWidget);
    });

    testWidgets('ErrorBox hides Ref under a collapsed "Detalles técnicos"', (tester) async {
      await pump(tester, const ErrorBox('Error interno.', details: 'HTTP 500 · Ref. abc-123'));

      expect(find.text('Error interno.'), findsOneWidget);
      expect(find.text('Detalles técnicos'), findsOneWidget);
      expect(find.textContaining('abc-123'), findsNothing);
      await tester.tap(find.text('Detalles técnicos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('abc-123'), findsOneWidget);
    });

    testWidgets('network dashboard shows the empty state without calling the API when nothing is active', (tester) async {
      final session = FakeSession(
        roles: general,
        globalPermissions: const ['branch.read'],
        branchList: const [],
      );
      var onboarding = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: NetworkDashboardPage(
            api: session,
            branches: [branch('d', 'draft'), branch('e', 'configured')],
            onOpenOnboarding: () => onboarding++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Aún no hay sucursales activas'), findsOneWidget);
      expect(session.calls, isNot(contains('network')));
      await tester.tap(find.byKey(const Key('open-onboarding')));
      expect(onboarding, 1);
    });

    testWidgets('app lands on the branch list with a call to action when no branch is active', (tester) async {
      final session = FakeSession(
        roles: general,
        globalPermissions: const ['branch.read', 'branch.manage'],
        branchList: [branch('d', 'draft', name: 'Borrador Uno')],
      );
      await tester.pumpWidget(OperationsApp(controller: OperationsController(session)));
      await tester.pumpAndSettle();

      expect(find.text('Aún no hay sucursales activas'), findsOneWidget);
      expect(find.text('Borrador Uno'), findsOneWidget);
      expect(find.text('Borrador'), findsOneWidget);
      expect(find.textContaining('NOT_FOUND'), findsNothing);

      await tester.tap(find.text('Borrador Uno'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('branch-not-ready')), findsOneWidget);
      expect(find.byKey(const Key('open-onboarding')), findsOneWidget);
      expect(session.calls.where((x) => x.startsWith('dashboard')), isEmpty);
    });
  });
}
