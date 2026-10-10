// Pure analytics model for the Reportes module: report catalogue, period maths, KPI and chart specs per report type,
// and the visual state of an asynchronous export job. No DOM access, so node tests can import it.
import { statusLabel } from './labels.js';

export const REPORT_TYPES = Object.freeze([
  { id: 'fuel_sales', label: 'Ventas de combustible', permission: 'sale.read', icon: 'drop', money: true },
  { id: 'closed_cuts', label: 'Cortes cerrados', permission: 'sale.read', icon: 'flag', money: true },
  { id: 'tank_movements', label: 'Movimientos de tanque', permission: 'inventory.read', icon: 'tank' },
  { id: 'incidents', label: 'Incidencias', permission: 'incident.read', icon: 'alert-triangle' },
  { id: 'purchase_orders', label: 'Órdenes de compra', permission: 'purchase.read', icon: 'cart' },
  { id: 'fuel_prices', label: 'Historial de precios', permission: 'price.read', icon: 'tag', money: true },
  { id: 'expenses', label: 'Gastos operativos', permission: 'finance.cost.read', icon: 'receipt', money: true },
  { id: 'cash_closures', label: 'Cierres de caja', permission: 'cash.read', icon: 'banknote', money: true },
  { id: 'store_stock', label: 'Movimientos de tienda', permission: 'pos.catalog.read', icon: 'bag' },
  { id: 'maintenance_orders', label: 'Órdenes de mantenimiento', permission: 'maintenance.plan', icon: 'wrench', money: true },
  { id: 'staff_shifts', label: 'Turnos de personal', permission: 'staff.read', icon: 'users' },
  { id: 'operational_assets', label: 'Activos operativos', permission: 'operational_asset.read', icon: 'cube' },
]);

export const reportMeta = id => REPORT_TYPES.find(t => t.id === id) || null;

/* ------------------------------ period maths ------------------------------ */
const DAY = 86400000;
const parseDay = iso => Date.parse(`${iso}T00:00:00Z`);
export const isValidDay = value => /^\d{4}-\d{2}-\d{2}$/.test(String(value)) && Number.isFinite(parseDay(value)) && new Date(parseDay(value)).toISOString().slice(0, 10) === value;
export const addDays = (iso, n) => new Date(parseDay(iso) + n * DAY).toISOString().slice(0, 10);
export const spanDays = (from, to) => Math.round((parseDay(to) - parseDay(from)) / DAY) + 1;

export function validateRange(from, to) {
  if (!isValidDay(from) || !isValidDay(to)) return { ok: false, message: 'Selecciona fechas válidas.' };
  if (from > to) return { ok: false, message: 'La fecha inicial debe ser anterior o igual a la final.' };
  if (spanDays(from, to) > 366) return { ok: false, message: 'El rango máximo es de 366 días.' };
  return { ok: true };
}

// Same-length window immediately before [from, to].
export function previousRange(from, to) {
  const len = spanDays(from, to);
  return { from: addDays(from, -len), to: addDays(from, -1) };
}

export function quickRange(kind, today) {
  if (kind === '7d') return { from: addDays(today, -6), to: today };
  if (kind === '30d') return { from: addDays(today, -29), to: today };
  if (kind === 'month') return { from: `${today.slice(0, 8)}01`, to: today };
  return { from: today, to: today };
}

export function pctDelta(current, previous) {
  const a = Number(current); const b = Number(previous);
  if (!Number.isFinite(a) || !Number.isFinite(b) || b === 0) return null;
  const pct = ((a - b) / Math.abs(b)) * 100;
  return { pct, dir: Math.abs(pct) < 0.05 ? 'flat' : pct > 0 ? 'up' : 'down' };
}

