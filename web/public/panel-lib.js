// Pure helpers for the DLC panel (no DOM access at import time, so node tests can load this file).

const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/* ------------------------------------------------------------------ */
/* Countries                                                          */
/* ------------------------------------------------------------------ */
export const DEFAULT_COUNTRY = 'SV';
export const COUNTRY_CHOICES = ['SV', 'GT', 'HN', 'NI', 'CR', 'PA', 'BZ', 'MX', 'CO', 'EC', 'PE', 'CL', 'AR', 'DO', 'US', 'ES'];

export function normalizeCountryCode(value, fallback = DEFAULT_COUNTRY) {
  const code = String(value ?? '').trim().toUpperCase();
  return /^[A-Z]{2}$/.test(code) ? code : fallback;
}

let displayNames;
export function countryName(code, locale = 'es') {
  const normalized = normalizeCountryCode(code, '');
  if (!normalized) return 'Sin país';
  try {
    displayNames ??= new Intl.DisplayNames([locale], { type: 'region' });
    return displayNames.of(normalized) || normalized;
  } catch {
    return normalized;
  }
}

// Text-only label (no flag emoji): "El Salvador (SV)".
export function countryLabel(code) {
  const normalized = normalizeCountryCode(code, '');
  return normalized ? `${countryName(normalized)} (${normalized})` : 'Sin país';
}

export function branchCountry(branch) {
  return normalizeCountryCode(branch?.countryCode);
}

export function sortCountries(rows) {
  return [...rows].sort((a, b) => countryName(a.countryCode).localeCompare(countryName(b.countryCode), 'es'));
}

// Older servers do not return `countries`; derive it from the branch list.
export function deriveCountries(branches) {
  const counts = new Map();
  for (const branch of branches || []) {
    const code = branchCountry(branch);
    counts.set(code, (counts.get(code) || 0) + 1);
  }
  return sortCountries([...counts].map(([countryCode, branchCount]) => ({ countryCode, branchCount })));
}

// Union of the server list (preferred, for counts) and the client list (so the select never shrinks while filtering).
export function resolveCountries(serverCountries, branches) {
  const merged = new Map(deriveCountries(branches).map(row => [row.countryCode, row]));
  if (Array.isArray(serverCountries)) {
    for (const row of serverCountries) {
      const countryCode = normalizeCountryCode(row?.countryCode, '');
      if (!countryCode) continue;
      const branchCount = Number(row.branchCount);
      merged.set(countryCode, { countryCode, branchCount: Number.isFinite(branchCount) ? branchCount : merged.get(countryCode)?.branchCount ?? 0 });
    }
  }
  return sortCountries([...merged.values()]);
}

export function branchesForCountry(branches, countryCode) {
  return countryCode ? (branches || []).filter(branch => branchCountry(branch) === countryCode) : [...(branches || [])];
}

// Changing the country resets a branch selection that no longer belongs to it.
export function reconcileBranchSelection(branchId, countryCode, branches) {
  if (!branchId) return null;
  const branch = (branches || []).find(item => item.id === branchId);
  if (!branch) return null;
  return countryCode && branchCountry(branch) !== countryCode ? null : branchId;
}

export function countrySelectMarkup(countries, selected) {
  return `<option value="">Todos los países</option>${countries.map(row => `<option value="${escapeHtml(row.countryCode)}" ${selected === row.countryCode ? 'selected' : ''}>${escapeHtml(countryName(row.countryCode))} (${escapeHtml(row.countryCode)}${Number.isFinite(Number(row.branchCount)) ? ` · ${Number(row.branchCount)}` : ''})</option>`).join('')}`;
}

export function countryChoiceMarkup(selected, extraCodes = []) {
  const codes = [...new Set([...COUNTRY_CHOICES, ...extraCodes.map(code => normalizeCountryCode(code, '')).filter(Boolean)])];
  const current = normalizeCountryCode(selected);
  if (!codes.includes(current)) codes.push(current);
  return codes.sort((a, b) => countryName(a).localeCompare(countryName(b), 'es')).map(code => `<option value="${code}" ${code === current ? 'selected' : ''}>${escapeHtml(countryName(code))} (${code})</option>`).join('');
}

