import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const read = name => readFile(new URL(`../public/${name}`, import.meta.url), 'utf8');
const css = await read('styles.css');
const html = await read('index.html');
const app = await read('app.js');
const themeScript = await read('theme.js');
const lib = await import('../public/panel-lib.js');

/* ---------------- CSS theme tokens ---------------- */
function block(source, startPattern) {
  const start = source.search(startPattern);
  assert.ok(start >= 0, `missing block ${startPattern}`);
  const open = source.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}' && --depth === 0) return { text: source.slice(open + 1, i), start, end: i + 1 };
  }
  throw new Error('unbalanced CSS');
}
const tokensOf = text => Object.fromEntries([...text.matchAll(/(--[a-z0-9-]+)\s*:\s*([^;]+);/g)].map(m => [m[1], m[2].trim()]));

const rootBlock = block(css, /^:root\s*\{/m);
const mediaBlock = block(css, /@media \(prefers-color-scheme:dark\)\s*\{/);
const guarded = block(mediaBlock.text, /:root:not\(\[data-theme="light"\]\)\s*\{/);
const explicit = block(css, /:root\[data-theme="dark"\]\s*\{/);
const light = tokensOf(rootBlock.text), darkSystem = tokensOf(guarded.text), darkExplicit = tokensOf(explicit.text);
const dark = { ...light, ...darkExplicit };

test('tema: paleta clara completa en :root y oscuridad solo sobrescribe tokens, con color-scheme', () => {
  assert.match(rootBlock.text, /color-scheme:light/);
  assert.match(guarded.text, /color-scheme:dark/);
  assert.match(explicit.text, /color-scheme:dark/);
  assert.deepEqual(darkSystem, darkExplicit, 'preferencia del sistema y data-theme="dark" deben definir los mismos tokens');
  for (const name of Object.keys(darkExplicit)) assert.ok(name in light, `${name} se redefine en oscuro pero no existe en la paleta clara`);
  for (const name of ['--ink', '--paper', '--card', '--muted', '--ok-fg', '--warn-fg', '--crit-fg', '--accent', '--track']) assert.ok(name in light && name in darkExplicit, `falta ${name}`);
});

test('tema: no quedan colores literales fuera de los bloques de tokens', () => {
  let rest = css;
  for (const { start, end } of [explicit, mediaBlock, rootBlock].sort((a, b) => b.start - a.start)) rest = rest.slice(0, start) + rest.slice(end);
  assert.doesNotMatch(rest, /#[0-9a-fA-F]{3,8}\b/, 'hay colores hexadecimales fuera de los tokens');
  assert.doesNotMatch(rest, /\brgba?\(|\bhsla?\(/);
  assert.doesNotMatch(rest, /:\s*(white|black)\b/);
  const used = new Set([...css.matchAll(/var\((--[a-z0-9-]+)/g)].map(m => m[1]));
  for (const name of used) assert.ok(name in light, `var(${name}) no está definido`);
});

function hexToRgb(hex) {
  const value = hex.replace('#', '');
  const full = value.length === 3 ? [...value].map(c => c + c).join('') : value.slice(0, 6);
  return [0, 2, 4].map(i => parseInt(full.slice(i, i + 2), 16) / 255);
}
function luminance(hex) {
  const [r, g, b] = hexToRgb(hex).map(c => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const textPairs = [
  ['--ink', '--paper'], ['--ink', '--card'], ['--ink', '--field-bg'], ['--muted', '--paper'], ['--muted', '--card'], ['--muted', '--surface-2'], ['--muted', '--surface-3'],
  ['--green2', '--card'], ['--green2', '--paper'], ['--accent-ink', '--accent'], ['--accent-ink', '--accent-hover'], ['--accent-text', '--peach'], ['--red', '--card'], ['--red', '--paper'],
  ['--side-ink', '--side-bg'], ['--side-link', '--side-bg'], ['--side-caption', '--side-bg'], ['--side-muted', '--side-bg'], ['--hero-ink', '--hero-bg'], ['--hero-muted', '--hero-bg'],
  ['--avatar-ink', '--avatar-bg'], ['--ok-fg', '--ok-bg'], ['--warn-fg', '--warn-bg'], ['--crit-fg', '--crit-bg'], ['--unknown-fg', '--unknown-bg'],
  ['--toast-ink', '--toast-bg'], ['--secondary-ink', '--secondary-bg'], ['--ink', '--secondary-bg'],
];
const graphicPairs = [
  ['--ok-bar', '--track'], ['--warn-bar', '--track'], ['--crit-bar', '--track'], ['--unknown-bar', '--track'],
  ['--ok-bar', '--card'], ['--warn-bar', '--card'], ['--crit-bar', '--card'],
  ['--control-line', '--card'], ['--control-line', '--field-bg'], ['--focus', '--card'], ['--focus', '--paper'],
  ['--series-super', '--card'], ['--series-regular', '--card'], ['--series-diesel', '--card'], ['--series-other', '--card'],
  ['--series-super', '--track'], ['--series-regular', '--track'],
];
for (const [themeName, palette] of [['claro', light], ['oscuro', dark]]) {
  test(`tema ${themeName}: contraste WCAG AA (texto 4.5:1, componentes gráficos 3:1)`, () => {
    for (const [fg, bg] of textPairs) assert.ok(contrast(palette[fg], palette[bg]) >= 4.5, `${fg} ${palette[fg]} sobre ${bg} ${palette[bg]} = ${contrast(palette[fg], palette[bg]).toFixed(2)}`);
    for (const [fg, bg] of graphicPairs) assert.ok(contrast(palette[fg], palette[bg]) >= 3, `${fg} ${palette[fg]} sobre ${bg} ${palette[bg]} = ${contrast(palette[fg], palette[bg]).toFixed(2)}`);
  });
}

test('tema: el selector vive en Configuración (menú del avatar), no en la cabecera ni en el login', async () => {
  assert.match(html, /<script src="\/theme\.js"><\/script>/);
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)[^>]*>/, 'la CSP bloquea scripts en línea');
  assert.equal([...html.matchAll(/data-theme-choice=/g)].length, 0, 'sin interruptor de tema en cabecera ni login');
  assert.match(html, /id="user-menu-button"/);
  const shell = await read('shell.js');
  assert.match(shell, /name: 'theme'/);
  assert.match(shell, /Configuración/);
  assert.match(shell, /Cerrar sesión/);
  assert.match(html, /name="color-scheme" content="light dark"/);
  assert.match(html, /rel="apple-touch-icon"/);
  assert.match(html, /rel="icon"[^>]*favicon-32\.png/);
  assert.match(themeScript, /try\s*\{[\s\S]*localStorage\.getItem/);
  assert.match(themeScript, /try\s*\{[\s\S]*localStorage\.(setItem|removeItem)/);
});

test('tema: theme.js aplica data-theme y tolera un almacenamiento bloqueado', () => {
  const attributes = new Map();
  const listeners = [];
  const document = {
    documentElement: { setAttribute: (k, v) => attributes.set(k, v), removeAttribute: k => attributes.delete(k) },
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: (type, fn) => listeners.push([type, fn]),
  };
  const blocked = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); }, removeItem() { throw new Error('blocked'); } };
  const sandbox = { document, localStorage: blocked, matchMedia: () => ({ matches: false, addEventListener() {} }) };
  sandbox.window = sandbox;
  vm.runInNewContext(themeScript, sandbox);
  assert.equal(sandbox.window.dlcTheme.get(), 'system');
  sandbox.window.dlcTheme.set('dark');
  assert.equal(attributes.get('data-theme'), 'dark');
  sandbox.window.dlcTheme.set('system');
  assert.equal(attributes.has('data-theme'), false);

  const store = new Map([['dlc.theme', 'light']]);
  const working = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
  attributes.clear();
  const second = { document, localStorage: working, matchMedia: sandbox.matchMedia };
  second.window = second;
  vm.runInNewContext(themeScript, second);
  assert.equal(attributes.get('data-theme'), 'light', 'restaura la preferencia guardada');
});

/* ---------------- Countries ---------------- */
test('países: nombres en español sin banderas, valor por defecto SV y derivación desde las sucursales', () => {
  assert.equal(lib.countryName('SV'), 'El Salvador');
  assert.equal(lib.countryLabel('gt'), 'Guatemala (GT)');
  assert.equal(lib.normalizeCountryCode(undefined), 'SV');
  assert.equal(lib.normalizeCountryCode('xx1', ''), '');
  const branches = [{ id: 'a' }, { id: 'b', countryCode: 'GT' }, { id: 'c', countryCode: 'sv' }];
  assert.deepEqual(lib.deriveCountries(branches), [{ countryCode: 'SV', branchCount: 2 }, { countryCode: 'GT', branchCount: 1 }]);
  assert.deepEqual(lib.resolveCountries([{ countryCode: 'SV', branchCount: 5 }], branches), [{ countryCode: 'SV', branchCount: 5 }, { countryCode: 'GT', branchCount: 1 }]);
  assert.deepEqual(lib.resolveCountries(undefined, branches).map(r => r.countryCode), ['SV', 'GT']);
  const options = lib.countrySelectMarkup(lib.deriveCountries(branches), 'GT');
  assert.match(options, /Todos los países/);
  assert.match(options, /value="GT" selected/);
  assert.doesNotMatch(options, /[\u{1F1E6}-\u{1F1FF}]/u, 'sin emoji de bandera');
});

test('países: cambiar el país reinicia una sucursal incompatible y la consulta usa countryCode', () => {
  const branches = [{ id: 'a' }, { id: 'b', countryCode: 'GT' }];
  assert.equal(lib.reconcileBranchSelection('b', 'SV', branches), null);
  assert.equal(lib.reconcileBranchSelection('b', 'GT', branches), 'b');
  assert.equal(lib.reconcileBranchSelection('a', null, branches), 'a');
  assert.equal(lib.reconcileBranchSelection('missing', null, branches), null);
  assert.deepEqual(lib.branchesForCountry(branches, 'SV').map(b => b.id), ['a']);
  assert.equal(lib.networkQuery({ days: 30, branchId: 'x', countryCode: 'GT' }), 'days=30&branchId=x&countryCode=GT');
  assert.equal(lib.networkQuery({ days: 7 }), 'days=7');
});

test('países: el ScopeBar combina país y sucursal, y el alta envía countryCode', async () => {
  const scope = await read('scopebar.js'); const wizard = await read('wizard-model.js'); const model = await read('dashboard-model.js');
  assert.match(scope, /label: 'País'/);
  assert.match(scope, /label: 'Sucursal', multi: true/);
  assert.match(model, /networkQuery\(\{ days, branchId: id/);
  assert.match(wizard, /countryCode: String\(v\.countryCode\)/);
  assert.match(wizard, /profile: 'operational'/);
  assert.match(app, /searchParams\.set\('country',state\.countryCode\)/);
});

/* ---------------- Charts ---------------- */
test('gráficos: niveles de tanque críticos <=30 %, medios <=60 %, óptimos >60 % con texto e icono', () => {
  assert.deepEqual([0, 30, 30.01, 60, 60.01, 100].map(v => lib.tankLevel(v).key), ['critical', 'critical', 'medium', 'medium', 'optimal', 'optimal']);
  assert.equal(lib.tankLevel(null).key, 'unknown');
  assert.equal(lib.tankLevel('').key, 'unknown');
  for (const level of [lib.tankLevel(10), lib.tankLevel(50), lib.tankLevel(90)]) assert.ok(level.label && level.icon);
});

const sampleBranches = [
  { id: 'a', name: 'Norte', tanks: [{ family: 'super', fuelName: 'Súper', onHandLiters: '1000', capacityLiters: '4000' }, { family: 'regular', fuelName: 'Regular', onHandLiters: '5000', capacityLiters: '8000' }, { family: 'diesel', fuelName: 'Diésel', onHandLiters: '7000', capacityLiters: '8000' }] },
  { id: 'b', name: 'Sur', tanks: [{ family: 'super', fuelName: 'Súper', onHandLiters: '3000', capacityLiters: '4000' }, { family: 'diesel', fuelName: 'Diésel', onHandLiters: null, capacityLiters: '8000' }] },
];

test('gráficos: agregación por combustible y marcado accesible sin estilos en línea', () => {
  const rows = lib.aggregateTanksByFuel(sampleBranches);
  assert.deepEqual(rows.map(r => r.name), ['Súper', 'Regular', 'Diésel']);
  assert.equal(rows[0].percentage, 50);
  assert.equal(rows[0].minimumPercent, 25);
  assert.equal(rows[2].measuredTanks, 1);
  const markup = lib.tankLevelsMarkup(rows);
  assert.match(markup, /Medio/);
  assert.match(markup, /Óptimo/);
  assert.match(markup, /role="img" aria-label="Súper: nivel medio, 50 %/);
  assert.match(markup, /tank-fill--medium/);
  assert.match(markup, /tank-fill--optimal/);
  assert.match(markup, /<svg class="icon pill-icon"/);
  assert.doesNotMatch(markup, /style=/);
  assert.match(lib.tankLevelsMarkup([]), /No hay tanques/);
});

test('gráficos: la tendencia de ventas es un SVG con alternativa textual, sin estilos en línea ni colores fijos', () => {
  const daily = [{ date: '2026-05-01', salesUsd: '120.5', soldLiters: '40', closedCuts: 2 }, { date: '2026-05-02', salesUsd: '300', soldLiters: '90', closedCuts: 2 }, { date: '2026-05-03', salesUsd: '0', soldLiters: '0', closedCuts: 1 }];
  const svg = lib.salesTrendSvg(daily, { money: v => `$${v}`, number: v => String(v), dayLabel: item => item.date.slice(5) });
  assert.match(svg, /<svg class="chart-svg"[^>]*role="img" aria-label="Tendencia diaria de ventas: 3 día\(s\)/);
  assert.match(svg, /<title>05-02: \$300/);
  assert.match(svg, /class="chart-line"/);
  assert.doesNotMatch(svg, /style=|#[0-9a-f]{3,6}\b|rgb\(/i);
  assert.equal(lib.salesTrendSvg([], { money: String, number: String, dayLabel: String }), '');
  assert.match(css, /@media\(prefers-reduced-motion:no-preference\)\{\.chart-svg \.chart-line/);
  assert.match(css, /@media\(prefers-reduced-motion:reduce\)/);
});

test('gráficos: el resumen consolidado incluye niveles por combustible y no usa atributos style bloqueados por la CSP', async () => {
  const page = await read('dashboard-page.js');
  assert.match(page, /Nivel de tanques por combustible/);
  assert.match(page, /salesTrendSvg\(daily,/);
  assert.match(page, /Tendencia de ventas/);
  for (const source of [app, page, await read('charts.js'), await read('components.js'), await read('branch-wizard.js')]) assert.doesNotMatch(source, /style="/);
  assert.doesNotMatch(app, /#[0-9a-fA-F]{6}\b/, 'app.js no debe contener colores fijos');
});

/* ---------------- Validation ---------------- */
const field = (props) => ({ tagName: 'INPUT', type: 'text', value: '', min: '', max: '', step: '', minLength: -1, maxLength: -1, required: false, dataset: {}, validity: { valid: true }, ...props });
const invalid = (flag, props) => field({ ...props, validity: { valid: false, [flag]: true } });

test('validación: mensajes en español por restricción y textos personalizados', () => {
  assert.equal(lib.describeValidity(field()), '');
  assert.match(lib.describeValidity(invalid('valueMissing')), /obligatorio/);
  assert.match(lib.describeValidity(invalid('valueMissing', { tagName: 'SELECT', type: 'select-one' })), /Selecciona/);
  assert.match(lib.describeValidity(invalid('typeMismatch', { type: 'email' })), /correo válido/);
  assert.match(lib.describeValidity(invalid('tooShort', { value: 'abc', minLength: 8 })), /al menos 8 caracteres/);
  assert.equal(lib.describeValidity(invalid('rangeUnderflow', { type: 'number', min: '0.000000001' })), 'La cantidad debe ser mayor que cero.');
  assert.equal(lib.describeValidity(invalid('rangeUnderflow', { type: 'number', min: '0' })), 'No puede ser negativo.');
  assert.equal(lib.describeValidity(invalid('rangeOverflow', { type: 'number', max: '500' })), 'Debe ser menor o igual a 500.');
  assert.equal(lib.describeValidity(invalid('stepMismatch', { type: 'number', step: '0.01' })), 'Usa como máximo 2 decimales.');
  assert.equal(lib.describeValidity(invalid('stepMismatch', { type: 'number', step: '1' })), 'Ingresa un número entero.');
});

test('validación: la lectura final no puede ser menor que la inicial', () => {
  const reading = invalid('rangeUnderflow', { type: 'number', min: '1200.5', value: '1000', dataset: { msgMin: 'La lectura final no puede ser menor que la lectura inicial registrada ({min}).' } });
  assert.equal(lib.describeValidity(reading), 'La lectura final no puede ser menor que la lectura inicial registrada (1200.5).');
  assert.match(app, /min="\$\{esc\(n\.lastMeterValue\|\|0\)\}" step="0\.001" data-msg-min="La lectura final no puede ser menor que la lectura inicial/);
});

test('validación: la explicación obligatoria rechaza espacios en blanco y textos demasiado cortos', () => {
  const blank = field({ type: 'textarea', tagName: 'TEXTAREA', value: '            ', required: true, minLength: 12 });
  assert.match(lib.describeValidity(blank), /solo espacios/);
  const short = field({ type: 'textarea', tagName: 'TEXTAREA', value: '  perdida  ', minLength: 12 });
  assert.match(lib.describeValidity(short), /al menos 12 caracteres/);
  assert.equal(lib.describeValidity(field({ type: 'textarea', tagName: 'TEXTAREA', value: 'Derrame por manguera dañada', minLength: 12 })), '');
  assert.match(lib.describeValidity(field({ value: '0', dataset: { positive: '' } })), /mayor que cero/);
  assert.equal(lib.describeValidity(field({ value: '2.5', dataset: { positive: '' } })), '');
});

test('validación: reglas entre campos (fin posterior al inicio)', () => {
  const form = { elements: { startsAt: { value: '2026-05-01T08:00', type: 'datetime-local' } } };
  const end = field({ type: 'datetime-local', value: '2026-05-01T07:00', dataset: { gt: 'startsAt', crossLabel: 'Inicio', msgCross: 'La hora de fin debe ser posterior al inicio del turno.' } });
  assert.equal(lib.fieldMessage(end, form), 'La hora de fin debe ser posterior al inicio del turno.');
  end.value = '2026-05-01T16:00';
  assert.equal(lib.fieldMessage(end, form), '');
  const gte = field({ type: 'number', value: '5', dataset: { gte: 'initial' } });
  assert.match(lib.fieldMessage(gte, { elements: { initial: { value: '9', type: 'number' } } }), /mayor o igual que «initial»/);
});

test('validación: los formularios usan aria-invalid, aria-describedby y envío bloqueado hasta ser válidos', async () => {
  const ui = await read('panel-ui.js');
  assert.match(ui, /aria-invalid/);
  assert.match(ui, /aria-describedby/);
  assert.match(ui, /button\.disabled = true/);
  assert.match(ui, /addEventListener\('input'/);
  assert.match(ui, /addEventListener\('focusout'/);
  assert.match(ui, /stopImmediatePropagation/);
  assert.match(app, /startPanelUi\(\)/);
  assert.match(app, /data-max-for="quantity"/);
  assert.match(app, /data-gt="startsAt"/);
  assert.match(css, /\.field-error/);
});

/* ---------------- cut windows come from the API ---------------- */
test('cuts show their window from startsAt/endsAt and never hardcode 14:00-22:00', async () => {
  const helpers = /const cutName=[\s\S]*?cutLabel=c=>[^;\r\n]*;/.exec(app)?.[0];
  assert.ok(helpers, 'falta el ayudante cutName/cutWindow/cutLabel');
  assert.doesNotMatch(helpers, /1[4-9]:00|2[0-2]:00|06:00/);
  const sandbox = { esc: value => String(value), Date, result: null };
  vm.runInNewContext(`${helpers.replace(/^const /, 'var ')}; result = [cutName({slot:1}), cutName({slot:2}), cutWindow({startsAt:'2026-10-10T12:00:00Z',endsAt:'2026-10-10T20:00:00Z'}), cutLabel({slot:2,startsAt:'2026-10-10T20:00:00Z',endsAt:'2026-10-11T04:00:00Z'})]`, sandbox);
  const [morning, evening, window, label] = sandbox.result;
  assert.equal(morning, 'Matutino');
  assert.equal(evening, 'Vespertino');
  assert.match(window, /^\d{2}:\d{2}–\d{2}:\d{2}$/);
  assert.match(label, /^Vespertino<div class="branch-meta">\d{2}:\d{2}–\d{2}:\d{2}<\/div>$/);
  assert.equal((app.match(/label:'Turno',render:cutLabel/g) ?? []).length, 1, 'cuts table uses the shared label');
  assert.match(await read('dashboard-page.js'), /label: 'Turno', render: helpers\.cutLabel/);
  assert.match(app, /Detalle del corte · \$\{esc\(cutName\(cut\)\)\} \$\{esc\(cutWindow\(cut\)\)\}/);
});
