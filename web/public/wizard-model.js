// Pure model of the branch creation wizard: steps, live validation, server payloads and resume logic.
// The server stores each onboarding step as free-form JSON (identity has a fixed schema), so everything the API cannot model
// natively (manager, store plans, fuel mix) is kept in the `review` step under `wizard` as a server-side checkpoint.
import { CODE_HINT, suggestNextCode, validateCode } from './codes.js';

export const STEPS = Object.freeze([
  { id: 'basic', title: 'Datos básicos', why: 'El nombre, el código y el país identifican la sucursal en todos los reportes. La zona horaria define a qué hora cierran sus cortes.' },
  { id: 'infra', title: 'Infraestructura', why: 'Con cuántas bombas y qué combustibles maneja la sucursal, el sistema sabe qué cortes, tanques y precios esperar. Si tienes dudas, déjalo como está y ajústalo en “Bombas y tanques”.' },
  { id: 'staff', title: 'Personal', why: 'Alguien debe administrar la estación para activarla. Puedes completar esto después: el borrador se conserva.' },
  { id: 'store', title: 'Tienda', why: 'Solo si la estación vende productos de tienda se preparan categorías y caja. Si no, sigue adelante.' },
  { id: 'review', title: 'Revisión y activación', why: 'El servidor revisa que la sucursal esté lista. Lo que falte aparece aquí con un enlace para resolverlo.' },
]);

export const ZONES = Object.freeze([['occidental', 'Occidental'], ['central', 'Central'], ['oriental', 'Oriental'], ['other', 'Otra']]);
export const FUEL_FAMILIES = Object.freeze([{ id: 'super', label: 'Súper' }, { id: 'regular', label: 'Regular' }, { id: 'diesel', label: 'Diésel' }]);

export const TIMEZONE_BY_COUNTRY = Object.freeze({
  SV: 'America/El_Salvador', GT: 'America/Guatemala', HN: 'America/Tegucigalpa', NI: 'America/Managua', CR: 'America/Costa_Rica', PA: 'America/Panama',
  MX: 'America/Mexico_City', US: 'America/New_York', CO: 'America/Bogota', BZ: 'America/Belize', EC: 'America/Guayaquil', PE: 'America/Lima',
  CL: 'America/Santiago', AR: 'America/Argentina/Buenos_Aires', DO: 'America/Santo_Domingo', ES: 'Europe/Madrid',
});
export const timezoneFor = country => TIMEZONE_BY_COUNTRY[String(country || '').toUpperCase()] || 'America/El_Salvador';

export const DEFAULT_VALUES = Object.freeze({
  code: '', name: '', countryCode: 'SV', zone: 'central', timezone: 'America/El_Salvador',
  dispenserCount: 6, fuelCount: 3, fuels: ['super', 'regular', 'diesel'], tanksPerFuel: 1,
  staffMode: 'later', managerName: '', managerEmail: '',
  hasStore: false, registers: 1, categories: '',
});

export const progressText = index => `Paso ${index + 1} de ${STEPS.length}`;
export const progressPercent = index => Math.round(((index + 1) / STEPS.length) * 100);

export function defaultFuels(count) {
  const n = Math.max(1, Math.min(3, Number(count) || 3));
  return n === 1 ? ['regular'] : n === 2 ? ['super', 'regular'] : ['super', 'regular', 'diesel'];
}

const isInt = (value, min, max) => { const n = Number(value); return value !== '' && value !== null && value !== undefined && Number.isInteger(n) && n >= min && n <= max; };
const validZone = tz => { try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return true; } catch { return false; } };

