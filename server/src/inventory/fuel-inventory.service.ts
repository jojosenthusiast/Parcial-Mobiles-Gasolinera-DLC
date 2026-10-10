import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { Decimal } from 'decimal.js';
import { PG_POOL } from '../database/database.module.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { applyInventoryMovement, gallonsToLiters, money, weightedAverageCost } from '../core/quantities.js';
import type { FuelInventoryCommandDto, FuelInventoryOpeningDto } from './inventory.dto.js';

type MovementType = 'opening' | 'receipt' | 'sale' | 'loss' | 'adjustment_in' | 'adjustment_out';
type BalanceRow = { on_hand_l: string; inventory_value_usd: string | null; average_cost_per_l_usd: string | null; valuation_quality: 'known' | 'unknown' | 'provisional'; version: number };

@Injectable()
export class FuelInventoryService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly audit: AuditService) {}

  open(branchId: string, tankId: string, principal: AuthPrincipal, input: FuelInventoryOpeningDto, correlationId: string) {
    return this.apply(branchId, tankId, principal, input, 'opening', correlationId);
  }
  receive(branchId: string, tankId: string, principal: AuthPrincipal, input: FuelInventoryCommandDto, correlationId: string) {
    return this.apply(branchId, tankId, principal, input, 'receipt', correlationId);
  }
  sell(branchId: string, tankId: string, principal: AuthPrincipal, input: FuelInventoryCommandDto, correlationId: string) {
    return this.apply(branchId, tankId, principal, input, 'sale', correlationId);
  }
  lose(branchId: string, tankId: string, principal: AuthPrincipal, input: FuelInventoryCommandDto, correlationId: string) {
    return this.apply(branchId, tankId, principal, input, 'loss', correlationId);
  }
  adjust(branchId: string, tankId: string, principal: AuthPrincipal, input: FuelInventoryCommandDto, correlationId: string) {
    if (!input.direction) throw new BadRequestException('Indica si el ajuste agrega o retira producto.');
    return this.apply(branchId, tankId, principal, input, input.direction === 'in' ? 'adjustment_in' : 'adjustment_out', correlationId);
  }

  async balance(branchId: string, tankId: string, principal: AuthPrincipal) {
    const tank = await this.pool.query(
      `SELECT id,branch_id AS "branchId",code,name,fuel_product_id AS "fuelProductId",nominal_capacity_l AS "nominalCapacityL",
              safe_fill_limit_l AS "safeFillLimitL",unusable_reserve_l AS "unusableReserveL",status
         FROM tanks WHERE id=$1 AND branch_id=$2 AND organization_id=$3`, [tankId, branchId, principal.organizationId],
    );
    if (!tank.rowCount) throw new NotFoundException('El tanque no existe en esta sucursal.');
    const result = await this.pool.query(
      `SELECT on_hand_l AS "onHandL",inventory_value_usd AS "inventoryValueUsd",average_cost_per_l_usd AS "averageCostPerLUsd",
              valuation_quality AS "valuationQuality",version,last_movement_id AS "lastMovementId",updated_at AS "updatedAt"
         FROM tank_inventory_balances WHERE tank_id=$1 AND organization_id=$2`, [tankId, principal.organizationId],
    );
    const blocked=await this.pool.query(`SELECT 1 FROM asset_blocks WHERE organization_id=$1 AND branch_id=$2
      AND asset_type='tank' AND asset_id=$3 AND resolved_at IS NULL LIMIT 1`,[principal.organizationId,branchId,tankId]);
    const quarantine=await this.pool.query(`SELECT d.prior_quantity_l+d.incoming_quantity_l AS physical_estimate_l
      FROM contaminated_deliveries d WHERE d.tank_id=$1 AND d.organization_id=$2 AND NOT EXISTS(
       SELECT 1 FROM contamination_disposals x WHERE x.contamination_id=d.id) ORDER BY d.created_at DESC LIMIT 1`,[tankId,principal.organizationId]);
    return { tank: tank.rows[0], balance: result.rows[0] ?? null, balanceKnown: result.rowCount === 1,
      blocked:!!blocked.rowCount,availableForSaleL:blocked.rowCount?'0':result.rows[0]?.onHandL??null,
      quarantinedPhysicalEstimateL:quarantine.rows[0]?.physical_estimate_l??null };

  }

  async history(branchId: string, tankId: string, principal: AuthPrincipal, limit: number, cursor?: string) {
    await this.assertTank(branchId, tankId, principal);
    const values: unknown[] = [principal.organizationId, branchId, tankId];
    let where = 'organization_id=$1 AND branch_id=$2 AND tank_id=$3';
    if (cursor) {
      const parsed = decodeCursor(cursor);
      values.push(parsed.time, parsed.id);
      where += ` AND (occurred_at,id)<($${values.length - 1}::timestamptz,$${values.length}::uuid)`;
    }
    values.push(Math.max(1, Math.min(limit, 100)) + 1);
    const result = await this.pool.query(
      `SELECT id,movement_type AS "movementType",source_type AS "sourceType",source_id AS "sourceId",source_line AS "sourceLine",
              quantity_entered AS "quantityEntered",unit_entered AS "unitEntered",conversion_factor_to_l AS "conversionFactorToL",
              observed_l AS "observedL",compensated_l AS "compensatedL",delta_l AS "deltaL",volume_basis AS "volumeBasis",
              temperature_c AS "temperatureC",reference_temperature_c AS "referenceTemperatureC",water_l AS "waterL",
              unit_cost_usd_per_l AS "unitCostUsdPerL",total_cost_usd AS "totalCostUsd",cost_recognized_usd AS "costRecognizedUsd",
              valuation_quality AS "valuationQuality",reason_code AS "reasonCode",reason,document_reference AS "documentReference",
              before_quantity_l AS "beforeQuantityL",after_quantity_l AS "afterQuantityL",actor_user_id AS "actorUserId",occurred_at AS "occurredAt"
         FROM inventory_movements WHERE ${where} ORDER BY occurred_at DESC,id DESC LIMIT $${values.length}`,
      values,
    );
    const pageLimit = Math.max(1, Math.min(limit, 100));
    const hasMore = result.rows.length > pageLimit;
    const data = hasMore ? result.rows.slice(0, pageLimit) : result.rows;
    const last = data.at(-1);
    return { data, meta: { limit: pageLimit, nextCursor: hasMore && last ? encodeCursor(last.occurredAt, last.id) : null } };
  }

  private async apply(branchId: string, tankId: string, principal: AuthPrincipal, input: FuelInventoryCommandDto | FuelInventoryOpeningDto, type: MovementType, correlationId: string) {
    const normalized = normalizeCommand(type, input);
    const requestHash = createHash('sha256').update(stableStringify({ type, branchId, tankId, normalized })).digest('hex');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const prior = await findCommand(client, principal.organizationId, input.commandId);
      if (prior) {
        if (prior.request_hash !== requestHash) throw new ConflictException('commandId ya fue usado para otra operación.');
        await client.query('COMMIT');
        return { movement: prior, idempotentReplay: true };
      }
      const tankResult = await client.query<{
        id: string; fuel_product_id: string; nominal_capacity_l: string; safe_fill_limit_l: string; unusable_reserve_l: string; status: string;
      }>(
        `SELECT id,fuel_product_id,nominal_capacity_l,safe_fill_limit_l,unusable_reserve_l,status
           FROM tanks WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`,
        [tankId, branchId, principal.organizationId],
      );
      const tank = tankResult.rows[0];
      if (!tank) throw new NotFoundException('El tanque no existe en esta sucursal.');
      if (tank.status === 'decommissioned') throw new ConflictException('No se puede mover inventario en un tanque dado de baja.');
      const racedCommand = await findCommand(client, principal.organizationId, input.commandId);
      if (racedCommand) {
        if (racedCommand.request_hash !== requestHash) throw new ConflictException('commandId ya fue usado para otra operación.');
        await client.query('COMMIT');
        return { movement: racedCommand, idempotentReplay: true };
      }
      if (type === 'sale' && tank.status !== 'active') throw new ConflictException('El tanque debe estar activo para registrar venta.');
      if(type === 'sale' || type === 'receipt') {
        const blocked = await client.query("SELECT 1 FROM asset_blocks WHERE organization_id=$1 AND branch_id=$2 AND asset_type='tank' AND asset_id=$3 AND resolved_at IS NULL LIMIT 1", [principal.organizationId,branchId,tankId]);
        if(blocked.rowCount) throw new ConflictException('El tanque tiene un bloqueo de seguridad; no puede vender combustible.');
      }
      if(type === 'adjustment_in' || type === 'adjustment_out') {
        const quarantined=await client.query(`SELECT 1 FROM contaminated_deliveries d JOIN asset_blocks b ON b.incident_id=d.incident_id
          WHERE d.tank_id=$1 AND d.organization_id=$2 AND b.resolved_at IS NULL LIMIT 1`,[tankId,principal.organizationId]);
        if(quarantined.rowCount) throw new ConflictException('No ajustes manualmente un tanque contaminado; usa la pérdida aprobada y la disposición verificada.');
      }
      if (type === 'opening') {
        const existing = await client.query('SELECT 1 FROM inventory_movements WHERE tank_id=$1 AND organization_id=$2 AND movement_type=$3 LIMIT 1', [tankId, principal.organizationId, 'opening']);
        if (existing.rowCount) throw new ConflictException('El saldo inicial de este tanque ya se registró. Use un ajuste con motivo.');
      }
      const balanceResult = await client.query<BalanceRow>(
        'SELECT on_hand_l,inventory_value_usd,average_cost_per_l_usd,valuation_quality,version FROM tank_inventory_balances WHERE tank_id=$1 AND organization_id=$2 FOR UPDATE', [tankId, principal.organizationId],
      );
      const previous = balanceResult.rows[0] ?? null;
      if (type !== 'opening' && !previous) throw new ConflictException('Registra y confirma el saldo inicial antes de operar este tanque.');
      if (type === 'opening' && previous) throw new ConflictException('El tanque ya tiene un saldo inicial.');
      if (input.expectedBalanceVersion !== undefined && previous?.version !== input.expectedBalanceVersion) throw new ConflictException('El saldo cambió; actualiza antes de repetir la operación.');

      const before = previous?.on_hand_l ?? '0';
      const delta = normalized.deltaLiters;
      let after: string;
      try { after = applyInventoryMovement({ currentLiters: before, capacityLiters: tank.safe_fill_limit_l, deltaLiters: delta }); }
      catch (error) { throw new ConflictException(error instanceof Error ? error.message : 'El movimiento no cabe en el saldo del tanque.'); }
      if (type === 'sale' && new Decimal(after).lt(tank.unusable_reserve_l)) throw new ConflictException('La venta dejaría el tanque por debajo de su reserva no utilizable.');
      if(['sale','loss','adjustment_out'].includes(type)){
        const completing=type==='sale'&&normalized.sourceId?await client.query<{id:string}>(`SELECT id FROM dispense_authorizations WHERE id=$1 AND organization_id=$2
          AND branch_id=$3 AND tank_id=$4 AND status='posting' AND completion_command_id=$5`,
          [normalized.sourceId,principal.organizationId,branchId,tankId,input.commandId]):null;
        const excludedAuthorizationId=completing?.rows[0]?.id??null;
        const reservations=await client.query<{reserved:string}>(`SELECT COALESCE(sum(reserved_l),0)::text AS reserved FROM dispense_authorizations
          WHERE tank_id=$1 AND status IN ('authorized','dispensing','unknown','posting') AND (status<>'authorized' OR expires_at>now())
            AND ($2::uuid IS NULL OR id<>$2::uuid)`,[tankId,excludedAuthorizationId]);
        const protectedStock=new Decimal(type==='sale'?tank.unusable_reserve_l:'0').plus(reservations.rows[0]?.reserved??'0');
        if(new Decimal(after).lt(protectedStock)) throw new ConflictException('El movimiento invadiría combustible reservado para despachos autorizados; resuelve esas autorizaciones primero.');
      }
      const valuation = calculateValuation(type, normalized, previous, before, delta);
      const movementId = randomUUID();
      const movement = await client.query(
        `INSERT INTO inventory_movements (
           id,organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,source_id,source_line,
           quantity_entered,unit_entered,conversion_factor_to_l,observed_l,compensated_l,delta_l,volume_basis,temperature_c,reference_temperature_c,water_l,
           unit_cost_usd_per_l,total_cost_usd,valuation_quality,reason_code,reason,document_reference,before_quantity_l,after_quantity_l,cost_recognized_usd,
           actor_user_id,correlation_id,metadata)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33::jsonb)
         RETURNING id,movement_type AS "movementType",tank_id AS "tankId",fuel_product_id AS "fuelProductId",command_id AS "commandId",
           source_type AS "sourceType",quantity_entered AS "quantityEntered",unit_entered AS "unitEntered",observed_l AS "observedL",
           compensated_l AS "compensatedL",delta_l AS "deltaL",volume_basis AS "volumeBasis",total_cost_usd AS "totalCostUsd",
           cost_recognized_usd AS "costRecognizedUsd",valuation_quality AS "valuationQuality",reason,document_reference AS "documentReference",
           before_quantity_l AS "beforeQuantityL",after_quantity_l AS "afterQuantityL",actor_user_id AS "actorUserId",occurred_at AS "occurredAt"`,
        [movementId, principal.organizationId, branchId, tankId, tank.fuel_product_id, type, input.commandId, requestHash,
          normalized.sourceType, normalized.sourceId, normalized.sourceLine, normalized.quantityEntered, normalized.unit, normalized.conversionFactor,
          normalized.observedLiters, normalized.compensatedLiters, delta, normalized.volumeBasis, input.temperatureC ?? null,
          input.referenceTemperatureC ?? null, input.waterLiters ?? null, valuation.unitCost, valuation.totalCost, valuation.quality,
          input.reasonCode ?? null, normalized.reason, normalized.documentReference, before, after, valuation.costRecognized,
          principal.userId, correlationId, JSON.stringify({ inputUnit: normalized.unit, volumeBasis: normalized.volumeBasis })],
      );
      if (previous) {
        await client.query(
          `UPDATE tank_inventory_balances SET on_hand_l=$2,inventory_value_usd=$3,average_cost_per_l_usd=$4,
             valuation_quality=$5,version=version+1,last_movement_id=$6,updated_at=now()
           WHERE tank_id=$1 AND version=$7`,
          [tankId, after, valuation.inventoryValue, valuation.averageCost, valuation.balanceQuality, movementId, previous.version],
        );
      } else {
        await client.query(
          `INSERT INTO tank_inventory_balances(tank_id,organization_id,branch_id,fuel_product_id,on_hand_l,inventory_value_usd,average_cost_per_l_usd,valuation_quality,last_movement_id)
           VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
          [tankId, principal.organizationId, branchId, tank.fuel_product_id, after, valuation.inventoryValue, valuation.averageCost, valuation.balanceQuality, movementId],
        );
      }
      await this.audit.appendTransaction(client, { principal, branchId, correlationId, action: `inventory.${type}`, entityType: 'inventory_movement', entityId: movementId, after: { tankId, movementType: type, deltaL: delta, valuationQuality: valuation.quality, commandId: input.commandId } });
      await client.query('COMMIT');
      return { movement: movement.rows[0], balance: { onHandL: after, inventoryValueUsd: valuation.inventoryValue, averageCostPerLUsd: valuation.averageCost, valuationQuality: valuation.balanceQuality, version: (previous?.version ?? 0) + 1 }, idempotentReplay: false };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (isUnique(error)) {
        const prior = await findCommand(client, principal.organizationId, input.commandId).catch(() => null);
        if (prior?.request_hash === requestHash) return { movement: prior, idempotentReplay: true };
        throw new ConflictException('La operación ya se procesó o existe una referencia duplicada.');
      }
      throw error;
    } finally { client.release(); }
  }

  private async assertTank(branchId: string, tankId: string, principal: AuthPrincipal) {
    const result = await this.pool.query('SELECT 1 FROM tanks WHERE id=$1 AND branch_id=$2 AND organization_id=$3', [tankId, branchId, principal.organizationId]);
    if (!result.rowCount) throw new NotFoundException('El tanque no existe en esta sucursal.');
  }
}

function normalizeCommand(type: MovementType, input: FuelInventoryCommandDto | FuelInventoryOpeningDto) {
  validateTemperature(input);
  const entered = convertToLiters(input.quantity, input.unit, type === 'opening');
  const compensated = input.compensatedQuantity ? convertToLiters(input.compensatedQuantity, input.unit, type === 'opening') : null;
  if (type !== 'opening' && new Decimal(entered).lte(0)) throw new BadRequestException('La cantidad del movimiento debe ser mayor que cero.');
  if (input.volumeBasis === 'compensated' && !compensated) throw new BadRequestException('El volumen compensado debe indicarse por separado del observado.');
  if (input.volumeBasis === 'compensated' && compensated && new Decimal(compensated).lte(0)) throw new BadRequestException('El volumen compensado debe ser mayor que cero.');
  if (input.volumeBasis === 'compensated' && (input.temperatureC === undefined || input.referenceTemperatureC === undefined)) throw new BadRequestException('La compensación requiere temperatura medida y temperatura de referencia.');
  if (input.volumeBasis !== 'compensated' && compensated) throw new BadRequestException('compensatedQuantity solo se admite con volumeBasis compensated.');
  if (type === 'receipt' && !input.documentReference?.trim()) throw new BadRequestException('La recepción requiere referencia documental.');
  if (['loss','adjustment_in','adjustment_out'].includes(type) && !input.reason?.trim()) throw new BadRequestException('La pérdida o ajuste requiere motivo.');
  if (['sale','loss','adjustment_out'].includes(type) && input.totalCostUsd !== undefined) throw new BadRequestException('El costo de salida se calcula con el costo promedio móvil del tanque.');
  const openingQuality = type === 'opening' && 'valuationQuality' in input ? input.valuationQuality : undefined;
  if (type === 'opening' && openingQuality === 'known' && !input.totalCostUsd) throw new BadRequestException('Un saldo inicial con costo conocido requiere costo total documentado.');
  if (type === 'opening' && openingQuality !== 'known' && input.totalCostUsd !== undefined) throw new BadRequestException('Solo se acepta costo total cuando la valuación del saldo inicial es conocida.');
  if (type === 'opening' && new Decimal(input.quantity).isZero() && input.totalCostUsd !== undefined && !new Decimal(input.totalCostUsd).isZero()) throw new BadRequestException('Un tanque con saldo inicial cero no puede tener valor de inventario.');
  const signed = ['sale','loss','adjustment_out'].includes(type) ? new Decimal(entered).negated().toFixed(12) : entered;
  const deltaLiters = input.volumeBasis === 'compensated'
    ? (signed.startsWith('-') ? new Decimal(compensated!).negated().toFixed(12) : compensated!)
    : signed;
  if (type === 'adjustment_in' && input.direction !== 'in' || type === 'adjustment_out' && input.direction !== 'out') throw new BadRequestException('El sentido del ajuste no coincide con el movimiento.');
  return {
    quantityEntered: input.quantity,
    unit: input.unit,
    conversionFactor: input.unit === 'us_gallon' ? '3.785411784000' : '1.000000000000',
    observedLiters: entered,
    compensatedLiters: compensated,
    deltaLiters,
    volumeBasis: input.volumeBasis,
    totalCostInput: input.totalCostUsd ? money(input.totalCostUsd) : null,
    valuationQualityInput: openingQuality,
    sourceType: type === 'opening' ? 'opening_balance' : type === 'receipt' ? 'supplier_receipt' : type === 'sale' ? 'pump_sales' : type === 'loss' ? 'incident_loss' : 'manual_adjustment',
    sourceId: input.sourceId ?? null,
    sourceLine: input.sourceLine ?? null,
    reason: input.reason?.trim() || null,
    documentReference: input.documentReference?.trim() || null,
  };
}

function validateTemperature(input: FuelInventoryCommandDto): void {
  for (const [label, value] of [['temperatureC', input.temperatureC], ['referenceTemperatureC', input.referenceTemperatureC]] as const) {
    if (value === undefined) continue;
    const temperature = new Decimal(value);
    if (!temperature.isFinite() || temperature.lt(-50) || temperature.gt(100)) throw new BadRequestException(`${label} debe estar entre −50 y 100 °C.`);
  }
}

function convertToLiters(value: string, unit: 'liter' | 'us_gallon', allowZero = false): string {
  try { return unit === 'liter' ? normalizeDecimal(value, allowZero) : gallonsToLiters(value); }
  catch (error) { throw new BadRequestException(error instanceof Error ? error.message : 'La cantidad no es válida.'); }
}

function normalizeDecimal(value: string, allowZero = false): string {
  if (!/^\d{1,12}(?:\.\d{1,12})?$/.test(value)) throw new BadRequestException('La cantidad debe ser decimal y positiva.');
  const result = new Decimal(value);
  if (!result.isFinite() || (allowZero ? result.isNegative() : !result.gt(0))) throw new BadRequestException(allowZero ? 'La cantidad no puede ser negativa.' : 'La cantidad debe ser mayor que cero.');
  return result.toDecimalPlaces(12, Decimal.ROUND_HALF_UP).toFixed(12);
}

function calculateValuation(type: MovementType, input: ReturnType<typeof normalizeCommand>, previous: BalanceRow | null, before: string, delta: string) {
  const quantity = new Decimal(before);
  const magnitude = new Decimal(delta).abs();
  const existingKnown = previous?.valuation_quality === 'known';
  const oldValue = previous?.inventory_value_usd ?? null;
  let balanceQuality: 'known' | 'unknown' | 'provisional' = previous?.valuation_quality ?? 'unknown';
  let inventoryValue: string | null = oldValue;
  let averageCost: string | null = previous?.average_cost_per_l_usd ?? null;
  let totalCost = input.totalCostInput;
  let unitCost: string | null = null;
  let costRecognized: string | null = null;
  let quality: 'known' | 'unknown' | 'provisional' = 'unknown';

  if (type === 'opening') {
    quality = input.valuationQualityInput ?? 'unknown';
    balanceQuality = quality;
    if (quality === 'known') {
      if (magnitude.isZero() && totalCost && new Decimal(totalCost).isZero()) {
        inventoryValue = '0.00'; averageCost = '0.000000000000';
      } else {
        inventoryValue = totalCost;
        averageCost = totalCost ? new Decimal(totalCost).div(magnitude).toDecimalPlaces(12, Decimal.ROUND_HALF_UP).toFixed(12) : null;
      }
      unitCost = averageCost;
    } else { inventoryValue = null; averageCost = null; totalCost = null; }
    return { quality, balanceQuality, inventoryValue, averageCost, totalCost, unitCost, costRecognized };
  }

  if (type === 'receipt' || type === 'adjustment_in') {
    if (totalCost) unitCost = new Decimal(totalCost).div(magnitude).toDecimalPlaces(12, Decimal.ROUND_HALF_UP).toFixed(12);
    const incomingKnown = Boolean(totalCost);
    if (incomingKnown && (existingKnown || quantity.isZero())) {
      const previousValue = existingKnown && oldValue ? oldValue : '0';
      inventoryValue = money(new Decimal(previousValue).plus(totalCost!).toString());
      averageCost = weightedAverageCost({ currentQuantity: before, currentValue: previousValue, incomingQuantity: magnitude.toString(), incomingValue: totalCost! });
      balanceQuality = 'known'; quality = 'known';
    } else {
      balanceQuality = 'unknown'; quality = input.valuationQualityInput ?? (incomingKnown ? 'provisional' : 'unknown');
      inventoryValue = null; averageCost = null;
    }
    return { quality, balanceQuality, inventoryValue, averageCost, totalCost, unitCost, costRecognized };
  }

  if (existingKnown && averageCost) {
    unitCost = averageCost;
    costRecognized = money(magnitude.mul(averageCost).toString());
    const remaining = new Decimal(oldValue ?? '0').minus(costRecognized);
    if (remaining.isNegative() && remaining.abs().gt('0.01')) throw new ConflictException('La valuación resultante sería negativa; revisa el saldo de costo.');
    inventoryValue = money(remaining.isNegative() ? '0' : remaining.toString());
    averageCost = new Decimal(before).eq(magnitude) ? '0.000000000000' : averageCost;
    balanceQuality = 'known'; quality = 'known';
  } else {
    inventoryValue = null; averageCost = null; balanceQuality = 'unknown'; quality = 'unknown';
  }
  totalCost = null;
  return { quality, balanceQuality, inventoryValue, averageCost, totalCost, unitCost, costRecognized };
}

async function findCommand(client: PoolClient, organizationId: string, commandId: string) {
  const result = await client.query('SELECT id,request_hash,movement_type AS "movementType",tank_id AS "tankId",delta_l AS "deltaL",after_quantity_l AS "afterQuantityL" FROM inventory_movements WHERE organization_id=$1 AND command_id=$2', [organizationId, commandId]);
  return result.rows[0] ?? null;
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.entries(value as Record<string, unknown>).sort(([a],[b]) => a.localeCompare(b)).map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`).join(',')}}`;
  return JSON.stringify(value) ?? 'null';
}

function encodeCursor(time: Date | string, id: string): string { return Buffer.from(`${new Date(time).toISOString()}|${id}`).toString('base64url'); }
function decodeCursor(value: string): { time: string; id: string } {
  try {
    const decoded = Buffer.from(value, 'base64url').toString('utf8');
    const [time, id] = decoded.split('|');
    if (!time || !id || !Number.isFinite(Date.parse(time)) || !/^[0-9a-f-]{36}$/i.test(id)) throw new Error('bad cursor');
    return { time: new Date(time).toISOString(), id };
  } catch { throw new BadRequestException('El cursor del historial no es válido.'); }
}
function isUnique(error: unknown): boolean { return Boolean(error && typeof error === 'object' && 'code' in error && error.code === '23505'); }
