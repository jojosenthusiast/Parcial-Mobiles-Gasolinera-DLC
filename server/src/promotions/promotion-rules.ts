export type PromotionKind = 'unit_discount' | 'percent_discount' | 'cashback' | 'points_multiplier' | 'announcement';
export type PromotionRecurrence =
  | { kind: 'once' }
  | { kind: 'weekly'; weekdays: number[] }
  | { kind: 'monthly'; dayOfMonth: number };

export interface PromotionTargetMetric {
  metric: 'sales_usd_30d' | 'fuel_liters_30d';
  threshold: string;
  windowDays?: 30;
  asOf?: string;
  includedBranches?: Array<{ branchId: string; observedValue: string }>;
}

export interface PromotionDefinition {
  title: string;
  motive: string;
  kind: PromotionKind;
  scope: 'network' | 'branch';
  branchId?: string;
  targetBranchIds?: string[];
  targetZones?: Array<'occidental' | 'central' | 'oriental' | 'other'>;
  targetMetric?: PromotionTargetMetric;
  startsAt: string;
  endsAt: string;
  timeZone: string;
  recurrence: PromotionRecurrence;
  productIds?: string[];
  serviceModes?: Array<'full_service' | 'self_service'>;
  value?: string;
  valueUnit?: 'liter' | 'us_gallon';
  bankCode?: string;
  minimumSpendUsd?: string;
  benefitCapUsd?: string;
  totalBudgetUsd?: string;
  maxUsesPerCustomer?: number;
  priority: number;
  stacking: 'none' | 'with_points';
  terms: { applies: string[]; excludes: string[] };
  imageUrl?: string;
  imageAlt?: string;
}

export function normalizePromotionBoundary(value: string, timeZone: string, boundary: 'start' | 'end'): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year!, month! - 1, day!));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month! - 1 || date.getUTCDate() !== day) throw new Error('La fecha local no existe en el calendario.');
  const localDate = boundary === 'end' ? new Date(Date.UTC(year!, month! - 1, day! + 1)) : date;
  const desired = { year: localDate.getUTCFullYear(), month: localDate.getUTCMonth() + 1, day: localDate.getUTCDate(), hour: 0, minute: 0, second: 0 };
  let candidate = Date.UTC(desired.year, desired.month - 1, desired.day, desired.hour, desired.minute, desired.second);
  const formatter = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
  for (let attempt = 0; attempt < 5; attempt++) {
    const parts = formatter.formatToParts(new Date(candidate));
    const actual = Object.fromEntries(parts.filter(part => part.type !== 'literal').map(part => [part.type, Number(part.value)]));
    const represented = Date.UTC(actual.year!, actual.month! - 1, actual.day!, actual.hour!, actual.minute!, actual.second!);
    const difference = Date.UTC(desired.year, desired.month - 1, desired.day, desired.hour, desired.minute, desired.second) - represented;
    if (difference === 0) return new Date(candidate).toISOString();
    candidate += difference;
  }
  throw new Error('No se pudo resolver la fecha local en la zona horaria seleccionada.');
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MONEY = /^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/;
const RATE = /^(0|[1-9][0-9]{0,2})(\.[0-9]{1,4})?$/;