// Returns { ok, errors: { field: message } } for one step.
export function validateStep(stepId, values, { existingCodes = [], currentCode = '' } = {}) {
  const errors = {};
  if (stepId === 'basic') {
    if (!String(values.name || '').trim()) errors.name = 'Escribe el nombre de la sucursal.';
    else if (String(values.name).trim().length > 120) errors.name = 'Usa máximo 120 caracteres.';
    const code = validateCode(values.code, { existing: existingCodes, current: currentCode });
    if (!code.ok) errors.code = code.message;
    if (!/^[A-Za-z]{2}$/.test(String(values.countryCode || ''))) errors.countryCode = 'Elige el país.';
    if (!ZONES.some(([id]) => id === values.zone)) errors.zone = 'Elige una zona.';
    if (!String(values.timezone || '').trim() || !validZone(String(values.timezone).trim())) errors.timezone = 'Usa un identificador válido, por ejemplo America/El_Salvador.';
  } else if (stepId === 'infra') {
    if (!isInt(values.dispenserCount, 1, 200)) errors.dispenserCount = 'Indica de 1 a 200 bombas.';
    if (!isInt(values.fuelCount, 1, 3)) errors.fuelCount = 'Elige 1, 2 o 3 tipos de combustible.';
    const fuels = Array.isArray(values.fuels) ? values.fuels : [];
    if (isInt(values.fuelCount, 1, 3) && fuels.length !== Number(values.fuelCount)) errors.fuels = `Marca exactamente ${values.fuelCount} ${Number(values.fuelCount) === 1 ? 'combustible' : 'combustibles'}.`;
    if (!isInt(values.tanksPerFuel, 1, 6)) errors.tanksPerFuel = 'Indica de 1 a 6 tanques por combustible.';
  } else if (stepId === 'staff') {
    if (values.staffMode === 'now') {
      if (String(values.managerName || '').trim().length < 3) errors.managerName = 'Escribe el nombre completo de quien administra.';
      if (String(values.managerEmail || '').trim() && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(values.managerEmail).trim())) errors.managerEmail = 'Escribe un correo válido o déjalo vacío.';
    }
  } else if (stepId === 'store') {
    if (values.hasStore && !isInt(values.registers, 1, 10)) errors.registers = 'Indica de 1 a 10 cajas.';
  }
  return { ok: Object.keys(errors).length === 0, errors };
}

export const categoryList = text => [...new Set(String(text || '').split(/[,\n]/).map(s => s.trim()).filter(Boolean))].slice(0, 20);

/* ---- payloads for PATCH /branches/:id/onboarding ---- */
export const identityPayload = v => ({ code: String(v.code).trim().toUpperCase(), name: String(v.name).trim().replace(/\s+/g, ' '), zone: v.zone, timezone: String(v.timezone).trim(), countryCode: String(v.countryCode).trim().toUpperCase() });
export const createDraftPayload = v => ({ ...identityPayload(v), profile: 'operational', expectedDispenserCount: Number(v.dispenserCount) || 6 });
export const infraPayloads = v => ({
  dispensers: { expectedDispenserCount: Number(v.dispenserCount), source: 'wizard' },
  products: { families: [...v.fuels], source: 'wizard' },
  tanks: { perFuel: Number(v.tanksPerFuel), families: [...v.fuels], source: 'wizard' },
});
// Server rule: confirmed needs at least one real employee, so the wizard only ever defers (the manager is kept in the checkpoint).
export const staffPayload = (activeEmployees = 0) => ({ status: Number(activeEmployees) >= 1 ? 'confirmed' : 'deferred', employeeCount: Math.max(0, Number(activeEmployees) || 0) });
// completed = number of finished steps (1 after the basic data was saved).
export function wizardCheckpoint(v, completed, now = new Date().toISOString()) {
  return { wizard: { completed, savedAt: now, infra: { dispenserCount: Number(v.dispenserCount), fuelCount: Number(v.fuelCount), fuels: [...v.fuels], tanksPerFuel: Number(v.tanksPerFuel) }, staff: { mode: v.staffMode, managerName: String(v.managerName || '').trim(), managerEmail: String(v.managerEmail || '').trim() }, store: { hasStore: Boolean(v.hasStore), registers: Boolean(v.hasStore) ? Number(v.registers) : 0, categories: Boolean(v.hasStore) ? categoryList(v.categories) : [] } } };
}

