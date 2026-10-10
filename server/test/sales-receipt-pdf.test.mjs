import test from 'node:test';
import assert from 'node:assert/strict';
import { serializeReceiptPdf } from '../dist/reports/export-documents.js';
import { SalesService } from '../dist/sales/sales.service.js';

test('sale receipt PDF is compact, printable and explicitly non-fiscal', async () => {
  const pdf = await serializeReceiptPdf([
    'DLC GASOLINERAS',
    'COMPROBANTE INTERNO - NO FISCAL',
    'No sustituye factura, credito fiscal ni DTE.',
    'Venta: sale-123',
    'Gasolina regular',
    '25.000 gal x USD 3.50/gal = USD 87.50',
    'Total: USD 87.50',
    'Pagado: USD 87.50',
    'Saldo: USD 0.00',
  ]);
  const output = pdf.toString('ascii');
  assert.ok(output.startsWith('%PDF-1.4'));
  assert.ok(output.includes('COMPROBANTE INTERNO - NO FISCAL'));
  assert.ok(output.includes('25.000 gal x USD 3.50/gal = USD 87.50'));
  assert.ok(output.includes('Saldo: USD 0.00'));
  assert.ok(output.includes('/MediaBox [0 0 300 800]'));
  assert.ok(output.endsWith('%%EOF\n'));
});

test('sale service puts scoped sale details and computed fuel quantity into the internal receipt', async () => {
  const service = Object.create(SalesService.prototype);
  service.access = async () => ['sale.read'];
  service.detail = async () => ({ data: {
    id: 'sale-456', branchId: 'branch-1', occurredAt: '2026-10-09T12:00:00.000Z', status: 'paid', currency: 'USD',
    totalUsd: '87.50', collectedUsd: '87.50', outstandingUsd: '0.00', taxStatus: 'unknown',
    lines: [{ kind: 'fuel', description: 'Gasolina regular', priceUnit: 'us_gallon', quantityL: '94.6352946', quantityUnits: null, priceUsdPerUnit: '3.50', totalUsd: '87.50' }],
  } });
  const pdf = await service.receiptPdf('branch-1', 'sale-456', { organizationId: 'org-1', userId: 'user-1' });
  const output = pdf.toString('ascii');
  assert.ok(output.includes('COMPROBANTE INTERNO - NO FISCAL'));
  assert.ok(output.includes('25.000 gal x USD 3.50/gal = USD 87.50'));
  assert.ok(output.includes('Total: USD 87.50'));
  assert.ok(output.includes('Saldo: USD 0.00'));
  assert.ok(output.includes('Sucursal: branch-1'));
});
