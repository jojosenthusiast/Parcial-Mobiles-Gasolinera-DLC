// Central Spanish labels, tones and icons for every status-like value coming from the API. Unknown values fall back gracefully.
import { icon } from './icons.js';

const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));

// tone: ok | warn | crit | info | muted
const S = (label, tone, ic) => Object.freeze({ label, tone, icon: ic });

export const STATUS = Object.freeze({
  // branch lifecycle
  active: S('Activa', 'ok', 'circle-check'),
  configured: S('Configurada', 'info', 'check'),
  draft: S('Borrador', 'muted', 'pencil'),
  suspended: S('Suspendida', 'warn', 'alert-triangle'),
  archived: S('Archivada', 'muted', 'layers'),
  // physical assets
  maintenance: S('En mantenimiento', 'warn', 'wrench'),
  offline: S('Fuera de servicio', 'crit', 'circle-x'),
  inactive: S('Inactivo', 'muted', 'minus'),
  // approvals and workflow
  pending: S('Pendiente', 'warn', 'clock'),
  pending_approval: S('Pendiente de aprobación', 'warn', 'clock'),
  approved: S('Aprobada', 'ok', 'check-seal'),
  rejected: S('Rechazada', 'crit', 'xmark'),
  scheduled: S('Programada', 'info', 'calendar'),
  applied: S('Aplicada', 'ok', 'circle-check'),
  cancelled: S('Cancelada', 'muted', 'xmark'),
  canceled: S('Cancelada', 'muted', 'xmark'),
  expired: S('Vencida', 'warn', 'clock'),
  confirmed: S('Confirmado', 'ok', 'circle-check'),
  deferred: S('Pospuesto', 'muted', 'clock'),
  reviewed: S('Revisado', 'ok', 'circle-check'),
  listo: S('Listo', 'ok', 'circle-check'),
  // cuts, incidents, orders
  open: S('Abierto', 'info', 'clock'),
  opened: S('Abierto', 'info', 'clock'),
  closed: S('Cerrado', 'ok', 'circle-check'),
  in_review: S('En revisión', 'warn', 'eye'),
  in_progress: S('En curso', 'info', 'clock'),
  prepared: S('Preparado', 'info', 'check'),
  reported: S('Reportada', 'warn', 'flag'),
  assessed: S('Evaluada', 'info', 'eye'),
  resolved: S('Resuelta', 'ok', 'circle-check'),
  completed: S('Completada', 'ok', 'circle-check'),
  done: S('Hecho', 'ok', 'circle-check'),
  received: S('Recibida', 'ok', 'circle-check'),
  partial: S('Parcial', 'warn', 'alert-circle'),
  overdue: S('Vencido', 'crit', 'alert-triangle'),
  blocked: S('Bloqueado', 'crit', 'lock'),
  // inventory levels (kept in sync with TANK_THRESHOLDS: crit <= 30, medium <= 60)
  critical: S('Crítico', 'crit', 'alert-triangle'),
  warning: S('Atención', 'warn', 'alert-circle'),
  attention: S('Atención', 'warn', 'alert-circle'),
  medium: S('Medio', 'warn', 'alert-circle'),
  optimal: S('Óptimo', 'ok', 'circle-check'),
  ok: S('Operativo', 'ok', 'circle-check'),
  normal: S('Normal', 'ok', 'circle-check'),
  operational: S('Operativo', 'ok', 'circle-check'),
  unknown: S('Sin medición', 'muted', 'info'),
  configuración_lista: S('Configuración lista', 'ok', 'circle-check'),
  revisar_configuración: S('Revisar configuración', 'warn', 'alert-circle'),
  lista_para_activar: S('Lista para activar', 'ok', 'circle-check'),
  preparación_pendiente: S('Preparación pendiente', 'warn', 'clock'),
  // price market direction
  increase: S('Subirá', 'warn', 'trend-up'),
  decrease: S('Bajará', 'ok', 'trend-down'),
  unchanged: S('Sin cambio', 'muted', 'minus'),
  // block types
  technical: S('Técnico', 'info', 'wrench'),
  safety: S('Seguridad', 'crit', 'alert-triangle'),
  inventory: S('Inventario', 'info', 'drop'),
  // severities
  high: S('Alta', 'crit', 'alert-triangle'),
  low: S('Baja', 'info', 'info'),
  urgent: S('Urgente', 'crit', 'alert-triangle'),
});

