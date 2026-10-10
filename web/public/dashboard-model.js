// Pure data model for the Resumen module: which requests to run for a scope, how to merge their results,
// which alerts to derive and which numbers feed the KPI cards. No DOM access: covered by node tests.
import { branchCountry, deriveCountries, networkQuery, normalizeCountryCode } from './panel-lib.js';
import { currencyForCountry, toNumber } from './format.js';
import { branchesInScope, reconcileSelection } from './scopebar.js';

export const CRITICAL_PERCENT = 30;
export const MEDIUM_PERCENT = 60;

// One request per branch when branches are picked, otherwise one per country (or one for the whole single-country network).
export function sliceRequests({ branches = [], countryCode = null, branchIds = [], days = 7 } = {}) {
  const picked = reconcileSelection(branchIds, branches, countryCode);
  if (picked.length) {
    return picked.map(id => {
      const branch = branches.find(b => b.id === id);
      const country = branchCountry(branch || {});
      return { key: `b:${id}`, query: networkQuery({ days, branchId: id, countryCode: null }), countryCode: country, currency: currencyForCountry(country) };
    });
  }
  if (countryCode) return [{ key: `c:${countryCode}`, query: networkQuery({ days, countryCode }), countryCode, currency: currencyForCountry(countryCode) }];
  const countries = deriveCountries(branches);
  if (countries.length > 1) return countries.map(c => ({ key: `c:${c.countryCode}`, query: networkQuery({ days, countryCode: c.countryCode }), countryCode: c.countryCode, currency: currencyForCountry(c.countryCode) }));
  const only = countries[0]?.countryCode || null;
  return [{ key: 'all', query: networkQuery({ days }), countryCode: only, currency: currencyForCountry(only) }];
}

const sum = (rows, pick) => rows.reduce((total, row) => total + (toNumber(pick(row)) || 0), 0);

export function tankPercent(tank) {
  const direct = toNumber(tank?.minimumPercent ?? tank?.percentage);
  if (Number.isFinite(direct)) return direct;
  const onHand = toNumber(tank?.onHandLiters); const capacity = toNumber(tank?.capacityLiters);
  return Number.isFinite(onHand) && Number.isFinite(capacity) && capacity > 0 ? (onHand / capacity) * 100 : NaN;
}

// Merges the per-slice network payloads. Sales stay grouped by currency: different currencies are never added.
export function mergeNetwork(results) {
  const branchById = new Map();
  const seriesByCurrency = new Map();
  let closed = 0; let expected = 0; let lastSourceAt = null; let periodDays = 0;
  const permissions = { sales: false, inventory: false };
  let sawPermissions = false;
  for (const { slice, data } of results) {
    if (!data) continue;
    for (const row of data.branches || []) {
      const country = normalizeCountryCode(row.countryCode || slice.countryCode, '') || slice.countryCode || '';
      const currency = currencyForCountry(country, slice.currency);
      branchById.set(row.id || row.name, { ...row, countryCode: country, currency, sales: sum(row.products || [], p => p.salesUsd), liters: sum(row.products || [], p => p.soldLiters) });
    }
    const bucket = seriesByCurrency.get(slice.currency) || new Map();
    for (const day of data.dailySeries || []) {
      const key = String(day.date).slice(0, 10);
      const cur = bucket.get(key) || { date: key, salesUsd: 0, soldLiters: 0, closedCuts: 0 };
      cur.salesUsd += toNumber(day.salesUsd) || 0; cur.soldLiters += toNumber(day.soldLiters) || 0; cur.closedCuts += toNumber(day.closedCuts) || 0;
      bucket.set(key, cur);
    }
    seriesByCurrency.set(slice.currency, bucket);
    closed += toNumber(data.cutCoverage?.closed) || 0; expected += toNumber(data.cutCoverage?.expected) || 0;
    if (data.lastSourceAt && (!lastSourceAt || data.lastSourceAt > lastSourceAt)) lastSourceAt = data.lastSourceAt;
    periodDays = Math.max(periodDays, Number(data.periodDays) || 0);
    if (data.permissions) { sawPermissions = true; permissions.sales ||= data.permissions.sales !== false; permissions.inventory ||= data.permissions.inventory !== false; }
  }
  if (!sawPermissions) { permissions.sales = true; permissions.inventory = true; }
  const series = [...seriesByCurrency].map(([currency, map]) => ({ currency, daily: [...map.values()].sort((a, b) => a.date.localeCompare(b.date)) })).filter(s => s.daily.length);
  const branches = [...branchById.values()];
  const salesByCurrency = [...branches.reduce((acc, b) => acc.set(b.currency, (acc.get(b.currency) || 0) + b.sales), new Map())].map(([currency, total]) => ({ currency, total })).sort((a, b) => b.total - a.total);
  // The daily series is the closed-cut total of the period, so it is the preferred source for the headline number.
  const seriesTotals = series.map(s => ({ currency: s.currency, total: s.daily.reduce((t, d) => t + d.salesUsd, 0) })).sort((a, b) => b.total - a.total);
  return { branches, series, cutCoverage: { closed, expected }, lastSourceAt, periodDays, permissions, salesByCurrency: seriesTotals.length ? seriesTotals : salesByCurrency, seriesTotals };
}

