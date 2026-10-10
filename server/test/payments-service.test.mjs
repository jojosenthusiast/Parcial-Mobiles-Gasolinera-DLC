import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
let source=await readFile(new URL('../src/sales/payments.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\r?\n/gm,line=>line.includes('node:crypto')?line:'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(n=>`class ${n} extends Error {}`).join('\n')+'\n'+source;
const {PaymentsService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
function fixture(){
 const state={permissions:['cash.open','cash.read','cash.register.manage','cash.move','cash.close','payment.collect','payment.read','payment.resolve','payment.refund','sale.refund.request'],calls:[],audits:[],rows:new Map(),failure:null,advance:null,paymentAmountUsd:'20.00',refundedUsd:'0.00',activeRefundRequest:false,refundRequestRows:[],saleExists:true};
 const query=async(sql,values=[])=>{
  state.calls.push({sql,values});
  if(sql==='BEGIN'||sql==='COMMIT'||sql==='ROLLBACK'||sql.includes('pg_advisory'))return {rows:[]};
  if(sql.startsWith('SELECT id FROM branches'))return {rows:[{id}],rowCount:1};
  if(sql.startsWith('SELECT id FROM sales'))return {rows:state.saleExists?[{id:values[0]}]:[],rowCount:state.saleExists?1:0};
  if(sql.includes('FROM payment_events e JOIN payment_attempts a')&&sql.includes('FOR UPDATE OF e,a'))return {rows:[{mode:'manual',payment_amount_usd:state.paymentAmountUsd}],rowCount:1};
  if(sql.includes('SELECT coalesce(sum(amount_usd),0)::text AS refunded_usd FROM payment_refunds WHERE payment_event_id'))return {rows:[{refunded_usd:state.refundedUsd}],rowCount:1};
  if(sql.startsWith('SELECT EXISTS(')&&sql.includes('FROM approval_requests q'))return {rows:[{active:state.activeRefundRequest}],rowCount:1};
  if(sql.includes('FROM approval_requests q JOIN payment_events e'))return {rows:state.refundRequestRows,rowCount:state.refundRequestRows.length};
  if(sql.startsWith('SELECT id FROM cash_sessions'))return {rows:[{id}],rowCount:1};
  if(sql.includes('FROM cash_movements m WHERE m.session_id='))return {rows:[
   {id,kind:'deposit',deltaUsd:'-5.00',reason:'Banco',createdAt:'2026-10-07T00:00:00.000Z'},
   {id:other,kind:'cash_in',deltaUsd:'2.00',reason:'Entrada',createdAt:'2026-10-06T23:00:00.000Z'}
  ]};
  if(/SELECT[\s\S]+FROM prepayment_advances/i.test(sql))return {rows:state.advance?[state.advance]:[],rowCount:state.advance?1:0};
  if(sql.startsWith('SELECT s.id FROM cash_sessions'))return {rows:values.includes(id)?[{id}]:[],rowCount:values.includes(id)?1:0};
  if(sql.startsWith('SELECT id,organization_id,branch_id,requested_by,action')&&sql.includes('FROM approval_requests')){
   const row=state.rows.get('approval_requests');const match=row?.id===values[0];return {rows:match?[row]:[],rowCount:match?1:0};
  }
  if(sql.includes('request_hash')&&sql.startsWith('SELECT id,')){const table=sql.match(/FROM (\w+)/)[1];const row=state.rows.get(table);return {rows:row?.command_id===values[1]||row?.id===values[0]?[row]:[]};}
 if(sql.startsWith('SELECT mode FROM payment_attempts')||sql.startsWith('SELECT a.mode'))return {rows:[{mode:'manual'}]};
  if(sql.startsWith('INSERT INTO')){
   if(state.failure)throw Object.assign(new Error('PG failed'),{code:state.failure});
   if(sql.startsWith('INSERT INTO approval_requests')&&sql.includes("'sale.refund.approve'")){
    const columns=sql.match(/\(([^)]+)\)/)[1].split(',').map(column=>column.trim());
    const tokens=sql.match(/\bVALUES\s*\(([^)]*)\)/i)[1].split(',').map(token=>token.trim());
    const row=Object.fromEntries(columns.map((column,index)=>{
     const parameter=tokens[index].match(/^\$(\d+)(?:::[\w.]+)?$/);
     const literal=tokens[index].match(/^'((?:''|[^'])*)'$/);
     return [column,parameter?values[Number(parameter[1])-1]:literal?literal[1].replace(/''/g,"'"):tokens[index]==='NULL'?null:undefined];
    }));
    row.id??=other;row.payload=JSON.parse(row.payload);state.rows.set('approval_requests',row);
    return {rows:[{id:row.id}],rowCount:1};
   }
   const table=sql.match(/INSERT INTO (\w+)/)[1];
   const columns=sql.match(/\(([^)]+)\)/)[1].split(',');
   if(!sql.includes("'sale.refund.approve'")){
    const row=Object.fromEntries(columns.map((c,i)=>[c,values[i]]));row.id??=other;row.created_by??=row.cashier_id;state.rows.set(table,row);
   }
   return {rows:[{id:other}],rowCount:1};
  }
  if(sql.startsWith('SELECT id,expected_cash'))return {rows:[{id:other,expectedCashUsd:'220.00',expectedCardUsd:'80.00',varianceCashUsd:'0.00',varianceCardUsd:'0.00',reviewStatus:'balanced'}]};
  if(sql.startsWith('SELECT id,organization_id')||sql.startsWith('SELECT id,code'))return {rows:[]};
  throw new Error('Unexpected query '+sql);
 };
 const service=new PaymentsService({query,connect:async()=>({query,release(){}})},{capabilities:async()=>state.permissions},{appendTransaction:async(_c,a)=>state.audits.push(a)});
 const p={userId:id,organizationId:id,branchId:id};
 const body={commandId:id,saleId:id,cashSessionId:id,method:'cash',mode:'manual',amountUsd:'20',outcome:'confirmed'};
 return {state,service,p,body,collect:(b=body)=>service.collect(id,p,b,id)};
}
function insertedValue(call,column){
 const columns=call.sql.match(/\(([^)]+)\)/)?.[1].split(',').map(value=>value.trim())??[];
 const tokens=call.sql.match(/\bVALUES\s*\(([^)]*)\)/i)?.[1].split(',').map(value=>value.trim())??[];
 const index=columns.indexOf(column);
 if(index<0)return undefined;
 const parameter=tokens[index]?.match(/^\$(\d+)/);
 return parameter?call.values[Number(parameter[1])-1]:undefined;
}
function advanceRefundFixture({tenderKind='captured',method='cash',outcome='confirmed',allocatedUsd='17.00'}={}){
 const f=fixture();
 f.state.advance={id:other,organization_id:id,branch_id:id,amount_usd:'20.00',amountUsd:'20.00',allocated_usd:allocatedUsd,allocatedUsd,outcome,tender_kind:tenderKind,tenderKind,method,mode:'manual',disposition:null};
 return f;
}
test('cash collection persists attempt/event atomically and audit once',async()=>{
 const f=fixture();await f.collect();const r=await f.collect({...f.body,amountUsd:'20.00'});
 assert.equal(r.data.idempotentReplay,true);assert.equal(f.state.audits.length,1);
 assert.equal(f.state.calls.filter(c=>c.sql.startsWith('INSERT INTO payment_attempts')).length,1);
 assert.equal(f.state.calls.filter(c=>c.sql.startsWith('INSERT INTO payment_events')).length,1);
 assert.equal(f.state.calls.find(c=>c.sql.startsWith('INSERT INTO payment_attempts')).values[5],'20.00');
});
test('changed amount, method, sale, actor or branch cannot replay payment',async()=>{
 const f=fixture();await f.collect();
 for(const patch of [{amountUsd:'21'},{saleId:other},{method:'card',evidenceReference:'REF'}])await assert.rejects(f.collect({...f.body,...patch}),/otros datos/);
 await assert.rejects(f.service.collect(id,{...f.p,userId:other},f.body,id),/otros datos/);
 await assert.rejects(f.service.collect(other,f.p,f.body,id),/otros datos/);
});
test('every action rechecks scoped permissions before querying or connecting',async()=>{
 const f=fixture();f.state.permissions=[];
 for(const work of [()=>f.collect(),()=>f.service.open(id,f.p,{commandId:id,registerId:id,openingUsd:'0'},id),()=>f.service.move(id,id,f.p,{},id),()=>f.service.close(id,id,f.p,{},id),()=>f.service.refund(id,id,f.p,{},id),()=>f.service.resolve(id,id,f.p,{},id),()=>f.service.requestRefund(id,id,f.p,{},id),()=>f.service.registers(id,f.p),()=>f.service.payments(id,id,f.p),()=>f.service.refundRequests(id,id,f.p)])await assert.rejects(work(),/No tienes permiso/);
 assert.equal(f.state.calls.length,0);
});
test('invalid money, ids, method and zero payments fail before BEGIN',async()=>{
 for(const patch of [{amountUsd:'0'},{amountUsd:'-1'},{amountUsd:'1.001'},{amountUsd:'NaN'},{amountUsd:'1e2'},{amountUsd:'1000000000'},{saleId:'bad'},{method:'transfer'},{outcome:'paid'}]){
  const f=fixture();await assert.rejects(f.collect({...f.body,...patch}));assert.equal(f.state.calls.some(c=>c.sql==='BEGIN'),false);
 }
});
test('cash is manual and confirmed, never simulated/unknown/declined',async()=>{
 for(const patch of [{mode:'simulated'},{outcome:'unknown'},{outcome:'declined'}]){const f=fixture();await assert.rejects(f.collect({...f.body,...patch}),/efectivo/);}
});
test('manual card terminal result requires documentary source',async()=>{
 const f=fixture();await assert.rejects(f.collect({...f.body,method:'card'}),/referencia/);
 await f.collect({...f.body,method:'card',evidenceReference:' Terminal 123 '});
 assert.equal(f.state.calls.find(c=>c.sql.startsWith('INSERT INTO payment_events')).values[4],'Terminal 123');
});
test('unknown manual card persists uncertainty instead of a paid result',async()=>{
 const f=fixture();await f.collect({...f.body,method:'card',outcome:'unknown'});
 assert.equal(f.state.calls.find(c=>c.sql.startsWith('INSERT INTO payment_events')).values[3],'unknown');
});
test('simulator evidence is explicit, deterministic and never supplied by caller',async()=>{
 const f=fixture();await f.collect({...f.body,method:'card',mode:'simulated',outcome:'declined',evidenceReference:'pretend real'});
 assert.equal(f.state.calls.find(c=>c.sql.startsWith('INSERT INTO payment_events')).values[4],`SIMULATED:${id}:declined`);
});
test('production blocks simulated collection and replay before BEGIN',async()=>{
 const old=process.env.NODE_ENV;process.env.NODE_ENV='production';
 try{const f=fixture();await assert.rejects(f.collect({...f.body,method:'card',mode:'simulated'}),/producción/);assert.equal(f.state.calls.some(c=>c.sql==='BEGIN'),false);}
 finally{if(old===undefined)delete process.env.NODE_ENV;else process.env.NODE_ENV=old;}
});
test('database failure rolls back without audit and maps domain constraint',async()=>{
 const f=fixture();f.state.failure='23514';await assert.rejects(f.collect(),/Revisa saldo/);
 assert.equal(f.state.calls.at(-1).sql,'ROLLBACK');assert.equal(f.state.audits.length,0);
});
test('opening uses cashier ownership and canonical fund for idempotent retry',async()=>{
 const f=fixture();const b={commandId:id,registerId:id,openingUsd:'100'};
 await f.service.open(id,f.p,b,id);const r=await f.service.open(id,f.p,{...b,openingUsd:'100.00'},id);
 assert.equal(r.data.idempotentReplay,true);assert.equal(f.state.calls.filter(c=>c.sql.startsWith('INSERT INTO cash_sessions')).length,1);
 assert.ok(f.state.calls.some(c=>c.sql.includes('cashier_id AS created_by')));
});
test('deposit is a negative cash movement, never an expense or a sale',async()=>{
 const f=fixture();await f.service.move(id,id,f.p,{commandId:id,kind:'deposit',amountUsd:'50',reason:' Bank '},id);
 const insert=f.state.calls.find(c=>c.sql.startsWith('INSERT INTO cash_movements'));assert.equal(insert.values[4],'-50.00');assert.equal(insert.values[5],'Bank');
 assert.equal(f.state.calls.some(c=>c.sql.startsWith('INSERT INTO sales')||c.sql.startsWith('INSERT INTO expenses')),false);
});
test('closure returns database-computed variance and distinguishes card settlement',async()=>{
 const f=fixture();const r=await f.service.close(id,id,f.p,{commandId:id,countedCashUsd:'220',settledCardUsd:'80'},id);
 assert.equal(r.data.expectedCashUsd,'220.00');assert.equal(r.data.expectedCardUsd,'80.00');assert.equal(r.data.reviewStatus,'balanced');
});
test('negative card settlement supports refund-only sessions without negative cash counts',async()=>{
 const f=fixture();await f.service.close(id,id,f.p,{commandId:id,countedCashUsd:'0',settledCardUsd:'-30'},id);
 assert.equal(f.state.calls.find(c=>c.sql.startsWith('INSERT INTO cash_closures')).values[4],'-30.00');
});
test('cash movement history requires a scoped session and returns a stable next cursor',async()=>{
 const f=fixture();const result=await f.service.cashMovements(id,id,f.p,{kind:'deposit',limit:'1'});
 assert.equal(result.data.length,1);assert.deepEqual(result.nextCursor,{beforeAt:'2026-10-07T00:00:00.000Z',beforeId:id});
 const query=f.state.calls.find(call=>call.sql.includes('FROM cash_movements m WHERE m.session_id='));
 assert.deepEqual(query.values,[id,id,id,'deposit',null,null,2]);
 await assert.rejects(f.service.cashMovements(id,id,f.p,{beforeAt:'2026-10-07T00:00:00Z'}),/cursor requiere fecha/);
 await assert.rejects(f.service.cashMovements(id,id,f.p,{kind:'fake'}),/Tipo de movimiento/);
});
test('refund requires approval identity and never posts physical inventory from API',async()=>{
 const f=fixture();const b={approvalId:other,commandId:id,cashSessionId:id,amountUsd:'3',reason:'Remaining balance'};
 await f.service.refund(id,id,f.p,b,id);const r=await f.service.refund(id,id,f.p,{...b,amountUsd:'3.00'},id);
 assert.equal(r.data.idempotentReplay,true);assert.equal(f.state.calls.filter(c=>c.sql.startsWith('INSERT INTO payment_refunds')).length,1);
 assert.equal(f.state.calls.some(c=>c.sql.includes('inventory_movements')),false);
 const refund=f.state.calls.find(c=>c.sql.startsWith('INSERT INTO payment_refunds'));
 assert.equal(refund.values[11],other);
 const columns=refund.sql.match(/\(([^)]+)\)/)?.[1].split(',').map(column=>column.trim())??[];
 assert.ok(columns.includes('payment_event_id'),'existing sale refund must retain its payment-event source');
 assert.equal(columns.includes('advance_id'),false,'sale refund path must not switch to the advance source');
});
test('refund request binds original payment, normalized amount, actor and reason',async()=>{
 const f=fixture();const input={commandId:id,amountUsd:'3',reason:' Remainder '};await f.service.requestRefund(id,other,f.p,input,id);
 const replay=await f.service.requestRefund(id,other,f.p,{...input,amountUsd:'3.00',reason:'Remainder'},id);assert.equal(replay.data.idempotentReplay,true);
 const insert=f.state.calls.find(c=>c.sql.startsWith('INSERT INTO approval_requests'));assert.equal(insert.values[3],other);assert.equal(insert.values[4],id);assert.deepEqual(JSON.parse(insert.values[5]),{amountUsd:'3.00',reason:'Remainder'});
 assert.equal(f.state.calls.filter(call=>call.sql.startsWith('INSERT INTO approval_requests')).length,1);
 assert.ok(f.state.calls.some(call=>call.sql.includes('FOR UPDATE OF e,a')),'the confirmed payment must be locked while validating the refund request');
 assert.ok(f.state.calls.some(call=>call.values.includes(`refund-payment:${other}`)),'refund requests serialize against other financial commands for this payment');
 f.state.rows.get('approval_requests').entity_type='other';
 await assert.rejects(f.service.requestRefund(id,other,f.p,{...input,amountUsd:'3.00',reason:'Remainder'},id),/otros datos/);
});

