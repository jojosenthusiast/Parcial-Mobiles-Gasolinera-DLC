import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

// Exercise the actual orchestration class without pretending Nest/pg is built.
// Only framework decorators/imports are replaced; adapter/business code is kept.
let source=await readFile(new URL('../src/infrastructure/dispense-device.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\r?\n/gm,line=>line.includes("node:crypto")?line:line.includes('selectDispenseAdapter')?
  `import { selectDispenseAdapter } from '${new URL('../scripts/dispense-device-adapters.mjs',import.meta.url).href}';\n`:'');
source=source.replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source='class ConflictException extends Error {}\nclass BadRequestException extends Error {}\n'+source;
const transformed=stripTypeScriptTypes(source,{mode:'transform',sourceUrl:'dispense-device.service.ts'});
const {DispenseDeviceService}=await import('data:text/javascript;base64,'+Buffer.from(transformed).toString('base64'));

function setup(mode='simulated') {
  const operations=[];let connects=0;let authorized=true;
  const auth={id:'authorization',nozzleId:'nozzle',reservedL:'10.123456789',status:'authorized',version:1};
  const events=new Map();let sales=0;let failAfterSale=false;
  const pool={connect:async()=>{connects++;return {release(){},async query(sql,values){
    if(sql.includes('pg_try_advisory_lock'))return {rows:[{locked:true}]};
    if(sql.includes('pg_advisory_unlock'))return {rows:[{}]};
    if(sql.startsWith('SELECT *')&&sql.includes('command_id=$2'))return {rows:operations.filter(x=>x.command_id===values[1])};
    if(sql.startsWith('SELECT *'))return {rows:operations.filter(x=>x.operation==='start'),rowCount:operations.filter(x=>x.operation==='start').length};
    if(sql.startsWith('INSERT')){
      const row={command_id:values[3],request_hash:values[4],operation:values[5],adapter_mode:values[6],scenario:values[7],snapshot:structuredClone(values[8]),outcome:null,state:'prepared'};
      operations.push(row);return {rows:[structuredClone(row)]};
    }
    const row=operations.find(x=>x.command_id===values[1]);
    if(sql.includes("state='observed'")){row.outcome=values[2];row.state='observed';return {rows:[structuredClone(row)]};}
    if(sql.includes("state='applied'")){row.state='applied';return {rows:[]};}
    throw new Error('Unhandled repository operation');
  }}}};
  function transition(commandId,version,status){
    if(events.has(commandId))return;
    assert.equal(auth.version,version);events.set(commandId,true);auth.status=status;auth.version++;
  }
  const infrastructure={
    async dispenseDetail(){if(!authorized)throw new Error('Forbidden branch');return {data:{...auth}};},
    async startDispense(b,a,p,input){transition(input.commandId,input.expectedVersion,'dispensing');},
    async markDispenseUnknown(b,a,p,input){transition(input.commandId,input.expectedVersion,'unknown');},
    async completeDispense(b,a,p,input){
      if(!events.has(input.commandId)){assert.equal(input.quantity,auth.reservedL);transition(input.commandId,input.expectedVersion,'posting');sales++;}
      if(failAfterSale){failAfterSale=false;throw new Error('Process crashed after inventory commit');}
      auth.status='completed';auth.version++;
    },
    async reconcileDispenseNoFlow(b,a,p,input){assert.match(input.evidenceReference,/^SIM-/);transition(input.commandId,input.expectedVersion,'cancelled');},
  };
  const values={DISPENSE_ADAPTER_MODE:mode,NODE_ENV:'development'};
  const create=(normalPool=pool)=>new DispenseDeviceService(normalPool,pool,infrastructure,{get:key=>values[key]});
  const principal={organizationId:'org',userId:'actor'};
  const execute=(service,operation,commandId,scenario,version=auth.version)=>service.execute(operation,'branch','authorization',principal,
    {commandId,expectedVersion:version,...(scenario?{scenario}:{})},'correlation');
  return {create,execute,auth,operations,values,get sales(){return sales;},get connects(){return connects;},deny(){authorized=false;},crash(){failAfterSale=true;}};
}

test('timeout does not release reservation; durable query confirms exactly one sale',async()=>{
  const f=setup();await f.execute(f.create(),'start','start-command','timeout_after_completion');
  assert.equal(f.auth.status,'unknown');assert.equal(f.auth.reservedL,'10.123456789');assert.equal(f.sales,0);
  const version=f.auth.version;
  await f.execute(f.create(),'query','query-command',null,version);
  assert.equal(f.auth.status,'completed');assert.equal(f.sales,1);
  const replay=await f.execute(f.create(),'query','query-command',null,version);
  assert.equal(replay.device.idempotentReplay,true);assert.equal(f.sales,1);
});
test('crash after sale resumes stored observation instead of dispatching again',async()=>{
  const f=setup();await f.execute(f.create(),'start','start-command','normal');const version=f.auth.version;
  f.crash();await assert.rejects(f.execute(f.create(),'query','query-command',null,version),/crashed/);
  assert.equal(f.auth.status,'posting');assert.equal(f.operations[1].state,'observed');assert.equal(f.sales,1);
  await f.execute(f.create(),'query','query-command',null,version);assert.equal(f.auth.status,'completed');assert.equal(f.sales,1);
});
test('confirmed no-flow cancels without inventory sale',async()=>{
  const f=setup();await f.execute(f.create(),'start','start-command','timeout_before_start');
  await f.execute(f.create(),'query','query-command');assert.equal(f.auth.status,'cancelled');assert.equal(f.sales,0);
});
test('manual query requires operator verification and leaves facts untouched',async()=>{
  const f=setup('manual');await f.execute(f.create(),'start','start-command');
  const result=await f.execute(f.create(),'query','query-command');
  assert.equal(result.device.outcome.status,'operator_required');assert.equal(f.auth.status,'authorized');assert.equal(f.sales,0);
});
test('new start ID, changed replay payload and denied branch do not send a second start',async()=>{
  const f=setup();await f.execute(f.create(),'start','start-command','normal');
  await assert.rejects(f.execute(f.create(),'start','other-command','normal'),/ya fue registrado/);
  await assert.rejects(f.execute(f.create(),'start','start-command','timeout_before_start',1),/otra operación/);
  const connects=f.connects;f.deny();await assert.rejects(f.execute(f.create(),'query','query-command'),/Forbidden/);
  assert.equal(f.connects,connects);assert.equal(f.operations.length,1);
});
test('pending simulated outcome cannot post after environment changes to production',async()=>{
  const f=setup();await f.execute(f.create(),'start','start-command','normal');const version=f.auth.version;
  f.crash();await assert.rejects(f.execute(f.create(),'query','query-command',null,version));
  f.values.NODE_ENV='production';
  await assert.rejects(f.execute(f.create(),'query','query-command',null,version),/disabled in production/);
  assert.equal(f.operations[1].state,'observed');assert.equal(f.sales,1);
});
test('device coordination does not occupy a business pool connection',async()=>{
  const f=setup();const saturatedBusinessPool={connect:async()=>{throw new Error('Business pool saturated');}};
  await f.execute(f.create(saturatedBusinessPool),'start','start-command','normal');
  assert.equal(f.auth.status,'dispensing');
});
