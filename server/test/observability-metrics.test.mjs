import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

const source = await readFile(new URL('../src/observability/http-metrics.ts', import.meta.url), 'utf8');
const moduleSource = stripTypeScriptTypes(source, { mode: 'transform' });
const metrics = await import(`data:text/javascript;base64,${Buffer.from(moduleSource).toString('base64')}`);

test('HTTP metrics aggregate durations into cumulative histogram buckets', () => {
  const registry = new metrics.HttpMetricsRegistry();
  registry.record('GET', '/api/v1/branches/:branchId/dashboard', 200, 0.03);
  registry.record('GET', '/api/v1/branches/:branchId/dashboard', 200, 0.11);
  const [sample] = registry.snapshot();
  assert.equal(sample.count, 2);
  assert.equal(sample.sumSeconds, 0.14);
  assert.equal(sample.maxSeconds, 0.11);
  assert.deepEqual(sample.buckets, [1, 1, 2, 2, 2, 2, 2]);
});

test('dynamic UUID/numeric paths collapse and query strings never become labels', () => {
  const registry = new metrics.HttpMetricsRegistry();
  registry.record('GET', '/api/v1/branches/123e4567-e89b-42d3-a456-426614174000/tanks/42', 200, 0.01);
  registry.record('GET', '/api/v1/branches?secret=token', 200, 0.01);
  const routes = registry.snapshot().map(sample => sample.route);
  assert.deepEqual(routes, ['/api/v1/branches/:id/tanks/:id', 'unmatched']);
});

test('invalid metric labels and durations are bounded and nonnegative', () => {
  const registry = new metrics.HttpMetricsRegistry();
  registry.record('get /private', '/secret?token=abc', 700, -5);
  const [sample] = registry.snapshot();
  assert.equal(sample.method, 'OTHER');
  assert.equal(sample.route, 'unmatched');
  assert.equal(sample.status, 0);
  assert.equal(sample.sumSeconds, 0);
  assert.equal(sample.maxSeconds, 0);
  assert.doesNotMatch(metrics.renderPrometheusMetrics([sample], { total: 1, idle: 0, waiting: 0 }), /private|secret|token=abc/);
});

test('middleware records completed responses using route templates, not request URLs', () => {
  metrics.httpMetrics.reset();
  const request = { method: 'GET', url: '/api/v1/branches/123e4567-e89b-42d3-a456-426614174000/dashboard?token=secret', route: { path: '/api/v1/branches/:branchId/dashboard' } };
  const response = new EventEmitter();
  response.statusCode = 201;
  let called = false;
  metrics.httpMetricsMiddleware(request, response, () => { called = true; });
  response.emit('finish');
  const [sample] = metrics.httpMetrics.snapshot();
  assert.equal(called, true);
  assert.equal(sample.route, '/api/v1/branches/:branchId/dashboard');
  assert.equal(sample.status, 201);
  assert.ok(sample.sumSeconds >= 0);
  metrics.httpMetrics.reset();
});

test('Prometheus output includes process and PostgreSQL pool gauges with safe counts', () => {
  const registry = new metrics.HttpMetricsRegistry();
  registry.record('POST', '/api/v1/cuts', 409, 0.4);
  const output = metrics.renderPrometheusMetrics(registry.snapshot(), { total: 8, idle: 6, waiting: 2 });
  assert.match(output, /dlc_http_requests_total\{method="POST",route="\/api\/v1\/cuts",status="409"\} 1/);
  assert.match(output, /dlc_process_uptime_seconds [0-9.]+/);
  assert.match(output, /dlc_process_resident_memory_bytes [0-9]+/);
  assert.match(output, /dlc_pg_pool_connections\{state="total"\} 8/);
  assert.match(output, /dlc_pg_pool_connections\{state="waiting"\} 2/);
  assert.ok(output.endsWith('\n'));
  const invalidCounts = metrics.renderPrometheusMetrics([], { total: Number.NaN, idle: -2, waiting: Number.POSITIVE_INFINITY });
  assert.match(invalidCounts, /state="total"\} 0/);
  assert.match(invalidCounts, /state="idle"\} 0/);
  assert.match(invalidCounts, /state="waiting"\} 0/);
});

test('registry snapshots are detached from later mutation', () => {
  const registry = new metrics.HttpMetricsRegistry();
  registry.record('GET', '/health/ready', 200, 0.01);
  const snapshot = registry.snapshot();
  snapshot[0].buckets[0] = 999;
  registry.record('GET', '/health/ready', 200, 0.02);
  assert.equal(registry.snapshot()[0].buckets[0], 2);
});
