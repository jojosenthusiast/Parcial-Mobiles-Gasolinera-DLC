import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const spec=JSON.parse(await readFile(new URL('../../../contracts/openapi.json',import.meta.url),'utf8'));
test('fuel ticket API exposes creation, detail, paginated master and dispatch link',()=>{
 for(const path of ['/branches/{branchId}/sales/from-dispatch','/branches/{branchId}/sales','/branches/{branchId}/sales/{saleId}',
 '/branches/{branchId}/dispense-authorizations/{authorizationId}/sale']) assert.ok(spec.paths[path]);
 assert.deepEqual(spec.components.schemas.FuelSale.properties.status.enum,['pending_collection','on_credit','paid']);
 assert.equal(spec.components.schemas.FuelSale.properties.receiptType.const,'internal');
 assert.deepEqual(spec.components.schemas.FuelSale.properties.taxUsd.type,['string','null']);
 assert.equal(spec.components.schemas.CreateFuelSaleRequest.additionalProperties,false);
});

test('combined receipt API keeps the fuel and POS sales as separate internal components',()=>{
 assert.ok(spec.paths['/branches/{branchId}/sales/combined-receipts']);
 assert.ok(spec.paths['/branches/{branchId}/sales/combined-receipts/{receiptId}']);
 assert.ok(spec.paths['/branches/{branchId}/sales/{saleId}/combined-receipt']);
 const request=spec.components.schemas.CreateCombinedReceiptRequest;
 assert.deepEqual(request.required,['commandId','fuelSaleId','posSaleId']);
 assert.equal(request.additionalProperties,false);
 const receipt=spec.components.schemas.CombinedInternalReceipt;
 assert.equal(receipt.properties.receiptType.const,'internal_combined');
 assert.equal(receipt.properties.fiscalStatus.const,'not_fiscal');
 assert.deepEqual(receipt.properties.components.required,['fuel','pos']);
});

test('tax policy contract requires documented proposals and preserves internal receipt classification',()=>{
 for(const suffix of ['', '/proposals','/proposals/{proposalId}/approve','/preview'])assert.ok(spec.paths['/branches/{branchId}/fuel-tax-policies'+suffix]);
 assert.ok(spec.components.schemas.ProposeFuelTaxRequest.required.includes('sourceReference'));
 assert.ok(spec.components.schemas.ProposeFuelTaxRequest.required.includes('effectiveAt'));
 assert.deepEqual(spec.components.schemas.FuelSale.properties.taxStatus.enum,['configured','unconfigured']);
 assert.equal(spec.components.schemas.FuelSale.properties.receiptType.const,'internal');
});

test('POS contract exposes versioned catalog, receipts, lot detail and multi-line sales',()=>{
 for(const path of ['/branches/{branchId}/pos/catalog','/branches/{branchId}/pos/catalog/offers','/branches/{branchId}/pos/stock/receipts',
  '/branches/{branchId}/pos/catalog/{productId}/lots','/branches/{branchId}/pos/catalog/{productId}','/branches/{branchId}/sales/pos'])assert.ok(spec.paths[path]);
 assert.deepEqual(spec.components.schemas.FuelSaleLine.properties.kind.enum,['fuel','store','service']);
 assert.equal(spec.components.schemas.CreatePosSaleRequest.properties.items.maxItems,50);
 assert.equal(spec.components.schemas.CreatePosSaleRequest.additionalProperties,false);
 assert.equal(spec.components.schemas.FuelSale.properties.lines.maxItems,50);
 assert.ok(spec.components.schemas.FuelSaleSummary.required.includes('lineCount'));
 assert.ok(spec.components.schemas.ReceivePosLotRequest.required.includes('sourceReference'));
});


test('POS catalog can categorize quick retail items and filter categories server-side', async () => {
  const source = await readFile(new URL('../../src/sales/pos.service.ts', import.meta.url), 'utf8');
  assert.match(source, /lower\(c\.category\)=lower\(\$10\)/);
  assert.match(source, /async categories\(/);
  const contract = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
  assert.ok(contract.paths['/branches/{branchId}/pos/catalog/categories']);
  assert.ok(contract.paths['/branches/{branchId}/pos/catalog'].get.parameters.some(p => p.name === 'category'));
});
