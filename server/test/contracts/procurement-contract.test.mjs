import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const controller = await readFile(new URL('../../src/procurement/procurement.controller.ts', import.meta.url), 'utf8');
const service = await readFile(new URL('../../src/procurement/procurement.service.ts', import.meta.url), 'utf8');
const dto = await readFile(new URL('../../src/procurement/procurement.dto.ts', import.meta.url), 'utf8');
const web = await readFile(new URL('../../../web/public/app.js', import.meta.url), 'utf8');

test('supplier offers and purchase orders share the fuel product contract', () => {
  const createSupplier = spec.paths['/suppliers']?.post;
  assert.ok(createSupplier);
  assert.match(createSupplier.responses['403'].description, /purchase\.create/);
  const supplier = spec.components.schemas.SupplierCreateRequest;
  assert.ok(supplier.properties.offers);
  assert.equal(supplier.properties.offers.items.$ref, '#/components/schemas/SupplierOfferRequest');
  assert.ok(spec.components.schemas.SupplierOfferRequest.required.includes('fuelProductId'));
  assert.ok(dto.includes('offers?: SupplierFuelOfferDto[]'));
  assert.ok(service.includes('supplier_fuel_offers'));
});

test('purchase API rejects products without an active supplier offer', () => {
  const order = spec.paths['/branches/{branchId}/purchase-orders']?.post;
  const list = spec.paths['/branches/{branchId}/purchase-orders']?.get;
  assert.ok(order);
  assert.ok(list);
  const parameters = new Map(list.parameters.map(parameter => [parameter.name, parameter]));
  assert.equal(parameters.get('cursor').schema.format, 'uuid');
  assert.equal(parameters.get('limit').schema.maximum, 100);
  assert.equal(parameters.get('q').schema.maxLength, 100);
  assert.match(order.responses['403'].description, /purchase\.create/);
  assert.ok(spec.components.schemas.PurchaseOrderCreateRequest.required.includes('supplierId'));
  assert.ok(service.includes('AND is_active'));
  assert.ok(service.includes('El proveedor no tiene una oferta activa'));
  assert.match(controller, /@Query\('cursor'\)/);
  assert.match(controller, /@Query\('q'\)/);
  assert.match(service, /nextCursor:result\.rows\.length>limit/);
  assert.match(service, /escapeLike\(q\)/);
  assert.match(service, /fp\.display_name ILIKE/);
  assert.match(web, /supplier\?\.offers\?\.some\(o=>o\.fuelProductId===p\.id\)/);
  assert.match(web, /data-quoted-price/);
  assert.match(web, /cotización vencida/);
  assert.match(web, /purchase-order-search/);
  assert.match(web, /saveFilter\('purchases\.orderQuery'/);
  assert.match(web, /Buscar número, proveedor o combustible/);
  assert.match(web, /request\(`\/suppliers\?\$\{params\}`\)/);
  assert.match(web, /form\.elements\.supplierId\.dispatchEvent\(new Event\('change'\)\)/);
  assert.match(web, /saveFilter\('purchases\.orderStatus'/);
  assert.match(web, /saveFilter\('purchases\.orderQuery'/);
  assert.match(web, /p\.set\('q',orderQuery\)/);
  assert.match(web, /Buscar número, proveedor o combustible/);
  assert.match(web, /Mostrar más órdenes/);
});
