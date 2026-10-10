import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const lib = await import('../public/panel-lib.js');
const app = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');

const branches = [
  { id: 'd1', name: 'Borrador Uno', status: 'draft', countryCode: 'SV' },
  { id: 'a1', name: 'Activa Uno', status: 'active', countryCode: 'SV' },
  { id: 'a2', name: 'Activa GT', status: 'active', countryCode: 'GT' },
  { id: 'c1', name: 'Configurada', status: 'configured', countryCode: 'SV' }
];

test('sucursal: etiquetas y activas', () => {
  assert.equal(lib.branchStatusLabel('draft'), 'Borrador');
  assert.equal(lib.branchStatusLabel('active'), 'Activa');
  assert.equal(lib.branchStatusLabel(undefined), 'Sin estado');
  assert.deepEqual(lib.activeBranches(branches).map(b => b.id), ['a1', 'a2']);
  assert.equal(lib.isBranchActive(branches[0]), false);
});

test('sucursal: pickDefaultBranch prefiere una activa y nunca devuelve un borrador', () => {
  assert.equal(lib.pickDefaultBranch(branches), 'a1');
  assert.equal(lib.pickDefaultBranch(branches, { preferredId: 'a2' }), 'a2');
  assert.equal(lib.pickDefaultBranch(branches, { preferredId: 'd1' }), 'a1', 'un borrador preferido se descarta');
  assert.equal(lib.pickDefaultBranch(branches, { countryCode: 'GT' }), 'a2');
  assert.equal(lib.pickDefaultBranch([branches[0], branches[3]]), null);
  assert.equal(lib.pickDefaultBranch([]), null);
  assert.equal(lib.pickDefaultBranch(undefined), null);
});

test('sucursal: isBranchScopeError reconoce el 404 de alcance y no otros errores', () => {
  assert.equal(lib.isBranchScopeError({ status: 404, message: 'Sucursal fuera de tu ámbito.' }), true);
  assert.equal(lib.isBranchScopeError({ status: 404, message: 'Sucursal activa fuera de tu ambito.' }), true);
  assert.equal(lib.isBranchScopeError({ status: 404, message: 'Sucursal fuera de tu red.' }), true);
  assert.equal(lib.isBranchScopeError({ status: 404, message: 'Corte fuera de tu sucursal.' }), false);
  assert.equal(lib.isBranchScopeError({ status: 500, message: 'Sucursal fuera de tu ámbito.' }), false);
  assert.equal(lib.isBranchScopeError(null), false);
});

test('sucursal: branchPageGate bloquea páginas operativas de sucursales no activas', () => {
  const draft = branches[0], active = branches[1];
  assert.equal(lib.branchPageGate({ page: 'dashboard', branch: draft }).blocked, true);
  for (const page of ['inventory', 'finance', 'cuts', 'cash', 'reports', 'incidents']) assert.equal(lib.branchPageGate({ page, branch: draft, canManage: true }).blocked, true, page);
  assert.equal(lib.branchPageGate({ page: 'dashboard', branch: active }).blocked, false);
  assert.equal(lib.branchPageGate({ page: 'branches', branch: draft }).blocked, false);
  assert.equal(lib.branchPageGate({ page: 'users', branch: draft }).blocked, false);
  // páginas de preparación: solo con permiso de administración
  assert.equal(lib.branchPageGate({ page: 'equipment', branch: draft, canManage: true }).blocked, false);
  assert.equal(lib.branchPageGate({ page: 'staff', branch: draft, canManage: false }).blocked, true);
  assert.equal(lib.branchPageGate({ page: 'dashboard', branch: null }).blocked, false);
});

test('sucursal: mensaje de borrador con insignia y botón solo para quien administra', () => {
  const manager = lib.branchNotReadyMarkup({ branch: branches[0], canManage: true });
  assert.match(manager, /Esta sucursal está en preparación \(borrador\)\. Completa la preparación operativa y actívala para ver su operación\./);
  assert.match(manager, /class="pill warn"/);
  assert.match(manager, /Borrador/);
  assert.match(manager, /data-open-onboarding="d1"/);
  assert.doesNotMatch(manager, /NOT_FOUND|HTTP 404|Ref\./);
  const viewer = lib.branchNotReadyMarkup({ branch: branches[0], canManage: false });
  assert.doesNotMatch(viewer, /data-open-onboarding/);
  assert.match(viewer, /Gerente General/);
  const unknown = lib.branchNotReadyMarkup({ branch: null, canManage: true });
  assert.doesNotMatch(unknown, /data-open-onboarding/);
  assert.match(unknown, /no está disponible/);
  assert.match(lib.branchNotReadyMarkup({ branch: { id: 'x', name: '<b>x</b>', status: 'draft' }, canManage: true }), /&lt;b&gt;x&lt;\/b&gt;/);
});

test('sucursal: estado vacío sin sucursales activas con llamada a la acción', () => {
  const html = lib.noActiveBranchesMarkup({ canRead: true, canManage: true });
  assert.match(html, /Aún no hay sucursales activas/);
  assert.match(html, /data-go="branches"/);
  assert.doesNotMatch(lib.noActiveBranchesMarkup({ canRead: false }), /data-go=/);
});

test('error genuino: referencia técnica colapsada en Detalles técnicos', () => {
  const html = lib.errorCardMarkup({ message: 'Fallo <interno>', code: 'BOOM', status: 500, correlationId: 'abc-123' });
  assert.match(html, /<details[^>]*>\s*<summary>Detalles técnicos<\/summary>/);
  assert.match(html, /abc-123/);
  assert.match(html, /Fallo &lt;interno&gt;/);
  assert.ok(html.indexOf('abc-123') > html.indexOf('<details'), 'la referencia solo aparece dentro de details');
  assert.match(html, /id="retry"/);
  assert.doesNotMatch(lib.errorCardMarkup({ message: 'x' }), /<details/);
});

test('panel: app.js usa el estado de sucursal antes de pedir métricas y mapea el 404 de alcance', () => {
  assert.match(app, /branchPageGate\(/);
  assert.match(app, /isBranchScopeError\(e\)/);
  assert.match(app, /errorCardMarkup\(e\)/);
  assert.match(app, /noActiveBranchesMarkup\(/);
  assert.match(app, /pickDefaultBranch\(/);
  assert.doesNotMatch(app, /\/branches\?limit=100&status=active/, 'la lista debe incluir el estado de todas las sucursales');
  assert.doesNotMatch(app, /<p>\$\{esc\(errorSummary\(e\)\)\}<\/p><button class="secondary" id="retry"/);
});
