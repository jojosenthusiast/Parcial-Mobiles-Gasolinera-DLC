import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
const spec=JSON.parse(await readFile(new URL('../../../contracts/openapi.json',import.meta.url),'utf8'));
const controller=await readFile(new URL('../../src/sales/payments.controller.ts',import.meta.url),'utf8');
const service=await readFile(new URL('../../src/sales/payments.service.ts',import.meta.url),'utf8');
test('financial endpoints have explicit permission and matching request/response contracts',()=>{
 const routes=[['cash/registers','get','cash.read'],['cash/registers','post','cash.register.manage'],['cash/sessions','post','cash.open'],
 ['cash/sessions/{sessionId}','get','cash.read'],['cash/sessions/{sessionId}/movements','post','cash.move'],['cash/sessions/{sessionId}/close','post','cash.close'],
 ['payments','post','payment.collect'],['payments/{attemptId}/resolve','post','payment.resolve'],['payment-events/{paymentEventId}/refund-requests','post','sale.refund.request'],
 ['payment-events/{paymentEventId}/refunds','post','payment.refund'],['sales/{saleId}/payments','get','payment.read'],['sales/{saleId}/refund-requests','get','payment.read']];
 for(const [route,method,permission]of routes){const operation=spec.paths['/branches/{branchId}/'+route]?.[method];assert.ok(operation,route);assert.match(operation.responses['403'].description,new RegExp(permission));assert.ok(controller.includes(`@RequirePermission('${permission}')`));assert.ok(operation.responses[method==='post'?'201':'200'].content['application/json'].schema.properties.data);}
});
test('refund binds approval and original payment; deposits cannot masquerade as expenses',()=>{
 assert.ok(spec.components.schemas.RefundPaymentRequest.required.includes('approvalId'));
 assert.deepEqual(spec.components.schemas.CashMovementRequest.properties.kind.enum,['cash_in','withdrawal','deposit']);
 assert.equal(spec.components.schemas.RefundPaymentRequest.additionalProperties,false);
 assert.ok(service.includes("this.access(branch,p,'payment.refund')"));
});
test('refund requests lock the source payment and reject an excessive balance or an already active approval',()=>{
 assert.match(service,/refund-payment:\$\{event\.toLowerCase\(\)\}/);
 assert.match(service,/FOR UPDATE OF e,a/);
 assert.match(service,/payment_event_id=\$1/);
 assert.match(service,/q\.status IN \('pending','approved'\)/);
 assert.match(service,/NOT EXISTS\(SELECT 1 FROM payment_refunds r WHERE r\.approval_id=q\.id\)/);
 assert.ok(service.includes("this.access(branch,p,'payment.read')"));
 assert.ok(service.includes("async refundRequests(branch:string,sale:string,p:AuthPrincipal)"));
 const operation=spec.paths['/branches/{branchId}/sales/{saleId}/refund-requests']?.get;
 assert.ok(operation);
 assert.equal(operation.responses['200'].content['application/json'].schema.properties.data.items.$ref,'#/components/schemas/RefundRequestDetail');
 for(const field of ['id','paymentEventId','requestedBy','amountUsd','reason','status','createdAt'])assert.ok(spec.components.schemas.RefundRequestDetail.required.includes(field));
});
test('money remains decimal text and cash/card counts are separate',()=>{
 for(const [schema,fields]of [['CollectPaymentRequest',['amountUsd']],['OpenCashRequest',['openingUsd']],['CloseCashRequest',['countedCashUsd','settledCardUsd']]])for(const field of fields)assert.equal(spec.components.schemas[schema].properties[field].type,'string');
 assert.ok(spec.components.schemas.CashClosureResult.required.includes('varianceCashUsd'));
 assert.ok(spec.components.schemas.CashClosureResult.required.includes('expectedCardUsd'));
 assert.deepEqual(spec.components.schemas.CashClosureResult.properties.reviewStatus.enum,['balanced','pending_review']);
});
test('simulation and uncertainty are visible; real collection is derived from immutable events',()=>{
 assert.deepEqual(spec.components.schemas.PaymentAttempt.properties.mode.enum,['manual','simulated']);
 assert.ok(spec.components.schemas.PaymentAttempt.properties.status.enum.includes('unknown'));
 assert.deepEqual(spec.components.schemas.FuelSale.properties.status.enum,['pending_collection','on_credit','paid']);
 for(const key of ['collectedUsd','outstandingUsd','reservedUsd','refundedUsd','refundStatus'])assert.ok(spec.components.schemas.FuelSale.required.includes(key));
});

test('advance refund source is exclusive with sale-event source while existing sale-refund routes remain unchanged',()=>{
 const migration=readFileSync(new URL('../../migrations/0022_prepaid_advances.sql',import.meta.url),'utf8').replace(/--[^\n]*/g,'').replace(/\s+/g,' ');
 assert.match(migration,/payment_refunds_one_source_check[\s\S]*payment_event_id IS NOT NULL AND advance_id IS NULL\)\s*OR\s*\(advance_id IS NOT NULL AND payment_event_id IS NULL/i);
 assert.match(service,/payment_refunds[\s\S]*advance_id/);
 for(const [path,permission] of [
  ['/branches/{branchId}/payment-events/{paymentEventId}/refund-requests','sale.refund.request'],
  ['/branches/{branchId}/payment-events/{paymentEventId}/refunds','payment.refund'],
 ]){
  const operation=spec.paths[path]?.post;
  assert.ok(operation,`existing sale refund route changed: ${path}`);
  assert.match(operation.responses['403'].description,new RegExp(permission));
  assert.ok(controller.includes(`@RequirePermission('${permission}')`));
 }
 assert.ok(spec.components.schemas.RefundPaymentRequest.required.includes('approvalId'));
});
