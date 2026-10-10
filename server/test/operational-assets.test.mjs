import test from 'node:test';
import assert from 'node:assert/strict';
import { OperationalAssetsService } from '../dist/operational-assets/operational-assets.service.js';

const principal = { userId:'4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',organizationId:'2f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e' };
const branch='3f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',assetId='5f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e';
const asset={id:assetId,organization_id:principal.organizationId,branch_id:branch,code:'POS-01',asset_type:'payment_terminal',name:'POS banco A',description:'',manufacturer:null,model:null,serial_number:null,acquired_on:null,acquisition_cost_usd:'180.00',location_label:'Caja principal',custodian_employee_id:null,status:'available',version:1};
const input={commandId:'6f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',code:'pos-01',assetType:'payment_terminal',name:'POS banco A',note:'Registro inicial con etiqueta física.'};

function createService({capabilities=['operational_asset.read','operational_asset.manage','operational_asset.verify','operational_asset.transfer','operational_asset.retire'],poolQuery,clientQuery}={}){
 const client={query:clientQuery??(async()=>({rows:[]})),release(){}};
 const pool={query:poolQuery??(async sql=>String(sql).includes('SELECT id FROM branches')?{rows:[{id:branch}]}:{rows:[]}),connect:async()=>client};
 const auth={capabilities:async()=>capabilities};const audit={appendTransaction:async()=>{}};
 return new OperationalAssetsService(pool,auth,audit);
}

test('operational asset creation snapshots the record and writes its first immutable event', async()=>{
 const calls=[];const service=createService({clientQuery:async(sql,values)=>{calls.push({sql:String(sql),values});return String(sql).includes('INSERT INTO operational_assets')?{rows:[asset]}:{rows:[]};}});
 const result=await service.create(branch,principal,input,'7f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e');
 assert.equal(result.data.id,assetId);assert.equal(result.data.code,'POS-01');assert.equal(result.data.idempotentReplay,false);
 assert.ok(calls.some(x=>x.sql.includes('INSERT INTO operational_asset_events')));
 const event=calls.find(x=>x.sql.includes('INSERT INTO operational_asset_events'));
 assert.equal(event.values[4],'created');assert.equal(event.values[5],null);assert.equal(event.values[6],'available');
});

test('a retried create command returns the original asset without inserting another record',async()=>{
 let writes=0;const service=createService({clientQuery:async sql=>{const q=String(sql);if(q.includes('FROM operational_asset_events WHERE organization_id=$1 AND command_id=$2'))return {rows:[{asset_id:assetId,request_hash:'different',actor_id:principal.userId,asset_version:1,to_status:'available',to_branch_id:branch,to_custodian_employee_id:null}]};if(q.includes('INSERT INTO operational_assets'))writes++;return {rows:[]};}});
 await assert.rejects(service.create(branch,principal,input,'7f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e'),/otros datos/);assert.equal(writes,0);
});

test('stale optimistic version blocks a condition change before writing',async()=>{
 let updated=false;const service=createService({clientQuery:async sql=>{const q=String(sql);if(q.includes('FROM operational_asset_events WHERE organization_id=$1 AND command_id=$2'))return {rows:[]};if(q.includes('FROM operational_assets WHERE id=$1'))return {rows:[{...asset,version:5}]};if(q.includes('UPDATE operational_assets'))updated=true;return {rows:[]};}});
 await assert.rejects(service.changeStatus(branch,assetId,principal,{commandId:'8f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',expectedVersion:4,status:'under_repair',note:'Daño reportado, separar de servicio.'},'7f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e'),/cambió/);
 assert.equal(updated,false);
});

test('asset acquisition cost is omitted unless the caller has the explicit cost permission',async()=>{
 let listSql='',listValues=[];const service=createService({capabilities:['operational_asset.read'],poolQuery:async(sql,values)=>{if(String(sql).includes('SELECT id FROM branches'))return {rows:[{id:branch}]};listSql=String(sql);listValues=values;return {rows:[]};},clientQuery:async()=>({rows:[]})});
 await service.list(branch,principal,{});assert.match(listSql,/CASE WHEN \$3::boolean THEN a\.acquisition_cost_usd/);assert.equal(listValues[2],false);
});

test('profile edits preserve masked acquisition cost and reject unauthorized cost writes',async()=>{
 let values;const service=createService({capabilities:['operational_asset.manage'],clientQuery:async(sql,v)=>{const q=String(sql);if(q.includes('FROM operational_asset_events WHERE organization_id=$1 AND command_id=$2'))return {rows:[]};if(q.includes('FROM operational_assets WHERE id=$1'))return {rows:[asset]};if(q.includes('UPDATE operational_assets SET name=')){values=v;return {rows:[{...asset,name:v[3],version:2}]};}if(q.includes('INSERT INTO operational_asset_events'))return {rows:[]};return {rows:[]};}});
 await service.update(branch,assetId,principal,{commandId:'9f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',expectedVersion:1,name:'POS actualizado',note:'Ficha física revisada y ubicación confirmada.'},'7f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e');assert.equal(values[9],'180.00');
 await assert.rejects(service.update(branch,assetId,principal,{commandId:'af22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',expectedVersion:1,name:'POS actualizado',acquisitionCostUsd:'1.00',note:'Intento de cambiar un dato protegido.'},'7f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e'),/costos/);
});
