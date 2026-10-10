import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const api = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const controller = await readFile(new URL('../../src/staff/staff.controller.ts', import.meta.url), 'utf8');
const service = await readFile(new URL('../../src/staff/staff.service.ts', import.meta.url), 'utf8');
const dto = await readFile(new URL('../../src/staff/staff.dto.ts', import.meta.url), 'utf8');

test('la ficha laboral usa PATCH, alcance de sucursal y permiso privado para contacto', () => {
  const path = api.paths['/branches/{branchId}/staff/employees/{employeeId}']?.patch;
  assert.ok(path);
  assert.equal(path.operationId, 'updateEmployeeProfile');
  assert.equal(path.requestBody.content['application/json'].schema.$ref, '#/components/schemas/UpdateEmployeeProfileRequest');
  assert.equal(api.components.schemas.UpdateEmployeeProfileRequest.properties.expectedVersion.minimum, 1);
  assert.match(controller, /@RequirePermission\('staff\.manage'\) @Patch\('employees\/:employeeId'\)/);
  assert.match(service, /!caps\.includes\('staff\.private\.read'\)/);
  assert.match(service, /current\.version!==input\.expectedVersion/);
  assert.match(service, /current\.status==='terminated'/);
  assert.match(dto, /export class UpdateEmployeeProfileDto/);
});
