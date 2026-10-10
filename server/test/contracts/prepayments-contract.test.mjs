import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';

const migrationPath=new URL('../../migrations/0022_prepaid_advances.sql',import.meta.url);
const migrationExists=existsSync(migrationPath);
const migration=migrationExists?readFileSync(migrationPath,'utf8').replace(/--[^\n]*/g,'').replace(/\s+/g,' '):'';
const paymentsMigration=readFileSync(new URL('../../migrations/0021_payments_and_cash.sql',import.meta.url),'utf8').replace(/--[^\n]*/g,'').replace(/\s+/g,' ');
const paymentsController=readFileSync(new URL('../../src/sales/payments.controller.ts',import.meta.url),'utf8');
const prepaymentsController=readFileSync(new URL('../../src/sales/prepayments.controller.ts',import.meta.url),'utf8');
const openapi=JSON.parse(readFileSync(new URL('../../../contracts/openapi.json',import.meta.url),'utf8'));
const approvalController=readFileSync(new URL('../../src/authorization/approval.controller.ts',import.meta.url),'utf8');
const table=(name)=>migration.match(new RegExp(`CREATE\\s+TABLE\\s+${name}\\s*\\(([\\s\\S]*?);`,'i'))?.[1]??'';

test('prepayment migration exists and creates the separate ledger tables',()=>{
 assert.ok(migrationExists,'expected migration 0022_prepaid_advances.sql');
 for(const name of ['prepayment_advances','prepayment_allocations','prepayment_events'])assert.ok(table(name),`missing ${name} table`);
});

