import test from 'node:test';
import assert from 'node:assert/strict';

const base = process.env.DLC_API_BASE_URL;
const apiHealthTest = base ? test : test.skip;
apiHealthTest('API responde el health contract (requiere DLC_API_BASE_URL)', async () => {
  const response = await fetch(`${base}/api/v1/health/live`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.status, 'ok');
  assert.ok(Number.isFinite(Date.parse(body.timestamp)));
});

apiHealthTest('API solo queda ready cuando PostgreSQL responde', async () => {
  const response = await fetch(`${base}/api/v1/health/ready`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.status, 'ready');
  assert.equal(body.database, 'reachable');
});

apiHealthTest('API protege la sesión y devuelve correlación en errores 401', async () => {
  const correlationId = '11111111-1111-4111-8111-111111111111';
  const response = await fetch(`${base}/api/v1/auth/me`, { headers: { 'X-Request-ID': correlationId } });
  assert.equal(response.status, 401);
  const body = await response.json();
  assert.equal(body.code, 'UNAUTHENTICATED');
  assert.equal(body.correlationId, correlationId);
  assert.equal(response.headers.get('x-request-id'), correlationId);
});
