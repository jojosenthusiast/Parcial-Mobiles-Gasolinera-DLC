import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
let source=await readFile(new URL('../src/sales/sales.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\n/gm,line=>line.includes('node:crypto')?line:'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(name=>`class ${name} extends Error {}`).join('\n')+'\n'+source;
const {SalesService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
function fixture(){
 const state={permission:['sale.create','sale.read'],dispatchStatus:'completed',branchFound:true,dispatchFound:true,lineCount:1,sale:null,lines:[],audits:0,commits:0,rollbacks:0,locks:[],calls:[],inventoryWrites:0};
 let beforeTransaction;
 const query=async(sql,v=[])=>{
  state.calls.push(sql);
  if(sql==='BEGIN'){beforeTransaction={sale:state.sale?{...state.sale}:null,lines:[...state.lines]};return {rows:[]};}
  if(sql==='COMMIT'){state.commits++;return {rows:[]};}
  if(sql==='ROLLBACK'){state.rollbacks++;state.sale=beforeTransaction.sale;state.lines=beforeTransaction.lines;return {rows:[]};}
  if(sql.includes('pg_advisory_xact_lock')){state.locks.push(v[0]);return {rows:[]};}
  if(sql.includes('FROM branches')) return {rows:state.branchFound?[{id}]:[],rowCount:state.branchFound?1:0};
  if(sql.startsWith('SELECT id,request_hash')) return {rows:state.sale?.command===v[1]?[{id:state.sale.id,request_hash:state.sale.hash,created_by:id}]:[]};
  if(sql.startsWith('SELECT id,status'))return {rows:state.dispatchFound?[{id,status:state.dispatchStatus}]:[]};
  if(sql.startsWith('SELECT id FROM sales')) return {rows:state.sale?[{id:state.sale.id}]:[],rowCount:state.sale?1:0};
  if(sql.includes('INSERT INTO sales(')){state.sale={id:other,command:v[3],hash:v[4]};return {rows:[{id:other}],rowCount:1};}
  if(sql.includes('INSERT INTO sale_lines')){state.lines=[{id,quantityL:'10',totalUsd:'10.57'}];return {rows:[],rowCount:state.lineCount};}
  if(sql.includes('FROM sale_tax_snapshots'))return {rows:[]};
  if(sql.includes('FROM sales s LEFT JOIN'))return {rows:state.sale?[{id:state.sale.id,status:'pending_collection',totalUsd:'10.57',taxUsd:null,netUsd:null}]:[]};
  if(sql.startsWith('SELECT id,kind'))return {rows:state.lines.map(l=>({...l,costUsd:v[3]?'5.00000000':null,costQuality:v[3]?'known':'restricted'}))};
  if(sql.includes('FROM sales s JOIN'))return {rows:[{id,occurredAt:new Date('2026-10-06T10:00:00Z'),cursorAt:'2026-10-06 10:00:00.000123+00'},{id:other,occurredAt:new Date('2026-10-06T09:00:00Z'),cursorAt:'2026-10-06 09:00:00+00'}]};
  throw new Error('Unhandled SQL: '+sql);
 };
 const pool={query,connect:async()=>({query,release(){}})};
 const service=new SalesService(pool,{capabilities:async()=>state.permission},{appendTransaction:async()=>{state.audits++;}});
 const principal={userId:id,organizationId:id};
 return {state,service,principal,create:(command=id,authorizationId=id)=>service.createFuelSale(id,principal,{commandId:command,authorizationId},id)};
}
test('completed dispatch becomes one pending ticket; same command replays without another line/audit',async()=>{
 const f=fixture();let r=await f.create();assert.equal(r.data.totalUsd,'10.57');assert.equal(r.data.status,'pending_collection');
 assert.equal(r.data.taxUsd,null);assert.equal(r.data.lines[0].costQuality,'restricted');
 r=await f.create();assert.equal(r.data.idempotentReplay,true);assert.equal(f.state.audits,1);
 assert.equal(f.state.calls.filter(q=>q.includes('INSERT INTO sale_lines')).length,1);
 assert.equal(f.state.calls.some(q=>/INSERT INTO inventory|UPDATE tank_inventory/.test(q)),false);
});
test('a reused command with changed dispatch conflicts before any insertion',async()=>{
 const f=fixture();await f.create();await assert.rejects(f.create(id,other),/otra venta/);
 assert.equal(f.state.calls.filter(q=>q.includes('INSERT INTO sales(')).length,1);assert.equal(f.state.sale.id,other);
});
test('new command cannot ticket an already linked dispatch',async()=>{
 const f=fixture();await f.create();await assert.rejects(f.create(other),/ya tiene una venta/);
});
test('posting, unknown, cancelled, expired and authorized dispatches cannot be sold',async()=>{
 for(const status of ['posting','unknown','interrupted','cancelled','expired','authorized']) {
  const f=fixture();f.state.dispatchStatus=status;await assert.rejects(f.create(),/confirma el despacho/);
  assert.equal(f.state.sale,null);assert.equal(f.state.audits,0);
 }
});
test('scope is enforced by the service before repository mutation, including replay',async()=>{
 const f=fixture();await f.create();f.state.permission=[];const count=f.state.calls.length;
 await assert.rejects(f.create(),/No tienes permiso/);assert.equal(f.state.calls.length,count);
});
test('foreign tenant branch and missing dispatch do not create a ticket',async()=>{
 let f=fixture();f.state.branchFound=false;await assert.rejects(f.create(),/sucursal no existe/);
 f=fixture();f.state.dispatchFound=false;await assert.rejects(f.create(),/despacho no existe/);assert.equal(f.state.sale,null);
});
test('missing inventory source line rolls back the header and skips audit',async()=>{
 const f=fixture();f.state.lineCount=0;await assert.rejects(f.create(),/movimiento confirmado/);
 assert.equal(f.state.sale,null);assert.equal(f.state.audits,0);assert.equal(f.state.rollbacks,1);
});
test('cost snapshot is only returned with finance.cost.read',async()=>{
 const f=fixture();f.state.permission.push('finance.cost.read');const result=await f.create();
 assert.equal(result.data.lines[0].costUsd,'5.00000000');assert.equal(result.data.lines[0].costQuality,'known');
});
test('pagination preserves PostgreSQL microseconds and bounded query metadata',async()=>{
 const f=fixture();const result=await f.service.list(id,f.principal,{limit:1});
 assert.equal(result.meta.limit,1);const cursor=JSON.parse(Buffer.from(result.meta.nextCursor,'base64url').toString());
 assert.equal(cursor.at,'2026-10-06 10:00:00.000123+00');assert.equal('cursorAt' in result.data[0],false);
 await f.service.list(id,f.principal,{limit:1,cursor:result.meta.nextCursor});
});
test('malformed UUIDs, pagination and timestamps fail validation',async()=>{
 const f=fixture();await assert.rejects(f.create('bad'),/UUID/);
 for(const input of [{limit:0},{limit:101},{limit:1.5},{q:'a'.repeat(121)},{cursor:'bad'},
  {cursor:Buffer.from(JSON.stringify({at:'1',id})).toString('base64url')},{cursor:'a'.repeat(2049)}]) {
  await assert.rejects(f.service.list(id,f.principal,input),/no es válido|no válidos/);
 }
});

test('create-only permission cannot replay another actor ticket to read it',async()=>{
 const f=fixture();await f.create();f.state.permission=['sale.create'];
 await assert.rejects(f.service.createFuelSale(id,{...f.principal,userId:other},{commandId:id,authorizationId:id},id),/otro usuario/);
 assert.equal(f.state.sale.id,other);
});