test('advance and sale allocation retain original authorization, tender, and sale links',()=>{
 const advances=table('prepayment_advances');
 const allocations=table('prepayment_allocations');
 assert.match(advances,/REFERENCES\s+dispense_authorizations\s*\(/i);
 assert.match(advances,/method\s+text/i);
 assert.match(advances,/mode\s+text/i);
 assert.match(advances,/cash_session_id\s+uuid/i);
 assert.match(allocations,/REFERENCES\s+sales\s*\(/i);
 assert.match(allocations,/REFERENCES\s+prepayment_advances\s*\(/i);
});

test('allocation, residual, and event idempotency are constrained in SQL',()=>{
 const allocations=table('prepayment_allocations');
 const advances=table('prepayment_advances');
 const events=table('prepayment_events');
 assert.match(allocations,/amount_usd\s*>\s*0/i);
 assert.match(migration,/NEW\.amount_usd\s*>\s*adv\.amount_usd\s*-\s*allocated/i);
 assert.match(migration,/NEW\.amount_usd\s*>\s*s\.total_usd\s*-\s*sale_allocated/i);
 assert.match(advances,/amount_usd\s*>\s*0/i);
 assert.match(migration,/refundPending/);
 assert.match(migration,/refunded/);
 assert.match(migration,/released/);
 assert.match(events,/command_id/i);
 assert.match(events,/request_hash/i);
 assert.match(events,/UNIQUE\s*\([^)]*command_id[^)]*\)/i);
});

test('refund source is exclusive and refund SQL does not adjust fuel inventory',()=>{
 assert.match(migration,/payment_refunds/i);
 assert.match(migration,/payment_event_id/i);
 assert.match(migration,/advance_id/i);
 assert.match(migration,/payment_event_id\s+IS\s+NOT\s+NULL[\s\S]{0,200}advance_id\s+IS\s+NULL[\s\S]{0,200}OR[\s\S]{0,200}advance_id\s+IS\s+NOT\s+NULL[\s\S]{0,200}payment_event_id\s+IS\s+NULL|advance_id\s+IS\s+NOT\s+NULL[\s\S]{0,200}payment_event_id\s+IS\s+NULL[\s\S]{0,200}OR[\s\S]{0,200}payment_event_id\s+IS\s+NOT\s+NULL[\s\S]{0,200}advance_id\s+IS\s+NULL/i);
 assert.doesNotMatch(migration,/\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(?:public\.)?inventory_movements\b/i);
});

test('advance persists captured versus authorization_hold and restricts holds to manual card',()=>{
 const advances=table('prepayment_advances');
 assert.match(advances,/tender_kind\s+text\s+NOT NULL/i);
 assert.match(advances,/tender_kind\s+IN\s*\(\s*'captured'\s*,\s*'authorization_hold'\s*\)/i);
 assert.match(advances,/tender_kind\s*<>\s*'authorization_hold'[\s\S]*method\s*=\s*'card'[\s\S]*mode\s*=\s*'manual'|method\s*=\s*'card'[\s\S]*mode\s*=\s*'manual'[\s\S]*tender_kind\s*=\s*'authorization_hold'/i);
});

test('unknown tender outcomes retain existing vocabulary, stay reserved, and block cash closure',()=>{
 assert.match(paymentsMigration,/outcome\s+text\s+NOT NULL\s+CHECK\s*\(\s*outcome\s+IN\s*\(\s*'confirmed'\s*,\s*'declined'\s*,\s*'unknown'\s*\)\s*\)/i);
 assert.match(migration,/unknown/i);
 assert.match(migration,/reserved/i);
 assert.match(migration,/cash_closures[\s\S]*prepayment_advances|prepayment_advances[\s\S]*cash_closures/i);
 assert.match(migration,/prepayment_advances[\s\S]*unknown[\s\S]*cash_session_id|unknown[\s\S]*prepayment_advances[\s\S]*cash_session_id/i);
});

test('unknown manual-card advances may omit evidence; known card results and holds require documentation',()=>{
 const advances=table('prepayment_advances');
 const guard=migration.match(/CREATE FUNCTION validate_prepayment_advance\(\)[\s\S]*?\$\$;/i)?.[0]??'';
 assert.match(advances,/tender_kind\s*<>\s*'authorization_hold'[\s\S]{0,220}(?:outcome\s*=\s*'unknown'[\s\S]{0,80}OR[\s\S]{0,80}evidence_reference\s+IS\s+NOT\s+NULL|evidence_reference\s+IS\s+NOT\s+NULL[\s\S]{0,80}OR[\s\S]{0,80}outcome\s*=\s*'unknown')/i);
 assert.match(guard,/NEW\.method\s*=\s*'card'[\s\S]{0,100}NEW\.mode\s*=\s*'manual'[\s\S]{0,100}NEW\.outcome\s*<>\s*'unknown'[\s\S]{0,100}NEW\.evidence_reference\s+IS\s+NULL/i);
});

test('sale collection counts captured allocations once and hold allocations link to confirmed sale payment events',()=>{
 assert.match(migration,/CREATE\s+OR\s+REPLACE\s+VIEW\s+sale_collection_balances/i);
 const view=migration.match(/CREATE\s+OR\s+REPLACE\s+VIEW\s+sale_collection_balances[\s\S]*?(?=;)/i)?.[0]??'';
 assert.match(view,/prepayment_allocations/i);
 assert.match(view,/captured/i);
 assert.doesNotMatch(view,/cash_movements/i);
 assert.match(view,/payment_refunds[\s\S]*payment_event_id/i);
 assert.doesNotMatch(view,/payment_refunds[\s\S]*advance_id/i);
 const allocations=table('prepayment_allocations');
 assert.match(allocations,/payment_event_id\s+uuid/i);
 assert.match(allocations,/REFERENCES\s+payment_events\s*\(/i);
 assert.match(migration,/payment_event_id[\s\S]*outcome\s*=\s*'confirmed'[\s\S]*sale_id|outcome\s*=\s*'confirmed'[\s\S]*payment_event_id[\s\S]*sale_id/i);
});

test('allocation events are immutable, idempotent, and expose the schema-derived remainder',()=>{
 const allocations=table('prepayment_allocations');
 const events=table('prepayment_events');
 const residual=migration.match(/CREATE\s+VIEW\s+prepayment_residuals[\s\S]*?(?=;)/i)?.[0]??'';
 assert.match(allocations,/UNIQUE\s*\(advance_id\s*,\s*sale_id\)/i);
 assert.match(allocations,/UNIQUE\s*\(organization_id\s*,\s*command_id\)/i);
 assert.match(events,/event_type\s+text[\s\S]*'allocated'/i);
 assert.match(migration,/prepayment_one_allocation_event_idx[\s\S]*event_type='allocated'/i);
 assert.match(residual,/remaining_usd/i);
 assert.match(residual,/refundPending/i);
});

test('sale collection view parses and captured allocations share sale capacity with payment attempts',()=>{
 const view=migration.match(/CREATE\s+OR\s+REPLACE\s+VIEW\s+sale_collection_balances[\s\S]*?(?=;)/i)?.[0]??'';
 const allocationGuard=migration.match(/CREATE\s+FUNCTION\s+validate_prepayment_allocation\(\)[\s\S]*?\$\$;/i)?.[0]??'';
 const paymentGuard=migration.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+validate_payment_attempt\(\)[\s\S]*?\$\$;/i)?.[0]??'';
 assert.match(view,/LEFT\s+JOIN\s+LATERAL\s*\(\s*SELECT/i);
 assert.match(allocationGuard,/payment_attempts[\s\S]*sale_allocated/i);
 assert.match(paymentGuard,/prepayment_allocations/i);
 assert.match(allocationGuard,/pa\.amount_usd\s*=\s*NEW\.amount_usd/i);
 assert.doesNotMatch(allocationGuard,/pa\.amount_usd\s*=\s*s\.total_usd/i);
});

test('disposition constraints pair captured advances with refunds and confirmed manual-card holds with evidenced release',()=>{
 assert.match(migration,/tender_kind\s*=\s*'captured'[\s\S]*disposition\s*=\s*'refund'|disposition\s*=\s*'refund'[\s\S]*tender_kind\s*=\s*'captured'/i);
 assert.match(migration,/tender_kind\s*=\s*'authorization_hold'[\s\S]*prepayment_current_outcome\(adv\.id\)\s*=\s*'confirmed'[\s\S]*method\s*=\s*'card'[\s\S]*mode\s*=\s*'manual'[\s\S]*disposition\s*=\s*'release'[\s\S]*confirmation_reference|disposition\s*=\s*'release'[\s\S]*tender_kind\s*=\s*'authorization_hold'[\s\S]*prepayment_current_outcome\(adv\.id\)\s*=\s*'confirmed'[\s\S]*method\s*=\s*'card'[\s\S]*mode\s*=\s*'manual'[\s\S]*confirmation_reference/i);
});

test('prepayment advances reject simulated tender mode',()=>{
 const advances=table('prepayment_advances');
 assert.match(advances,/CHECK\s*\(\s*mode\s*=\s*'manual'\s*\)/i);
});

test('allocation is locked after selecting a disposition',()=>{
 const allocationGuard=migration.match(/CREATE\s+FUNCTION\s+validate_prepayment_allocation\(\)[\s\S]*?\$\$;/i)?.[0]??'';
 assert.match(allocationGuard,/prepayment_events[\s\S]*event_type\s*=\s*'refundPending'/i);
});

test('confirmed captured cash advances cannot commit without their cash movement',()=>{
 const receiptGuard=migration.match(/CREATE\s+FUNCTION\s+assert_prepayment_cash_receipt\(\)[\s\S]*?\$\$;/i)?.[0]??'';
 assert.match(migration,/CREATE\s+CONSTRAINT\s+TRIGGER[\s\S]*ON\s+prepayment_advances\s+DEFERRABLE\s+INITIALLY\s+DEFERRED/i);
 assert.match(receiptGuard,/cash_movements[\s\S]*advance_id/i);
});

test('allocation 201 response uses a strict dedicated allocation result schema',()=>{
 const allocate=openapi.paths['/branches/{branchId}/prepayments/{advanceId}/allocate'].post;
 const response=allocate.responses['201'].content['application/json'].schema;
 const resultRef=response.properties.data.$ref;
 assert.notEqual(resultRef,'#/components/schemas/FinancialResult',
  'allocation response must not use the generic FinancialResult schema');
 assert.match(resultRef,/^#\/components\/schemas\//);
 const result=openapi.components.schemas[resultRef.split('/').at(-1)];
 assert.ok(result,'expected the dedicated allocation result schema to exist');
 assert.equal(result.type,'object');
 assert.equal(result.additionalProperties,false);
 const fields=['id','advanceId','saleId','amountUsd','remainingUsd','remainderStatus','idempotentReplay'];
 for(const field of fields){
  assert.ok(Object.hasOwn(result.properties,field),`missing allocation result field ${field}`);
 }
 for(const field of fields.filter(field=>field!=='remainderStatus')){
  assert.notEqual(result.properties[field].nullable,true,`${field} must not be nullable`);
 }
 for(const field of ['id','advanceId','saleId']){
  assert.equal(result.properties[field].type,'string');
  assert.equal(result.properties[field].format,'uuid');
 }
 for(const field of ['amountUsd','remainingUsd'])assert.equal(result.properties[field].type,'string');
 assert.deepEqual(result.properties.remainderStatus.type,['string','null']);
 assert.deepEqual(result.properties.remainderStatus.enum,['refundPending',null]);
 assert.equal(result.properties.idempotentReplay.type,'boolean');
 assert.deepEqual([...result.required].sort(),[...fields].sort(),
  'every allocation result field must be required and non-null');
});

test('prepayment routes continue to use established permissions and C07 residual states',()=>{
 for(const permission of ['payment.collect','payment.resolve','sale.refund.request','payment.refund'])assert.ok(paymentsController.includes(`@RequirePermission('${permission}')`),`missing existing permission ${permission}`);
 assert.ok(approvalController.includes("@RequirePermission('approval.decide')"));
 assert.ok(prepaymentsController.includes("@RequirePermission('payment.collect')"));
 assert.ok(prepaymentsController.includes("@RequirePermission('payment.resolve')"));
 assert.ok(openapi.paths['/branches/{branchId}/dispense-authorizations/{authorizationId}/prepayments']);
 assert.ok(openapi.paths['/branches/{branchId}/prepayments/{advanceId}/resolve']);
 const allocatePath='/branches/{branchId}/prepayments/{advanceId}/allocate';
 assert.ok(openapi.paths[allocatePath]?.post,'missing allocate endpoint contract');
 assert.equal(openapi.paths[allocatePath].post.operationId,'allocatePrepayment');
 assert.ok(openapi.paths[allocatePath].post.requestBody.content['application/json'].schema.$ref.endsWith('/AllocatePrepaymentRequest'));
 assert.ok(openapi.components.schemas.AllocatePrepaymentRequest);
 assert.ok(prepaymentsController.includes("@RequirePermission('payment.collect')"));
 assert.ok(prepaymentsController.includes("@Post('prepayments/:advanceId/allocate')"));
 assert.ok(openapi.components.schemas.CollectPrepaymentRequest);
 assert.ok(openapi.components.schemas.ResolvePrepaymentRequest);
 const history=openapi.paths['/branches/{branchId}/prepayments']?.get;
 assert.ok(history,'missing branch prepayment history endpoint');
 assert.equal(history.operationId,'listPrepayments');
 assert.match(history.responses['403'].description,/payment\.read/);
 assert.ok(prepaymentsController.includes("@RequirePermission('payment.read')"));
 assert.ok(prepaymentsController.includes("@Get('prepayments')"));
 const historySchema=openapi.components.schemas.PrepaymentRecord;
 for(const field of ['id','authorizationId','tenderKind','outcome','amountUsd','allocatedUsd','remainingUsd','refundableUsd','createdAt','requestStatus','refundId','releaseStatus'])assert.ok(Object.hasOwn(historySchema.properties,field),`missing prepayment history field ${field}`);
 for(const state of ['refundPending','refunded','released'])assert.ok(migration.includes(state),`missing C07 residual state ${state}`);
});

test('advance disposition endpoints expose the approved routes, permissions, and request contracts',()=>{
 const routes=[
  ['/branches/{branchId}/prepayments/{advanceId}/refund-requests','sale.refund.request',['amountUsd','commandId','reason']],
  ['/branches/{branchId}/prepayments/{advanceId}/refunds','payment.refund',['approvalId','amountUsd','cashSessionId','commandId','evidenceReference','reason']],
  ['/branches/{branchId}/prepayments/{advanceId}/release-requests','payment.resolve',['amountUsd','commandId']],
  ['/branches/{branchId}/prepayments/{advanceId}/release-confirmations','payment.resolve',['commandId','confirmationReference']],
 ];
 for(const [path,permission,fields] of routes){
  const operation=openapi.paths[path]?.post;
  assert.ok(operation,`missing approved endpoint ${path}`);
  assert.match(operation.responses['403'].description,new RegExp(permission));
  const ref=operation.requestBody.content['application/json'].schema.$ref.split('/').at(-1);
  const schema=openapi.components.schemas[ref];
  assert.ok(schema,`missing request schema ${ref}`);
  for(const field of fields)assert.ok(Object.hasOwn(schema.properties,field),`${path} request schema missing ${field}`);
 }
 for(const [route,permission] of [
  ["@Post('prepayments/:advanceId/refund-requests')",'sale.refund.request'],
  ["@Post('prepayments/:advanceId/refunds')",'payment.refund'],
  ["@Post('prepayments/:advanceId/release-requests')",'payment.resolve'],
  ["@Post('prepayments/:advanceId/release-confirmations')",'payment.resolve'],
 ])assert.ok(prepaymentsController.includes(route)&&prepaymentsController.includes(`@RequirePermission('${permission}')`),`missing ${permission} route ${route}`);
});

test('refund approval binds the advance source and preserves exclusive refund source and C07-only states',()=>{
 const refunds=migration.match(/ALTER TABLE\s+payment_refunds[\s\S]*?payment_refunds_one_source_check[\s\S]*?;/i)?.[0]??'';
 assert.match(refunds,/CHECK\s*\(\s*\(payment_event_id\s+IS\s+NOT\s+NULL\s+AND\s+advance_id\s+IS\s+NULL\)\s+OR\s+\(advance_id\s+IS\s+NOT\s+NULL\s+AND\s+payment_event_id\s+IS\s+NULL\)\s*\)/i);
 const approvalGuard=migration.match(/CREATE OR REPLACE FUNCTION validate_payment_refund\(\)[\s\S]*?\$\$;/i)?.[0]??'';
 assert.match(approvalGuard,/approval_entity:=NEW\.advance_id::text/i);
 assert.match(approvalGuard,/q\.entity_id=approval_entity[\s\S]*q\.requested_by=NEW\.created_by[\s\S]*q\.decided_by<>NEW\.created_by/i);
 const cashPost=migration.match(/CREATE OR REPLACE FUNCTION post_payment_cash_movement\(\)[\s\S]*?\$\$;/i)?.[0]??'';
 assert.match(cashPost,/NEW\.advance_id[\s\S]*adv\.method='cash'[\s\S]*NEW\.cash_session_id[\s\S]*-NEW\.amount_usd/i);
 assert.match(cashPost,/NEW\.payment_event_id IS NOT NULL[\s\S]*ELSE[\s\S]*SELECT \* INTO adv FROM prepayment_advances WHERE id=NEW\.advance_id/i);
 assert.doesNotMatch(cashPost,/inventory_movements/i);
 const eventTypes=table('prepayment_events').match(/event_type\s+text[\s\S]*?CHECK\s*\(event_type\s+IN\s*\(([^)]+)\)/i)?.[1]??'';
 assert.deepEqual([...eventTypes.matchAll(/'([^']+)'/g)].map(match=>match[1]).sort(),['allocated','outcomeResolved','received','refundPending','refunded','released'].sort());
});

test('disposition 201 responses use dedicated strict result schemas',()=>{
 const routes=[
  ['/branches/{branchId}/prepayments/{advanceId}/refund-requests',[
   ['id','uuid'],['status','string'],['idempotentReplay','boolean'],
  ]],
  ['/branches/{branchId}/prepayments/{advanceId}/refunds',[
   ['id','uuid'],['idempotentReplay','boolean'],
  ]],
  ['/branches/{branchId}/prepayments/{advanceId}/release-requests',[
   ['id','uuid'],['amountUsd','string'],['remainderStatus','refundPending'],['idempotentReplay','boolean'],
  ]],
  ['/branches/{branchId}/prepayments/{advanceId}/release-confirmations',[
   ['id','uuid'],['remainderStatus','released'],['eventId','uuid'],['idempotentReplay','boolean'],
  ]],
 ];
 const resultRefs=new Set();
 for(const [path,fields] of routes){
  const response=openapi.paths[path]?.post?.responses['201'];
  assert.ok(response,`missing 201 response for ${path}`);
  const content=response.content?.['application/json'];
  assert.ok(content,`${path} 201 response must declare application/json content`);
  const responseSchema=content.schema;
  assert.equal(responseSchema?.type,'object',`${path} 201 response must have an object schema`);
  assert.ok(responseSchema.properties?.data?.$ref,`${path} 201 response data must reference a result schema`);
  const resultRef=responseSchema.properties.data.$ref;
  assert.match(resultRef,/^#\/components\/schemas\//);
  assert.ok(!resultRefs.has(resultRef),`${path} must use its own dedicated result schema`);
  resultRefs.add(resultRef);
  const schemaName=resultRef.split('/').at(-1);
  const result=openapi.components.schemas[schemaName];
  assert.ok(result,`${path} result schema ${schemaName} must exist`);
  assert.equal(result.type,'object',`${schemaName} must be an object`);
  assert.equal(result.additionalProperties,false,`${schemaName} must reject additional properties`);
  for(const [field] of fields)assert.ok(Object.hasOwn(result.properties??{},field),`${schemaName} is missing ${field}`);
  assert.deepEqual([...result.required].sort(),fields.map(([field])=>field).sort(),`${schemaName} must require exactly its response fields`);
  for(const [field,type] of fields){
   const property=result.properties[field];
   if(field==='remainderStatus')assert.deepEqual(property.enum,[type],`${schemaName}.${field} must have the endpoint-specific state`);
   else if(type==='uuid'){
    assert.equal(property.type,'string',`${schemaName}.${field} must be a string UUID`);
    assert.equal(property.format,'uuid',`${schemaName}.${field} must be a UUID`);
   } else assert.equal(property.type,type,`${schemaName}.${field} must be ${type}`);
  }
 }
});
