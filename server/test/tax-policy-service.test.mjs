import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {stripTypeScriptTypes} from 'node:module';
let source=await readFile(new URL('../src/sales/tax-policy.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\n/gm,line=>line.includes('node:crypto')?line:line.includes('calculateFuelTax,validateFuelTaxPolicy')?`import {calculateFuelTax,validateFuelTaxPolicy} from '${new URL('../scripts/fuel-tax.mjs',import.meta.url).href}';\n`:'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(n=>`class ${n} extends Error {}`).join('\n')+'\n'+source;
const {TaxPolicyService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const actor='11111111-1111-4111-8111-111111111111',approver='22222222-2222-4222-8222-222222222222',id='33333333-3333-4333-8333-333333333333';
const input={commandId:id,fuelProductId:id,mode:'exempt',rules:[],sourceReference:'Synthetic fixture',reason:'Arithmetic test only',effectiveAt:'2099-01-01T00:00:00Z'};
function fixture(){
 const state={caps:['sale.read','tax.policy.propose','tax.policy.approve'],branch:true,product:true,proposal:null,version:null,audits:0,connects:0,locks:[],queries:[]};
 let snapshot;
 async function query(sql,v=[]){
  state.queries.push(sql);
  if(sql==='BEGIN'){snapshot={proposal:state.proposal,version:state.version};return {rows:[]};}
  if(sql==='ROLLBACK'){Object.assign(state,snapshot);return {rows:[]};}
  if(sql==='COMMIT')return {rows:[]};
  if(sql.includes('advisory')){state.locks.push(v[0]);return {rows:[]};}
  if(sql.includes('FROM branches'))return {rows:[],rowCount:state.branch?1:0};
  if(sql.includes('JOIN branch_fuel_offers'))return {rows:[],rowCount:state.product?1:0};
  if(sql.startsWith('SELECT id,request_hash,proposed_by'))return {rows:state.proposal?.command===v[1]?[state.proposal]:[]};
  if(sql.startsWith('SELECT id,request_hash,approved_by'))return {rows:state.version?.command===v[1]?[state.version]:[]};
  if(sql.startsWith('INSERT INTO fuel_tax_proposals')){state.proposal={id,command:v[3],request_hash:v[4],proposed_by:v[10],fuel_product_id:id,effective_at:new Date(v[9])};return {rows:[{id}]};}
  if(sql.startsWith('SELECT id,fuel_product_id'))return {rows:state.proposal?[state.proposal]:[]};
  if(sql.startsWith('SELECT id FROM fuel_tax_versions'))return {rows:state.version?[{id}]:[],rowCount:state.version?1:0};
  if(sql.startsWith('INSERT INTO fuel_tax_versions')){state.version={id,command:v[3],request_hash:v[4],approved_by:v[5]};return {rows:[{id}]};}
  if(sql.startsWith('SELECT mode,rules'))return {rows:state.version?[{mode:'exempt',rules:[]}]:[]};
  throw new Error('Unhandled SQL: '+sql);
 }
 const pool={query,connect:async()=>{state.connects++;return {query,release(){}};}};
 const service=new TaxPolicyService(pool,{capabilities:async()=>state.caps},{appendTransaction:async()=>{state.audits++;}});
 const principal=user=>({userId:user,organizationId:id});
 return {state,service,principal,propose:body=>service.propose(id,principal(actor),body??input,id),approve:(body={commandId:approver},user=approver)=>service.approve(id,id,principal(user),body,id)};
}
test('proposal/approval replay preserve commands and only append two audit events',async()=>{
 const f=fixture();await f.propose();assert.equal((await f.propose()).data.idempotentReplay,true);
 await f.approve();assert.equal((await f.approve()).data.idempotentReplay,true);assert.equal(f.state.audits,2);
 assert.ok(f.state.locks.some(x=>x.startsWith('tax-scope:')));
});
test('altered proposal retry, self approval and second approval ID are rejected',async()=>{
 const f=fixture();await f.propose();await assert.rejects(f.propose({...input,sourceReference:'Changed'}),/otra propuesta/);
 await assert.rejects(f.approve({commandId:approver},actor),/Otra persona/);await f.approve();
 await assert.rejects(f.approve({commandId:id}),/ya fue aprobada/);
});
test('expired proposal cannot approve, but successful replay ignores expiry',async()=>{
 const f=fixture();await f.propose();await f.approve();f.state.proposal.effective_at=new Date('2000-01-01');
 assert.equal((await f.approve()).data.idempotentReplay,true);
 await assert.rejects(f.approve({commandId:id}),/venció/);
});
test('permission revoked before retry denies repository access',async()=>{
 const f=fixture();await f.propose();f.state.caps=[];const connects=f.state.connects;
 await assert.rejects(f.propose(),/No tienes permiso/);assert.equal(f.state.connects,connects);
});
test('foreign branch, inactive fuel and undocumented source fail',async()=>{
 const f=fixture();f.state.branch=false;await assert.rejects(f.propose(),/sucursal no existe/);
 f.state.branch=true;f.state.product=false;await assert.rejects(f.propose(),/inactivo/);
 f.state.product=true;await assert.rejects(f.propose({...input,sourceReference:' '}),/fuente documental/);
 assert.equal(f.state.audits,0);
});
test('invalid policy, expired date and IDs fail without a successful insert',async()=>{
 const f=fixture();for(const bad of [{...input,commandId:'bad'},{...input,mode:'included'},{...input,effectiveAt:'bad'},{...input,effectiveAt:'2099-02-30T00:00:00Z'},{...input,effectiveAt:'2099-01-01T00:00:00'},{...input,sourceReference:42},{...input,effectiveAt:'2000-01-01T00:00:00Z'}])await assert.rejects(f.propose(bad));
 assert.equal(f.state.proposal,null);assert.equal(f.state.audits,0);
});
test('approved preview is read-only and uses exact strings; foreign version is unavailable',async()=>{
 const f=fixture();await assert.rejects(f.service.preview(id,f.principal(actor),{policyVersionId:id,grossUsd:'10.00',quantityL:'1'}),/no existe/);
 await f.propose();await f.approve();const audits=f.state.audits;
 const result=await f.service.preview(id,f.principal(actor),{policyVersionId:id,grossUsd:'10.00',quantityL:'1'});
 assert.equal(result.data.netUsd,'10.00');assert.equal(result.data.taxUsd,'0.00');assert.equal(result.data.preview,true);assert.equal(f.state.audits,audits);
});
