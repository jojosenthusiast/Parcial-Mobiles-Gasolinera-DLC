import test from 'node:test';
import assert from 'node:assert/strict';
import {
  applyInventoryMovement,
  gallonsToLiters,
  litersToGallons,
  money,
  weightedAverageCost,
} from '../dist/core/quantities.js';

test('galón estadounidense usa el factor exacto y no acumula redondeo', () => {
  assert.equal(gallonsToLiters('1'), '3.785411784000');
  assert.equal(gallonsToLiters('10'), '37.854117840000');
  assert.equal(litersToGallons('37.85411784'), '10.000000000000');
});

test('inventario impide saldos negativos o mayores que capacidad', () => {
  assert.equal(applyInventoryMovement({ currentLiters: '1000', capacityLiters: '2000', deltaLiters: '-125.5' }), '874.500000000000');
  assert.throws(() => applyInventoryMovement({ currentLiters: '4', capacityLiters: '10', deltaLiters: '-5' }), /negativo/);
  assert.throws(() => applyInventoryMovement({ currentLiters: '995', capacityLiters: '1000', deltaLiters: '10' }), /capacidad/);
});

test('costo ponderado se basa en las recepciones y el importe se redondea a centavos', () => {
  assert.equal(weightedAverageCost({ currentQuantity: '1000', currentValue: '800', incomingQuantity: '500', incomingValue: '450' }), '0.83333333');
  assert.equal(money('12.345'), '12.35');
});

test('rechaza NaN, separadores de miles y galones negativos', () => {
  assert.throws(() => gallonsToLiters('NaN'), /punto decimal/);
  assert.throws(() => gallonsToLiters('1,000'), /punto decimal/);
  assert.throws(() => gallonsToLiters('-1'), /negativos/);
});
