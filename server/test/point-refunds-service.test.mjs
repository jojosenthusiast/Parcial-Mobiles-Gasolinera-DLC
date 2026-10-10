import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
let source=(await readFile(new URL('../src/customers/point-refunds.ts',import.meta.url),'utf8')).split("@Controller(")[0];
source=source.replace(/^import .+?;\n/gm,'').replace(/@\w+\([^)]*\)\s*/g,'');
source=['ConflictException','ForbiddenException','NotFoundException'].map(n=>`class ${n} extends Error {}`).join('\n')+source;
const {PointRefundsService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111',sale='22222222-2222-4222-8222-222222222222';
const p={organizationId:id,userId:id};
const input={commandId:id,paymentId:id,points:250,reason:'Devolución parcial de puntos'};
function fixture({allowed=true,inScope=true}={}){
 const calls=[];let saved=null;
 const query=async(sql,v)=>{
  calls.push(sql);
  if(sql.startsWith('SELECT * FROM customer_point_refund_requests'))return {rows:saved?[saved]:[],rowCount:saved?1:0};
  if(sql.startsWith('SELECT 1 FROM customer_point_payments'))return {rows:inScope?[{}]:[],rowCount:inScope?1:0};
  if(sql.startsWith('INSERT INTO customer_point_refund_requests')){saved={id,organization_id:v[0],branch_id:v[1],payment_id:v[2],points:v[3],requested_by:v[4],command_id:v[5],reason:v[6]};return {rows:[saved],rowCount:1};}
  return {rows:[],rowCount:0};
 };
 return {calls,service:new PointRefundsService({connect:async()=>({query,release(){}})},{capabilities:async()=>allowed?['sale.refund.request']:[]},{appendTransaction:async()=>{}})};
}
test('point return request replays one command and rejects changed points',async()=>{
 const f=fixture();await f.service.write(id,sale,p,input,id,false);
 const replay=await f.service.write(id,sale,p,input,id,false);assert.equal(replay.idempotentReplay,true);
 assert.equal(f.calls.filter(s=>s.startsWith('INSERT INTO customer_point_refund_requests')).length,1);
 await assert.rejects(f.service.write(id,sale,p,{...input,points:251},id,false),/otros datos/);
});
test('foreign sale cannot receive a point return request',async()=>{
 const f=fixture({inScope:false});await assert.rejects(f.service.write(id,sale,p,input,id,false),/fuera de venta/);
 assert.ok(!f.calls.some(s=>s.startsWith('INSERT')));assert.ok(f.calls.includes('ROLLBACK'));
});
test('revoked refund permission is checked before replay or mutation',async()=>{
 const f=fixture({allowed:false});await assert.rejects(f.service.write(id,sale,p,input,id,false),/permiso/);assert.equal(f.calls.length,0);
});