export function networkQuery({ days = 7, branchId = null, countryCode = null } = {}) {
  const params = new URLSearchParams({ days: String(days) });
  if (branchId) params.set('branchId', branchId);
  if (countryCode) params.set('countryCode', countryCode);
  return params.toString();
}

/* ------------------------------------------------------------------ */
/* Branch lifecycle (draft -> configured -> active)                    */
/* ------------------------------------------------------------------ */
export const BRANCH_STATUS_LABEL = Object.freeze({ draft: 'Borrador', configured: 'Configurada', active: 'Activa', suspended: 'Suspendida', archived: 'Archivada' });
// Pages whose endpoints only accept ACTIVE branches. Setup pages stay reachable in draft/configured for branch managers.
export const SETUP_PAGES = Object.freeze(['equipment', 'prices', 'staff', 'purchases']);
export const BRANCH_FREE_PAGES = Object.freeze(['branches', 'users']);

export function branchStatusLabel(status) {
  return BRANCH_STATUS_LABEL[String(status ?? '').toLowerCase()] || (status ? String(status).replaceAll('_', ' ') : 'Sin estado');
}

export const isBranchActive = branch => branch?.status === 'active';
export const activeBranches = branches => (branches || []).filter(isBranchActive);

// Prefer the requested branch when it is active; otherwise the first active one (optionally within a country). Never returns a non-active branch.
export function pickDefaultBranch(branches, { preferredId = null, countryCode = null } = {}) {
  const pool = activeBranches(branches);
  const preferred = preferredId ? pool.find(branch => branch.id === preferredId) : null;
  if (preferred) return preferred.id;
  const scoped = branchesForCountry(pool, countryCode);
  return (scoped[0] || null)?.id ?? null;
}