test('refund request cannot exceed the remaining paid balance or coexist with an active request',async()=>{
 const over=fixture();
 over.state.refundedUsd='18.00';
 await assert.rejects(over.service.requestRefund(id,other,over.p,{commandId:id,amountUsd:'3.00',reason:'Too much'},id),/saldo reembolsable/);
 assert.equal(over.state.calls.some(call=>call.sql.startsWith('INSERT INTO approval_requests')),false);
 const duplicate=fixture();duplicate.state.activeRefundRequest=true;
 await assert.rejects(duplicate.service.requestRefund(id,other,duplicate.p,{commandId:id,amountUsd:'2.00',reason:'Duplicate'},id),/Ya existe una solicitud/);
 assert.equal(duplicate.state.calls.some(call=>call.sql.startsWith('INSERT INTO approval_requests')),false);
});

test('refund request listing is permissioned, sale-scoped, and returns decision and execution fields',async()=>{
 const f=fixture();const row={id:other,paymentEventId:id,method:'card',paymentAmountUsd:'20.00',requestedBy:id,amountUsd:'3.00',reason:'Remainder',status:'pending',decidedBy:null,decidedAt:null,decisionReason:null,createdAt:'2026-10-08T10:00:00.000Z',refundId:null,refundedAt:null};
 f.state.refundRequestRows=[row];
 const result=await f.service.refundRequests(id,other,f.p);
 assert.deepEqual(result.data,[row]);
 const query=f.state.calls.find(call=>call.sql.includes('FROM approval_requests q JOIN payment_events e'));
 assert.deepEqual(query.values,[id,id,other]);assert.match(query.sql,/q\.action='sale\.refund\.approve'/);assert.match(query.sql,/q\.branch_id=\$2/);assert.match(query.sql,/a\.sale_id=\$3/);assert.match(query.sql,/LIMIT 100/);
 const missing=fixture();missing.state.saleExists=false;
 await assert.rejects(missing.service.refundRequests(id,other,missing.p),/La venta no existe/);
 assert.equal(missing.state.calls.some(call=>call.sql.includes('FROM approval_requests q JOIN payment_events e')),false);
});