// Rebuilds form values from a saved branch (identity + wizard checkpoint) and decides where to resume (0-based step index).
export function restoreFromBranch(branch) {
  const data = branch?.onboardingData || {};
  const identity = data.identity || {};
  const wiz = data.review?.wizard || null;
  const values = { ...DEFAULT_VALUES, ...{ code: branch?.code || identity.code || '', name: branch?.name || identity.name || '', countryCode: branch?.countryCode || identity.countryCode || 'SV', zone: branch?.zone || identity.zone || 'central', timezone: branch?.timezone || identity.timezone || 'America/El_Salvador' } };
  if (typeof data.expectedDispenserCount === 'number') values.dispenserCount = data.expectedDispenserCount;
  if (wiz?.infra) Object.assign(values, { dispenserCount: wiz.infra.dispenserCount ?? values.dispenserCount, fuelCount: wiz.infra.fuelCount ?? values.fuelCount, fuels: wiz.infra.fuels?.length ? wiz.infra.fuels : defaultFuels(wiz.infra.fuelCount), tanksPerFuel: wiz.infra.tanksPerFuel ?? 1 });
  if (wiz?.staff) Object.assign(values, { staffMode: wiz.staff.mode || 'later', managerName: wiz.staff.managerName || '', managerEmail: wiz.staff.managerEmail || '' });
  if (wiz?.store) Object.assign(values, { hasStore: Boolean(wiz.store.hasStore), registers: wiz.store.registers || 1, categories: (wiz.store.categories || []).join(', ') });
  const completed = Number.isInteger(wiz?.completed) ? wiz.completed : 1; // a draft that only has its identity has finished step 1
  return { values, step: Math.min(STEPS.length - 1, Math.max(0, completed)), completed, savedAt: wiz?.savedAt || null };
}

/* ---- readiness items: server blocker codes -> human text + where to fix ---- */
const FIX = {
  PROFILE_MISSING: { label: 'Falta el perfil operativo', page: 'equipment' },
  FUEL_OFFER_MISSING: { label: 'Falta asignar combustibles a la sucursal', page: 'equipment' },
  TANK_MISSING: { label: 'Falta registrar al menos un tanque', page: 'equipment' },
  DISPENSER_COUNT_MISMATCH: { label: 'El número de bombas no coincide con lo esperado', page: 'equipment' },
  NOZZLE_WITHOUT_TANK: { label: 'Hay mangueras sin tanque conectado', page: 'equipment' },
  DISPENSER_WITHOUT_NOZZLE: { label: 'Hay bombas sin mangueras', page: 'equipment' },
  ACTIVE_EMPLOYEE_MISSING: { label: 'Falta registrar al menos una persona activa', page: 'staff' },
  STAFF_REVIEW_PENDING: { label: 'Falta confirmar el personal de la sucursal', page: 'branches' },
  OPENING_BALANCE_MISSING: { label: 'Faltan los saldos iniciales de los tanques', page: 'inventory' },
  PRICE_NOT_EFFECTIVE: { label: 'Falta un precio aprobado y vigente por combustible', page: 'prices' },
  NOZZLE_NOT_READY: { label: 'Hay mangueras que aún no están listas', page: 'equipment' },
};
export function readinessItems(blockers) {
  return (blockers || []).map(b => ({ code: b.code, label: FIX[b.code]?.label || b.message || b.code, detail: b.message || '', page: FIX[b.code]?.page || 'branches' }));
}

// Next suggested branch code from the codes already saved; prefers the family of the chosen country (QA-GT-01 -> QA-GT-02).
export function suggestCodeFor(codes, countryCode) {
  const country = String(countryCode || '').toUpperCase();
  const list = (codes || []).filter(Boolean);
  const family = country ? list.filter(code => new RegExp(`(^|[-_])${country}([-_]|\\d|$)`, 'i').test(code)) : [];
  return suggestNextCode(family.length ? family : list, { fallback: country ? `${country}-01` : '' }) || (country ? `${country}-01` : '');
}

export { CODE_HINT };
