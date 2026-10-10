// Formatting helpers: money (branch currency, never mixed), volume (litres/gallons), percentages and dates.
// Every function accepts explicit options so it is testable; defaults come from the user's preferences.
import { getPrefs } from './prefs.js';

export const LITERS_PER_GALLON = 3.785411784;

// Currency of a branch comes from its country. Unknown countries fall back to USD (the platform default).
export const CURRENCY_BY_COUNTRY = Object.freeze({
  SV: 'USD', GT: 'GTQ', HN: 'HNL', NI: 'NIO', CR: 'CRC', PA: 'USD', MX: 'MXN', US: 'USD', CO: 'COP',
  BZ: 'BZD', EC: 'USD', PE: 'PEN', CL: 'CLP', AR: 'ARS', DO: 'DOP', ES: 'EUR',
});

export function currencyForCountry(countryCode, fallback = 'USD') {
  const code = String(countryCode ?? '').trim().toUpperCase();
  return CURRENCY_BY_COUNTRY[code] || fallback;
}

const isBlank = value => value === null || value === undefined || value === '';
export const toNumber = value => (isBlank(value) ? NaN : Number(value));

const formatters = new Map();
function grouped(min, max) {
  const key = `${min}:${max}`;
  let f = formatters.get(key);
  if (!f) { f = new Intl.NumberFormat('en-US', { minimumFractionDigits: min, maximumFractionDigits: max, useGrouping: true }); formatters.set(key, f); }
  return f;
}

const clampDigits = (value, fallback) => {
  const n = Number(value);
  return Number.isInteger(n) && n >= 0 && n <= 6 ? n : fallback;
};

export const NO_DATA = '—';

// 1234.5 -> "1,234.50" (fixed decimals, thousands separator).
export function formatNumber(value, { decimals = getPrefs().decimals, fixed = true } = {}) {
  const n = toNumber(value);
  if (!Number.isFinite(n)) return NO_DATA;
  const d = clampDigits(decimals, 2);
  return grouped(fixed ? d : 0, d).format(Object.is(n, -0) ? 0 : n);
}

// Money: always two decimals unless the user chose otherwise (0-4); code of the branch currency, e.g. "USD 1,234.50".
export function formatMoney(value, { currency = 'USD', decimals = getPrefs().decimals, withCode = true } = {}) {
  const n = toNumber(value);
  if (!Number.isFinite(n)) return NO_DATA;
  const text = formatNumber(n, { decimals });
  return withCode ? `${currency} ${text}` : text;
}

export function moneyParts(value, { currency = 'USD', decimals = getPrefs().decimals } = {}) {
  return { code: currency, amount: formatMoney(value, { currency, decimals, withCode: false }) };
}

export function formatCompactMoney(value, { currency = 'USD' } = {}) {
  const n = toNumber(value);
  if (!Number.isFinite(n)) return NO_DATA;
  const abs = Math.abs(n);
  const body = abs >= 1_000_000 ? `${grouped(0, 1).format(n / 1_000_000)} M` : abs >= 1_000 ? `${grouped(0, 1).format(n / 1_000)} k` : grouped(0, 0).format(n);
  return `${currency} ${body}`;
}

// A price per unit keeps its native unit; the converted equivalent is a secondary line. Prices never show 6+ decimals.
export function formatPrice(value, { currency = 'USD', decimals = getPrefs().decimals } = {}) {
  return formatMoney(value, { currency, decimals });
}

export function convertPriceUnit(price, fromUnit, toUnit) {
  const n = toNumber(price);
  if (!Number.isFinite(n) || fromUnit === toUnit) return n;
  return toUnit === 'liter' ? n / LITERS_PER_GALLON : n * LITERS_PER_GALLON;
}

export const isGallonUnit = unit => ['us_gallon', 'gallon_us', 'gallon', 'gallons'].includes(String(unit ?? '').toLowerCase());
export const normalizePriceUnit = unit => (isGallonUnit(unit) ? 'gallon' : 'liter');
export const priceUnitName = unit => (isGallonUnit(unit) ? 'galón' : 'litro');

