// Code helpers: suggest the next identifier from the last saved one and validate format + uniqueness live.

export const CODE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
export const CODE_MAX = 24;

const SPLIT = /^(.*?)(\d+)$/;

// "QA-GT-01" -> "QA-GT-02"; "SV9" -> "SV10"; "QA-GT-99" -> "QA-GT-100"; "ABC" -> "ABC-01"; "" -> "".
export function nextCode(lastCode, { width } = {}) {
  const code = String(lastCode ?? '').trim();
  if (!code) return '';
  const match = SPLIT.exec(code);
  if (!match) return `${code}-01`;
  const [, stem, digits] = match;
  const next = String(Number(digits) + 1).padStart(width ?? digits.length, '0');
  return `${stem}${next}`;
}

// Picks the stem of the last code in the list (callers pass codes ordered by creation), then returns that family's highest number + 1.
// With `prefix`, only codes starting with it are considered (e.g. the country: "QA-GT-").
export function suggestNextCode(codes, { prefix = '', fallback = '' } = {}) {
  const wanted = String(prefix ?? '').toUpperCase();
  const candidates = (codes || [])
    .map(code => String(code ?? '').trim())
    .filter(code => code && code.toUpperCase().startsWith(wanted) && SPLIT.test(code));
  if (!candidates.length) return fallback;
  const lastStem = SPLIT.exec(candidates[candidates.length - 1])[1];
  let best = null;
  for (const code of candidates) {
    const [, stem, digits] = SPLIT.exec(code);
    if (stem.toUpperCase() !== lastStem.toUpperCase()) continue;
    if (!best || Number(digits) >= Number(best.digits)) best = { code, digits };
  }
  return nextCode(best.code);
}

export function validateCode(value, { existing = [], current = '', max = CODE_MAX } = {}) {
  const code = String(value ?? '').trim();
  if (!code) return { ok: false, message: 'Escribe un código.' };
  if (code.length > max) return { ok: false, message: `Usa máximo ${max} caracteres.` };
  if (!CODE_PATTERN.test(code)) return { ok: false, message: 'Usa letras, números, guion o guion bajo, empezando con letra o número.' };
  const taken = (existing || []).some(item => String(item ?? '').trim().toUpperCase() === code.toUpperCase() && code.toUpperCase() !== String(current ?? '').trim().toUpperCase());
  if (taken) return { ok: false, message: 'Ese código ya existe. Elige otro.' };
  return { ok: true, message: 'Código disponible.' };
}

export const CODE_HINT = 'Letras, números y guiones, por ejemplo QA-GT-01. El número sube de uno en uno.';