test('captured advance refund request binds the advance and exact unallocated remainder to approval',async()=>{
 const f=advanceRefundFixture();
 const input={commandId:id,amountUsd:'3.00',reason:'Unused captured advance'};
 const first=await f.service.requestAdvanceRefund(id,other,f.p,input,id);
 const sourceLookup=f.state.calls.find(call=>/SELECT[\s\S]+FROM prepayment_advances/i.test(call.sql));
 assert.ok(sourceLookup?.values.includes(other),'request must load the exact advance source');
 const replay=await f.service.requestAdvanceRefund(id,other,f.p,input,id);
 assert.equal(first.data.idempotentReplay,false);assert.equal(replay.data.idempotentReplay,true);
 const replaySelect=f.state.calls.find(call=>/^SELECT[\s\S]+FROM approval_requests\b/i.test(call.sql));
 assert.deepEqual(replaySelect?.sql.match(/^SELECT\s+([\s\S]+?)\s+FROM/i)?.[1].split(',').map(column=>column.trim()),['id','organization_id','branch_id','requested_by','action','entity_type','entity_id','payload','status'],'approval replay SELECT must project every field checked by replay validation');
 const approval=f.state.calls.find(call=>call.sql.startsWith('INSERT INTO approval_requests'));
 assert.ok(approval,'captured advance refund request must create an approval request');
 assert.equal(insertedValue(approval,'entity_id'),other,'approval must bind to the advance, not a payment event');
 assert.equal(insertedValue(approval,'requested_by'),f.p.userId,'approval must record the original requesting actor');
 assert.deepEqual(JSON.parse(insertedValue(approval,'payload')),{amountUsd:'3.00',reason:'Unused captured advance'});
 assert.equal(f.state.calls.filter(call=>call.sql.startsWith('INSERT INTO approval_requests')).length,1);
});

