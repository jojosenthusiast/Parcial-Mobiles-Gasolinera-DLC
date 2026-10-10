import test from 'node:test';
import assert from 'node:assert/strict';
import { isPromotionActiveAt, normalizePromotionBoundary, previewPromotionOccurrences, validatePromotionDefinition } from '../dist/promotions/promotion-rules.js';

const base = {
  title: 'Miércoles DLC', motive: 'Oferta semanal para combustible elegible', kind: 'unit_discount', scope: 'branch', branchId: '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',
  startsAt: '2026-10-01T00:00:00-06:00', endsAt: '2026-11-01T00:00:00-06:00', timeZone: 'America/El_Salvador',
  recurrence: { kind: 'weekly', weekdays: [3] }, value: '0.25', valueUnit: 'us_gallon', priority: 10, stacking: 'none',
  terms: { applies: ['Combustible regular en estaciones participantes'], excludes: ['No se combina con otros descuentos'] },
};

test('promotion validation accepts a bounded, disclosed recurring discount', () => {
  const value = validatePromotionDefinition(base);
  assert.equal(value.title, 'Miércoles DLC');
  assert.equal(value.terms.applies.length, 1);
});

test('promotion validation rejects missing timezone, conditions, invalid ranges and malformed values', () => {
  for (const change of [
    { startsAt: '2026-10-01' }, { startsAt: '2026-02-30T00:00:00-06:00' }, { startsAt: '2026-10-01T00:00:00+15:00' }, { timeZone: 'Mars/Nope' }, { endsAt: '2026-09-01T00:00:00-06:00' },
    { value: '0' }, { recurrence: { kind: 'weekly', weekdays: [3, 3] } }, { terms: { applies: [], excludes: [] } },
    { scope: 'network', branchId: base.branchId }, { imageUrl: 'http://untrusted.example/promo.png', imageAlt: 'Promo image' },
  ]) assert.throws(() => validatePromotionDefinition({ ...base, ...change }));
});

test('cashback requires bank, cap and disclosed conditions; points multiplier is bounded', () => {
  const cashback = { ...base, kind: 'cashback', valueUnit: undefined, value: '10', bankCode: 'BANK_1', benefitCapUsd: '50.00' };
  assert.equal(validatePromotionDefinition(cashback).bankCode, 'BANK_1');
  assert.throws(() => validatePromotionDefinition({ ...cashback, bankCode: undefined }));
  assert.throws(() => validatePromotionDefinition({ ...cashback, benefitCapUsd: '0' }));
  assert.throws(() => validatePromotionDefinition({ ...base, valueUnit: undefined, kind: 'points_multiplier', value: '1' }));
  assert.equal(validatePromotionDefinition({ ...base, valueUnit: undefined, kind: 'points_multiplier', value: '3' }).value, '3');
});

test('recurrence evaluation uses the station timezone and excludes the end instant', () => {
  const promo = validatePromotionDefinition(base);
  assert.equal(isPromotionActiveAt(promo, new Date('2026-10-07T12:00:00Z')), true); // Wednesday, El Salvador
  assert.equal(isPromotionActiveAt(promo, new Date('2026-10-08T12:00:00Z')), false);
  assert.equal(isPromotionActiveAt(promo, new Date('2026-11-01T06:00:00Z')), false);
});

test('monthly recurrence omits a date that does not exist instead of shifting it', () => {
  const promo = validatePromotionDefinition({ ...base, startsAt: '2026-02-01T00:00:00-06:00', endsAt: '2026-03-01T00:00:00-06:00', recurrence: { kind: 'monthly', dayOfMonth: 31 } });
  assert.deepEqual(previewPromotionOccurrences(promo, new Date('2026-02-01T06:00:00Z')), []);
});

test('promotion validity and preview work are bounded', () => {
  assert.throws(() => validatePromotionDefinition({ ...base, endsAt: '2032-10-01T00:00:00-06:00' }), /máxima.*cinco años/);
  const promo = validatePromotionDefinition({ ...base, recurrence: { kind: 'weekly', weekdays: [3] } });
  assert.ok(previewPromotionOccurrences(promo, new Date('2026-10-01T00:00:00Z'), 4).length <= 4);
});

test('network targeting accepts explicit branch and zone sets and rejects ambiguous empty filters', () => {
  const network = { ...base, scope: 'network', branchId: undefined, recurrence: { kind: 'once' },
    targetZones: ['oriental'], targetBranchIds: ['4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e'] };
  assert.deepEqual(validatePromotionDefinition(network).targetZones, ['oriental']);
  assert.equal(validatePromotionDefinition({ ...network, targetMetric: { metric: 'sales_usd_30d', threshold: '10000.00' } }).targetMetric.threshold, '10000.00');
  assert.throws(() => validatePromotionDefinition({ ...network, targetMetric: { metric: 'sales_usd_30d', threshold: '0' } }), /umbral positivo/);
  assert.throws(() => validatePromotionDefinition({ ...network, targetZones: [], targetBranchIds: [] }), /sucursales válidas/);
  assert.throws(() => validatePromotionDefinition({ ...base, targetZones: ['oriental'] }), /solo se permiten en campañas/);
});

test('calendar dates resolve against the promotion timezone rather than the manager device timezone', () => {
  assert.equal(normalizePromotionBoundary('2026-10-09', 'America/El_Salvador', 'start'), '2026-10-09T06:00:00.000Z');
  assert.equal(normalizePromotionBoundary('2026-10-09', 'America/El_Salvador', 'end'), '2026-10-10T06:00:00.000Z');
  assert.throws(() => normalizePromotionBoundary('2026-02-30', 'America/El_Salvador', 'start'), /calendario/);
});
