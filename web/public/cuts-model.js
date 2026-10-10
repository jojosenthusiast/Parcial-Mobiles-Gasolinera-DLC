// Pure model for the guided cut workflow (Cortes): step definitions, pump x fuel grid, live reading validation,
// tank level alerts and movement filtering. The cut windows always come from the API (startsAt/endsAt).
import { fuelFamilyOf } from './reports-model.js';

export const CUT_STEPS = Object.freeze([
  { id: 'select', label: 'Seleccionar corte', short: 'Corte' },
  { id: 'readings', label: 'Lecturas por bomba', short: 'Lecturas' },
  { id: 'receipts', label: 'Recepciones', short: 'Recepciones' },
  { id: 'losses', label: 'Pérdidas', short: 'Pérdidas' },
  { id: 'summary', label: 'Resumen y cierre', short: 'Cierre' },
]);

export const LOSS_CATEGORIES = Object.freeze([
  { id: 'evaporation', label: 'Evaporación' },
  { id: 'spill', label: 'Derrame' },
  { id: 'measurement_error', label: 'Error de medición' },
  { id: 'shortage', label: 'Faltante' },
  { id: 'other', label: 'Otro' },
]);

const num = v => (v === null || v === undefined || v === '' ? NaN : Number(v));

// Live validation of one accumulated meter reading. initial = last recorded meter value (continuity base).
export function validateReading({ initial, value, max = 9_999_999_999 }) {
  const raw = String(value ?? '').trim();
  if (raw === '') return { state: 'empty', ok: false, message: '', sold: null };
  const v = num(raw);
  const base = num(initial);
  if (!Number.isFinite(v)) return { state: 'error', ok: false, message: 'Escribe un número válido.', sold: null };
  if (v < 0) return { state: 'error', ok: false, message: 'La lectura no puede ser negativa.', sold: null };
  if (Number.isFinite(base) && v < base) return { state: 'error', ok: false, message: `La lectura final (${v}) es menor que la inicial (${base}).`, sold: null };
  if (v > max) return { state: 'error', ok: false, message: 'La lectura es demasiado grande.', sold: null };
  const sold = Number.isFinite(base) ? Math.round((v - base) * 1000) / 1000 : null;
  return { state: 'ok', ok: true, message: '', sold };
}

// Continuity: the initial reading of this cut must equal the closing reading of the previous one.
export function checkContinuity({ initial, previousFinal }) {
  const a = num(initial); const b = num(previousFinal);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return { state: 'unknown' };
  return Math.abs(a - b) < 0.0005 ? { state: 'ok' } : { state: 'gap', difference: Math.round((a - b) * 1000) / 1000 };
}

// Rows = pumps, columns = fuels. A cell holds the nozzle (or null when a pump does not dispense that fuel).
export function buildGrid(nozzles = [], dispensers = []) {
  const fuelMap = new Map();
  for (const n of nozzles) if (!fuelMap.has(n.fuelProductId)) fuelMap.set(n.fuelProductId, { id: n.fuelProductId, name: n.fuelName || 'Combustible', family: fuelFamilyOf(n.fuelName) });
  const fuels = [...fuelMap.values()].sort((a, b) => ['super', 'regular', 'diesel', 'other'].indexOf(a.family) - ['super', 'regular', 'diesel', 'other'].indexOf(b.family));
  const ids = [...new Set(nozzles.map(n => n.dispenserId))];
  const rows = ids.map(id => {
    const d = dispensers.find(x => x.id === id);
    return { dispenserId: id, name: d?.name || d?.code || 'Bomba', code: d?.code || '', cells: fuels.map(f => nozzles.find(n => n.dispenserId === id && n.fuelProductId === f.id) || null) };
  }).sort((a, b) => String(a.code || a.name).localeCompare(String(b.code || b.name), 'es', { numeric: true }));
  return { fuels, rows };
}

export function readingProgress(nozzles = []) {
  const expected = nozzles.filter(n => n.participation === 'expected');
  const captured = expected.filter(n => n.cutReadingId);
  return { expected: expected.length, captured: captured.length, pending: expected.filter(n => !n.cutReadingId), complete: expected.length > 0 && captured.length === expected.length };
}

