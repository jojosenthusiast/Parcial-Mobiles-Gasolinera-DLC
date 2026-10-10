import test from 'node:test';
import assert from 'node:assert/strict';
import { ManualDispenseAdapter, SimulatedDispenseAdapter, selectDispenseAdapter } from '../scripts/dispense-device-adapters.mjs';
import { validateEnvironment } from '../src/core/environment.ts';

const snapshot={authorizationId:'auth-1',nozzleId:'nozzle-1',reservedL:'10.123456789',scenario:'normal',startCommandId:'original-start'};
test('manual mode never fabricates volume or physical confirmation',async()=>{
  const adapter=new ManualDispenseAdapter();
  assert.deepEqual(await adapter.start(snapshot),{source:'manual',status:'operator_required',measuredL:null,evidenceReference:null});
  assert.deepEqual(await adapter.query(snapshot),await adapter.start(snapshot));
});
test('normal simulated flow has explicit provenance and exact decimal volume',async()=>{
  const adapter=new SimulatedDispenseAdapter();
  assert.equal((await adapter.start(snapshot)).status,'started');
  const result=await adapter.query(snapshot);
  assert.equal(result.status,'completed');assert.equal(result.measuredL,'10.123456789');
  assert.equal(result.source,'simulated');assert.match(result.evidenceReference,/^SIM-auth-1-original-start$/);
});
test('timeout after completion is resolved by query of original snapshot after restart',async()=>{
  const input={...snapshot,scenario:'timeout_after_completion'};
  assert.equal((await new SimulatedDispenseAdapter().start(input)).status,'timeout');
  const a=await new SimulatedDispenseAdapter().query(JSON.parse(JSON.stringify(input)));
  const b=await new SimulatedDispenseAdapter().query(input);
  assert.deepEqual(a,b);assert.equal(a.status,'completed');assert.equal(a.measuredL,input.reservedL);
});
test('timeout before start proves no flow instead of inventing a sale',async()=>{
  const input={...snapshot,scenario:'timeout_before_start'};
  const adapter=new SimulatedDispenseAdapter();
  assert.equal((await adapter.start(input)).status,'timeout');
  const result=await adapter.query(input);assert.equal(result.status,'no_flow');assert.equal(result.measuredL,'0');
});
test('production and unimplemented physical providers cannot silently select simulation',()=>{
  assert.throws(()=>selectDispenseAdapter('simulated','production'));
  assert.throws(()=>selectDispenseAdapter('physical','development'));
  assert.equal(selectDispenseAdapter('manual','production').mode,'manual');
  const base={DATABASE_URL:'postgresql://user:secret@localhost/dlc',AUTH_RATE_LIMIT_KEY:'x'.repeat(40),NODE_ENV:'production',DATABASE_SSL_MODE:'verify-full'};
  assert.throws(()=>validateEnvironment({...base,DISPENSE_ADAPTER_MODE:'simulated'}),/producción/);
});
test('invalid units, zero, excess precision and unknown scenarios are rejected',async()=>{
  const adapter=new SimulatedDispenseAdapter();
  for(const reservedL of ['0','-1','NaN','1e3','1.0000000001'])await assert.rejects(adapter.query({...snapshot,reservedL}));
  await assert.rejects(adapter.query({...snapshot,scenario:'invented'}));
});
