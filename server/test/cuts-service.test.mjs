import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';

let source=await readFile(new URL('../src/cuts/cuts.service.ts',import.meta.url),'utf8');
source=source.replace(/^import .+?;\r?\n/gm,'').replace('@Injectable()','').replace(/@Inject\([^)]+\) /g,'');
source=['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(n=>`class ${n} extends Error {}`).join('\n')+'\n'+source;
const {CutsService}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'transform'})).toString('base64'));
const id='11111111-1111-4111-8111-111111111111';
function fixture(){
 const calls=[];let timezone='America/El_Salvador',reviewRequired=true,autoEnabled=false;
 const query=async(sql,values)=>{
  calls.push({sql,values});
  if(sql.startsWith('SELECT timezone FROM branches'))return {rows:timezone?[{timezone}]:[]};
  if(sql.startsWith('SELECT cut_id,slot'))return {rows:[
   {cut_id:id,slot:1,starts_at:new Date('2026-10-07T12:00:00Z'),ends_at:new Date('2026-10-07T20:00:00Z')},
   {cut_id:id,slot:2,starts_at:new Date('2026-10-07T20:00:00Z'),ends_at:new Date('2026-10-08T12:00:00Z')}
  ]};
  if(sql.startsWith('SELECT c.id,c.slot'))return {rows:[]};
  if(sql.startsWith('SELECT * FROM open_operational_cut'))return {rows:[{cut_id:id,version:2,expected_dispenser_count:2,expected_nozzle_count:1,excused_nozzle_count:1}]};
  if(sql.startsWith('SELECT id,status,version'))return {rows:[{id,status:'open',version:2}]};
  if(sql.startsWith('SELECT dispenser_id AS id'))return {rows:[{id,code:'D1'}]};
  if(sql.startsWith('SELECT n.nozzle_id AS id'))return {rows:[{id,participation:'expected',fuelName:'Regular',meterVersion:3,lastMeterValue:'100'}]};
  if(sql.startsWith('SELECT t.id,t.code,t.name'))return {rows:[{id,code:'T1',fuelName:'Regular',measuredLiters:'9000'}]};
  if(sql.startsWith('SELECT * FROM capture_cut_meter'))return {rows:[{version:3,opening_value:'100',closing_value:'110',measured_l:'37.854117840'}]};
  if(sql.startsWith('SELECT * FROM record_cut_tank_measurement'))return {rows:[{version:4,measured_l:'9000'}]};
  if(sql.startsWith('SELECT * FROM prepare_operational_cut'))return {rows:[{preparation_id:id,version:5,review_required:reviewRequired}]};
  if(sql.startsWith('SELECT p.auto_close_enabled,c.ends_at'))return {rows:[{auto_close_enabled:autoEnabled,ends_at:new Date('2025-10-07T20:00:00Z')}]};
  if(sql.startsWith('SELECT * FROM review_operational_cut'))return {rows:[{review_id:id,version:6}]};
  if(sql.startsWith('SELECT * FROM close_operational_cut'))return {rows:[{closure_id:id,version:7,closed_at:new Date()}]};
  if(sql.startsWith('SELECT id,cut_id AS "cutId",preparation_id AS "preparationId"'))return {rows:[{id,cutId:id,closedBy:id}]};
  if(sql.startsWith('SELECT closure.id,closure.cut_id'))return {rows:[{id,cutId:id,closedBy:id,closedByName:'Gerente',closedAt:new Date()}]};
  if(sql.startsWith('SELECT p.id,p.cut_id'))return {rows:[{id,products:[{varianceLiters:'37.854117840'}],reviewRequired:true,status:'inReview',review:null}]};
  if(sql.startsWith('SELECT n.fuel_product_id AS'))return {rows:[{fuelProductId:id,expected:1,captured:1,meterLiters:'37.854117840'}]};
  if(sql.startsWith('SELECT a.fuel_product_id AS'))return {rows:[]};
  if(sql.startsWith('SELECT im.fuel_product_id AS'))return {rows:[]};
  if(sql==='BEGIN'||sql==='COMMIT'||sql==='ROLLBACK')return {rows:[]};
  if(sql.startsWith('INSERT INTO operational_cut_profiles'))return {rows:[{id}]};
  if(sql.startsWith('INSERT INTO operational_cut_reconciliation_policies'))return {rows:[{id}]};
  throw new Error('Unexpected SQL '+sql);
 };
 const pool={query,connect:async()=>({query,release(){}})};
 const permissions=['cut.read','cut.capture','cut.submit','cut.close','branch.manage'];
 const service=new CutsService(pool,{capabilities:async()=>permissions},{appendTransaction:async()=>{}});
 return {service,calls,permissions,p:{organizationId:id,userId:id},setTimezone:x=>{timezone=x},setAutomatic:(review,enabled)=>{reviewRequired=review;autoEnabled=enabled}};
}

