import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const api=JSON.parse(await readFile(new URL('../../../contracts/openapi.json',import.meta.url),'utf8'));
test('device mutations require a stable command, version and authenticated operation',()=>{
  for(const suffix of ['device-start','device-query']){
    const op=api.paths[`/branches/{branchId}/dispense-authorizations/{authorizationId}/${suffix}`].post;
    assert.ok(op.security.some(s=>s.bearerAuth));assert.match(op.responses['403'].description,/dispense.authorize/);
    assert.equal(op.responses['201'].content['application/json'].schema.$ref,'#/components/schemas/DeviceOperationResponse');
  }
  assert.deepEqual(api.components.schemas.DeviceQuery.required,['commandId','expectedVersion']);
  assert.equal(api.components.schemas.DeviceQuery.additionalProperties,false);
  assert.equal(api.components.schemas.DeviceQuery.properties.scenario,undefined);
});
test('device capability and history cannot claim physical hardware or anonymous access',()=>{
  assert.equal(api.components.schemas.DeviceCapabilities.properties.physicalHardwareConnected.const,false);
  assert.ok(api.paths['/dispense-device/capabilities'].get.security.length);
  assert.ok(api.paths['/branches/{branchId}/dispense-authorizations/{authorizationId}/device-operations'].get.security.length);
  assert.equal(api.components.schemas.DeviceOperationResponse.properties.device.properties.physicalHardwareConnected.const,false);
});
test('all internal OpenAPI schema references resolve',()=>{
  function visit(value){
    if(!value||typeof value!=='object')return;
    if(value.$ref?.startsWith('#/components/schemas/'))assert.ok(api.components.schemas[value.$ref.split('/').at(-1)],value.$ref);
    Object.values(value).forEach(visit);
  }
  visit(api);
});