test('captured advance refund request rejects holds, unconfirmed advances, and amounts above the exact remainder',async()=>{
 for(const options of [{tenderKind:'authorization_hold'},{outcome:'unknown'},{allocatedUsd:'17.00'}]){
  const f=advanceRefundFixture(options);
  await assert.rejects(f.service.requestAdvanceRefund(id,other,f.p,{commandId:id,amountUsd:'3.01',reason:'Unused balance'},id));
  assert.equal(f.state.calls.some(call=>call.sql.startsWith('INSERT INTO approval_requests')),false);
 }
});

test('captured advance refund execution is advance-exclusive, approved, evidenced, replayable, and has no inventory movement',async()=>{
 for(const method of ['cash','card']){
  const f=advanceRefundFixture({method});
  const input={approvalId:id,commandId:id,cashSessionId:id,amountUsd:'3',reason:'Unused balance',evidenceReference:`Original ${method} refund confirmation`};
  const first=await f.service.refundAdvance(id,other,f.p,input,id);
  const replay=await f.service.refundAdvance(id,other,f.p,input,id);
  assert.equal(first.data.idempotentReplay,false);assert.equal(replay.data.idempotentReplay,true);
  const refund=f.state.calls.find(call=>call.sql.startsWith('INSERT INTO payment_refunds'));
  assert.ok(refund,'advance refund must use the payment_refunds ledger');
  assert.ok(refund.sql.includes('advance_id'),'advance must be the refund source');
  assert.equal(refund.sql.includes('payment_event_id'),false,'advance source must be exclusive of payment-event source');
  assert.equal(insertedValue(refund,'advance_id'),other);
  assert.equal(insertedValue(refund,'approval_id'),id,'execution must pass the approved request id');
  assert.equal(insertedValue(refund,'cash_session_id'),id,'execution must bind its cash session');
  assert.equal(insertedValue(refund,'evidence_reference'),input.evidenceReference,'execution must preserve confirmation evidence');
  assert.equal(f.state.calls.filter(call=>call.sql.startsWith('INSERT INTO payment_refunds')).length,1);
  assert.equal(f.state.calls.some(call=>/INSERT INTO\s+cash_movements/i.test(call.sql)),false,'cash movement remains database-triggered');
  assert.equal(f.state.calls.some(call=>/inventory_movements/i.test(call.sql)),false,'a refund must not move fuel inventory');
 }
});

test('authorization holds cannot be refunded as captured advances',async()=>{
 const f=advanceRefundFixture({tenderKind:'authorization_hold',method:'card'});
 await assert.rejects(f.service.refundAdvance(id,other,f.p,{approvalId:id,commandId:id,cashSessionId:id,amountUsd:'3',reason:'Not captured'},id));
 assert.equal(f.state.calls.some(call=>call.sql.startsWith('INSERT INTO payment_refunds')),false);
});