export function tankLevel(tank) {
  const cap = num(tank.capacityLiters);
  const liters = Number.isFinite(num(tank.measuredLiters)) ? num(tank.measuredLiters) : num(tank.onHandLiters);
  const percent = Number.isFinite(liters) && cap > 0 ? Math.max(0, Math.min(100, (liters / cap) * 100)) : NaN;
  const tone = !Number.isFinite(percent) ? 'muted' : percent <= 30 ? 'crit' : percent <= 60 ? 'warn' : 'ok';
  return { percent, liters, tone, measured: Number.isFinite(num(tank.measuredLiters)) };
}

export function replenishmentAlerts(tanks = []) {
  return tanks.map(t => ({ tank: t, ...tankLevel(t) })).filter(x => x.tone === 'crit' || x.tone === 'warn').sort((a, b) => a.percent - b.percent);
}

export function movementsInWindow(rows = [], cut, types) {
  const start = Date.parse(cut?.startsAt); const end = Date.parse(cut?.endsAt);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return [];
  return rows.filter(r => types.includes(String(r.movementType)) && Date.parse(r.occurredAt) >= start && Date.parse(r.occurredAt) <= end);
}

export function sumLiters(rows, key = 'deltaL') { return rows.reduce((a, r) => a + Math.abs(Number(r[key]) || 0), 0); }

// Step state machine. Returns { steps:[{...step, status, checkpoint}], canAdvance(stepId) }.
export function stepStates({ cut = null, readings = { expected: 0, captured: 0 }, tanksTotal = 0, tanksMeasured = 0, receipts = 0, losses = 0, current = 'select' }) {
  const open = cut?.status === 'open';
  const cutReady = Boolean(cut) && cut.status !== 'scheduled';
  const readingsDone = readings.expected > 0 && readings.captured === readings.expected;
  const order = CUT_STEPS.map(s => s.id);
  const gate = {
    select: cut ? (cutReady ? { ok: true } : { ok: false, reason: 'Abre el corte para capturar lecturas.' }) : { ok: false, reason: 'Selecciona un corte.' },
    readings: !open && cutReady ? { ok: true } : readingsDone && (tanksTotal === 0 || tanksMeasured === tanksTotal) ? { ok: true } : { ok: false, reason: readingsDone ? 'Falta medir los tanques.' : `Faltan ${Math.max(0, readings.expected - readings.captured)} lecturas por bomba.` },
    receipts: { ok: true },
    losses: { ok: true },
    summary: { ok: true },
  };
  const checkpoints = {
    select: cut ? { done: cutReady, text: cutReady ? 'Corte abierto' : 'Pendiente de abrir' } : { done: false, text: 'Sin selección' },
    readings: { done: readingsDone, text: `${readings.captured} de ${readings.expected} lecturas` },
    receipts: { done: true, text: receipts ? `${receipts} recepciones` : 'Sin recepciones' },
    losses: { done: true, text: losses ? `${losses} pérdidas` : 'Sin pérdidas' },
    summary: { done: cut?.status === 'closed', text: cut?.status === 'closed' ? 'Cerrado' : 'Pendiente' },
  };
  const idx = order.indexOf(current);
  const steps = CUT_STEPS.map((s, i) => ({ ...s, index: i + 1, status: i === idx ? 'current' : (checkpoints[s.id].done && i < idx ? 'done' : i < idx ? 'visited' : 'todo'), checkpoint: checkpoints[s.id], gate: gate[s.id] }));
  const reachable = id => {
    const target = order.indexOf(id);
    for (let i = 0; i < target; i++) if (!gate[order[i]].ok) return { ok: false, reason: gate[order[i]].reason, blockedAt: order[i] };
    return { ok: true };
  };
  return { steps, reachable };
}

export const CUT_STATUS_ORDER = ['scheduled', 'open', 'inReview', 'prepared', 'closed'];