test('generates only the requested branch and date and returns two contiguous windows',async()=>{
 const f=fixture();const result=await f.service.generate(id,f.p,{operationalDate:'2026-10-07'});
 assert.equal(result.data.length,2);assert.equal(result.data[0].endsAt.getTime(),result.data[1].startsAt.getTime());
 assert.deepEqual(f.calls.find(x=>x.sql.startsWith('SELECT cut_id,slot')).values,[id,id,'2026-10-07']);
});
test('rejects invalid dates, unauthorized users and inactive branches before generating',async()=>{
 const f=fixture();await assert.rejects(f.service.generate(id,f.p,{operationalDate:'2026-02-30'}),/Fecha operativa/);
 f.permissions.length=0;await assert.rejects(f.service.generate(id,f.p,{operationalDate:'2026-10-07'}),/Permiso insuficiente/);
 f.permissions.push('cut.capture');f.setTimezone(null);
 await assert.rejects(f.service.generate(id,f.p,{operationalDate:'2026-10-07'}),/sucursal activa/);
});
test('profile requires distinct valid local times and captures explicit timezone',async()=>{
 const f=fixture();await assert.rejects(f.service.createProfile(id,f.p,{effectiveDate:'2026-10-07',dayStart:'06:00',splitAt:'06:00'},id),/dos horarios distintos/);
 const result=await f.service.createProfile(id,f.p,{effectiveDate:'2026-10-07',dayStart:'22:00',splitAt:'06:00'},id);
 assert.equal(result.data.timezone,'America/El_Salvador');
 assert.deepEqual(f.calls.find(x=>x.sql.startsWith('INSERT INTO operational_cut_profiles')).values.slice(2,6),['2026-10-07','22:00','06:00','America/El_Salvador']);
});
test('opening freezes a variable asset set with optimistic version and audit in one transaction',async()=>{
 const f=fixture();const result=await f.service.open(id,id,f.p,{expectedVersion:1},id);
 assert.equal(result.data.expectedDispensers,2);assert.equal(result.data.excusedNozzles,1);
 assert.deepEqual(f.calls.find(x=>x.sql.startsWith('SELECT * FROM open_operational_cut')).values,[id,id,id,id,1]);
 assert.equal(f.calls.at(-1).sql,'COMMIT');
 const detail=await f.service.assets(id,id,f.p);assert.equal(detail.data.nozzles[0].participation,'expected');
 assert.equal(detail.data.nozzles[0].fuelName,'Regular');assert.equal(detail.data.nozzles[0].meterVersion,3);
 assert.equal(detail.data.tanks[0].code,'T1');
});
test('opening rejects invalid version and permission before any mutation',async()=>{
 const f=fixture();await assert.rejects(f.service.open(id,id,f.p,{expectedVersion:0},id),/Versión/);
 f.permissions.length=0;await assert.rejects(f.service.open(id,id,f.p,{expectedVersion:1},id),/Permiso/);
 assert.ok(!f.calls.some(x=>x.sql==='BEGIN'));
});
test('meter capture ties an existing reading to a cut version and product progress',async()=>{
 const f=fixture();const result=await f.service.capture(id,id,f.p,{nozzleId:id,readingId:id,expectedVersion:2},id);
 assert.equal(result.data.measuredL,'37.854117840');assert.equal(result.data.version,3);
 assert.deepEqual(f.calls.find(x=>x.sql.startsWith('SELECT * FROM capture_cut_meter')).values,[id,id,id,id,id,id,2]);
 const progress=await f.service.progress(id,id,f.p);assert.equal(progress.data.products[0].captured,1);
 assert.equal(progress.data.provisional,true);
 assert.ok(f.calls.some(call=>call.sql.includes('fp.display_name AS "productName"')&&call.sql.includes('JOIN fuel_products fp')));
});
test('cut lists expose who closed each shift and the detail resolves human-readable fuels and tanks',async()=>{
 const f=fixture();await f.service.list(id,f.p,'2026-10-07');
 const listQuery=f.calls.find(call=>call.sql.startsWith('SELECT c.id,c.slot'));
 assert.match(listQuery.sql,/operational_cut_closures closure/);assert.match(listQuery.sql,/closer\.display_name AS "closedByName"/);
 assert.deepEqual(listQuery.values,[id,id,'2026-10-07']);
 const detail=await f.service.assets(id,id,f.p);
 assert.equal(detail.data.nozzles[0].fuelName,'Regular');assert.equal(detail.data.tanks[0].fuelName,'Regular');
 assert.ok(f.calls.some(call=>call.sql.includes('operational_cut_meter_captures capture')));
});
test('physical tank reading is a separate measurement with version, unit and audit',async()=>{
 const f=fixture();const result=await f.service.measureTank(id,id,f.p,{tankId:id,expectedVersion:3,measuredL:'9000',observedAt:'2026-10-07T20:00:00Z',source:'manual'},id);
 assert.equal(result.data.measuredL,'9000');assert.equal(result.data.version,4);
 assert.deepEqual(f.calls.find(x=>x.sql.startsWith('SELECT * FROM record_cut_tank_measurement')).values,
  [id,id,id,id,id,3,'9000',null,null,'2026-10-07T20:00:00Z','manual',null]);
});
test('preparation records policy and discrepancy review with a frozen version',async()=>{
 const f=fixture();const policy=await f.service.createPolicy(id,f.p,{effectiveDate:'2026-10-07',meterToleranceL:'1',tankToleranceL:'10',collectionToleranceUsd:'0.01',autoCloseEnabled:false},id);
 assert.equal(policy.data.id,id);
 const result=await f.service.prepare(id,id,f.p,{expectedVersion:4},id);
 assert.equal(result.data.reviewRequired,true);assert.equal(result.data.version,5);
 const detail=await f.service.reconciliation(id,id,f.p);assert.equal(detail.data.status,'inReview');
 assert.equal(detail.data.review,null);
 const reviewQuery=f.calls.find(call=>call.sql.startsWith('SELECT p.id,p.cut_id'));
 assert.match(reviewQuery.sql,/p\.prepared_by AS "preparedBy"/);assert.match(reviewQuery.sql,/price\.value->>'unitPriceUsd'/);
 assert.match(reviewQuery.sql,/item\.value->>'varianceLiters'/);assert.match(reviewQuery.sql,/operational_cut_reviews review/);
});
test('review and close carry different versions and write audit transactionally',async()=>{
 const f=fixture();
 await assert.rejects(f.service.review(id,id,f.p,{expectedVersion:5,reason:'short'},id),/Explica/);
 const review=await f.service.review(id,id,f.p,{expectedVersion:5,reason:'Diferencia verificada en la inspección'},id);
 assert.equal(review.data.version,6);
 const closed=await f.service.close(id,id,f.p,{expectedVersion:6},id);assert.equal(closed.data.version,7);
 assert.deepEqual(f.calls.find(x=>x.sql.startsWith('SELECT * FROM close_operational_cut')).values,[id,id,id,id,6]);
 assert.equal((await f.service.closure(id,id,f.p)).data.closedBy,id);
});
test('auto-close only occurs under explicit policy, with no discrepancy and closing permission',async()=>{
 const f=fixture();f.setAutomatic(false,true);
 const result=await f.service.prepare(id,id,f.p,{expectedVersion:4},id);
 assert.equal(result.data.automaticClosureId,id);assert.equal(result.data.version,7);
 const g=fixture();g.setAutomatic(false,true);g.permissions.splice(g.permissions.indexOf('cut.close'),1);
 const manual=await g.service.prepare(id,id,g.p,{expectedVersion:4},id);
 assert.equal(manual.data.automaticClosureId,null);
 assert.ok(!g.calls.some(x=>x.sql.startsWith('SELECT * FROM close_operational_cut')));
});
