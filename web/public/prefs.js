// User preferences (theme, volume unit, decimals, density). Stored per user in localStorage, always inside try/catch.
// The theme itself is applied by theme.js (blocking script in <head>, no flash); this module only mirrors the choice.

export const DEFAULT_PREFS = Object.freeze({ theme: 'system', volumeUnit: 'liters', decimals: 2, density: 'comfortable' });
export const THEMES = Object.freeze(['light', 'dark', 'system']);
export const VOLUME_UNITS = Object.freeze(['liters', 'gallons']);
export const DENSITIES = Object.freeze(['comfortable', 'compact']);
export const MIN_DECIMALS = 0;
export const MAX_DECIMALS = 4;

export function clampDecimals(value, fallback = DEFAULT_PREFS.decimals) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(MAX_DECIMALS, Math.max(MIN_DECIMALS, Math.round(n)));
}

export function normalizePrefs(raw = {}) {
  const input = raw && typeof raw === 'object' ? raw : {};
  return {
    theme: THEMES.includes(input.theme) ? input.theme : DEFAULT_PREFS.theme,
    volumeUnit: VOLUME_UNITS.includes(input.volumeUnit) ? input.volumeUnit : DEFAULT_PREFS.volumeUnit,
    decimals: clampDecimals(input.decimals),
    density: DENSITIES.includes(input.density) ? input.density : DEFAULT_PREFS.density,
  };
}

const storageKey = userId => `dlc.prefs.${userId || 'anonymous'}`;
const safeStorage = () => { try { return globalThis.localStorage || null; } catch { return null; } };

export function readPrefs(userId, storage = safeStorage()) {
  try { return normalizePrefs(JSON.parse(storage?.getItem(storageKey(userId)) || '{}')); } catch { return normalizePrefs({}); }
}

export function writePrefs(userId, prefs, storage = safeStorage()) {
  try { storage?.setItem(storageKey(userId), JSON.stringify(normalizePrefs(prefs))); return true; } catch { return false; }
}

let current = normalizePrefs({});
let currentUser = '';
const listeners = new Set();

export const getPrefs = () => current;

function applyToDocument(prefs, doc = globalThis.document) {
  const root = doc?.documentElement;
  if (!root) return;
  root.setAttribute('data-density', prefs.density);
  try { globalThis.dlcTheme?.set?.(prefs.theme); } catch { /* theme.js owns persistence; ignore */ }
}

// Called after login with the user id so each person keeps their own settings on a shared computer.
export function loadPrefs(userId, { storage = safeStorage(), doc } = {}) {
  currentUser = userId || '';
  const saved = readPrefs(currentUser, storage);
  // The theme chosen before login (theme.js) wins when this user has never stored a preference of their own.
  const fromTheme = (() => { try { return globalThis.dlcTheme?.get?.(); } catch { return null; } })();
  const hasOwn = (() => { try { return Boolean(storage?.getItem(storageKey(currentUser))); } catch { return false; } })();
  current = hasOwn || !fromTheme ? saved : { ...saved, theme: THEMES.includes(fromTheme) ? fromTheme : saved.theme };
  applyToDocument(current, doc);
  for (const fn of listeners) fn(current);
  return current;
}

export function setPrefs(patch, { storage = safeStorage(), doc } = {}) {
  current = normalizePrefs({ ...current, ...patch });
  writePrefs(currentUser, current, storage);
  applyToDocument(current, doc);
  for (const fn of listeners) fn(current);
  return current;
}

export function onPrefsChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }

/* ---- Scope (country + selected branches), remembered per user ---- */
const scopeKey = userId => `dlc.scope.${userId || 'anonymous'}`;

export function normalizeScope(raw = {}) {
  const input = raw && typeof raw === 'object' ? raw : {};
  const country = typeof input.countryCode === 'string' && /^[A-Za-z]{2}$/.test(input.countryCode) ? input.countryCode.toUpperCase() : null;
  const ids = Array.isArray(input.branchIds) ? [...new Set(input.branchIds.filter(id => typeof id === 'string' && id))] : [];
  return { countryCode: country, branchIds: ids };
}

export function readScope(userId, storage = safeStorage()) {
  try { return normalizeScope(JSON.parse(storage?.getItem(scopeKey(userId)) || '{}')); } catch { return normalizeScope({}); }
}

export function writeScope(userId, scope, storage = safeStorage()) {
  try { storage?.setItem(scopeKey(userId), JSON.stringify(normalizeScope(scope))); return true; } catch { return false; }
}
