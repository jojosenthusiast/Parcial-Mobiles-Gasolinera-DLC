import { Decimal } from 'decimal.js';

Decimal.set({ precision: 48, rounding: Decimal.ROUND_HALF_UP, toExpNeg: -24, toExpPos: 48 });

export const US_GALLON_IN_LITERS = new Decimal('3.785411784');
export const VOLUME_SCALE = 12;
export type DecimalInput = string | number;

function decimal(value: DecimalInput, label: string): Decimal {
  if (typeof value === 'number' && !Number.isFinite(value)) {
    throw new Error(`${label} debe ser un número finito.`);
  }
  const text = String(value).trim();
  if (!/^-?\d+(?:\.\d+)?$/.test(text)) {
    throw new Error(`${label} debe usar punto decimal y no incluir separadores de miles.`);
  }
  const result = new Decimal(text);
  if (!result.isFinite()) throw new Error(`${label} debe ser un número finito.`);
  return result;
}

export function normalizeVolume(value: DecimalInput): string {
  return decimal(value, 'El volumen').toDecimalPlaces(VOLUME_SCALE, Decimal.ROUND_HALF_UP).toFixed(VOLUME_SCALE);
}

export function gallonsToLiters(gallons: DecimalInput): string {
  const value = decimal(gallons, 'Los galones');
  if (value.isNegative()) throw new Error('Los galones no pueden ser negativos.');
  return value.mul(US_GALLON_IN_LITERS).toDecimalPlaces(VOLUME_SCALE, Decimal.ROUND_HALF_UP).toFixed(VOLUME_SCALE);
}

export function litersToGallons(liters: DecimalInput): string {
  const value = decimal(liters, 'Los litros');
  if (value.isNegative()) throw new Error('Los litros no pueden ser negativos.');
  return value.div(US_GALLON_IN_LITERS).toDecimalPlaces(VOLUME_SCALE, Decimal.ROUND_HALF_UP).toFixed(VOLUME_SCALE);
}

export function applyInventoryMovement(input: {
  currentLiters: DecimalInput;
  capacityLiters: DecimalInput;
  deltaLiters: DecimalInput;
}): string {
  const current = decimal(input.currentLiters, 'El saldo actual');
  const capacity = decimal(input.capacityLiters, 'La capacidad');
  const delta = decimal(input.deltaLiters, 'El movimiento');
  if (current.isNegative() || capacity.lte(0) || current.gt(capacity)) {
    throw new Error('El saldo inicial debe estar entre cero y la capacidad del tanque.');
  }
  const resulting = current.plus(delta);
  if (resulting.isNegative()) throw new Error('El movimiento dejaría inventario negativo.');
  if (resulting.gt(capacity)) throw new Error('El movimiento supera la capacidad del tanque.');
  return resulting.toDecimalPlaces(VOLUME_SCALE, Decimal.ROUND_HALF_UP).toFixed(VOLUME_SCALE);
}

export function weightedAverageCost(input: {
  currentQuantity: DecimalInput;
  currentValue: DecimalInput;
  incomingQuantity: DecimalInput;
  incomingValue: DecimalInput;
}): string {
  const quantity = decimal(input.currentQuantity, 'La cantidad actual');
  const value = decimal(input.currentValue, 'El valor actual');
  const incomingQuantity = decimal(input.incomingQuantity, 'La cantidad recibida');
  const incomingValue = decimal(input.incomingValue, 'El valor recibido');
  if ([quantity, value, incomingQuantity, incomingValue].some(item => item.isNegative())) {
    throw new Error('Cantidades y valores de costo no pueden ser negativos.');
  }
  const totalQuantity = quantity.plus(incomingQuantity);
  if (totalQuantity.isZero()) return '0.00000000';
  return value.plus(incomingValue).div(totalQuantity)
    .toDecimalPlaces(8, Decimal.ROUND_HALF_UP).toFixed(8);
}

export function money(value: DecimalInput): string {
  const amount = decimal(value, 'El importe');
  return amount.toDecimalPlaces(2, Decimal.ROUND_HALF_UP).toFixed(2);
}
