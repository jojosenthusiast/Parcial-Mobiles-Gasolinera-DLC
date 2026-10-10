import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {createHash} from 'node:crypto';
let source=await readFile(new URL('../src/incidents/incidents.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\n/gm,'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(n=>`class ${n} extends Error {}`).join('\n')+'\nconst createHash=globalThis.__incidentTestHash;\n'+source;
globalThis.__incidentTestHash=createHash;
const {IncidentsService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111';
const input={commandId:'22222222-2222-4222-8222-222222222222',category:'equipment_damage',severity:'high',assetType:'nozzle',assetId:id,description:'Se desprendió la manguera, sin derrame observado.',occurredAt:'2026-10-01T12:00:00.000Z'};
function fixture(){
 let existing=false,hash='';const calls=[],permissions=['incident.create','incident.read','incident.assign','incident.resolve','loss.approve'];
 const query=async(sql,values)=>{
  calls.push({sql,values});
  if(sql.startsWith('SELECT id FROM branches'))return {rows:[{id}]};
  if(sql.startsWith('INSERT INTO incidents(')){
   if(existing)return {rows:[]};existing=true;hash=values.at(-1);return {rows:[{id,code:values[2]}]};
  }
  if(sql.startsWith('SELECT id,code,request_hash'))return {rows:[{id,code:'INC-20261001-22222222',request_hash:hash,branch_id:id}]};
  if(sql.startsWith('SELECT id,code,category'))return {rows:[]};
  if(sql.startsWith('SELECT * FROM incidents'))return {rows:[]};
  if(sql.startsWith('SELECT * FROM advance_incident'))return {rows:[{status:values[5],version:values[4]+1}]};
  if(sql.startsWith('SELECT a.id FROM incident_impact_assessments'))return {rows:[{id}]};
  if(sql.startsWith('SELECT * FROM approve_incident_loss'))return {rows:[{approval_id:id,tank_id:id,quantity_l:'10',movement_id:null}]};
  if(sql.startsWith('INSERT INTO incident_recovery_claims'))return {rows:[{id}]};
  if(sql.startsWith('INSERT INTO incident_recovery_receipts'))return {rows:[{id}]};
  if(sql.startsWith('SELECT outstanding_usd FROM incident_recovery_balances'))return {rows:[{outstanding_usd:'50.00'}]};
  return {rows:[]};
 };
 const pool={query,connect:async()=>({query,release(){}})};
 const inventory={lose:async(_branch,_tank,_principal,command)=>({movement:{id},idempotentReplay:false,command})};
 const service=new IncidentsService(pool,{capabilities:async()=>permissions},{appendTransaction:async()=>{}},inventory);
 return {service,calls,permissions,p:{organizationId:id,userId:id}};
}
test('hose damage reports and replays without inventing inventory movement',async()=>{
 const f=fixture();const first=await f.service.create(id,f.p,input,id);const replay=await f.service.create(id,f.p,input,id);
 assert.deepEqual(replay,first);
 assert.equal(f.calls.filter(x=>x.sql.startsWith('INSERT INTO incident_events')).length,1);
 assert.equal(f.calls.filter(x=>x.sql.startsWith('INSERT INTO asset_blocks')).length,1);
 assert.ok(!f.calls.some(x=>/inventory_movements|loss_assessments/.test(x.sql)));
 await assert.rejects(f.service.create(id,f.p,{...input,description:'Changed damage details, no fuel lost.'},id),/repetido/);
});
test('injury at a branch does not create a fuel loss or block a dispenser',async()=>{
 const f=fixture();await f.service.create(id,f.p,{...input,assetType:'branch',assetId:undefined,category:'personal_injury'},id);
 assert.ok(!f.calls.some(x=>/asset_blocks|inventory_movements/.test(x.sql)));
 const result=await f.service.advance(id,id,f.p,{expectedVersion:1,nextStatus:'assessed',note:'Se asignó la evaluación'},id);
 assert.equal(result.data.status,'assessed');
});
test('incident creation validates branch scope and resource payload',async()=>{
 const f=fixture();await assert.rejects(f.service.create(id,f.p,{...input,assetType:'branch'},id),/Recurso/);
 f.permissions.length=0;await assert.rejects(f.service.create(id,f.p,input,id),/No puedes/);
});
test('approved assessment posts one matching ledger movement and links it',async()=>{
 const f=fixture();const result=await f.service.approveLoss(id,id,id,f.p,{commandId:input.commandId,reason:'Pérdida física comprobada'},id);
 assert.equal(result.data.movementId,id);
 assert.ok(f.calls.some(x=>x.sql.startsWith('SELECT link_incident_loss')));
 assert.ok(!f.calls.some(x=>x.sql.startsWith('INSERT INTO inventory_movements')));
});
test('third-party recovery keeps original damage and tracks outstanding balance',async()=>{
 const f=fixture();const claim=await f.service.createClaim(id,id,f.p,{counterpartyType:'third_party',counterpartyName:'Propietario',reference:'RECLAMO-001',claimedUsd:'100.00'},id);
 assert.equal(claim.data.outstandingUsd,'100.00');
 const receipt=await f.service.receiveRecovery(id,id,id,f.p,{commandId:input.commandId,amountUsd:'50.00',method:'bank_transfer',evidenceReference:'transfer-001'},id);
 assert.equal(receipt.data.outstandingUsd,'50.00');
 assert.ok(!f.calls.some(x=>/inventory_movements/.test(x.sql)));
});

 test('wrong tank delivery cannot bypass the purchase contamination workflow',async()=>{
 const f=fixture();
  await assert.rejects(f.service.create(id,f.p,{...input,category:'wrong_tank_delivery'},id),/Compras.*Descarga contaminante/);
  await assert.rejects(f.service.create(id,f.p,{...input,category:'wrong_tank_delivery',assetType:'tank',severity:'critical'},id),/Compras.*Descarga contaminante/);
  assert.ok(!f.calls.some(x=>/INSERT INTO incidents|INSERT INTO asset_blocks|FROM tanks/.test(x.sql)));
 });
 test('generic incident creation never records a wrong tank delivery as a complete event',async()=>{
 const f=fixture();const data={...input,category:'wrong_tank_delivery',assetType:'tank'};
  await assert.rejects(f.service.create(id,f.p,data,id),/Descarga contaminante/);
  assert.equal(f.calls.filter(x=>x.sql.startsWith('INSERT INTO incidents')).length,0);
  assert.equal(f.calls.filter(x=>x.sql.startsWith('INSERT INTO asset_blocks')).length,0);
 });