const fold = text => String(text ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

// The server answers 404 "Sucursal (activa) fuera de tu ámbito/red." when a branch is not active (or not in scope).
export function isBranchScopeError(error) {
  return Number(error?.status) === 404 && /sucursal.*fuera de tu (ambito|red)/.test(fold(error?.message));
}

// Decides whether a page may call its branch-scoped endpoints for the selected branch.
export function branchPageGate({ page, branch, canManage = false }) {
  if (!branch || isBranchActive(branch) || BRANCH_FREE_PAGES.includes(page)) return { blocked: false };
  if (canManage && SETUP_PAGES.includes(page)) return { blocked: false, setup: true };
  return { blocked: true, status: branch.status };
}

export function branchNotReadyMessage(status) {
  switch (String(status ?? '').toLowerCase()) {
    case 'draft': return 'Esta sucursal está en preparación (borrador). Completa la preparación operativa y actívala para ver su operación.';
    case 'configured': return 'Esta sucursal ya está configurada, pero aún no está activa. Actívala para ver su operación.';
    case 'suspended': return 'Esta sucursal está suspendida; su operación no está disponible.';
    case 'archived': return 'Esta sucursal está archivada; su operación no está disponible.';
    default: return 'Esta sucursal todavía no está disponible para consultar su operación. Puede estar en preparación o fuera de tu alcance.';
  }
}

const statusPill = status => {
  const key = String(status ?? '').toLowerCase();
  const tone = key === 'draft' || key === 'configured' ? 'warn' : key === 'suspended' || key === 'archived' ? 'critical' : 'unknown';
  const icon = tone === 'warn' ? '▲' : tone === 'critical' ? '✖' : '?';
  return `<span class="pill ${tone}"><span class="pill-icon" aria-hidden="true">${icon}</span>${escapeHtml(branchStatusLabel(status))}</span>`;
};

// In-context state shown instead of the raw error card when the selected branch is not operating yet.
export function branchNotReadyMarkup({ branch = null, canManage = false } = {}) {
  const status = branch?.status;
  const preparing = status === 'draft' || status === 'configured';
  const action = preparing && canManage && branch?.id
    ? `<button class="primary" data-open-onboarding="${escapeHtml(branch.id)}">Completar preparación</button>`
    : '';
  const hint = preparing && !canManage ? '<p class="branch-meta">Un Gerente General debe completar la preparación operativa y activarla.</p>' : '';
  return `<div class="card empty branch-not-ready" role="status"><h2>${branch?.name ? escapeHtml(branch.name) : 'Sucursal'}${branch ? ` ${statusPill(status)}` : ''}</h2><p>${escapeHtml(branchNotReadyMessage(status))}</p>${hint}${action}</div>`;
}

// Network dashboard / module landing when no branch is active in scope.
export function noActiveBranchesMarkup({ canRead = false, canManage = false } = {}) {
  const action = canRead ? `<button class="primary" data-go="branches">${canManage ? 'Preparar una sucursal' : 'Abrir sucursales'}</button>` : '';
  return `<div class="card empty no-active-branches" role="status"><h2>Aún no hay sucursales activas</h2><p>El resumen de la red aparece cuando al menos una sucursal está activa. Las sucursales nuevas inician como borrador: completa su preparación operativa y actívalas.</p>${canRead ? '' : '<p class="branch-meta">Tu cuenta no puede consultar el listado de sucursales.</p>'}${action}</div>`;
}

// Genuine failures: friendly message first, technical metadata collapsed.
export function errorCardMarkup(error) {
  const meta = [];
  if (error?.code) meta.push(['Código', error.code]);
  if (error?.status) meta.push(['HTTP', error.status]);
  if (error?.correlationId) meta.push(['Ref.', error.correlationId]);
  const details = meta.length ? `<details class="chart-details error-details"><summary>Detalles técnicos</summary><p class="branch-meta">${meta.map(([label, value]) => `${escapeHtml(label)} ${escapeHtml(value)}`).join(' · ')}</p></details>` : '';
  return `<div class="card empty"><b>No se pudo cargar la información</b><p>${escapeHtml(error?.message || 'Error de operación')}</p>${details}<button class="secondary" id="retry">Reintentar</button></div>`;
}

/* ------------------------------------------------------------------ */
/* Tank levels                                                         */
/* ------------------------------------------------------------------ */
export const TANK_THRESHOLDS = Object.freeze({ critical: 30, medium: 60 });
export const FUEL_FAMILY_LABEL = Object.freeze({ super: 'Súper', regular: 'Regular', diesel: 'Diésel' });
const FUEL_ORDER = ['super', 'regular', 'diesel'];

// critical <= 30 %, medium <= 60 %, optimal > 60 %. Each state carries a text label and an icon so colour is never the only signal.
export function tankLevel(percentage) {
  const value = percentage === null || percentage === undefined || percentage === '' ? NaN : Number(percentage);
  if (!Number.isFinite(value)) return { key: 'unknown', label: 'Sin medición', icon: '?', tone: 'unknown' };
  if (value <= TANK_THRESHOLDS.critical) return { key: 'critical', label: 'Crítico', icon: '✖', tone: 'critical' };
  if (value <= TANK_THRESHOLDS.medium) return { key: 'medium', label: 'Medio', icon: '▲', tone: 'warn' };
  return { key: 'optimal', label: 'Óptimo', icon: '✓', tone: '' };
}

export function aggregateTanksByFuel(branches) {
  const groups = new Map();
  for (const branch of branches || []) {
    for (const tank of branch.tanks || []) {
      const rawFamily = String(tank.family || '').toLowerCase();
      const family = FUEL_ORDER.includes(rawFamily) ? rawFamily : `other:${tank.fuelName || 'Combustible'}`;
      const group = groups.get(family) || { family: FUEL_ORDER.includes(rawFamily) ? rawFamily : 'other', name: FUEL_FAMILY_LABEL[rawFamily] || tank.fuelName || 'Combustible', onHand: 0, capacity: 0, measured: 0, total: 0, branchIds: new Set(), minimum: null };
      group.total += 1;
      group.branchIds.add(branch.id || branch.name);
      const onHand = tank.onHandLiters === null || tank.onHandLiters === undefined ? NaN : Number(tank.onHandLiters);
      const capacity = Number(tank.capacityLiters);
      if (Number.isFinite(onHand) && Number.isFinite(capacity) && capacity > 0) {
        group.onHand += onHand;
        group.capacity += capacity;
        group.measured += 1;
        const own = (onHand / capacity) * 100;
        group.minimum = group.minimum === null ? own : Math.min(group.minimum, own);
      }
      groups.set(family, group);
    }
  }
  return [...groups.values()]
    .map(group => ({ family: group.family, name: group.name, onHand: group.onHand, capacity: group.capacity, measuredTanks: group.measured, totalTanks: group.total, branchCount: group.branchIds.size, minimumPercent: group.minimum, percentage: group.capacity > 0 ? (group.onHand / group.capacity) * 100 : null }))
    .sort((a, b) => {
      const ia = FUEL_ORDER.indexOf(a.family), ib = FUEL_ORDER.indexOf(b.family);
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.name.localeCompare(b.name, 'es');
    });
}

const numberFormat = (value, digits = 0) => new Intl.NumberFormat('es-SV', { maximumFractionDigits: digits }).format(value);

export function tankLevelsMarkup(rows) {
  if (!rows.length) return '<div class="empty">No hay tanques configurados en el alcance seleccionado.</div>';
  const legend = `<ul class="chart-legend" aria-label="Umbrales de nivel"><li><span aria-hidden="true">✖</span> Crítico: 30 % o menos</li><li><span aria-hidden="true">▲</span> Medio: hasta 60 %</li><li><span aria-hidden="true">✓</span> Óptimo: más de 60 %</li></ul>`;
  const items = rows.map(row => {
    const level = tankLevel(row.percentage);
    const pct = row.percentage === null ? null : Math.max(0, Math.min(100, row.percentage));
    const pctText = pct === null ? 'sin medición' : `${numberFormat(pct, 1)} %`;
    const description = `${row.name}: nivel ${level.label.toLowerCase()}, ${pctText}${row.capacity > 0 ? `, ${numberFormat(row.onHand)} de ${numberFormat(row.capacity)} litros` : ''}`;
    const family = FUEL_ORDER.includes(row.family) ? row.family : 'other';
    return `<li class="tank-level"><div class="tank-level-head"><b><span class="fuel-dot fuel-dot--${family}" aria-hidden="true"></span>${escapeHtml(row.name)}</b><span class="pill ${level.tone}"><span class="pill-icon" aria-hidden="true">${level.icon}</span>${escapeHtml(level.label)} · ${escapeHtml(pctText)}</span></div>`
      + `<svg class="tank-level-svg" role="img" aria-label="${escapeHtml(description)}" width="100%" height="16"><rect class="tank-track" width="100%" height="16" rx="4"/>${pct === null ? '' : `<rect class="tank-fill tank-fill--${level.key}" width="${pct.toFixed(2)}%" height="16" rx="4"/>`}<line class="tank-threshold" x1="30%" x2="30%" y1="0" y2="16"/><line class="tank-threshold" x1="60%" x2="60%" y1="0" y2="16"/></svg>`
      + `<div class="tank-level-meta">${row.capacity > 0 ? `${numberFormat(row.onHand)} L de ${numberFormat(row.capacity)} L` : 'Sin litros medidos'} · ${row.branchCount} sucursal(es)${row.minimumPercent === null ? '' : ` · tanque más bajo ${numberFormat(row.minimumPercent, 1)} %`}${row.measuredTanks < row.totalTanks ? ` · ${row.totalTanks - row.measuredTanks} tanque(s) sin medición` : ''}</div></li>`;
  }).join('');
  return `<ul class="tank-levels">${items}</ul><div class="chart-figure">${legend}</div>`;
}

/* ------------------------------------------------------------------ */
/* Sales trend chart (inline SVG, themed through CSS classes)         */
/* ------------------------------------------------------------------ */
function niceCeiling(value) {
  if (!(value > 0)) return 1;
  const magnitude = 10 ** Math.floor(Math.log10(value));
  const normalized = value / magnitude;
  const step = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10;
  return step * magnitude;
}

export function compactMoney(value) {
  const n = Number(value) || 0;
  if (Math.abs(n) >= 1_000_000) return `$${numberFormat(n / 1_000_000, 1)} M`;
  if (Math.abs(n) >= 1_000) return `$${numberFormat(n / 1_000, 1)} k`;
  return `$${numberFormat(n, 0)}`;
}

export function salesTrendSvg(daily, { money, number, dayLabel }) {
  const points = (daily || []).map(item => ({ value: Number(item.salesUsd) || 0, liters: Number(item.soldLiters) || 0, cuts: Number(item.closedCuts) || 0, label: dayLabel(item) }));
  if (!points.length) return '';
  const width = 640, height = 230, left = 54, right = 14, top = 18, bottom = 34;
  const plotW = width - left - right, plotH = height - top - bottom;
  const peak = Math.max(...points.map(p => p.value));
  const ceiling = niceCeiling(peak);
  const band = plotW / points.length;
  const x = index => left + band * index + band / 2;
  const y = value => top + plotH - (value / ceiling) * plotH;
  const total = points.reduce((sum, p) => sum + p.value, 0);
  const peakPoint = points.reduce((best, p) => (p.value > best.value ? p : best), points[0]);
  const grid = [0, 0.25, 0.5, 0.75, 1].map(f => `<line class="chart-grid" x1="${left}" x2="${width - right}" y1="${y(ceiling * f).toFixed(1)}" y2="${y(ceiling * f).toFixed(1)}"/><text x="${left - 8}" y="${(y(ceiling * f) + 3).toFixed(1)}" text-anchor="end">${escapeHtml(compactMoney(ceiling * f))}</text>`).join('');
  const every = Math.max(1, Math.ceil(points.length / 8));
  const labels = points.map((p, i) => (i % every === 0 || i === points.length - 1) ? `<text x="${x(i).toFixed(1)}" y="${height - 12}" text-anchor="middle">${escapeHtml(p.label)}</text>` : '').join('');
  const barW = Math.max(4, Math.min(34, band * 0.55));
  const bars = points.map((p, i) => `<rect class="chart-bar" x="${(x(i) - barW / 2).toFixed(1)}" y="${y(p.value).toFixed(1)}" width="${barW.toFixed(1)}" height="${Math.max(1, top + plotH - y(p.value)).toFixed(1)}" rx="3"/>`).join('');
  const line = points.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)} ${y(p.value).toFixed(1)}`).join(' ');
  const area = `${line} L${x(points.length - 1).toFixed(1)} ${top + plotH} L${x(0).toFixed(1)} ${top + plotH} Z`;
  const dots = points.map((p, i) => `<circle class="chart-dot" cx="${x(i).toFixed(1)}" cy="${y(p.value).toFixed(1)}" r="${points.length > 16 ? 2.5 : 4}"><title>${escapeHtml(`${p.label}: ${money(p.value)} · ${number(p.liters)} L · ${p.cuts} corte(s)`)}</title></circle>`).join('');
  const peakLabel = peak > 0 ? `<text class="chart-peak" x="${Math.min(width - right - 4, Math.max(left + 4, x(points.indexOf(peakPoint)))).toFixed(1)}" y="${(y(peakPoint.value) - 9).toFixed(1)}" text-anchor="middle">${escapeHtml(compactMoney(peakPoint.value))}</text>` : '';
  const summary = `Tendencia diaria de ventas: ${points.length} día(s), total ${money(total)}, máximo ${money(peakPoint.value)} el ${peakPoint.label}. Los valores exactos están en la tabla siguiente.`;
  return `<figure class="chart-figure"><svg class="chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeHtml(summary)}" preserveAspectRatio="xMidYMid meet">${grid}<line class="chart-axis" x1="${left}" x2="${width - right}" y1="${top + plotH}" y2="${top + plotH}"/>${bars}<path class="chart-area" d="${area}"/><path class="chart-line" pathLength="1" d="${line}"/>${dots}${peakLabel}${labels}</svg>`
    + `<figcaption><ul class="chart-legend"><li><span class="chart-swatch chart-swatch--line" aria-hidden="true"></span>Venta estimada diaria (línea y puntos)</li><li><span class="chart-swatch chart-swatch--bar" aria-hidden="true"></span>Barras: mismo valor como volumen visual</li></ul></figcaption></figure>`;
}

/* ------------------------------------------------------------------ */
/* Real-time form validation                                           */
/* ------------------------------------------------------------------ */
const fill = (template, element) => String(template).replaceAll('{min}', element.min ?? '').replaceAll('{max}', element.max ?? '').replaceAll('{minlength}', element.minLength ?? '').replaceAll('{maxlength}', element.maxLength ?? '');
const override = (element, key) => element?.dataset?.[`msg${key}`];

function decimalsOf(step) {
  const text = String(step ?? '');
  if (!text || text === 'any') return null;
  const [, fraction = ''] = text.split('.');
  return fraction.length;
}

// Returns a Spanish message for the first failing constraint, or '' when the field is valid.
export function describeValidity(element) {
  const validity = element?.validity;
  const value = String(element?.value ?? '');
  const isChoice = element?.tagName === 'SELECT' || element?.type === 'select-one';
  if (validity && !validity.valid) {
    if (validity.valueMissing) return override(element, 'Required') || (isChoice ? 'Selecciona una opción.' : element.type === 'checkbox' ? 'Debes aceptar esta casilla para continuar.' : 'Este campo es obligatorio.');
    if (validity.typeMismatch) return override(element, 'Type') || (element.type === 'email' ? 'Ingresa un correo válido, por ejemplo nombre@dominio.com.' : 'El formato no es válido.');
    if (validity.badInput) return override(element, 'Bad') || 'Ingresa un número o fecha válidos.';
    if (validity.tooShort) return fill(override(element, 'Length') || 'Escribe al menos {minlength} caracteres (llevas ' + value.length + ').', element);
    if (validity.tooLong) return fill(override(element, 'Length') || 'No puede superar {maxlength} caracteres.', element);
    if (validity.rangeUnderflow) {
      const min = Number(element.min);
      if (override(element, 'Min')) return fill(override(element, 'Min'), element);
      return min > 0 && min <= 0.01 ? 'La cantidad debe ser mayor que cero.' : min === 0 ? 'No puede ser negativo.' : fill('Debe ser mayor o igual a {min}.', element);
    }
    if (validity.rangeOverflow) return fill(override(element, 'Max') || 'Debe ser menor o igual a {max}.', element);
    if (validity.stepMismatch) {
      const decimals = decimalsOf(element.step);
      return override(element, 'Step') || (decimals === 0 ? 'Ingresa un número entero.' : decimals ? `Usa como máximo ${decimals} decimales.` : 'El valor no es válido para este campo.');
    }
    if (validity.patternMismatch) return override(element, 'Pattern') || element.title || 'El formato no es válido.';
    return 'El valor no es válido.';
  }
  const textLike = ['text', 'search', 'email', 'tel', 'url', 'password', 'textarea'].includes(element?.type);
  if (textLike && value.length) {
    const trimmed = value.trim();
    if (!trimmed.length && (element.required || element.minLength > 0)) return override(element, 'Required') || 'Escribe un valor; no puede contener solo espacios.';
    if (element.minLength > 0 && trimmed.length < element.minLength) return fill(override(element, 'Length') || 'Escribe al menos {minlength} caracteres sin contar espacios sobrantes (llevas ' + trimmed.length + ').', element);
  }
  if (element?.dataset?.positive !== undefined && value !== '' && !(Number(value) > 0)) return override(element, 'Min') || 'La cantidad debe ser mayor que cero.';
  return '';
}

function comparable(value, type) {
  if (value === '' || value === null || value === undefined) return null;
  if (['date', 'datetime-local', 'time', 'month'].includes(type)) {
    const parsed = Date.parse(type === 'time' ? `1970-01-01T${value}` : value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

// Cross-field rules: data-gte / data-gt / data-lte / data-lt reference another field by name in the same form.
export function crossFieldMessage(element, form) {
  const rules = [['gte', (a, b) => a >= b, 'mayor o igual que'], ['gt', (a, b) => a > b, 'posterior o mayor que'], ['lte', (a, b) => a <= b, 'menor o igual que'], ['lt', (a, b) => a < b, 'menor que']];
  for (const [key, ok, wording] of rules) {
    const otherName = element?.dataset?.[key];
    if (!otherName) continue;
    const other = form?.elements?.[otherName];
    if (!other) continue;
    const a = comparable(element.value, element.type), b = comparable(other.value, other.type || element.type);
    if (a === null || b === null) continue;
    if (!ok(a, b)) return override(element, 'Cross') || `Debe ser ${wording} «${element.dataset.crossLabel || otherName}».`;
  }
  return '';
}

export function fieldMessage(element, form) {
  return describeValidity(element) || crossFieldMessage(element, form);
}