export const litersToGallons = liters => toNumber(liters) / LITERS_PER_GALLON;
export const gallonsToLiters = gallons => toNumber(gallons) * LITERS_PER_GALLON;

export function volumeUnitSymbol(unit = getPrefs().volumeUnit) { return unit === 'gallons' ? 'gal' : 'L'; }
export function volumeUnitName(unit = getPrefs().volumeUnit) { return unit === 'gallons' ? 'galones' : 'litros'; }

// Converts a litre quantity to the user's volume unit.
export function volumeValue(liters, { unit = getPrefs().volumeUnit } = {}) {
  const n = toNumber(liters);
  if (!Number.isFinite(n)) return NaN;
  return unit === 'gallons' ? n / LITERS_PER_GALLON : n;
}

// Cards show whole units; detail views show two decimals. Input is always litres (API canonical unit).
export function formatVolume(liters, { unit = getPrefs().volumeUnit, detail = false, withUnit = true } = {}) {
  const v = volumeValue(liters, { unit });
  if (!Number.isFinite(v)) return NO_DATA;
  const text = formatNumber(v, { decimals: detail ? 2 : 0 });
  return withUnit ? `${text} ${volumeUnitSymbol(unit)}` : text;
}

export function formatPercent(value, { decimals = 0 } = {}) {
  const n = toNumber(value);
  return Number.isFinite(n) ? `${formatNumber(n, { decimals })} %` : NO_DATA;
}

// Groups amounts by currency; different currencies are never added together.
export function subtotalsByCurrency(rows, amountOf, currencyOf) {
  const totals = new Map();
  for (const row of rows || []) {
    const n = toNumber(amountOf(row));
    if (!Number.isFinite(n)) continue;
    const code = currencyOf(row) || 'USD';
    totals.set(code, (totals.get(code) || 0) + n);
  }
  return [...totals].map(([currency, total]) => ({ currency, total })).sort((a, b) => b.total - a.total);
}

export function formatSubtotals(subtotals, opts) {
  if (!subtotals.length) return NO_DATA;
  return subtotals.map(item => formatMoney(item.total, { ...opts, currency: item.currency })).join(' · ');
}

/* ---- dates: always rendered in the branch time zone when known ---- */
export function formatDateTime(value, { timeZone, withSeconds = false } = {}) {
  if (isBlank(value)) return NO_DATA;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return NO_DATA;
  const options = { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false, ...(withSeconds ? { second: '2-digit' } : {}) };
  try { return new Intl.DateTimeFormat('es', { ...options, ...(timeZone ? { timeZone } : {}) }).format(date); }
  catch { return new Intl.DateTimeFormat('es', options).format(date); }
}

export function formatTime(value, { timeZone } = {}) {
  if (isBlank(value)) return NO_DATA;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return NO_DATA;
  try { return new Intl.DateTimeFormat('es', { hour: '2-digit', minute: '2-digit', hour12: false, ...(timeZone ? { timeZone } : {}) }).format(date); }
  catch { return new Intl.DateTimeFormat('es', { hour: '2-digit', minute: '2-digit', hour12: false }).format(date); }
}

export function formatDay(value, { timeZone } = {}) {
  if (isBlank(value)) return NO_DATA;
  const day = String(value).slice(0, 10);
  const date = /^\d{4}-\d{2}-\d{2}$/.test(day) ? new Date(`${day}T12:00:00Z`) : new Date(value);
  if (Number.isNaN(date.getTime())) return NO_DATA;
  try { return new Intl.DateTimeFormat('es', { day: '2-digit', month: 'short', timeZone: /^\d{4}-\d{2}-\d{2}$/.test(day) ? 'UTC' : timeZone }).format(date); }
  catch { return day; }
}

// "Datos de las 14:32" for the stale-data banner.
export function formatClock(ms, { timeZone } = {}) { return formatTime(new Date(ms).toISOString(), { timeZone }); }
