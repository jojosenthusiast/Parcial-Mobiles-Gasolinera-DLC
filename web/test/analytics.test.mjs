import test from 'node:test';
import assert from 'node:assert/strict';
import { analyze, previousRange, quickRange, validateRange, pctDelta, exportView, columnKind, shortDay } from '../public/reports-model.js';
import { niceTicks, lineChartMarkup, barChartMarkup } from '../public/charts.js';
import { validatePromptValue } from '../public/dialogs.js';

test('reportes: el periodo anterior tiene la misma duración y termina el día previo', () => {
  assert.deepEqual(previousRange('2026-10-04', '2026-10-10'), { from: '2026-09-27', to: '2026-10-03' });
  assert.deepEqual(quickRange('30d', '2026-10-10'), { from: '2026-09-11', to: '2026-10-10' });
  assert.equal(validateRange('2026-10-10', '2026-10-01').ok, false);
  assert.equal(validateRange('2025-01-01', '2026-10-10').ok, false);
  assert.equal(validateRange('2026-02-30', '2026-03-01').ok, false);
  assert.equal(pctDelta(110, 100).dir, 'up');
  assert.equal(pctDelta(5, 0), null);
  assert.equal(shortDay('2026-10-03'), '3 oct');
});

test('reportes: KPIs y gráficas de ventas con variación contra el periodo anterior', () => {
  const byDay = [{ groupValue: '2026-10-02', totalUsd: '200', liters: '50', saleCount: 4 }, { groupValue: '2026-10-01', totalUsd: '100', liters: '30', saleCount: 2 }];
  const view = analyze('fuel_sales', { byDay, byFuel: [{ groupValue: 'Súper', totalUsd: '300', liters: '80' }] }, { previous: { byDay: [{ groupValue: 'x', totalUsd: '150', liters: '40', saleCount: 3 }] } });
  assert.equal(view.kpis[0].value, 300);
  assert.equal(view.kpis[0].delta.pct, 100);
  assert.equal(view.kpis[3].value, 50);
  assert.deepEqual(view.charts[0].categories, ['1 oct', '2 oct']);
  assert.equal(view.charts[1].rows[0].family, 'super');
});

test('reportes: incidencias, gastos y cierres de caja no mezclan ni pierden registros', () => {
  const inc = analyze('incidents', [{ severity: 'low', status: 'reported' }, { severity: 'critical', status: 'closed' }, { severity: 'high', status: 'reported' }]);
  assert.equal(inc.kpis[1].value, 2);
  assert.equal(inc.kpis[2].value, 2);
  assert.equal(inc.charts[0].series[0].values.length, 3);
  const exp = analyze('expenses', [{ category: 'A', amountUsd: '10', incurredOn: '2026-10-01' }, { category: 'B', amountUsd: '30', incurredOn: '2026-10-01' }], { previous: [{ amountUsd: '20' }] });
  assert.equal(exp.kpis[0].value, 40);
  assert.equal(exp.kpis[0].invertDelta, true);
  assert.equal(exp.charts[1].rows[0].label, 'B');
  const cash = analyze('cash_closures', [{ createdAt: '2026-10-01T10:00:00Z', varianceCashUsd: '-5', varianceCardUsd: '0' }, { createdAt: '2026-10-01T20:00:00Z', varianceCashUsd: '0', varianceCardUsd: '0' }]);
  assert.equal(cash.kpis[3].value, 1);
  assert.equal(cash.charts[0].categories.length, 2);
  assert.notEqual(cash.charts[0].categories[0], cash.charts[0].categories[1]);
  assert.deepEqual(analyze('desconocido', []), { kpis: [], charts: [] });
});

test('reportes: precios en escalón arrastran el último valor y los saldos por tanque no inventan datos', () => {
  const prices = analyze('fuel_prices', [{ effectiveAt: '2026-10-01T00:00:00Z', fuelName: 'Súper', serviceMode: 'self_service', price: '3.5' }, { effectiveAt: '2026-10-05T00:00:00Z', fuelName: 'Regular', serviceMode: 'self_service', price: '3.2' }]);
  const superSeries = prices.charts[0].series.find(s => s.name.startsWith('Súper'));
  assert.deepEqual(superSeries.values, [3.5, 3.5]);
  const tanks = analyze('tank_movements', [{ occurredAt: '2026-10-01T10:00:00Z', tankCode: 'T-1', balanceLiters: '100', deltaLiters: '-10', movementType: 'sale' }, { occurredAt: '2026-10-02T10:00:00Z', tankCode: 'T-2', balanceLiters: '50', deltaLiters: '5', movementType: 'delivery' }]);
  assert.deepEqual(tanks.charts[0].series[1].values, [null, 50]);
});

test('exportaciones: estados en cola, generando, listo y falló con reintento y cancelación', () => {
  assert.equal(exportView({ state: 'queued' }, 1000).canRetry, false);
  const stalled = exportView({ state: 'queued' }, 25000);
  assert.equal(stalled.stalled, true);
  assert.equal(stalled.canRetry, true);
  assert.equal(stalled.canCancel, true);
  const running = exportView({ state: 'running', progress: { completed: 5, total: 10, percent: 50 } });
  assert.equal(running.label, 'Generando');
  assert.match(running.detail, /5 de 10/);
  assert.equal(exportView({ state: 'succeeded', filename: 'a.csv' }).canDownload, true);
  const failed = exportView({ state: 'failed', error: 'boom' });
  assert.deepEqual([failed.label, failed.canRetry, failed.detail], ['Falló', true, 'boom']);
  assert.equal(exportView({ state: 'cancelled' }).canRetry, true);
});

test('tablas: cada columna se formatea según su tipo', () => {
  assert.equal(columnKind('totalUsd'), 'money');
  assert.equal(columnKind('balanceLiters'), 'liters');
  assert.equal(columnKind('occurredAt'), 'datetime');
  assert.equal(columnKind('severity'), 'status');
  assert.equal(columnKind('description'), 'text');
});

test('gráficas SVG: ejes agradables, barras con signo, texto alternativo y sin estilos en línea', () => {
  const t = niceTicks(0, 4870, 4);
  assert.equal(t.min, 0);
  assert.ok(t.max >= 4870 && t.ticks.length >= 4);
  const line = lineChartMarkup({ categories: ['a', 'b', 'c'], series: [{ name: 'Ventas', values: [1, 3, 2] }], area: true, ariaLabel: 'Ventas por día' });
  assert.match(line, /role="img" aria-label="Ventas por día"/);
  assert.match(line, /pathLength="1"/);
  assert.doesNotMatch(line, /style=/);
  const bars = barChartMarkup({ categories: ['a', 'b'], series: [{ name: 'Dif', values: [-5, 0] }], signed: true, ariaLabel: 'x' });
  assert.match(bars, /ch-neg/);
  assert.match(bars, /ch-zero-bar/);
  assert.equal(lineChartMarkup({ categories: [], series: [] }), '');
});

test('diálogos: la validación del texto exige longitud mínima y formato', () => {
  assert.equal(validatePromptValue('  ', { minLength: 1 }).ok, false);
  assert.equal(validatePromptValue('corto', { minLength: 10 }).ok, false);
  assert.equal(validatePromptValue(' motivo suficiente ', { minLength: 10 }).value, 'motivo suficiente');
  assert.equal(validatePromptValue('abc', { pattern: /^\d+$/ }).ok, false);
});
