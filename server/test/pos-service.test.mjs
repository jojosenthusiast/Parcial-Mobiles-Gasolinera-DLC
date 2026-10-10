import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
let source=await readFile(new URL('../src/sales/pos.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\n/gm,line=>line.includes('node:crypto')?line:'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(name=>`class ${name} extends Error {}`).join('\n')+'\n'+source;
const {PosService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
function fixture(){
 const state={capabilities:['pos.catalog.manage','pos.catalog.read','pos.stock.receive','sale.create','sale.read'],calls:[],audits:[],offer:null,lot:null,sale:null,current:id,productKind:'store',currentCost:'3.50000000',detail:null,rows:[],categories:['Lubricantes y fluidos','Surtido rápido']};
 const query=async(sql,values=[])=>{
  state.calls.push({sql,values});
  if(['BEGIN','COMMIT','ROLLBACK'].includes(sql)||sql.includes('pg_advisory'))return {rows:[]};
  if(sql.startsWith('SELECT id FROM branches'))return {rows:[{id}],rowCount:1};
  if(sql.startsWith('SELECT id,product_id'))return {rows:state.offer?[state.offer]:[]};
  if(sql.startsWith('SELECT id,request_hash'))return {rows:state.lot?[state.lot]:[]};
  if(sql.startsWith('SELECT id,created_by'))return {rows:state.sale?[state.sale]:[]};
  if(sql.startsWith('SELECT id,sku'))return {rows:[{id,sku:'OIL',kind:state.productKind,expiry_required:false}]};
  if(sql.startsWith('SELECT id,service_unit_cost'))return {rows:[{id:state.current,service_unit_cost_usd:state.currentCost}]};
  if(sql.startsWith('INSERT INTO pos_products'))return {rows:[{id}]};
  if(sql.startsWith('INSERT INTO store_catalog_products'))return {rows:[{id}]};
  if(sql.startsWith('INSERT INTO branch_assortments'))return {rows:[]};
  if(sql.startsWith('INSERT INTO pos_offer')){state.offer={id:other,product_id:id,request_hash:values[8],created_by:id};return {rows:[{id:other}]};}
  if(sql.startsWith('INSERT INTO pos_stock_lots')){state.lot={id:other,request_hash:values[9],created_by:id};return {rows:[{id:other}]};}
  if(sql.startsWith('SELECT post_pos_sale')){state.sale={id:other,request_hash:values[4],created_by:id};return {rows:[{id:other}]};}
  if(sql.includes('SELECT DISTINCT c.category FROM branch_assortments'))return {rows:state.categories.map(category=>({category}))};
  if(sql.includes('FROM pos_products p JOIN LATERAL')||sql.includes('FROM pos_stock_lots l WHERE'))return {rows:state.rows};
  throw Error('Unexpected SQL '+sql);
 };
 const service=new PosService({query,connect:async()=>({query,release(){}})},{capabilities:async()=>state.capabilities},{appendTransaction:async(_client,event)=>state.audits.push(event)},
 {detail:async(...args)=>{state.detail=args;return {data:{id:args[1],idempotentReplay:args[4]}};}});
 const principal={userId:id,organizationId:id};
 const offer={commandId:id,sku:' oil ',kind:'store',expiryRequired:false,description:' Motor oil ',active:true,priceUsd:'5.00'};
 const receipt={commandId:id,productId:id,lotCode:'L1',quantity:'3',sourceReference:'Invoice 1'};
 const sale={commandId:id,items:[{productId:id,offerVersionId:id,quantity:'1.000'}]};
 return {state,service,principal,offer,receipt,sale,publish:(body=offer)=>service.publish(id,principal,body,id),receive:(body=receipt)=>service.receive(id,principal,body,id),create:(body=sale)=>service.createSale(id,principal,body,id)};
}
test('catalog normalizes identity and replays equivalent decimal without another publication',async()=>{
 const f=fixture();await f.publish();const r=await f.publish({...f.offer,priceUsd:'5'});assert.equal(r.data.idempotentReplay,true);
 const insert=f.state.calls.find(c=>c.sql.startsWith('INSERT INTO pos_products'));assert.equal(insert.values[2],'OIL');
 assert.equal(f.state.audits.length,1);
});
test('changed command data or actor cannot replay publication',async()=>{
 const f=fixture();await f.publish();await assert.rejects(f.publish({...f.offer,priceUsd:'6'}),/otros datos/);
 await assert.rejects(f.service.publish(id,{...f.principal,userId:other},f.offer,id),/otros datos/);
});
test('quick retail item category is stored in shared store catalog and is part of idempotency',async()=>{
 const f=fixture();await f.publish({...f.offer,category:'Surtido rápido'});
 const insert=f.state.calls.find(c=>c.sql.startsWith('INSERT INTO store_catalog_products'));assert.equal(insert.values[2],'Surtido rápido');
 await assert.rejects(f.publish({...f.offer,category:'Lubricantes'}),/otros datos/);
});

test('catalog edits require current version and preserve product identity',async()=>{
 const f=fixture();f.state.current=other;
 await assert.rejects(f.publish({...f.offer,productId:id,expectedOfferVersionId:id}),/catálogo cambió/);
 f.state.current=id;
 await assert.rejects(f.publish({...f.offer,sku:'DIFFERENT',productId:id,expectedOfferVersionId:id}),/identifican el producto/);
 assert.equal(f.state.calls.some(c=>c.sql.startsWith('INSERT')),false);
});
test('permissions are rechecked for every mutation and read before connecting',async()=>{
 const f=fixture();f.state.capabilities=[];
 for(const work of [()=>f.publish(),()=>f.receive(),()=>f.create(),()=>f.service.catalog(id,f.principal,{}),()=>f.service.lots(id,id,f.principal,{})])await assert.rejects(work(),/No tienes permiso/);
 assert.equal(f.state.calls.length,0);
});
test('receipt retry preserves source and unknown cost without duplicate receipt or audit',async()=>{
 const f=fixture();await f.receive();const r=await f.receive();assert.equal(r.data.idempotentReplay,true);assert.equal(f.state.audits.length,1);
 const insert=f.state.calls.find(c=>c.sql.startsWith('INSERT INTO pos_stock_lots'));assert.equal(insert.values[6],null);
 await assert.rejects(f.receive({...f.receipt,quantity:'4'}),/otros datos/);
});
test('receipt validates real dates, whole units, source and nonnegative explicit costs',async()=>{
 for(const patch of [{quantity:'0'},{quantity:'1.5'},{sourceReference:' '},{expiresOn:'2026-02-30'},{expiresOn:'bad'},{unitCostUsd:'NaN'},{unitCostUsd:'-1'}]) {
  const f=fixture();await assert.rejects(f.receive({...f.receipt,...patch}),/no válid/);assert.equal(f.state.calls.some(c=>c.sql==='BEGIN'),false);
 }
});
test('POS sale uses server posting transaction and replays without a second inventory call',async()=>{
 const f=fixture();await f.create();const r=await f.create({...f.sale,items:[{...f.sale.items[0],quantity:'1'}]});assert.equal(r.data.idempotentReplay,true);
 assert.equal(f.state.calls.filter(c=>c.sql.startsWith('SELECT post_pos_sale')).length,1);assert.equal(f.state.audits.length,1);
 const posted=f.state.calls.find(c=>c.sql.startsWith('SELECT post_pos_sale'));assert.equal(JSON.parse(posted.values[5])[0].quantity,'1');
 assert.equal(f.state.detail[3],'sale.create');
});
test('create-only user cannot replay a ticket owned by another actor',async()=>{
 const f=fixture();await f.create();f.state.capabilities=['sale.create'];
 await assert.rejects(f.service.createSale(id,{...f.principal,userId:other},f.sale,id),/otra persona/);
});
test('empty/oversized baskets, duplicate products and malformed quantities fail before SQL mutation',async()=>{
 for(const items of [[],Array(51).fill({productId:id,offerVersionId:id,quantity:'1'}),[{productId:id,offerVersionId:id,quantity:'0'}],
  [{productId:id,offerVersionId:id,quantity:'1e3'}],[{productId:id,offerVersionId:id,quantity:'NaN'}],[{productId:id,offerVersionId:id,quantity:'1.0001'}],
  [{productId:id,offerVersionId:id,quantity:'1'},{productId:id,offerVersionId:id,quantity:'2'}]]) {
  const f=fixture();await assert.rejects(f.create({...f.sale,items}));assert.equal(f.state.calls.some(c=>c.sql==='BEGIN'),false);
 }
});
test('catalog pagination retains branch/tenant filters and hides cost without permission',async()=>{
 const f=fixture();f.state.rows=[{id},{id:other}];const r=await f.service.catalog(id,f.principal,{q:' oil ',kind:'store',limit:1});
 assert.equal(r.meta.nextCursor,id);const query=f.state.calls.find(c=>c.sql.includes('FROM pos_products p JOIN LATERAL'));
 assert.equal(query.values[0],f.principal.organizationId);assert.equal(query.values[1],id);assert.equal(query.values[2],'oil');assert.equal(query.values[7],false);
});
test('catalog filters by category on the server and exposes branch categories',async()=>{
 const f=fixture();f.state.rows=[{id,category:'Surtido rápido'}];const r=await f.service.catalog(id,f.principal,{category:'Surtido rápido'});
 assert.equal(r.data[0].category,'Surtido rápido');const query=f.state.calls.find(c=>c.sql.includes('FROM pos_products p JOIN LATERAL'));assert.equal(query.values[9],'Surtido rápido');
 const categories=await f.service.categories(id,f.principal);assert.deepEqual(categories.data,f.state.categories);
});

test('malformed catalog filters and lot cursors are rejected',async()=>{
 const f=fixture();for(const query of [{kind:'fuel'},{includeInactive:'yes'},{cursor:'bad'},{limit:0},{limit:101},{q:'a'.repeat(121)}])await assert.rejects(f.service.catalog(id,f.principal,query),/no válid/);
 await assert.rejects(f.service.lots(id,id,f.principal,{cursor:'bad'}),/no válida/);
});

test('consultar productos inactivos requiere permiso de administración del catálogo',async()=>{
 const f=fixture();f.state.capabilities=['pos.catalog.read'];
 await assert.rejects(f.service.catalog(id,f.principal,{includeInactive:'true'}),/No tienes permiso para consultar productos inactivos/);
 assert.equal(f.state.calls.some(c=>c.sql.includes('FROM pos_products p JOIN LATERAL')),false);
});

test('editing a service without a cost field preserves its previous known cost; explicit null clears it',async()=>{
 for(const explicitNull of [false,true]) {
  const f=fixture();f.state.productKind='service';
  await f.publish({...f.offer,kind:'service',productId:id,expectedOfferVersionId:id,...(explicitNull?{serviceUnitCostUsd:null}:{})});
  const insert=f.state.calls.find(c=>c.sql.startsWith('INSERT INTO pos_offer'));
  assert.equal(insert.values[6],explicitNull?null:'3.50000000');
 }
});

test('product master-detail uses the exact tenant/branch/product scope even for inactive products',async()=>{
 const f=fixture();f.state.rows=[{id,active:false}];const result=await f.service.product(id,id,f.principal);assert.equal(result.data.active,false);
 const query=f.state.calls.find(c=>c.sql.includes('FROM pos_products p JOIN LATERAL'));assert.equal(query.values[8],id);assert.equal(query.values[5],true);
 f.state.rows=[];await assert.rejects(f.service.product(id,id,f.principal),/no existe/);
});
