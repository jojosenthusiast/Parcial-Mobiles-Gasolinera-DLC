import type { NextFunction, Request, Response } from 'express';

const BUCKETS_SECONDS = [0.05, 0.1, 0.3, 1, 3, 10, Number.POSITIVE_INFINITY] as const;
type Aggregate = { count: number; sumSeconds: number; maxSeconds: number; buckets: number[] };
export type HttpMetricSample = { method: string; route: string; status: number; count: number; sumSeconds: number; maxSeconds: number; buckets: number[] };

export class HttpMetricsRegistry {
  private readonly values = new Map<string, Aggregate>();

  record(method: string, route: string, status: number, durationSeconds: number): void {
    const safeMethod = /^[A-Z]{1,12}$/.test(method) ? method : 'OTHER';
    const safeRoute = normalizeRoute(route);
    const safeStatus = Number.isInteger(status) && status >= 100 && status <= 599 ? status : 0;
    const seconds = Number.isFinite(durationSeconds) ? Math.max(0, durationSeconds) : 0;
    const key = `${safeMethod}\u0000${safeRoute}\u0000${safeStatus}`;
    const aggregate = this.values.get(key) ?? { count: 0, sumSeconds: 0, maxSeconds: 0, buckets: BUCKETS_SECONDS.map(() => 0) };
    aggregate.count += 1;
    aggregate.sumSeconds += seconds;
    aggregate.maxSeconds = Math.max(aggregate.maxSeconds, seconds);
    for (let index = 0; index < BUCKETS_SECONDS.length; index += 1) {
      if (seconds <= BUCKETS_SECONDS[index]!) aggregate.buckets[index] = aggregate.buckets[index]! + 1;
    }
    this.values.set(key, aggregate);
  }

  snapshot(): HttpMetricSample[] {
    return [...this.values.entries()].map(([key, value]) => {
      const [method, route, status] = key.split('\u0000');
      return { method: method!, route: route!, status: Number(status), count: value.count, sumSeconds: value.sumSeconds, maxSeconds: value.maxSeconds, buckets: [...value.buckets] };
    }).sort((a, b) => a.route.localeCompare(b.route) || a.method.localeCompare(b.method) || a.status - b.status);
  }

  reset(): void { this.values.clear(); }
}

export const httpMetrics = new HttpMetricsRegistry();

export function httpMetricsMiddleware(request: Request, response: Response, next: NextFunction): void {
  const started = process.hrtime.bigint();
  response.once('finish', () => {
    const seconds = Number(process.hrtime.bigint() - started) / 1_000_000_000;
    const path = typeof request.route?.path === 'string' ? request.route.path : 'unmatched';
    httpMetrics.record(request.method, path, response.statusCode, seconds);
  });
  next();
}

export function renderPrometheusMetrics(samples: HttpMetricSample[], pool: { total: number; idle: number; waiting: number }): string {
  const lines = [
    '# HELP dlc_http_requests_total Completed HTTP requests.',
    '# TYPE dlc_http_requests_total counter',
    '# HELP dlc_http_request_duration_seconds HTTP request duration in seconds.',
    '# TYPE dlc_http_request_duration_seconds histogram',
    '# HELP dlc_http_request_duration_seconds_max Maximum completed request duration in seconds since process start.',
    '# TYPE dlc_http_request_duration_seconds_max gauge',
  ];
  for (const sample of samples) {
    const labels = `method="${escapeLabel(sample.method)}",route="${escapeLabel(sample.route)}",status="${sample.status}"`;
    BUCKETS_SECONDS.forEach((boundary, index) => {
      const le = Number.isFinite(boundary) ? String(boundary) : '+Inf';
      lines.push(`dlc_http_request_duration_seconds_bucket{${labels},le="${le}"} ${sample.buckets[index] ?? 0}`);
    });
    lines.push(`dlc_http_requests_total{${labels}} ${sample.count}`);
    lines.push(`dlc_http_request_duration_seconds_sum{${labels}} ${formatNumber(sample.sumSeconds)}`);
    lines.push(`dlc_http_request_duration_seconds_count{${labels}} ${sample.count}`);
    lines.push(`dlc_http_request_duration_seconds_max{${labels}} ${formatNumber(sample.maxSeconds)}`);
  }
  lines.push('# HELP dlc_process_uptime_seconds Process uptime in seconds.', '# TYPE dlc_process_uptime_seconds gauge', `dlc_process_uptime_seconds ${formatNumber(process.uptime())}`);
  lines.push('# HELP dlc_process_resident_memory_bytes Resident memory in bytes.', '# TYPE dlc_process_resident_memory_bytes gauge', `dlc_process_resident_memory_bytes ${process.memoryUsage().rss}`);
  lines.push('# HELP dlc_pg_pool_connections PostgreSQL pool connections by state.', '# TYPE dlc_pg_pool_connections gauge');
  for (const [state, count] of Object.entries(pool)) {
    const safeCount = Number.isFinite(count) ? Math.max(0, Math.trunc(count)) : 0;
    lines.push(`dlc_pg_pool_connections{state="${state}"} ${safeCount}`);
  }
  return `${lines.join('\n')}\n`;
}

function normalizeRoute(route: string): string {
  if (!route || route === 'unmatched' || route.length > 200 || route.includes('?') || route.includes('#')) return 'unmatched';
  const parameterized = route
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi, ':id')
    .replace(/(^|\/)\d+(?=\/|$)/g, '$1:id');
  if (!/^\/?[A-Za-z0-9_:/{}.*-]+$/.test(parameterized)) return 'unmatched';
  return parameterized.startsWith('/') ? parameterized : `/${parameterized}`;
}

function escapeLabel(value: string): string { return value.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll('"', '\\"'); }
function formatNumber(value: number): string { return Number.isFinite(value) ? value.toFixed(6).replace(/0+$/, '').replace(/\.$/, '') || '0' : '0'; }
