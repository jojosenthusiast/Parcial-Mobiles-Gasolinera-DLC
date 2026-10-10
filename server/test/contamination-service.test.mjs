import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {createHash,randomUUID} from 'node:crypto';
import {Decimal} from 'decimal.js';
let source=await readFile(new URL('../src/procurement/contamination.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\r?\n/gm,'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
globalThis.__contaminationDependencies={Decimal,createHash,randomUUID};
source=`const {Decimal,createHash,randomUUID}=globalThis.__contaminationDependencies;\n`+['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(n=>`class ${n} extends Error {}`).join('\n')+source;
const {ContaminationService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111';
const input={commandId:id,purchaseOrderLineId:id,tankId:id,expectedBalanceVersion:7,actualQuantity:'250',unit:'liter',documentReference:'DEL-1',description:'Se descargó diesel en tanque de gasolina.'};
function fixture({version=7,permission=true,sameFuel=false}={}){
 const calls=[];let recorded=null;
 const query=async(sql,v)=>{
  calls.push({sql,v});
  if(sql.startsWith('SELECT * FROM contaminated_deliveries'))return {rows:recorded?[recorded]:[]};
  if(sql.startsWith('SELECT id,status FROM purchase_orders'))return {rows:[{id,status:'ordered'}]};
  if(sql.startsWith('SELECT * FROM purchase_order_lines'))return {rows:[{id,unit:'liter',quantity_ordered:'3000',received_quantity:'0',fuel_product_id:id,agreed_unit_price_usd:'1.25'}]};
  if(sql.startsWith('SELECT * FROM tanks'))return {rows:[{id,fuel_product_id:sameFuel?id:'22222222-2222-4222-8222-222222222222'}]};
  if(sql.startsWith('SELECT * FROM tank_inventory_balances'))return {rows:[{version,on_hand_l:'4000',valuation_quality:'known',inventory_value_usd:'4000'}]};
  if(sql.includes('COALESCE(sum('))return {rows:[{quantity:'0'}]};
  if(sql.startsWith('INSERT INTO contaminated_deliveries')){recorded={id:v[0],request_hash:v[20],reported_by:v[21],prior_quantity_l:v[9],incoming_quantity_l:v[12],prior_cost_usd:v[13],incoming_cost_usd:v[14],remaining_order_quantity:v[15]};return {rows:[recorded]};}
  return {rows:[]};
 };
 return {calls,service:new ContaminationService({query,connect:async()=>({query,release(){}})},{capabilities:async()=>permission?['purchase.receive']:[]},{appendTransaction:async()=>{}})};
}
test('partial wrong-tank discharge preserves two losses and remainder without normal inventory receipt',async()=>{
 const f=fixture();const r=await f.service.report(id,id,{organizationId:id,userId:id},input,id);
 assert.equal(r.data.prior_quantity_l,'4000');assert.equal(r.data.incoming_quantity_l,'250.000000000');
 assert.equal(r.data.incoming_cost_usd,'312.50000000');assert.equal(r.data.remaining_order_quantity,'2750.000000000');
 assert.ok(f.calls.some(c=>c.sql.startsWith('INSERT INTO asset_blocks')));
 assert.ok(f.calls.some(c=>c.sql==='COMMIT'));
 assert.ok(!f.calls.some(c=>c.sql.includes('INSERT INTO inventory_movements')));
});
test('changed balance and order over-discharge reject atomically',async()=>{
 const f=fixture({version:8});await assert.rejects(f.service.report(id,id,{organizationId:id,userId:id},input,id),/saldo cambió/);
 assert.ok(f.calls.some(c=>c.sql==='ROLLBACK'));
 const g=fixture();await assert.rejects(g.service.report(id,id,{organizationId:id,userId:id},{...input,actualQuantity:'3001'},id),/saldo del pedido/);
 assert.ok(!g.calls.some(c=>c.sql.startsWith('INSERT INTO incidents')));
});
test('scope denial prevents any database write',async()=>{
 const f=fixture({permission:false});await assert.rejects(f.service.report(id,id,{organizationId:id,userId:id},input,id),/permiso/);assert.equal(f.calls.length,0);
});

test('same-fuel delivery is not misclassified as contamination',async()=>{
 const f=fixture({sameFuel:true});await assert.rejects(f.service.report(id,id,{organizationId:id,userId:id},input,id),/coincide/);
 assert.ok(!f.calls.some(c=>c.sql.startsWith('INSERT INTO incidents')));
});

test('network retry replays one snapshot and changed payload conflicts',async()=>{
 const f=fixture();const p={organizationId:id,userId:id};
 const first=await f.service.report(id,id,p,input,id);const retry=await f.service.report(id,id,p,input,id);
 assert.equal(retry.idempotentReplay,true);assert.equal(first.data.id,retry.data.id);
 assert.equal(f.calls.filter(c=>c.sql.startsWith('INSERT INTO asset_blocks')).length,1);
 await assert.rejects(f.service.report(id,id,p,{...input,actualQuantity:'251'},id),/otros datos/);
});
