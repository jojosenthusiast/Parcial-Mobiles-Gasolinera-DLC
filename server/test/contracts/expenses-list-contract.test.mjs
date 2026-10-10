import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const controller = await readFile(new URL('../../src/finance/expenses.controller.ts', import.meta.url), 'utf8');
const service = await readFile(new URL('../../src/finance/expenses.service.ts', import.meta.url), 'utf8');
const incidentController = await readFile(new URL('../../src/incidents/incidents.controller.ts', import.meta.url), 'utf8');
const incidentService = await readFile(new URL('../../src/incidents/incidents.service.ts', import.meta.url), 'utf8');
const maintenanceController = await readFile(new URL('../../src/maintenance/maintenance.controller.ts', import.meta.url), 'utf8');
const maintenanceService = await readFile(new URL('../../src/maintenance/maintenance.service.ts', import.meta.url), 'utf8');
const web = await readFile(new URL('../../../web/public/app.js', import.meta.url), 'utf8');

test('expenses listing exposes bounded cursor, status, date, and literal text search', () => {
  const operation = spec.paths['/branches/{branchId}/finance/expenses']?.get;
  assert.ok(operation);
  const parameters = new Map(operation.parameters.map(parameter => [parameter.name, parameter]));
  assert.equal(parameters.get('q').schema.maxLength, 100);
  assert.ok(parameters.has('from'));
  assert.ok(parameters.has('to'));
  assert.ok(parameters.has('status'));
  assert.ok(parameters.has('cursor'));
  assert.match(controller, /q\?:string;cursor\?:string/);
  assert.match(service, /term\.length>100/);
  assert.match(service, /replaceAll\('%','!%'\)/);
  assert.match(service, /replaceAll\('_','!_'\)/);
});

test('incident list contract supports server-side search and stable cursor pagination', () => {
  const operation = spec.paths['/branches/{branchId}/incidents']?.get;
  assert.ok(operation);
  const parameters = new Map(operation.parameters.map(parameter => [parameter.name, parameter]));
  assert.equal(parameters.get('q').schema.maxLength, 100);
  assert.equal(parameters.get('cursor').schema.format, 'uuid');
  assert.match(incidentController, /@Query\('cursor'\)/);
  assert.match(incidentService, /reported_at,i\.id/);
  assert.match(incidentService, /replaceAll\('%','!%'\)/);
});

test('incident page uses persisted server filters and cursor continuation', () => {
  assert.match(web, /saveFilter\('incidents\.query'/);
  assert.match(web, /p\.set\('q',\$\('#incident-search'\)\.value\.trim\(\)\)/);
  assert.match(web, /incidentCursor\)/);
  assert.match(web, /Mostrar más incidencias/);
});

test('maintenance orders expose bounded search, status and cursor pagination', () => {
  const operation = spec.paths['/branches/{branchId}/maintenance/orders']?.get;
  assert.ok(operation);
  const parameters = new Map(operation.parameters.map(parameter => [parameter.name, parameter]));
  assert.equal(parameters.get('q').schema.maxLength, 100);
  assert.equal(parameters.get('cursor').schema.format, 'uuid');
  assert.equal(parameters.get('limit').schema.maximum, 100);
  assert.match(maintenanceController, /@Query\('cursor'\)/);
  assert.match(maintenanceService, /concat_ws\(' ',a\.asset_type,a\.asset_id,w\.kind/);
  assert.match(maintenanceService, /nextCursor:r\.rows\.length>limit/);
  assert.match(web, /saveFilter\('maintenance\.status'/);
  assert.match(web, /work-order-more/);
});

test('finance page persists filters, searches on the server, and loads later pages', () => {
  assert.match(web, /saveFilter\('finance\.from'/);
  assert.match(web, /saveFilter\('finance\.to'/);
  assert.match(web, /saveFilter\('finance\.status'/);
  assert.match(web, /saveFilter\('finance\.query'/);
  assert.match(web, /expenseParams\(expenseCursor\)/);
  assert.match(web, /expense-more/);
  assert.match(web, /finance\/expenses\?\$\{expenseParams\(\)\}/);
});
