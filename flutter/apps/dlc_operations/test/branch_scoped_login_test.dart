import 'package:dlc_api/dlc_api.dart';
import 'package:dlc_operations/branch_onboarding_screen.dart';
import 'package:dlc_operations/main.dart';
import 'package:flutter_test/flutter_test.dart';

const branchId = '11111111-1111-4111-8111-111111111111';

class ScopedSession extends EmployeeSession {
  ScopedSession({required this.globalPermissions, required this.roles});
  final List<String> globalPermissions;
  final List<EmployeeRole> roles;
  final calls = <String>[];

  @override
  Future<EmployeeIdentity?> restore() async => null;

  @override
  Future<EmployeeIdentity> login(String email, String password) async =>
      EmployeeIdentity(
        id: 'u1',
        organizationId: 'o1',
        displayName: 'Gerente',
        email: email,
        roles: roles,
      );

  @override
  Future<List<String>> capabilities({String? branchId}) async {
    calls.add('capabilities:${branchId ?? 'global'}');
    return branchId == null
        ? globalPermissions
        : const ['branch.read', 'dispenser.read'];
  }

  @override
  Future<List<BranchSummary>> branches({
    String status = 'active',
    String? countryCode,
  }) async {
    calls.add('branches');
    if (!globalPermissions.contains('branch.read')) {
      throw const DlcApiException('Sin permiso.', statusCode: 403);
    }
    return const [
      BranchSummary(
        id: branchId,
        code: 'A',
        name: 'Centro',
        zone: 'central',
        timezone: 'America/El_Salvador',
      ),
      BranchSummary(
        id: 'other',
        code: 'B',
        name: 'Otra',
        zone: 'central',
        timezone: 'America/El_Salvador',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> branchDetail(String id) async {
    calls.add('branchDetail:$id');
    return {
      'id': id,
      'code': 'A',
      'name': 'Centro',
      'zone': 'central',
      'timezone': 'America/El_Salvador',
      'status': 'active',
    };
  }

  @override
  Future<Map<String, dynamic>> branchDashboard(String id) async => {'ok': true};

  @override
  Future<List<Map<String, dynamic>>> dispensers(String id) async => const [];

  @override
  Future<void> clear() async {}
}

void main() {
  test('branch-scoped manager signs in without calling GET /branches', () async {
    final session = ScopedSession(
      globalPermissions: const [],
      roles: const [
        EmployeeRole(code: 'branch_manager', name: 'Gerente', branchId: branchId),
      ],
    );
    final controller = OperationsController(session);
    await controller.start();

    await controller.signIn('gerente@dlc.test', 'secret');

    expect(controller.error, isNull);
    expect(session.calls, isNot(contains('branches')));
    expect(session.calls, contains('branchDetail:$branchId'));
    expect(controller.identity, isNotNull);
    expect(controller.branches.map((b) => b.id), [branchId]);
    expect(controller.branch?.id, branchId);
    expect(controller.dashboard, {'ok': true});
    expect(controller.permissions, contains('dispenser.read'));
  });

  test('org-wide manager with branch.read lists branches from GET /branches',
      () async {
    final session = ScopedSession(
      globalPermissions: const ['branch.read'],
      roles: const [EmployeeRole(code: 'general_manager', name: 'General')],
    );
    final controller = OperationsController(session);
    await controller.start();

    await controller.signIn('general@dlc.test', 'secret');

    expect(session.calls, contains('branches'));
    expect(session.calls.where((c) => c.startsWith('branchDetail')), isEmpty);
    expect(controller.branches, hasLength(2));
    expect(controller.branch, isNull);
  });

  test('session expiry callback returns the controller to signed-out state',
      () async {
    final session = ScopedSession(
      globalPermissions: const ['branch.read'],
      roles: const [EmployeeRole(code: 'general_manager', name: 'General')],
    );
    final controller = OperationsController(session);
    await controller.start();
    await controller.signIn('general@dlc.test', 'secret');

    session.onSessionExpired!();

    expect(controller.identity, isNull);
    expect(controller.branches, isEmpty);
    expect(controller.error, contains('Inicia'));
  });

  test('academicLab22 always sends exactly six dispensers', () {
    expect(dispenserCountForProfile('academicLab22', 10), 6);
    expect(dispenserCountForProfile('academicLab22', 1), 6);
    expect(dispenserCountForProfile('operational', 10), 10);
  });
}

