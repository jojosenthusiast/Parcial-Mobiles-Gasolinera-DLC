import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const m = name => import(`../public/${name}`);
const { nextCode, suggestNextCode, validateCode } = await m('codes.js');
const fmt = await m('format.js');
const labels = await m('labels.js');
const { ICONS, icon, iconSprite } = await m('icons.js');
const drafts = await m('drawer.js');
const scope = await m('scopebar.js');
const model = await m('dashboard-model.js');
const wiz = await m('wizard-model.js');
const { classifyAction } = await m('decorate.js');
const view = await m('module-view.js');
const charts = await m('charts.js');
const prefs = await m('prefs.js');

test('códigos: sugiere el siguiente a partir del último guardado', () => {
  assert.equal(nextCode('QA-GT-01'), 'QA-GT-02');
  assert.equal(nextCode('QA-GT-99'), 'QA-GT-100');
  assert.equal(nextCode('SV9'), 'SV10');
  assert.equal(nextCode('ABC'), 'ABC-01');
  assert.equal(suggestNextCode(['QA-SV-01', 'QA-GT-01', 'QA-GT-02'], { prefix: 'QA-GT' }), 'QA-GT-03');
  assert.equal(wiz.suggestCodeFor(['QA-SV-01', 'QA-GT-01'], 'GT'), 'QA-GT-02');
  assert.equal(wiz.suggestCodeFor([], 'HN'), 'HN-01');
});

test('códigos: valida formato y unicidad en vivo', () => {
  assert.equal(validateCode('').ok, false);
  assert.equal(validateCode('-bad').ok, false);
  assert.equal(validateCode('qa-gt-01', { existing: ['QA-GT-01'] }).ok, false);
  assert.equal(validateCode('QA-GT-01', { existing: ['QA-GT-01'], current: 'QA-GT-01' }).ok, true);
  assert.equal(validateCode('QA-GT-02', { existing: ['QA-GT-01'] }).ok, true);
});

test('formato: dinero con 2 decimales, miles y moneda de la sucursal', () => {
  assert.equal(fmt.formatMoney(1234.5, { currency: 'USD', decimals: 2 }), 'USD 1,234.50');
  assert.equal(fmt.formatMoney('3.487100000', { currency: 'GTQ', decimals: 2 }), 'GTQ 3.49');
  assert.equal(fmt.formatMoney(null), '—');
  assert.equal(fmt.currencyForCountry('SV'), 'USD');
  assert.deepEqual(['GT', 'HN', 'NI', 'CR', 'PA', 'MX', 'US', 'CO'].map(c => fmt.currencyForCountry(c)), ['GTQ', 'HNL', 'NIO', 'CRC', 'USD', 'MXN', 'USD', 'COP']);
  const rows = [{ v: 10, c: 'USD' }, { v: 5, c: 'GTQ' }, { v: 2.5, c: 'USD' }];
  assert.deepEqual(fmt.subtotalsByCurrency(rows, r => r.v, r => r.c), [{ currency: 'USD', total: 12.5 }, { currency: 'GTQ', total: 5 }]);
});

test('formato: litros y galones (3.785411784 L/gal)', () => {
  assert.equal(fmt.LITERS_PER_GALLON, 3.785411784);
  assert.equal(fmt.formatVolume(3785.411784, { unit: 'gallons' }), '1,000 gal');
  assert.equal(fmt.formatVolume(15000.4, { unit: 'liters' }), '15,000 L');
  assert.equal(fmt.formatVolume(15000.456, { unit: 'liters', detail: true }), '15,000.46 L');
  assert.equal(fmt.convertPriceUnit(3.785411784, 'gallon', 'liter').toFixed(4), '1.0000');
});

test('estados: etiquetas en español con icono y tono, con respaldo', () => {
  for (const key of ['active', 'configured', 'draft', 'suspended', 'pending_approval', 'critical']) {
    const meta = labels.statusMeta(key);
    assert.ok(meta.label && !/[a-z]+_[a-z]+/.test(meta.label) && meta.icon && meta.tone);
  }
  assert.equal(labels.statusLabel('draft'), 'Borrador');
  assert.equal(labels.statusLabel('active'), 'Activa');
  assert.equal(labels.statusLabel('algo_nuevo'), 'Algo nuevo');
  assert.match(labels.statusBadge('critical'), /<svg class="icon pill-icon"/);
  assert.equal(labels.statusLabel('medium', { kind: 'severity' }), 'Media');
});

