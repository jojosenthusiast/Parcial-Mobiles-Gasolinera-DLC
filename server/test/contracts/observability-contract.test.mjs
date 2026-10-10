import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const openapi = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const controller = await readFile(new URL('../../src/metrics/metrics.controller.ts', import.meta.url), 'utf8');
const alerts = await readFile(new URL('../../../infra/monitoring/dlc-alerts.yml', import.meta.url), 'utf8');

test('Prometheus endpoint is documented as authenticated and system-scoped', () => {
  const endpoint = openapi.paths['/metrics/http']?.get;
  assert.ok(endpoint);
  assert.deepEqual(endpoint.security, [{ bearerAuth: [] }]);
  assert.equal(endpoint.operationId, 'httpMetricsPrometheus');
  assert.equal(endpoint.responses['200'].content['text/plain'].schema.type, 'string');
  assert.ok(endpoint.responses['401']);
  assert.ok(endpoint.responses['403']);
  assert.match(endpoint.description, /no incluyen usuario, IP, identificadores, parámetros de consulta/i);
  assert.match(controller, /@RequirePermission\('branch\.manage'\)\s+@Get\('http'\)/);
  assert.match(controller, /response\.setHeader\('Content-Type','text\/plain; version=0\.0\.4; charset=utf-8'\)/);
});

test('las alertas versionadas usan métricas publicadas y conservan umbrales definidos', () => {
  for (const name of ['DLCHighServerErrorRate','DLCHighRequestLatency','DLCDatabasePoolWaiting','DLCHighProcessMemory','DLCApiRestarted']) {
    assert.match(alerts, new RegExp(`alert: ${name}`));
  }
  for (const metric of ['dlc_http_requests_total','dlc_http_request_duration_seconds_bucket','dlc_pg_pool_connections','dlc_process_resident_memory_bytes','dlc_process_uptime_seconds']) {
    assert.ok(alerts.includes(metric), `falta métrica publicada ${metric}`);
  }
  assert.match(alerts, /for: 10m/);
  assert.match(alerts, /1073741824/);
});
