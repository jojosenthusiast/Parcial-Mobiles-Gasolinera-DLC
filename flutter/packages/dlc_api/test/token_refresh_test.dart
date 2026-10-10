import 'dart:async';
import 'dart:convert';

import 'package:dlc_api/dlc_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

typedef Handler = Future<(int, Object?)> Function(
  http.BaseRequest request,
  String? bearer,
);

class FakeClient extends http.BaseClient {
  FakeClient(this.handler);
  final Handler handler;
  final log = <String>[];

  int count(String route) => log.where((l) => l == route).length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    log.add('${request.method} ${request.url.path.replaceFirst('/api/v1', '')}');
    final (status, body) = await handler(
      request,
      request.headers['Authorization']?.replaceFirst('Bearer ', ''),
    );
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body ?? {}))),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, Object?> tokens(int n) => {
  'accessToken': 'access$n',
  'refreshToken': 'refresh$n',
  'sessionId': 'session$n',
};

const unauthenticated = {
  'error': {'code': 'UNAUTHENTICATED', 'message': 'Token vencido.'},
};

Future<EmployeeSession> loggedIn(FakeClient client) async {
  final session = EmployeeSession(
    client: client,
    storage: const FlutterSecureStorage(),
  );
  await session.login('gerente@dlc.test', 'secret');
  client.log.clear();
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<(int, Object?)> baseRoutes(http.BaseRequest r) async {
    final route = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
    if (route == 'POST /auth/login') return (200, tokens(1));
    if (route == 'GET /auth/me') {
      return (
        200,
        {
          'data': {
            'id': 'u1',
            'organizationId': 'o1',
            'displayName': 'Gerente',
            'email': 'gerente@dlc.test',
            'roles': <Object>[],
          },
        },
      );
    }
    throw StateError('unexpected $route');
  }

  test('401 triggers one refresh and the request is retried with the new token',
      () async {
    var refreshed = false;
    final client = FakeClient((r, bearer) async {
      final route = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
      if (route == 'POST /auth/refresh') {
        refreshed = true;
        return (200, tokens(2));
      }
      if (route == 'GET /auth/me/capabilities') {
        if (bearer != 'access2') return (401, unauthenticated);
        return (
          200,
          {
            'data': {
              'permissions': ['branch.read'],
            },
          },
        );
      }
      return baseRoutes(r);
    });
    final session = await loggedIn(client);

    final permissions = await session.capabilities();

    expect(permissions, ['branch.read']);
    expect(refreshed, isTrue);
    expect(client.log, [
      'GET /auth/me/capabilities',
      'POST /auth/refresh',
      'GET /auth/me/capabilities',
    ]);
  });

  test('concurrent 401s share a single refresh', () async {
    final gate = Completer<void>();
    final client = FakeClient((r, bearer) async {
      final route = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
      if (route == 'POST /auth/refresh') {
        await gate.future;
        return (200, tokens(2));
      }
      if (route == 'GET /auth/me/capabilities' || route == 'GET /suppliers') {
        if (bearer != 'access2') return (401, unauthenticated);
        return (200, {'data': route == 'GET /suppliers' ? [] : {'permissions': []}});
      }
      return baseRoutes(r);
    });
    final session = await loggedIn(client);

    final a = session.capabilities();
    final b = session.suppliers(branchId: 'branch-1');
    final c = session.capabilities(branchId: 'branch-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete();
    await Future.wait<dynamic>([a, b, c]);

    expect(client.count('POST /auth/refresh'), 1);
    expect(client.count('GET /suppliers'), 2); // first 401, then retry
  });

  test('a late 401 for an already-rotated token does not refresh again',
      () async {
    final slow = Completer<void>();
    final client = FakeClient((r, bearer) async {
      final route = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
      if (route == 'POST /auth/refresh') return (200, tokens(2));
      if (route == 'GET /auth/me/capabilities') {
        if (bearer == 'access1') {
          await slow.future; // answered only after the refresh finished
          return (401, unauthenticated);
        }
        return (200, {'data': {'permissions': ['x']}});
      }
      if (route == 'GET /suppliers') {
        return bearer == 'access2'
            ? (200, {'data': []})
            : (401, unauthenticated);
      }
      return baseRoutes(r);
    });
    final session = await loggedIn(client);

    final late = session.capabilities();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await session.suppliers(branchId: 'b'); // 401 -> refresh -> access2
    slow.complete();

    expect(await late, ['x']);
    expect(client.count('POST /auth/refresh'), 1);
  });

  test('refresh failure clears the session and reports expiry', () async {
    final client = FakeClient((r, bearer) async {
      final route = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
      if (route == 'POST /auth/refresh') return (401, unauthenticated);
      if (route == 'GET /auth/me/capabilities') return (401, unauthenticated);
      return baseRoutes(r);
    });
    final session = await loggedIn(client);
    var expired = 0;
    session.onSessionExpired = () => expired++;

    await expectLater(
      session.capabilities(),
      throwsA(
        isA<DlcApiException>()
            .having((e) => e.code, 'code', 'SESSION_EXPIRED')
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );

    expect(expired, 1);
    expect(client.count('POST /auth/refresh'), 1);
    expect(await const FlutterSecureStorage().read(key: 'operations.access'),
        isNull);
    expect(await const FlutterSecureStorage().read(key: 'operations.refresh'),
        isNull);
  });

  test('a request that keeps returning 401 is retried only once', () async {
    final client = FakeClient((r, bearer) async {
      final route = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
      if (route == 'POST /auth/refresh') return (200, tokens(2));
      if (route == 'GET /auth/me/capabilities') return (401, unauthenticated);
      return baseRoutes(r);
    });
    final session = await loggedIn(client);

    await expectLater(
      session.capabilities(),
      throwsA(isA<DlcApiException>().having((e) => e.statusCode, 'status', 401)),
    );

    expect(client.count('GET /auth/me/capabilities'), 2);
    expect(client.count('POST /auth/refresh'), 1);
  });

  test('login and refresh calls never trigger a refresh on 401', () async {
    final client = FakeClient((r, bearer) async => (401, unauthenticated));
    final session = EmployeeSession(
      client: client,
      storage: const FlutterSecureStorage(),
    );

    await expectLater(
      session.login('gerente@dlc.test', 'bad'),
      throwsA(isA<DlcApiException>()),
    );

    expect(client.log, ['POST /auth/login']);
  });

  test('restore clears the session when refresh answers UNAUTHENTICATED',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'operations.access': 'old',
      'operations.refresh': 'oldr',
      'operations.session': 'olds',
    });
    final client = FakeClient((r, bearer) async => (401, unauthenticated));
    final session = EmployeeSession(
      client: client,
      storage: const FlutterSecureStorage(),
    );

    expect(await session.restore(), isNull);
    expect(await const FlutterSecureStorage().read(key: 'operations.refresh'),
        isNull);
  });

  test('suppliers sends the branchId query for branch-scoped users', () async {
    Uri? seen;
    final client = FakeClient((r, bearer) async {
      final route = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
      if (route == 'GET /suppliers') {
        seen = r.url;
        return (200, {'data': []});
      }
      return baseRoutes(r);
    });
    final session = await loggedIn(client);

    await session.suppliers(branchId: 'b 1');

    expect(seen!.queryParameters['branchId'], 'b 1');
    expect(seen!.queryParameters['limit'], '100');
  });
}