test('iconos: sprite SVG propio, sin emojis en ningún archivo del panel', async () => {
  assert.ok(Object.keys(ICONS).length > 40);
  assert.match(iconSprite(), /<symbol id="i-plus"/);
  assert.match(icon('inexistente'), /#i-info/);
  const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}\u{2B1B}\u{2B1C}\u{25A0}-\u{25FF}\u{2300}-\u{23FF}]/u;
  for (const name of await readdir(new URL('../public/', import.meta.url))) {
    if (!/\.(js|html|css)$/.test(name)) continue;
    const text = await readFile(new URL(`../public/${name}`, import.meta.url), 'utf8');
    const hit = text.match(emoji);
    assert.equal(hit, null, `${name} contiene un emoji o glifo: ${hit?.[0]}`);
  }
});

test('borradores: se guardan, restauran, caducan y toleran almacenamiento bloqueado', () => {
  const store = new Map();
  const storage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
  assert.equal(drafts.saveDraft('f', { name: '   ' }, { storage }), false);
  assert.equal(drafts.saveDraft('f', { name: 'Sucursal A' }, { storage, now: 1000 }), true);
  assert.deepEqual(drafts.loadDraft('f', { storage, now: 2000 }).values, { name: 'Sucursal A' });
  assert.equal(drafts.loadDraft('f', { storage, now: 1000 + drafts.DRAFT_TTL_MS + 1 }), null);
  drafts.saveDraft('g', { a: 'x' }, { storage });
  drafts.clearDraft('g', { storage });
  assert.equal(drafts.loadDraft('g', { storage }), null);
  const blocked = { getItem() { throw new Error('x'); }, setItem() { throw new Error('x'); }, removeItem() { throw new Error('x'); } };
  assert.equal(drafts.saveDraft('f', { a: '1' }, { storage: blocked }), false);
  assert.equal(drafts.loadDraft('f', { storage: blocked }), null);
});

test('preferencias: decimales 0-4, unidad y alcance por usuario', () => {
  assert.equal(prefs.normalizePrefs({ decimals: 9 }).decimals, 4);
  assert.equal(prefs.normalizePrefs({ decimals: -2 }).decimals, 0);
  assert.equal(prefs.normalizePrefs({}).decimals, 2);
  assert.equal(prefs.normalizePrefs({ volumeUnit: 'x' }).volumeUnit, 'liters');
  const store = new Map();
  const storage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) };
  prefs.writeScope('u1', { countryCode: 'gt', branchIds: ['a', 'a', 'b'] }, storage);
  assert.deepEqual(prefs.readScope('u1', storage), { countryCode: 'GT', branchIds: ['a', 'b'] });
  assert.deepEqual(prefs.readScope('u2', storage), { countryCode: null, branchIds: [] });
});

const branches = [
  { id: 'a', name: 'Santa Ana', code: 'QA-SV-01', countryCode: 'SV', status: 'active' },
  { id: 'b', name: 'San Miguel', code: 'QA-SV-02', countryCode: 'SV', status: 'active' },
  { id: 'c', name: 'Zona 10', code: 'QA-GT-01', countryCode: 'GT', status: 'active' },
];

test('ScopeBar: resumen, selección múltiple y país reconcilian la selección', () => {
  assert.equal(scope.scopeSummary({ branches }), 'Viendo: Toda la red · 3 sucursales');
  assert.equal(scope.scopeSummary({ branches, branchIds: ['a', 'b'] }), 'Viendo: Toda la red · 2 sucursales');
  assert.equal(scope.scopeSummary({ branches, countryCode: 'GT' }), 'Viendo: Guatemala · 1 sucursal');
  assert.equal(scope.scopeSummary({ branches, branchIds: ['c'] }), 'Viendo: Zona 10');
  assert.equal(scope.scopeSummary({ lockedBranch: { name: 'Mi estación' } }), 'Viendo: Mi estación');
  assert.deepEqual(scope.reconcileSelection(['a', 'c', 'x'], branches, 'SV'), ['a']);
  assert.deepEqual(scope.branchesInScope(branches, 'SV', []).map(b => b.id), ['a', 'b']);
});