export function validatePromotionDefinition(input: PromotionDefinition): PromotionDefinition {
  const fail = (message: string): never => { throw new Error(message); };
  if (!input || typeof input !== 'object') fail('La promoción no es válida.');
  const title = text(input.title, 3, 120, 'El título');
  const motive = text(input.motive, 10, 500, 'El motivo');
  if (!['unit_discount', 'percent_discount', 'cashback', 'points_multiplier', 'announcement'].includes(input.kind)) fail('Selecciona un tipo de promoción válido.');
  if (!['network', 'branch'].includes(input.scope)) fail('Selecciona un alcance válido.');
  if (input.scope === 'branch' && !UUID.test(input.branchId ?? '')) fail('Selecciona una sucursal válida para esta promoción.');
  if (input.scope === 'network' && input.branchId) fail('Una promoción de red no puede traer una sucursal específica.');
  if (input.scope === 'branch' && (input.targetBranchIds?.length || input.targetZones?.length)) fail('Los filtros por zona o varias sucursales solo se permiten en campañas de Administración General.');
  if (input.targetBranchIds !== undefined && (!Array.isArray(input.targetBranchIds) || input.targetBranchIds.length < 1 || input.targetBranchIds.length > 500 || input.targetBranchIds.some(id => !UUID.test(id)) || new Set(input.targetBranchIds.map(id => id.toLowerCase())).size !== input.targetBranchIds.length)) fail('Selecciona sucursales válidas y sin repetir.');
  if (input.targetZones !== undefined && (!Array.isArray(input.targetZones) || input.targetZones.length < 1 || input.targetZones.length > 4 || input.targetZones.some(zone => !['occidental','central','oriental','other'].includes(zone)) || new Set(input.targetZones).size !== input.targetZones.length)) fail('Selecciona zonas válidas y sin repetir.');
  if (input.targetMetric !== undefined && (!['sales_usd_30d','fuel_liters_30d'].includes(input.targetMetric.metric) || !MONEY.test(input.targetMetric.threshold) || Number(input.targetMetric.threshold) <= 0)) fail('El criterio estadístico requiere métrica y umbral positivo válidos.');
  if (input.scope === 'branch' && input.targetMetric !== undefined) fail('Los criterios estadísticos solo se permiten en campañas de Administración General.');
  if (input.scope === 'network' && (input.targetBranchIds !== undefined || input.targetZones !== undefined) && !input.targetBranchIds?.length && !input.targetZones?.length) fail('Selecciona al menos una sucursal o zona para limitar la audiencia.');
  const start = validInstant(input.startsAt, 'La fecha de inicio');
  const end = validInstant(input.endsAt, 'La fecha de fin');
  if (end <= start) fail('La fecha de fin debe ser posterior a la de inicio.');
  if (end - start > 5 * 366 * 24 * 60 * 60 * 1000) fail('La vigencia máxima de una promoción es de cinco años.');
  let formatter: Intl.DateTimeFormat;
  try { formatter = new Intl.DateTimeFormat('en-US', { timeZone: input.timeZone, year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short' }); }
  catch { return fail('Selecciona una zona horaria IANA válida.'); }
  void formatter;
  validateRecurrence(input.recurrence, fail);
  if (input.productIds !== undefined && (!Array.isArray(input.productIds) || input.productIds.length > 50 || input.productIds.some(id => !UUID.test(id)) || new Set(input.productIds.map(id => id.toLowerCase())).size !== input.productIds.length)) fail('Selecciona productos válidos y sin repetir.');
  if (input.serviceModes !== undefined && (!Array.isArray(input.serviceModes) || input.serviceModes.length > 2 || input.serviceModes.some(mode => !['full_service', 'self_service'].includes(mode)) || new Set(input.serviceModes).size !== input.serviceModes.length)) fail('Selecciona modalidades válidas y sin repetir.');
  if (!Number.isInteger(input.priority) || input.priority < 1 || input.priority > 100) fail('La prioridad debe estar entre 1 y 100.');
  if (!['none', 'with_points'].includes(input.stacking)) fail('La combinación de beneficios no es válida.');
  const terms = validateTerms(input.terms, fail);
  const value = input.value;
  if (['unit_discount', 'percent_discount', 'cashback', 'points_multiplier'].includes(input.kind) && !value) fail('Este tipo de promoción requiere un valor.');
  if (input.kind === 'unit_discount' && (!MONEY.test(value ?? '') || Number(value) <= 0 || !['liter', 'us_gallon'].includes(input.valueUnit ?? ''))) fail('El descuento por unidad requiere un importe positivo y una unidad válida.');
  if (input.kind !== 'unit_discount' && input.valueUnit !== undefined) fail('La unidad solo aplica al descuento por litro o galón.');
  if (input.kind === 'percent_discount' && (!RATE.test(value ?? '') || Number(value) <= 0 || Number(value) > 100)) fail('El descuento porcentual debe ser mayor que cero y no exceder 100%.');
  if (input.kind === 'cashback') {
    if (!RATE.test(value ?? '') || Number(value) <= 0 || Number(value) > 100) fail('El cashback debe estar entre 0% y 100%.');
    if (!/^[A-Z0-9_-]{2,40}$/.test(input.bankCode ?? '')) fail('Selecciona el banco participante del cashback.');
    if (!input.benefitCapUsd || !MONEY.test(input.benefitCapUsd) || Number(input.benefitCapUsd) <= 0) fail('El cashback requiere un límite máximo por operación.');
  }
  if (input.kind === 'points_multiplier' && (!/^[2-9]$|^10$/.test(value ?? ''))) fail('El multiplicador debe ser un entero de 2 a 10.');
  if (input.kind === 'announcement' && (value || input.bankCode || input.benefitCapUsd)) fail('Un anuncio informativo no puede declarar un beneficio financiero.');
  for (const [label, amount] of [['El mínimo de compra', input.minimumSpendUsd], ['El límite total de presupuesto', input.totalBudgetUsd]] as const) {
    if (amount !== undefined && (!MONEY.test(amount) || Number(amount) <= 0)) fail(`${label} debe ser mayor que cero y tener máximo dos decimales.`);
  }
  if (input.benefitCapUsd !== undefined && (!MONEY.test(input.benefitCapUsd) || Number(input.benefitCapUsd) <= 0)) fail('El límite del beneficio debe ser mayor que cero.');
  if (input.maxUsesPerCustomer !== undefined && (!Number.isInteger(input.maxUsesPerCustomer) || input.maxUsesPerCustomer < 1 || input.maxUsesPerCustomer > 1000)) fail('El límite por cliente debe estar entre 1 y 1000.');
  if (!['none', 'with_points'].includes(input.stacking) || (input.kind === 'points_multiplier' && input.stacking !== 'none')) fail('Un multiplicador de puntos no se puede combinar con otra promoción.');
  if (input.imageUrl !== undefined) {
    let url: URL;
    try { url = new URL(input.imageUrl); } catch { return fail('La imagen debe tener una URL válida.'); }
    if (url.protocol !== 'https:' || url.username || url.password) fail('La imagen debe usar HTTPS y no incluir credenciales.');
    text(input.imageAlt ?? '', 5, 240, 'El texto alternativo de imagen');
  } else if (input.imageAlt) fail('Agrega la imagen antes de definir su texto alternativo.');
  return { ...input, title, motive, terms };
}

export function isPromotionActiveAt(definition: PromotionDefinition, instant: Date): boolean {
  const start = Date.parse(definition.startsAt), end = Date.parse(definition.endsAt), timestamp = instant.getTime();
  if (!Number.isFinite(timestamp) || timestamp < start || timestamp >= end) return false;
  if (definition.recurrence.kind === 'once') return true;
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: definition.timeZone, weekday: 'short', day: 'numeric' }).formatToParts(instant);
  const weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(parts.find(p => p.type === 'weekday')?.value ?? '');
  const day = Number(parts.find(p => p.type === 'day')?.value);
  if (definition.recurrence.kind === 'weekly') return definition.recurrence.weekdays.includes(weekday);
  return day === definition.recurrence.dayOfMonth;
}

export function previewPromotionOccurrences(definition: PromotionDefinition, from: Date, limit = 10): string[] {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('El límite de vista previa debe estar entre 1 y 100.');
  const start = Math.max(from.getTime(), Date.parse(definition.startsAt));
  const end = Date.parse(definition.endsAt);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return [];
  if (definition.recurrence.kind === 'once') return start < end ? [new Date(start).toISOString()] : [];
  const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: definition.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
  const dates = new Set<string>();
  for (let time = start; time < end && dates.size < limit; time += 24 * 60 * 60 * 1000) {
    if (isPromotionActiveAt(definition, new Date(time))) dates.add(formatter.format(new Date(time)));
  }
  return [...dates].sort().slice(0, limit);
}

function validateRecurrence(recurrence: PromotionRecurrence, fail: (message: string) => never) {
  if (!recurrence || typeof recurrence !== 'object') fail('Selecciona una recurrencia válida.');
  if (recurrence.kind === 'once') return;
  if (recurrence.kind === 'weekly') {
    if (!Array.isArray(recurrence.weekdays) || recurrence.weekdays.length < 1 || recurrence.weekdays.length > 7 || recurrence.weekdays.some(day => !Number.isInteger(day) || day < 0 || day > 6) || new Set(recurrence.weekdays).size !== recurrence.weekdays.length) fail('Selecciona uno o más días de semana, sin repetirlos.');
    return;
  }
  if (recurrence.kind === 'monthly' && Number.isInteger(recurrence.dayOfMonth) && recurrence.dayOfMonth >= 1 && recurrence.dayOfMonth <= 31) return;
  fail('La recurrencia mensual requiere un día entre 1 y 31; los días inexistentes se omiten.');
}

function validateTerms(value: PromotionDefinition['terms'], fail: (message: string) => never) {
  if (!value || !Array.isArray(value.applies) || value.applies.length < 1 || value.applies.length > 20 || !Array.isArray(value.excludes) || value.excludes.length > 20) fail('Indica al menos una condición aplicable y revisa las exclusiones.');
  return { applies: value.applies.map(item => text(item, 5, 300, 'Cada condición aplicable')), excludes: value.excludes.map(item => text(item, 5, 300, 'Cada exclusión')) };
}

function validInstant(value: string, label: string): number {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) throw new Error(`${label} debe incluir fecha, hora y zona horaria.`);
  const [year, month, day] = value.slice(0, 10).split('-').map(Number);
  const calendarDate = new Date(Date.UTC(year!, month! - 1, day!));
  if (calendarDate.getUTCFullYear() !== year || calendarDate.getUTCMonth() !== month! - 1 || calendarDate.getUTCDate() !== day) throw new Error(`${label} contiene una fecha de calendario inexistente.`);
  const offset = /([+-])(\d{2}):(\d{2})$/.exec(value);
  if (offset && (Number(offset[2]) > 14 || Number(offset[3]) > 59 || (Number(offset[2]) === 14 && Number(offset[3]) !== 0))) throw new Error(`${label} contiene una zona horaria inválida.`);
  const result = Date.parse(value);
  if (!Number.isFinite(result)) throw new Error(`${label} no es válida.`);
  return result;
}

function text(value: unknown, min: number, max: number, label: string): string {
  if (typeof value !== 'string') throw new Error(`${label} es obligatorio.`);
  const normalized = value.trim().normalize('NFKC');
  if (normalized.length < min || normalized.length > max) throw new Error(`${label} debe contener entre ${min} y ${max} caracteres.`);
  return normalized;
}