const MONTHS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
export function shortDay(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso ?? ''));
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]}` : String(iso ?? '—');
}

/* ------------------------------ row helpers ------------------------------ */
const num = v => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const dayOf = v => String(v ?? '').slice(0, 10);
const sum = (rows, key) => rows.reduce((a, r) => a + num(r[key]), 0);
function groupSum(rows, keyOf, valueOf) {
  const map = new Map();
  for (const r of rows) { const k = keyOf(r); map.set(k, (map.get(k) || 0) + valueOf(r)); }
  return map;
}
const sortedEntries = map => [...map.entries()].sort((a, b) => String(a[0]).localeCompare(String(b[0])));
const byValueDesc = map => [...map.entries()].sort((a, b) => b[1] - a[1]);
export const fuelFamilyOf = name => { const t = String(name ?? '').toLowerCase(); return /s[uú]per|premium/.test(t) ? 'super' : /regular/.test(t) ? 'regular' : /di[eé]sel/.test(t) ? 'diesel' : 'other'; };
const SEVERITY_ORDER = ['critical', 'high', 'medium', 'low'];
const DONE_STATES = ['resolved', 'closed', 'received', 'completed', 'cancelled', 'rejected', 'done'];

const kpi = (label, value, format, extra = {}) => ({ label, value, format, ...extra });
const dayChart = (id, title, entries, extra = {}) => ({ id, kind: 'bar', title, categories: entries.map(e => shortDay(e[0])), series: [{ name: extra.seriesName || title, values: entries.map(e => e[1]) }], ...extra });

/* ------------------------------ analysis ------------------------------ */
// data: array of rows (every type except fuel_sales) or { byDay, byFuel } for fuel_sales. previous: same shape for the previous period.
export function analyze(type, data, { previous = null, now = Date.now() } = {}) {
  const fn = ANALYZERS[type];
  return fn ? fn(data, previous, now) : { kpis: [], charts: [] };
}

export function headlineTotal(type, data) {
  if (!data) return null;
  if (type === 'fuel_sales') return sum(data.byDay || [], 'totalUsd');
  if (type === 'expenses') return sum(data, 'amountUsd');
  return null;
}

const ANALYZERS = {
  fuel_sales(data, previous) {
    const days = (data.byDay || []).slice().sort((a, b) => String(a.groupValue).localeCompare(String(b.groupValue)));
    const total = sum(days, 'totalUsd'); const liters = sum(days, 'liters'); const count = sum(days, 'saleCount');
    const prevDays = previous?.byDay || null;
    const delta = prevDays?.length ? pctDelta(total, sum(prevDays, 'totalUsd')) : null;
    const literDelta = prevDays?.length ? pctDelta(liters, sum(prevDays, 'liters')) : null;
    const fuels = byValueDesc(groupSum(data.byFuel || [], r => r.groupValue, r => num(r.totalUsd)));
    return {
      kpis: [kpi('Ventas', total, 'money', { icon: 'banknote', delta, hero: true }), kpi('Litros vendidos', liters, 'liters', { icon: 'drop', delta: literDelta }), kpi('Transacciones', count, 'count', { icon: 'receipt' }), kpi('Ticket promedio', count ? total / count : null, 'money', { icon: 'tag' })],
      charts: [
        { id: 'sales-day', kind: 'line', area: true, title: 'Ventas por día', subtitle: 'Importe total por día operativo', format: 'money', categories: days.map(r => shortDay(r.groupValue)), series: [{ name: 'Ventas', values: days.map(r => num(r.totalUsd)) }], wide: true },
        { id: 'sales-fuel', kind: 'hbar', title: 'Ventas por combustible', format: 'money', rows: fuels.map(([label, value]) => ({ label, value, family: fuelFamilyOf(label), liters: sum((data.byFuel || []).filter(r => r.groupValue === label), 'liters') })) },
      ],
    };
  },
  closed_cuts(rows) {
    const dates = [...new Set(rows.map(r => dayOf(r.operationalDate)))].sort();
    const slots = [...new Set(rows.map(r => String(r.slot)))].sort();
    return {
      kpis: [kpi('Cortes', rows.length, 'count', { icon: 'flag', hero: true }), kpi('Ventas de los cortes', sum(rows, 'salesUsd'), 'money', { icon: 'banknote' }), kpi('Requieren revisión', rows.filter(r => r.reviewRequired === true || r.reviewRequired === 'true').length, 'count', { icon: 'alert-circle', tone: rows.some(r => r.reviewRequired === true || r.reviewRequired === 'true') ? 'warn' : '' }), kpi('Días con corte', dates.length, 'count', { icon: 'calendar' })],
      charts: [{ id: 'cuts-day', kind: 'bar', stacked: true, title: 'Ventas por día y corte', subtitle: 'Apilado por corte', format: 'money', wide: true, categories: dates.map(shortDay), series: slots.map(s => ({ name: `Corte ${s}`, values: dates.map(d => sum(rows.filter(r => dayOf(r.operationalDate) === d && String(r.slot) === s), 'salesUsd')) })) }],
    };
  },
  tank_movements(rows) {
    const sorted = rows.slice().sort((a, b) => String(a.occurredAt).localeCompare(String(b.occurredAt)));
    const dates = [...new Set(sorted.map(r => dayOf(r.occurredAt)))];
    const tanks = [...new Set(sorted.map(r => r.tankCode))];
    const series = tanks.map(code => {
      const last = new Map(sorted.filter(r => r.tankCode === code && r.balanceLiters !== null && r.balanceLiters !== '').map(r => [dayOf(r.occurredAt), num(r.balanceLiters)]));
      let carry = null;
      const fuelName = sorted.find(r => r.tankCode === code)?.fuelName;
      return { name: `${code}${fuelName ? ` · ${fuelName}` : ''}`, values: dates.map(d => { if (last.has(d)) carry = last.get(d); return carry; }) };
    });
    const types = byValueDesc(groupSum(rows, r => r.movementType, r => num(r.deltaLiters)));
    const inflow = rows.reduce((a, r) => a + Math.max(0, num(r.deltaLiters)), 0);
    return {
      kpis: [kpi('Movimientos', rows.length, 'count', { icon: 'layers', hero: true }), kpi('Variación neta', sum(rows, 'deltaLiters'), 'liters', { icon: 'tank', signed: true }), kpi('Entradas', inflow, 'liters', { icon: 'trend-up' }), kpi('Tanques con movimiento', tanks.length, 'count', { icon: 'tank' })],
      charts: [
        { id: 'tank-balance', kind: 'line', title: 'Saldo por tanque', subtitle: 'Último saldo registrado de cada día', format: 'liters', zeroBase: false, wide: true, categories: dates.map(shortDay), series },
        { id: 'tank-types', kind: 'bar', signed: true, title: 'Variación por tipo de movimiento', format: 'liters', categories: types.map(t => statusLabel(t[0])), series: [{ name: 'Variación', values: types.map(t => t[1]) }] },
      ],
    };
  },
  incidents(rows) {
    const sev = groupSum(rows, r => String(r.severity), () => 1);
    const sevKeys = [...SEVERITY_ORDER.filter(k => sev.has(k)), ...[...sev.keys()].filter(k => !SEVERITY_ORDER.includes(k))];
    const st = byValueDesc(groupSum(rows, r => String(r.status), () => 1));
    const open = rows.filter(r => !DONE_STATES.includes(String(r.status))).length;
    const serious = rows.filter(r => ['critical', 'high'].includes(String(r.severity))).length;
    return {
      kpis: [kpi('Incidencias', rows.length, 'count', { icon: 'alert-triangle', hero: true }), kpi('Abiertas', open, 'count', { icon: 'alert-circle', tone: open ? 'warn' : 'ok' }), kpi('Graves o críticas', serious, 'count', { icon: 'flag', tone: serious ? 'crit' : 'ok' }), kpi('Cerradas', rows.length - open, 'count', { icon: 'circle-check' })],
      charts: [
        { id: 'inc-sev', kind: 'bar', title: 'Por severidad', format: 'count', categories: sevKeys.map(k => statusLabel(k, { kind: 'severity' })), series: [{ name: 'Incidencias', values: sevKeys.map(k => sev.get(k)) }] },
        { id: 'inc-status', kind: 'bar', title: 'Por estado', format: 'count', categories: st.map(t => statusLabel(t[0])), series: [{ name: 'Incidencias', values: st.map(t => t[1]) }] },
      ],
    };
  },
  purchase_orders(rows) {
    const st = byValueDesc(groupSum(rows, r => String(r.status), () => 1));
    const sup = byValueDesc(groupSum(rows, r => r.supplierName || 'Sin proveedor', () => 1)).slice(0, 8);
    const open = rows.filter(r => !DONE_STATES.includes(String(r.status))).length;
    return {
      kpis: [kpi('Órdenes', rows.length, 'count', { icon: 'cart', hero: true }), kpi('En curso', open, 'count', { icon: 'clock', tone: open ? 'warn' : '' }), kpi('Líneas', sum(rows, 'lineCount'), 'count', { icon: 'list' }), kpi('Proveedores', new Set(rows.map(r => r.supplierName)).size, 'count', { icon: 'store' })],
      charts: [
        { id: 'po-status', kind: 'bar', title: 'Órdenes por estado', format: 'count', categories: st.map(t => statusLabel(t[0])), series: [{ name: 'Órdenes', values: st.map(t => t[1]) }] },
        { id: 'po-supplier', kind: 'hbar', title: 'Órdenes por proveedor', format: 'count', rows: sup.map(([label, value]) => ({ label, value })) },
      ],
    };
  },
  fuel_prices(rows) {
    const sorted = rows.slice().sort((a, b) => String(a.effectiveAt).localeCompare(String(b.effectiveAt)));
    const dates = [...new Set(sorted.map(r => dayOf(r.effectiveAt)))];
    const keys = [...new Set(sorted.map(r => `${r.fuelName}${r.serviceMode ? ` · ${statusLabel(r.serviceMode)}` : ''}`))].slice(0, 6);
    const series = keys.map(key => {
      const at = new Map(sorted.filter(r => `${r.fuelName}${r.serviceMode ? ` · ${statusLabel(r.serviceMode)}` : ''}` === key).map(r => [dayOf(r.effectiveAt), num(r.price)]));
      let carry = null;
      return { name: key, values: dates.map(d => { if (at.has(d)) carry = at.get(d); return carry; }), cls: undefined };
    });
    return {
      kpis: [kpi('Cambios de precio', rows.length, 'count', { icon: 'tag', hero: true }), kpi('Combustibles', new Set(rows.map(r => r.fuelName)).size, 'count', { icon: 'drop' }), kpi('Último cambio', sorted.at(-1) ? dayOf(sorted.at(-1).effectiveAt) : null, 'day', { icon: 'calendar' })],
      charts: [{ id: 'price-step', kind: 'line', step: true, title: 'Precio vigente', subtitle: 'Escalón en cada cambio de vigencia', format: 'price', zeroBase: false, wide: true, categories: dates.map(shortDay), series }],
    };
  },
  expenses(rows, previous) {
    const total = sum(rows, 'amountUsd');
    const cat = byValueDesc(groupSum(rows, r => r.category || 'Sin categoría', r => num(r.amountUsd)));
    const day = sortedEntries(groupSum(rows, r => dayOf(r.incurredOn), r => num(r.amountUsd)));
    return {
      kpis: [kpi('Gasto total', total, 'money', { icon: 'receipt', hero: true, delta: Array.isArray(previous) && previous.length ? pctDelta(total, sum(previous, 'amountUsd')) : null, invertDelta: true }), kpi('Registros', rows.length, 'count', { icon: 'list' }), kpi('Categorías', cat.length, 'count', { icon: 'layers' }), kpi('Categoría mayor', cat[0]?.[0] ?? null, 'text', { icon: 'flag' })],
      charts: [
        dayChart('exp-day', 'Gasto por día', day, { format: 'money', wide: true, seriesName: 'Gasto' }),
        { id: 'exp-cat', kind: 'hbar', title: 'Gasto por categoría', format: 'money', rows: cat.slice(0, 8).map(([label, value]) => ({ label, value })) },
      ],
    };
  },
  cash_closures(rows) {
    const sorted = rows.slice().sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
    const labels = sorted.map((r, i) => `${shortDay(r.createdAt)}${sorted.filter((x, j) => j < i && dayOf(x.createdAt) === dayOf(r.createdAt)).length ? ` #${sorted.filter((x, j) => j <= i && dayOf(x.createdAt) === dayOf(r.createdAt)).length}` : ''}`);
    const withVariance = sorted.filter(r => num(r.varianceCashUsd) !== 0 || num(r.varianceCardUsd) !== 0).length;
    return {
      kpis: [kpi('Cierres', rows.length, 'count', { icon: 'banknote', hero: true }), kpi('Variación de efectivo', sum(rows, 'varianceCashUsd'), 'money', { icon: 'banknote', signed: true }), kpi('Variación de tarjeta', sum(rows, 'varianceCardUsd'), 'money', { icon: 'receipt', signed: true }), kpi('Con diferencia', withVariance, 'count', { icon: 'alert-circle', tone: withVariance ? 'warn' : 'ok' })],
      charts: [
        { id: 'cash-var', kind: 'bar', signed: true, title: 'Variación de efectivo por cierre', subtitle: 'Contado menos esperado', format: 'money', wide: true, categories: labels, series: [{ name: 'Efectivo', values: sorted.map(r => num(r.varianceCashUsd)) }] },
        { id: 'card-var', kind: 'bar', signed: true, title: 'Variación de tarjeta por cierre', format: 'money', wide: true, categories: labels, series: [{ name: 'Tarjeta', values: sorted.map(r => num(r.varianceCardUsd)) }] },
      ],
    };
  },
  store_stock(rows) {
    const top = rows.slice().sort((a, b) => num(b.soldUnits) - num(a.soldUnits)).slice(0, 8);
    return {
      kpis: [kpi('Productos con movimiento', rows.length, 'count', { icon: 'bag', hero: true }), kpi('Unidades vendidas', sum(rows, 'soldUnits'), 'count', { icon: 'cart' }), kpi('Unidades recibidas', sum(rows, 'receivedUnits'), 'count', { icon: 'arrow-down' }), kpi('Variación neta', sum(rows, 'netUnits'), 'count', { icon: 'layers', signed: true })],
      charts: [{ id: 'store-top', kind: 'hbar', title: 'Más vendidos', subtitle: 'Unidades vendidas en el periodo', format: 'count', rows: top.map(r => ({ label: r.productName, value: num(r.soldUnits) })) }],
    };
  },
  maintenance_orders(rows, _p, now) {
    const st = byValueDesc(groupSum(rows, r => String(r.status), () => 1));
    const kind = byValueDesc(groupSum(rows, r => String(r.kind), r => num(r.estimateUsd)));
    const overdue = rows.filter(r => r.dueAt && Date.parse(r.dueAt) < now && !DONE_STATES.includes(String(r.status))).length;
    return {
      kpis: [kpi('Órdenes', rows.length, 'count', { icon: 'wrench', hero: true }), kpi('Costo estimado', sum(rows, 'estimateUsd'), 'money', { icon: 'banknote' }), kpi('Vencidas', overdue, 'count', { icon: 'clock', tone: overdue ? 'crit' : 'ok' }), kpi('Activos atendidos', new Set(rows.map(r => r.assetLabel)).size, 'count', { icon: 'cube' })],
      charts: [
        { id: 'mnt-status', kind: 'bar', title: 'Órdenes por estado', format: 'count', categories: st.map(t => statusLabel(t[0])), series: [{ name: 'Órdenes', values: st.map(t => t[1]) }] },
        { id: 'mnt-kind', kind: 'bar', title: 'Costo estimado por tipo', format: 'money', categories: kind.map(t => statusLabel(t[0])), series: [{ name: 'Estimado', values: kind.map(t => t[1]) }] },
      ],
    };
  },
  staff_shifts(rows) {
    const day = sortedEntries(groupSum(rows, r => dayOf(r.date), r => num(r.plannedHours)));
    const pos = byValueDesc(groupSum(rows, r => r.position || 'Sin puesto', r => num(r.plannedHours)));
    return {
      kpis: [kpi('Turnos', sum(rows, 'shiftCount'), 'count', { icon: 'users', hero: true }), kpi('Horas planeadas', sum(rows, 'plannedHours'), 'hours', { icon: 'clock' }), kpi('Puestos', pos.length, 'count', { icon: 'layers' })],
      charts: [
        dayChart('shift-day', 'Horas por día', day, { format: 'hours', wide: true, seriesName: 'Horas' }),
        { id: 'shift-pos', kind: 'hbar', title: 'Horas por puesto', format: 'hours', rows: pos.slice(0, 8).map(([label, value]) => ({ label, value })) },
      ],
    };
  },
  operational_assets(rows) {
    const ev = byValueDesc(groupSum(rows, r => String(r.eventType), () => 1));
    return {
      kpis: [kpi('Eventos', rows.length, 'count', { icon: 'cube', hero: true }), kpi('Activos', new Set(rows.map(r => r.code)).size, 'count', { icon: 'layers' }), kpi('Ligados a incidencias', rows.filter(r => r.incidentCode).length, 'count', { icon: 'alert-triangle' })],
      charts: [{ id: 'asset-events', kind: 'bar', title: 'Eventos por tipo', format: 'count', categories: ev.map(t => statusLabel(t[0])), series: [{ name: 'Eventos', values: ev.map(t => t[1]) }] }],
    };
  },
};

/* ------------------------------ export jobs ------------------------------ */
export const STALLED_AFTER_MS = 20_000;

// Visual state of an export job (server states: queued, running, succeeded, failed, cancelled).
export function exportView(job, elapsedMs = 0) {
  const state = job?.state || 'queued';
  const percent = Math.max(0, Math.min(100, Number(job?.progress?.percent) || 0));
  const rows = job?.progress ? `${Number(job.progress.completed) || 0} de ${Number(job.progress.total) || 0} filas` : '';
  switch (state) {
    case 'queued': {
      const stalled = elapsedMs >= STALLED_AFTER_MS;
      return { state, label: 'En cola', tone: stalled ? 'warn' : 'info', percent, detail: stalled ? 'Sigue en cola. El servicio de exportación puede estar ocupado; puedes cancelar y reintentar.' : 'Esperando turno de generación.', canCancel: true, canRetry: stalled, canDownload: false, busy: true, stalled };
    }
    case 'running': return { state, label: 'Generando', tone: 'info', percent, detail: rows || 'Preparando archivo.', canCancel: true, canRetry: false, canDownload: false, busy: true, stalled: false };
    case 'succeeded': return { state, label: 'Listo', tone: 'ok', percent: 100, detail: job?.filename || 'Archivo listo para descargar.', canCancel: false, canRetry: false, canDownload: true, busy: false, stalled: false };
    case 'cancelled': return { state, label: 'Cancelada', tone: 'muted', percent, detail: 'La exportación se canceló.', canCancel: false, canRetry: true, canDownload: false, busy: false, stalled: false };
    default: return { state: 'failed', label: 'Falló', tone: 'crit', percent, detail: job?.error || 'No se pudo generar el archivo.', canCancel: false, canRetry: true, canDownload: false, busy: false, stalled: false };
  }
}

/* ------------------------------ table columns ------------------------------ */
export const COLUMN_LABELS = Object.freeze({
  id: 'ID', occurredAt: 'Fecha y hora', dispenserCode: 'Bomba', fuelName: 'Combustible', liters: 'Litros', totalUsd: 'Total', paymentStatus: 'Pago',
  operationalDate: 'Fecha operativa', slot: 'Corte', status: 'Estado', closedAt: 'Cerrado', closedBy: 'Cerrado por', salesUsd: 'Ventas', reviewRequired: 'Revisión', productSummary: 'Productos',
  tankCode: 'Tanque', movementType: 'Movimiento', deltaLiters: 'Variación', balanceLiters: 'Saldo', costQuality: 'Calidad de costo',
  code: 'Código', category: 'Categoría', severity: 'Severidad', description: 'Descripción', orderNumber: 'Orden', createdAt: 'Creada', supplierName: 'Proveedor', lineCount: 'Líneas',
  effectiveAt: 'Vigente desde', serviceMode: 'Modalidad', price: 'Precio', unit: 'Unidad', version: 'Versión', incurredOn: 'Fecha', costCenter: 'Centro de costo', amountUsd: 'Monto', sourceKind: 'Origen',
  reviewStatus: 'Revisión', expectedCashUsd: 'Efectivo esperado', countedCashUsd: 'Efectivo contado', varianceCashUsd: 'Dif. efectivo', expectedCardUsd: 'Tarjeta esperada', settledCardUsd: 'Tarjeta liquidada', varianceCardUsd: 'Dif. tarjeta',
  productName: 'Producto', kind: 'Tipo', movementCount: 'Movimientos', receivedUnits: 'Recibidas', soldUnits: 'Vendidas', netUnits: 'Neto', latestMovementAt: 'Último movimiento',
  assetType: 'Tipo de activo', assetLabel: 'Activo', dueAt: 'Vence', estimateUsd: 'Estimado', date: 'Fecha', position: 'Puesto', shiftCount: 'Turnos', plannedHours: 'Horas planeadas',
  assetName: 'Nombre', eventType: 'Evento', fromStatus: 'Estado previo', toStatus: 'Estado nuevo', fromBranch: 'Sucursal origen', toBranch: 'Sucursal destino', custodian: 'Custodio', incidentCode: 'Incidencia', note: 'Nota',
  groupBy: 'Agrupación', groupValue: 'Grupo', saleCount: 'Ventas (n)',
});

export const columnLabel = key => COLUMN_LABELS[key] || String(key).replace(/([A-Z])/g, ' $1').replace(/^./, c => c.toUpperCase());

// How a column should be rendered: money | liters | price | datetime | date | status | bool | id | count | text.
export function columnKind(key, type = '') {
  if (key === 'id') return 'id';
  if (/Usd$/.test(key)) return 'money';
  if (/Liters$/.test(key) || (key === 'liters')) return 'liters';
  if (key === 'price') return 'price';
  if (['occurredAt', 'createdAt', 'closedAt', 'effectiveAt', 'dueAt', 'latestMovementAt'].includes(key)) return 'datetime';
  if (['operationalDate', 'incurredOn', 'date'].includes(key)) return 'date';
  if (['status', 'severity', 'paymentStatus', 'reviewStatus', 'fromStatus', 'toStatus', 'serviceMode', 'movementType', 'eventType', 'kind', 'category', 'assetType'].includes(key)) return 'status';
  if (key === 'reviewRequired') return 'bool';
  if (['lineCount', 'movementCount', 'receivedUnits', 'soldUnits', 'netUnits', 'shiftCount', 'plannedHours', 'saleCount', 'slot', 'version'].includes(key)) return 'count';
  if (key === 'groupValue' && type === 'fuel_sales') return 'text';
  return 'text';
}