test('resumen: una petición por país (o sucursal) y las monedas nunca se suman', () => {
  const slices = model.sliceRequests({ branches, days: 7 });
  assert.deepEqual(slices.map(s => [s.countryCode, s.currency]), [['SV', 'USD'], ['GT', 'GTQ']]);
  assert.equal(model.sliceRequests({ branches, branchIds: ['a', 'b'], days: 1 }).length, 2);
  assert.equal(model.sliceRequests({ branches: branches.slice(0, 2), days: 7 }).length, 1);
  const mk = (id, name, cc, sales, pct) => ({ id, name, countryCode: cc, closedCuts: 1, expectedCuts: 2, products: [{ fuelName: 'Súper', family: 'super', soldLiters: '100', salesUsd: String(sales) }], tanks: [{ fuelName: 'Súper', family: 'super', minimumPercent: pct, onHandLiters: '1', capacityLiters: '2' }] });
  const merged = model.mergeNetwork([
    { slice: slices[0], data: { branches: [mk('a', 'Santa Ana', 'SV', 100, 20)], dailySeries: [{ date: '2026-01-01', salesUsd: '100', soldLiters: '10', closedCuts: 2 }], cutCoverage: { closed: 1, expected: 2 } } },
    { slice: slices[1], data: { branches: [mk('c', 'Zona 10', 'GT', 50, 70)], dailySeries: [{ date: '2026-01-01', salesUsd: '50', soldLiters: '5', closedCuts: 2 }], cutCoverage: { closed: 2, expected: 2 } } },
  ]);
  assert.deepEqual(merged.salesByCurrency.map(s => [s.currency, s.total]), [['USD', 100], ['GTQ', 50]]);
  assert.equal(merged.series.length, 2);
  assert.deepEqual(merged.cutCoverage, { closed: 3, expected: 4 });
  const alerts = model.deriveAlerts(merged.branches);
  assert.equal(alerts[0].severity, 'crit');
  assert.match(alerts[0].title, /Santa Ana: Súper al 20 %/);
  assert.equal(alerts.length, 1);
  assert.equal(model.deriveAlerts(merged.branches, { days: 1 }).at(-1).severity, 'warn');
});

test('asistente de sucursal: validación por paso, payloads y reanudación', () => {
  assert.equal(wiz.STEPS.length, 5);
  assert.equal(wiz.progressText(1), 'Paso 2 de 5');
  const basic = { ...wiz.DEFAULT_VALUES, name: 'DLC Antigua', code: 'QA-GT-02', countryCode: 'GT', timezone: 'America/Guatemala' };
  assert.equal(wiz.validateStep('basic', basic, { existingCodes: ['QA-GT-01'] }).ok, true);
  assert.ok(wiz.validateStep('basic', { ...basic, code: 'QA-GT-01' }, { existingCodes: ['QA-GT-01'] }).errors.code);
  assert.ok(wiz.validateStep('basic', { ...basic, name: ' ' }).errors.name);
  assert.ok(wiz.validateStep('basic', { ...basic, timezone: 'Mars/Base' }).errors.timezone);
  assert.ok(wiz.validateStep('infra', { ...basic, fuelCount: 2, fuels: ['super'] }).errors.fuels);
  assert.equal(wiz.validateStep('infra', { ...basic, fuelCount: 2, fuels: ['super', 'diesel'] }).ok, true);
  assert.ok(wiz.validateStep('infra', { ...basic, dispenserCount: 0 }).errors.dispenserCount);
  assert.equal(wiz.validateStep('staff', { ...basic, staffMode: 'later' }).ok, true);
  assert.ok(wiz.validateStep('staff', { ...basic, staffMode: 'now', managerName: 'A' }).errors.managerName);
  assert.equal(wiz.validateStep('store', { ...basic, hasStore: false }).ok, true);
  assert.ok(wiz.validateStep('store', { ...basic, hasStore: true, registers: 0 }).errors.registers);
  assert.deepEqual(wiz.defaultFuels(2), ['super', 'regular']);
  assert.deepEqual(wiz.createDraftPayload(basic), { code: 'QA-GT-02', name: 'DLC Antigua', zone: 'central', timezone: 'America/Guatemala', countryCode: 'GT', profile: 'operational', expectedDispenserCount: 6 });
  assert.deepEqual(wiz.staffPayload(0), { status: 'deferred', employeeCount: 0 });
  assert.equal(wiz.staffPayload(2).status, 'confirmed');
  const cp = wiz.wizardCheckpoint({ ...basic, hasStore: true, registers: 2, categories: 'Bebidas, Snacks, bebidas' }, 3);
  assert.deepEqual(cp.wizard.store.categories, ['Bebidas', 'Snacks', 'bebidas']);
  const back = wiz.restoreFromBranch({ code: 'QA-GT-02', name: 'DLC Antigua', countryCode: 'GT', zone: 'central', timezone: 'America/Guatemala', onboardingData: { review: cp } });
  assert.equal(back.step, 3);
  assert.equal(back.values.hasStore, true);
  assert.equal(wiz.restoreFromBranch({ code: 'X-1', name: 'X', onboardingData: { identity: {} } }).step, 1);
  const items = wiz.readinessItems([{ code: 'TANK_MISSING', message: 'Registra...' }, { code: 'NUEVO', message: 'Algo nuevo' }]);
  assert.deepEqual(items.map(i => i.page), ['equipment', 'branches']);
});

