import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
let source=await readFile(new URL('../src/maintenance/maintenance.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\n/gm,'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(n=>`class ${n} extends Error {}`).join('\n')+'\n'+source;
const {MaintenanceService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111';
function fixture(){
 const calls=[],permissions=['maintenance.plan','maintenance.work','maintenance.verify','maintenance.release'];
 const query=async(sql,values)=>{
  calls.push({sql,values});
  if(sql.startsWith('SELECT 1 FROM branches'))return {rows:[{}]};
  if(sql.startsWith('SELECT * FROM release_maintenance_block'))return {rows:[{block_id:id,remaining_blocks:1,can_operate:false}]};
  if(sql.startsWith('SELECT * FROM advance_work_order'))return {rows:[{order_id:id,status:values[5],version:values[4]+1}]};
  if(sql.startsWith('INSERT INTO equipment_observations'))return {rows:[{id}]};
  return {rows:[]};
 };
 const pool={query,connect:async()=>({query,release(){}})};
 return {service:new MaintenanceService(pool,{capabilities:async()=>permissions},{appendTransaction:async()=>{}}),calls,permissions,p:{organizationId:id,userId:id}};
}
test('unknown sensor reading is null; numeric zero requires unit',async()=>{
 const f=fixture();await assert.rejects(f.service.observe(id,f.p,{assetProfileId:id,metric:'water_level',outcome:'unknown',source:'manual',value:'0',unit:'liter',observedAt:'2026-10-07T12:00:00Z'},id),/lectura ausente/);
 const result=await f.service.observe(id,f.p,{assetProfileId:id,metric:'water_level',outcome:'unknown',source:'manual',observedAt:'2026-10-07T12:00:00Z'},id);
 assert.equal(result.data.value,null);
 assert.equal(f.calls.find(x=>x.sql.startsWith('INSERT INTO equipment_observations')).values[5],null);
});
test('release returns remaining blocks and does not claim an asset is operating',async()=>{
 const f=fixture();const result=await f.service.release(id,id,f.p,{blockId:id,reason:'Prueba técnica aprobada'},id);
 assert.equal(result.data.canOperate,false);assert.equal(result.data.remainingBlocks,1);
 f.permissions.splice(f.permissions.indexOf('maintenance.release'),1);
 await assert.rejects(f.service.release(id,id,f.p,{blockId:id,reason:'Prueba técnica aprobada'},id),/Permiso/);
});
test('verification checks its own permission and optimistic version',async()=>{
 const f=fixture();const result=await f.service.advance(id,id,f.p,{expectedVersion:3,nextStatus:'verified'},id);
 assert.equal(result.data.version,4);
 f.permissions.splice(f.permissions.indexOf('maintenance.verify'),1);
 await assert.rejects(f.service.advance(id,id,f.p,{expectedVersion:3,nextStatus:'verified'},id),/Permiso/);
});
