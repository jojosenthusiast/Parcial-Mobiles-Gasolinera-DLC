import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

let source=await readFile(new URL('../src/sales/sales.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\r?\n/gm,line=>line.includes('node:crypto')?line:'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(name=>`class ${name} extends Error {}`).join('\n')+'\n'+source;
const {SalesService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));

const org='11111111-1111-4111-8111-111111111111';
const branch='22222222-2222-4222-8222-222222222222';
const fuel='33333333-3333-4333-8333-333333333333';
const pos='44444444-4444-4444-8444-444444444444';
const receipt='55555555-5555-4555-8555-555555555555';
const command='66666666-6666-4666-8666-666666666666';

function fixture(){
 const state={caps:['sale.create','sale.read'],commands:new Map(),group:null,insertions:0,audits:0,commits:0,rollbacks:0,locks:[],calls:[],source:[
  {id:fuel,authorization_id:'77777777-7777-4777-8777-777777777777'},
  {id:pos,authorization_id:null}
 ]};
 const query=async(sql,values=[])=>{
  state.calls.push(sql);
  if(sql==='BEGIN'||sql==='COMMIT'||sql==='ROLLBACK'){
   if(sql==='COMMIT')state.commits++;if(sql==='ROLLBACK')state.rollbacks++;return {rows:[]};
  }
  if(sql.includes('pg_advisory_xact_lock')){state.locks.push(values[0]);return {rows:[]};}
  if(sql.includes('FROM branches'))return {rows:[{id:branch}],rowCount:1};
  if(sql.startsWith('SELECT id,request_hash,created_by FROM combined_internal_receipts')){
   const row=state.commands.get(values[1]);return {rows:row?[row]:[]};
  }
  if(sql.includes('FROM sales WHERE organization_id=$1 AND branch_id=$2 AND id=ANY'))return {rows:state.source};
  if(sql.includes('INSERT INTO combined_internal_receipts')){
   state.insertions++;state.group={id:receipt,fuelSaleId:values[2],posSaleId:values[3],request_hash:values[5],created_by:values[6]};
   state.commands.set(values[4],{id:receipt,request_hash:values[5],created_by:values[6]});return {rows:[{id:receipt}]};
  }
  if(sql.includes('FROM combined_internal_receipts c JOIN sales'))return {rows:[{
   id:receipt,fuelSaleId:fuel,posSaleId:pos,createdAt:new Date('2026-10-08T12:00:00Z'),createdBy:org,correlationId:org,totalUsd:'19.57',
   fuelStatus:'pending_collection',posStatus:'pending_collection',fuelCollectedUsd:'0.00',posCollectedUsd:'0.00',fuelReservedUsd:'0.00',posReservedUsd:'0.00',collectionStatus:'pending_collection'
  }]};
  if(sql.includes('FROM sales s LEFT JOIN sale_tax_snapshots'))return {rows:[{
   id:values[0],branchId:branch,authorizationId:values[0]===fuel?'77777777-7777-4777-8777-777777777777':null,
   status:'pending_collection',currency:'USD',totalUsd:values[0]===fuel?'10.57':'9.00',collectedUsd:'0.00',outstandingUsd:values[0]===fuel?'10.57':'9.00',reservedUsd:'0.00',
   taxStatus:'unconfigured',netUsd:null,taxUsd:null,taxPolicyVersionId:null,taxComponents:[],receiptType:'internal',version:1,occurredAt:new Date('2026-10-08T11:00:00Z'),createdAt:new Date('2026-10-08T11:00:00Z'),createdBy:org,correlationId:org
  }]};
  if(sql.startsWith('SELECT id,kind,description'))return {rows:[{id:values[0],kind:values[0]===fuel?'fuel':'store',description:values[0]===fuel?'Regular':'Bebida',totalUsd:values[0]===fuel?'10.57':'9.00',costQuality:'restricted'}]};
  throw new Error(`Unhandled SQL: ${sql}`);
 };
 const pool={query,connect:async()=>({query,release(){}})};
 const service=new SalesService(pool,{capabilities:async()=>state.caps},{appendTransaction:async()=>{state.audits++;}});
 const principal={userId:org,organizationId:org};
 return {state,service,principal,create:(id=command,fuelId=fuel,posId=pos)=>service.createCombinedReceipt(branch,principal,{commandId:id,fuelSaleId:fuelId,posSaleId:posId},org)};
}

test('creates one internal combined receipt with separate source totals and tax states',async()=>{
 const f=fixture();const result=await f.create();
 assert.equal(result.data.id,receipt);assert.equal(result.data.receiptType,'internal_combined');
 assert.equal(result.data.fiscalStatus,'not_fiscal');assert.equal(result.data.totalUsd,'19.57');
 assert.equal(result.data.components.fuel.totalUsd,'10.57');assert.equal(result.data.components.pos.totalUsd,'9.00');
 assert.equal(result.data.components.fuel.taxStatus,'unconfigured');assert.equal(result.data.components.pos.taxStatus,'unconfigured');
 assert.equal(f.state.insertions,1);assert.equal(f.state.audits,1);assert.equal(f.state.commits,1);
 assert.ok(f.state.locks.some(lock=>lock.includes('sale-collection:')));
});

test('retry of the same command returns the original combined receipt without duplicate audit',async()=>{
 const f=fixture();await f.create();const result=await f.create();
 assert.equal(result.data.idempotentReplay,true);assert.equal(f.state.insertions,1);assert.equal(f.state.audits,1);
});

test('command reuse with another pair and same-source pair are rejected before insertion',async()=>{
 const f=fixture();await f.create();await assert.rejects(f.create(command,pos,fuel),/otras ventas/);
 await assert.rejects(f.create('66666666-6666-4666-8666-666666666667',fuel,fuel),/UUID distintos/);
 assert.equal(f.state.insertions,1);
});

test('a receipt needs one fuel ticket and one POS ticket inside the branch scope',async()=>{
 for(const source of [[],[{id:fuel,authorization_id:null},{id:pos,authorization_id:null}],
  [{id:fuel,authorization_id:'77777777-7777-4777-8777-777777777777'},{id:pos,authorization_id:'88888888-8888-4888-8888-888888888888'}]]){
  const f=fixture();f.state.source=source;await assert.rejects(f.create(),/no existe|requiere una venta/);assert.equal(f.state.insertions,0);
 }
});

test('authorization is checked on initial creation and replay',async()=>{
 const f=fixture();await f.create();f.state.caps=[];
 const before=f.state.calls.length;await assert.rejects(f.create(),/No tienes permiso/);assert.equal(f.state.calls.length,before);
});