// Alerts sorted by severity (critical first), then by how low the level is.
export function deriveAlerts(branches, { days = 7 } = {}) {
  const alerts = [];
  for (const branch of branches || []) {
    for (const tank of branch.tanks || []) {
      const pct = tankPercent(tank);
      if (!Number.isFinite(pct)) continue;
      if (pct <= CRITICAL_PERCENT) alerts.push({ severity: 'crit', rank: pct, title: `${branch.name}: ${tank.fuelName || 'Combustible'} al ${Math.round(pct)} %`, detail: 'Nivel crítico (30 % o menos). Programa una compra o revisa la medición.', page: 'inventory', branchId: branch.id });
      else if (pct <= MEDIUM_PERCENT) alerts.push({ severity: 'warn', rank: 100 + pct, title: `${branch.name}: ${tank.fuelName || 'Combustible'} al ${Math.round(pct)} %`, detail: 'Nivel medio (hasta 60 %). Conviene planear el reabastecimiento.', page: 'inventory', branchId: branch.id });
    }
    const expected = Number(branch.expectedCuts) || 0; const closed = Number(branch.closedCuts) || 0;
    if (days === 1 && expected > 0 && closed < expected) alerts.push({ severity: 'warn', rank: 300 + closed, title: `${branch.name}: ${closed} de ${expected} cortes cerrados`, detail: 'Quedan cortes del día sin cerrar.', page: 'cuts', branchId: branch.id });
  }
  return alerts.sort((a, b) => (a.severity === b.severity ? a.rank - b.rank : a.severity === 'crit' ? -1 : 1));
}

export function summarizeNetwork(merged, { days = 7 } = {}) {
  const branches = merged.branches;
  const critical = branches.filter(b => (b.tanks || []).some(t => tankPercent(t) <= CRITICAL_PERCENT)).length;
  const warn = branches.filter(b => !(b.tanks || []).some(t => tankPercent(t) <= CRITICAL_PERCENT) && (b.tanks || []).some(t => tankPercent(t) <= MEDIUM_PERCENT)).length;
  const liters = branches.reduce((t, b) => t + b.liters, 0);
  const { closed, expected } = merged.cutCoverage;
  return {
    branchCount: branches.length, critical, warn, liters,
    coveragePercent: expected > 0 ? Math.round((closed / expected) * 100) : null, closed, expected,
    sales: merged.salesByCurrency, alerts: deriveAlerts(branches, { days }),
  };
}

// Aggregates sold litres and sales per fuel family across branches (sales stay per currency).
export function fuelBreakdown(branches) {
  const map = new Map();
  for (const branch of branches) {
    for (const item of branch.products || []) {
      const key = item.fuelProductId || item.fuelName;
      const cur = map.get(key) || { name: item.fuelName || 'Combustible', family: item.family || 'other', liters: 0, sales: new Map() };
      cur.liters += toNumber(item.soldLiters) || 0;
      cur.sales.set(branch.currency, (cur.sales.get(branch.currency) || 0) + (toNumber(item.salesUsd) || 0));
      map.set(key, cur);
    }
  }
  return [...map.values()].sort((a, b) => b.liters - a.liters);
}

// Branch-manager view: null totals must read "Sin dato", never 0.
export function summarizeBranch(d) {
  const inventory = d?.inventory || {}; const tanks = inventory.tanks || []; const cuts = d?.cuts || [];
  const measuredTanks = tanks.filter(t => t.percentage !== null && t.percentage !== undefined && Number.isFinite(Number(t.percentage)));
  const average = measuredTanks.length ? Math.round(measuredTanks.reduce((s, t) => s + Number(t.percentage), 0) / measuredTanks.length) : null;
  const totalLiters = inventory.totalLiters === null || inventory.totalLiters === undefined ? null : Number(inventory.totalLiters);
  return {
    tanks, measuredCount: measuredTanks.length, averagePercent: average, totalLiters,
    cutsClosed: cuts.filter(c => c.status === 'closed').length, cutsTotal: cuts.length || 2,
    openIncidents: d?.openIncidents?.length ?? 0, openMaintenance: d?.openMaintenanceOrders ?? 0,
    alerts: (d?.alerts || []).map(a => ({ severity: 'warn', title: a.title, detail: a.detail, page: 'inventory' })),
    note: average === null ? 'Sin mediciones de nivel' : `${average} % promedio de ${measuredTanks.length} tanques medidos`,
  };
}

export const scopeBranches = (branches, countryCode, branchIds) => branchesInScope(branches, countryCode, branchIds);