// Severity words differ from tank-level words ("medium" is "Media" for an incident, "Medio" for a tank).
export const SEVERITY = Object.freeze({
  critical: S('Crítica', 'crit', 'alert-triangle'),
  high: S('Alta', 'crit', 'alert-triangle'),
  medium: S('Media', 'warn', 'alert-circle'),
  low: S('Baja', 'info', 'info'),
});

export const SERVICE_MODE = Object.freeze({ full_service: 'Servicio completo', self_service: 'Autoservicio' });
export const ZONE = Object.freeze({ occidental: 'Occidental', central: 'Central', oriental: 'Oriental', other: 'Otra' });
export const UNIT = Object.freeze({ us_gallon: 'galón', gallon_us: 'galón', gallon: 'galón', liter: 'litro', litre: 'litro' });
export const FUEL_FAMILY = Object.freeze({ super: 'Súper', regular: 'Regular', diesel: 'Diésel', other: 'Otro' });
export const ASSET_KIND = Object.freeze({ dispenser: 'Bomba', tank: 'Tanque', nozzle: 'Manguera' });

const key = value => String(value ?? '').trim().toLowerCase().replace(/[\s-]+/g, '_');

export function humanize(value) {
  const text = String(value ?? '').replace(/[_-]+/g, ' ').trim();
  return text ? text.charAt(0).toUpperCase() + text.slice(1) : 'Sin dato';
}

// Accepts raw API values plus a few already-Spanish phrases the legacy panel passes in ("sin medición", "Óptimo").
const FOLDED = new Map(Object.entries({
  'sin medicion': 'unknown', 'sin dato': 'unknown', 'sin medición': 'unknown', 'optimo': 'optimal', 'crítico': 'critical', 'critico': 'critical',
  'atencion': 'warning', 'atención': 'warning', 'operativo': 'ok', 'pendiente': 'pending', 'activa': 'active', 'activo': 'active',
}));

export function statusMeta(value, { kind = '' } = {}) {
  const raw = String(value ?? '');
  const plain = raw.trim().toLowerCase();
  const k = key(raw);
  const table = kind === 'severity' ? SEVERITY : STATUS;
  const hit = table[k] || STATUS[FOLDED.get(plain) || ''] || STATUS[k];
  if (hit) return hit;
  if (!raw.trim()) return S('Sin dato', 'muted', 'info');
  return S(humanize(raw), 'muted', 'info');
}

export function statusLabel(value, opts) { return statusMeta(value, opts).label; }

// <span class="pill pill--ok">[icon] Activa</span>: icon + text + tone, never colour alone.
export function statusBadge(value, { kind = '', label = '', size = 14 } = {}) {
  const meta = statusMeta(value, { kind });
  return `<span class="pill pill--${meta.tone}">${icon(meta.icon, { size, cls: 'pill-icon' })}${escapeHtml(label || meta.label)}</span>`;
}

export const modeLabel = value => SERVICE_MODE[key(value)] || humanize(value);
export const zoneLabel = value => ZONE[key(value)] || humanize(value);
export const unitLabel = value => UNIT[key(value)] || humanize(value);
export const fuelFamilyLabel = value => FUEL_FAMILY[key(value)] || humanize(value);
export const assetKindLabel = value => ASSET_KIND[key(value)] || humanize(value);

export function toneForPercent(percentage, { critical = 30, medium = 60 } = {}) {
  const value = percentage === null || percentage === undefined || percentage === '' ? NaN : Number(percentage);
  if (!Number.isFinite(value)) return 'muted';
  return value <= critical ? 'crit' : value <= medium ? 'warn' : 'ok';
}