test('botones heredados: la acción se reconoce por su texto', () => {
  assert.equal(classifyAction('Crear sucursal'), 'create');
  assert.equal(classifyAction('Guardar aviso'), 'save');
  assert.equal(classifyAction('Aprobar'), 'approve');
  assert.equal(classifyAction('Rechazar →'), 'delete');
  assert.equal(classifyAction('Editar perfil'), 'edit');
  assert.equal(classifyAction('Cancelar'), 'cancel');
  assert.equal(classifyAction('Mostrar más'), 'view');
  assert.equal(classifyAction('Zzz'), null);
});

test('render parcial: caché con vigencia, secuenciador y claves deterministas', () => {
  let now = 0;
  const cache = view.createCache({ ttl: 60_000, now: () => now });
  cache.set('k', { v: 1 });
  assert.equal(cache.get('k').fresh, true);
  now = 61_000;
  assert.equal(cache.get('k').fresh, false);
  assert.deepEqual(cache.get('k').data, { v: 1 });
  assert.equal(view.cacheKey({ b: 1, a: [2] }), view.cacheKey({ a: [2], b: 1 }));
  const seq = view.createSequencer();
  const first = seq.next(); const second = seq.next();
  assert.equal(seq.isCurrent(first), false);
  assert.equal(seq.isCurrent(second), true);
  assert.equal(view.isAbortError(new DOMException('x', 'AbortError')), true);
});

test('gráficos: medidor con umbrales 30/60, texto e icono; marcador de precio con 2 decimales', () => {
  const g = charts.gaugeMarkup({ name: 'Diésel', family: 'diesel', percent: 18 });
  assert.match(g, /tone-crit/);
  assert.match(g, /Crítico/);
  assert.match(g, /gauge-mark--30/);
  assert.match(g, /aria-label="Diésel: 18 % de capacidad/);
  assert.match(charts.gaugeMarkup({ name: 'Súper', percent: 45 }), /tone-warn/);
  assert.match(charts.gaugeMarkup({ name: 'Regular', percent: 61 }), /tone-ok/);
  assert.match(charts.gaugeMarkup({ name: 'X', percent: null }), /Sin medición/);
  const marker = charts.markerMarkup({ name: 'Regular', family: 'regular', price: '3.241200000', previous: '3.1', currency: 'USD', unit: 'us_gallon', decimals: 2 });
  assert.match(marker, /3\.24/);
  assert.doesNotMatch(marker, /3\.2412/);
  assert.match(marker, /marker-var--up/);
  assert.match(marker, /galón/);
  assert.equal(charts.variationOf(3, 3).dir, 'flat');
  assert.doesNotMatch(g, /style=/);
});
