import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { Decimal } from 'decimal.js';
import { createHash, randomUUID } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { AuditService } from '../audit/audit.service.js';
import { FuelInventoryService } from '../inventory/fuel-inventory.service.js';
import type { CreateDispenseAuthorizationDto, DispenseCompletionDto, DispenseNoFlowReconciliationDto, DispenseProgressDto, DispenseReasonDto } from './dispensing.dto.js';
import {
  BranchProfileDto, ChangePhysicalStatusDto, ConnectNozzleDto, CreateAssetBlockDto,
  CreateDispenserDto, CreateFuelProductDto, CreateNozzleDto, CreateTankDto,
  FuelSpecificationDto, ResolveAssetBlockDto, UpdateFuelOfferDto, UpdateFuelProductDto,
  NozzleMeterBaselineDto, NozzleMeterChangeDto, NozzleMeterReadingDto,
} from './infrastructure.dto.js';

@Injectable()
export class InfrastructureService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly audit: AuditService, private readonly inventory: FuelInventoryService) {}

  async setProfile(branchId: string, principal: AuthPrincipal, input: BranchProfileDto) {
    if (input.profile === 'academicLab22' && input.expectedDispenserCount !== 6) {
      throw new BadRequestException('El perfil académico requiere exactamente seis dispensadores configurados.');
    }
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const branch = await client.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 FOR UPDATE', [branchId, principal.organizationId]);
      if (!branch.rowCount) throw new NotFoundException('La sucursal no existe.');
      const current = await client.query<{ configuration_version: number }>(
        'SELECT configuration_version FROM branch_operating_profiles WHERE branch_id=$1 AND organization_id=$2 FOR UPDATE', [branchId, principal.organizationId],
      );
      const actualVersion = current.rows[0]?.configuration_version ?? 0;
      if (actualVersion !== input.expectedVersion) throw new ConflictException('El perfil cambió; recarga la configuración.');
      const row = await client.query(
        `INSERT INTO branch_operating_profiles (branch_id, organization_id, profile, expected_dispenser_count, updated_by)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (branch_id) DO UPDATE SET profile=EXCLUDED.profile,
           expected_dispenser_count=EXCLUDED.expected_dispenser_count,
           configuration_version=branch_operating_profiles.configuration_version+1,
           updated_by=EXCLUDED.updated_by,updated_at=now()
         RETURNING branch_id AS "branchId", profile, expected_dispenser_count AS "expectedDispenserCount", configuration_version AS version`,
        [branchId, principal.organizationId, input.profile, input.expectedDispenserCount, principal.userId],
      );
      await client.query('COMMIT');
      return row.rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw mapConstraint(error);
    } finally { client.release(); }
  }

  async createFuelProduct(principal: AuthPrincipal, input: CreateFuelProductDto) {
    try {
      const result = await this.pool.query(
        `INSERT INTO fuel_products (organization_id, sku, display_name, family, brand)
         VALUES ($1,$2,$3,$4,$5)
         RETURNING id,sku,display_name AS "displayName",family,brand,status,created_at AS "createdAt"`,
        [principal.organizationId, input.sku.trim().toUpperCase(), input.displayName.trim(), input.family, input.brand?.trim() ?? null],
      );
      return result.rows[0];
    } catch (error) { throw mapConstraint(error); }
  }

  async listFuelProducts(principal: AuthPrincipal, filters: { query?: string; family?: string; status?: string; limit: number; cursor?: string }) {
    const values: unknown[] = [principal.organizationId];
    const where = ['organization_id=$1'];
    if (filters.query) { values.push(`%${escapeLike(filters.query.trim())}%`); where.push(`(sku ILIKE $${values.length} ESCAPE '\\' OR display_name ILIKE $${values.length} ESCAPE '\\' OR COALESCE(brand,'') ILIKE $${values.length} ESCAPE '\\')`); }
    if (filters.family) { values.push(filters.family); where.push(`family=$${values.length}`); }
    if (filters.status) { values.push(filters.status); where.push(`status=$${values.length}`); }
    if (filters.cursor) { values.push(filters.cursor); where.push(`id>$${values.length}::uuid`); }
    const limit = Math.max(1, Math.min(200, filters.limit));
    values.push(limit + 1);
    const result = await this.pool.query(
      `SELECT id,sku,display_name AS "displayName",family,brand,status
         FROM fuel_products WHERE ${where.join(' AND ')} ORDER BY id LIMIT $${values.length}`,
      values,
    );
    const hasMore = result.rows.length > limit;
    const data = hasMore ? result.rows.slice(0, limit) : result.rows;
    return { data, meta: { limit, nextCursor: hasMore ? data.at(-1)!.id : null } };
  }

  async fuelProductDetail(productId: string, principal: AuthPrincipal) {
    const product = await this.pool.query(
      `SELECT id,sku,display_name AS "displayName",family,brand,status,version,created_at AS "createdAt",updated_at AS "updatedAt"
         FROM fuel_products WHERE id=$1 AND organization_id=$2`, [productId, principal.organizationId],
    );
    if (!product.rowCount) throw new NotFoundException('El producto no existe.');
    const [specifications, offers] = await Promise.all([
      this.pool.query(`SELECT id,attribute_code AS "attributeCode",value,unit,test_method AS "testMethod",source_name AS "sourceName",source_reference AS "sourceReference",valid_from AS "validFrom",valid_until AS "validUntil" FROM fuel_product_specifications WHERE fuel_product_id=$1 AND organization_id=$2 ORDER BY attribute_code,valid_from DESC`, [productId, principal.organizationId]),
      this.pool.query(`SELECT o.branch_id AS "branchId",b.code AS "branchCode",b.name AS "branchName",o.status,o.valid_from AS "validFrom",o.valid_until AS "validUntil" FROM branch_fuel_offers o JOIN branches b ON b.id=o.branch_id WHERE o.fuel_product_id=$1 AND o.organization_id=$2 ORDER BY b.name`, [productId, principal.organizationId]),
    ]);
    return { data: { ...product.rows[0], specifications: specifications.rows, branchOffers: offers.rows } };
  }

  async updateFuelProduct(productId: string, principal: AuthPrincipal, input: UpdateFuelProductDto) {
    const setters: string[] = [];
    const values: unknown[] = [productId, principal.organizationId];
    if (input.displayName !== undefined) { values.push(input.displayName.trim()); setters.push(`display_name=$${values.length}`); }
    if (input.brand !== undefined) { values.push(input.brand?.trim() || null); setters.push(`brand=$${values.length}`); }
    if (input.status !== undefined) { values.push(input.status); setters.push(`status=$${values.length}`); }
    if (!setters.length) throw new BadRequestException('Envía al menos un campo para modificar.');
    setters.push('version=version+1','updated_at=now()');
    values.push(input.expectedVersion);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const current = await client.query('SELECT version FROM fuel_products WHERE id=$1 AND organization_id=$2 FOR UPDATE', [productId, principal.organizationId]);
      if (!current.rowCount || current.rows[0]!.version !== input.expectedVersion) throw new ConflictException('El producto cambió o no existe; actualiza la ficha.');
      if (input.status && input.status !== 'active') {
        const activeOffers = await client.query('SELECT 1 FROM branch_fuel_offers WHERE fuel_product_id=$1 AND organization_id=$2 AND status=$3 LIMIT 1', [productId, principal.organizationId, 'active']);
        if (activeOffers.rowCount) throw new ConflictException('Desactiva primero las ofertas activas por sucursal.');
      }
      const result = await client.query(
        `UPDATE fuel_products SET ${setters.join(',')} WHERE id=$1 AND organization_id=$2 AND version=$${values.length}
         RETURNING id,sku,display_name AS "displayName",family,brand,status,version,updated_at AS "updatedAt"`, values,
      );
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw mapConstraint(error); }
    finally { client.release(); }
  }

  async updateFuelOffer(branchId: string, productId: string, principal: AuthPrincipal, input: UpdateFuelOfferDto) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const product = await client.query<{ status: string }>('SELECT status FROM fuel_products WHERE id=$1 AND organization_id=$2 FOR UPDATE', [productId, principal.organizationId]);
      if (!product.rowCount) throw new NotFoundException('El producto no existe.');
      if (input.status === 'active' && product.rows[0]!.status !== 'active') throw new ConflictException('No se puede habilitar oferta para un producto inactivo.');
      const result = await client.query(
      `UPDATE branch_fuel_offers SET status=$4,
          valid_from=CASE WHEN $4='active' AND status<>'active' THEN now() ELSE valid_from END,
          valid_until=CASE WHEN $4='inactive' THEN now() ELSE NULL END,
          version=version+1
        WHERE branch_id=$1 AND fuel_product_id=$2 AND organization_id=$3 AND version=$5
        RETURNING branch_id AS "branchId",fuel_product_id AS "fuelProductId",status,version,valid_from AS "validFrom",valid_until AS "validUntil"`,
      [branchId, productId, principal.organizationId, input.status, input.expectedVersion],
      );
      if (!result.rowCount) throw new ConflictException('La oferta cambió o no existe; actualiza la ficha.');
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw mapConstraint(error); }
    finally { client.release(); }
  }

  async addSpecification(productId: string, principal: AuthPrincipal, input: FuelSpecificationDto) {
    try {
      const result = await this.pool.query(
        `INSERT INTO fuel_product_specifications
          (organization_id,fuel_product_id,attribute_code,value,unit,test_method,source_name,source_reference,valid_from,valid_until)
         SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10 FROM fuel_products
          WHERE id=$2 AND organization_id=$1 AND status <> 'archived'
         RETURNING id,fuel_product_id AS "fuelProductId",attribute_code AS "attributeCode",value,unit,test_method AS "testMethod",source_name AS "sourceName",source_reference AS "sourceReference",valid_from AS "validFrom",valid_until AS "validUntil"`,
        [principal.organizationId, productId, input.attributeCode, input.value.trim(), input.unit ?? null,
         input.testMethod ?? null, input.sourceName.trim(), input.sourceReference ?? null, input.validFrom, input.validUntil ?? null],
      );
      if (!result.rowCount) throw new NotFoundException('El producto no existe.');
      return result.rows[0];
    } catch (error) { throw mapConstraint(error); }
  }

  async createOffer(branchId: string, principal: AuthPrincipal, fuelProductId: string) {
    try {
      const client = await this.pool.connect();
      try {
        await client.query('BEGIN');
        await this.requireBranch(client, branchId, principal);
        const product = await client.query('SELECT id FROM fuel_products WHERE id=$1 AND organization_id=$2 AND status=$3 FOR UPDATE', [fuelProductId, principal.organizationId, 'active']);
        if (!product.rowCount) throw new NotFoundException('El combustible no existe o está inactivo.');
        const result = await client.query(
          `INSERT INTO branch_fuel_offers (organization_id,branch_id,fuel_product_id,created_by)
           VALUES ($1,$2,$3,$4) ON CONFLICT (branch_id,fuel_product_id) DO UPDATE
             SET status='active',valid_from=now(),valid_until=NULL,created_by=EXCLUDED.created_by,version=branch_fuel_offers.version+1
           RETURNING branch_id AS "branchId",fuel_product_id AS "fuelProductId",status,version,valid_from AS "validFrom"`,
          [principal.organizationId, branchId, fuelProductId, principal.userId],
        );
        await client.query('COMMIT');
        return result.rows[0];
      } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
      finally { client.release(); }
    } catch (error) { throw mapConstraint(error); }
  }

  async createTank(branchId: string, principal: AuthPrincipal, input: CreateTankDto) {
    const nominal = positive(input.nominalCapacityL, 'Capacidad nominal');
    const safe = positive(input.safeFillLimitL, 'Límite de llenado seguro');
    const reserve = nonnegative(input.unusableReserveL, 'Reserva no utilizable');
    if (safe.gt(nominal) || reserve.gte(safe)) throw new BadRequestException('El límite seguro debe ser menor o igual a la capacidad y mayor que la reserva.');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const offer = await client.query(`SELECT 1 FROM branch_fuel_offers WHERE organization_id=$1 AND branch_id=$2 AND fuel_product_id=$3 AND status='active' FOR UPDATE`, [principal.organizationId, branchId, input.fuelProductId]);
      if (!offer.rowCount) throw new ConflictException('El combustible no está habilitado en esta sucursal.');
      const result = await client.query(
        `INSERT INTO tanks (organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l,unusable_reserve_l)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         RETURNING id,branch_id AS "branchId",code,name,fuel_product_id AS "fuelProductId",nominal_capacity_l AS "nominalCapacityL",safe_fill_limit_l AS "safeFillLimitL",unusable_reserve_l AS "unusableReserveL",status,version`,
        [principal.organizationId, branchId, input.code.trim().toUpperCase(), input.name.trim(), input.fuelProductId, nominal.toString(), safe.toString(), reserve.toString()],
      );
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw mapConstraint(error); }
    finally { client.release(); }
  }

  async listTanks(branchId: string, principal: AuthPrincipal, filters: { query?: string; status?: string; fuelProductId?: string; limit: number; cursor?: string }) {
    await this.requireBranch(this.pool, branchId, principal);
    const values: unknown[] = [principal.organizationId, branchId];
    const where = ['t.organization_id=$1','t.branch_id=$2'];
    if (filters.query) { values.push(`%${escapeLike(filters.query.trim())}%`); where.push(`(t.code ILIKE $${values.length} ESCAPE '\\' OR t.name ILIKE $${values.length} ESCAPE '\\')`); }
    if (filters.status) { values.push(filters.status); where.push(`t.status=$${values.length}`); }
    if (filters.fuelProductId) { values.push(filters.fuelProductId); where.push(`t.fuel_product_id=$${values.length}`); }
    if (filters.cursor) { values.push(filters.cursor); where.push(`t.id>$${values.length}::uuid`); }
    const limit = Math.max(1, Math.min(200, filters.limit));
    values.push(limit + 1);
    const result = await this.pool.query(
      `SELECT t.id,t.code,t.name,t.fuel_product_id AS "fuelProductId",p.display_name AS "fuelName",p.family,
              t.nominal_capacity_l AS "nominalCapacityL",t.safe_fill_limit_l AS "safeFillLimitL",
              t.unusable_reserve_l AS "unusableReserveL",t.status,t.version
         FROM tanks t JOIN fuel_products p ON p.id=t.fuel_product_id
        WHERE ${where.join(' AND ')} ORDER BY t.id LIMIT $${values.length}`,
      values,
    );
    const hasMore = result.rows.length > limit;
    const data = hasMore ? result.rows.slice(0, limit) : result.rows;
    return { data, meta: { limit, nextCursor: hasMore ? data.at(-1)!.id : null } };
  }

  async tankDetail(branchId: string, tankId: string, principal: AuthPrincipal) {
    const result = await this.pool.query(
      `SELECT t.id,t.branch_id AS "branchId",t.code,t.name,t.fuel_product_id AS "fuelProductId",p.display_name AS "fuelName",p.family,
              t.nominal_capacity_l AS "nominalCapacityL",t.safe_fill_limit_l AS "safeFillLimitL",t.unusable_reserve_l AS "unusableReserveL",t.status,t.version,
              COALESCE(jsonb_agg(jsonb_build_object('connectionId',c.id,'nozzleId',n.id,'nozzleCode',n.code,'dispenserId',d.id,'dispenserCode',d.code,'validFrom',c.valid_from,'validUntil',c.valid_until)) FILTER (WHERE c.id IS NOT NULL),'[]'::jsonb) AS connections
         FROM tanks t JOIN fuel_products p ON p.id=t.fuel_product_id
         LEFT JOIN nozzle_tank_connections c ON c.tank_id=t.id
         LEFT JOIN nozzles n ON n.id=c.nozzle_id LEFT JOIN dispensers d ON d.id=n.dispenser_id
        WHERE t.id=$1 AND t.branch_id=$2 AND t.organization_id=$3 GROUP BY t.id,p.id`,
      [tankId, branchId, principal.organizationId],
    );
    if (!result.rowCount) throw new NotFoundException('El tanque no existe en esta sucursal.');
    return result.rows[0];
  }

  async createDispenser(branchId: string, principal: AuthPrincipal, input: CreateDispenserDto) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const branch = await client.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 FOR UPDATE', [branchId, principal.organizationId]);
      if (!branch.rowCount) throw new NotFoundException('La sucursal no existe.');
      const profile = await client.query<{ profile: string; expected_dispenser_count: number }>(
        'SELECT profile,expected_dispenser_count FROM branch_operating_profiles WHERE branch_id=$1 AND organization_id=$2', [branchId, principal.organizationId],
      );
      const current = await client.query<{ count: string }>('SELECT count(*) FROM dispensers WHERE branch_id=$1 AND organization_id=$2 AND physical_status <> $3', [branchId, principal.organizationId, 'decommissioned']);
      const count = Number(current.rows[0]!.count);
      if (profile.rows[0]?.profile === 'academicLab22' && count >= 6) throw new ConflictException('El perfil académico solo admite seis dispensadores.');
      const result = await client.query(
        `INSERT INTO dispensers (organization_id,branch_id,code,name,commissioned_at)
         VALUES ($1,$2,$3,$4,$5) RETURNING id,branch_id AS "branchId",code,name,physical_status AS "physicalStatus",version`,
        [principal.organizationId, branchId, input.code.trim().toUpperCase(), input.name?.trim() ?? null, input.commissionedAt ?? null],
      );
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw mapConstraint(error); }
    finally { client.release(); }
  }

  async createNozzle(branchId: string, dispenserId: string, principal: AuthPrincipal, input: CreateNozzleDto) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const dispenser = await client.query(`SELECT id FROM dispensers WHERE id=$1 AND branch_id=$2 AND organization_id=$3 AND physical_status<>'decommissioned' FOR UPDATE`, [dispenserId, branchId, principal.organizationId]);
      const offer = await client.query(`SELECT 1 FROM branch_fuel_offers WHERE branch_id=$1 AND fuel_product_id=$2 AND organization_id=$3 AND status='active' FOR UPDATE`, [branchId, input.fuelProductId, principal.organizationId]);
      if (!dispenser.rowCount || !offer.rowCount) throw new ConflictException('Dispensador inexistente o combustible no ofertado en la sucursal.');
      const result = await client.query(
        `INSERT INTO nozzles (organization_id,branch_id,dispenser_id,code,product_code,fuel_product_id,service_mode,meter_unit,meter_precision)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         RETURNING id,dispenser_id AS "dispenserId",code,product_code AS "productCode",fuel_product_id AS "fuelProductId",service_mode AS "serviceMode",physical_status AS "physicalStatus",meter_unit AS "meterUnit",meter_precision AS "meterPrecision",version`,
        [principal.organizationId, branchId, dispenserId, input.code.trim().toUpperCase(), input.productCode.trim().toUpperCase(), input.fuelProductId, input.serviceMode, input.meterUnit, input.meterPrecision],
      );
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw mapConstraint(error); }
    finally { client.release(); }
  }

  async connectNozzle(branchId: string, nozzleId: string, principal: AuthPrincipal, input: ConnectNozzleDto) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const nozzle = await client.query<{ fuel_product_id: string }>(
        `SELECT fuel_product_id FROM nozzles WHERE id=$1 AND branch_id=$2 AND organization_id=$3 AND physical_status <> 'removed' FOR UPDATE`,
        [nozzleId, branchId, principal.organizationId],
      );
      if (!nozzle.rowCount) throw new NotFoundException('La manguera no existe en esta sucursal.');
      const tank = await client.query(
        `SELECT id FROM tanks WHERE id=$1 AND branch_id=$2 AND organization_id=$3
          AND fuel_product_id=$4 AND status <> 'decommissioned' FOR UPDATE`,
        [input.tankId, branchId, principal.organizationId, nozzle.rows[0]!.fuel_product_id],
      );
      if (!tank.rowCount) throw new ConflictException('La conexión debe apuntar a un tanque de la misma sucursal y combustible.');
      await client.query('UPDATE nozzle_tank_connections SET valid_until=now() WHERE nozzle_id=$1 AND valid_until IS NULL', [nozzleId]);
      const result = await client.query(
        `INSERT INTO nozzle_tank_connections (organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,created_by,reason)
         VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id,nozzle_id AS "nozzleId",tank_id AS "tankId",fuel_product_id AS "fuelProductId",valid_from AS "validFrom"`,
        [principal.organizationId, branchId, nozzleId, input.tankId, nozzle.rows[0]!.fuel_product_id, principal.userId, input.reason.trim()],
      );
      await client.query('UPDATE nozzles SET version=version+1,updated_at=now() WHERE id=$1', [nozzleId]);
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw mapConstraint(error); }
    finally { client.release(); }
  }

  async listDispensers(branchId: string, principal: AuthPrincipal, filters: { query?: string; status?: string; fuelProductId?: string; serviceMode?: string; limit: number; cursor?: string }) {
    await this.requireBranch(this.pool, branchId, principal);
    const values: unknown[] = [principal.organizationId, branchId];
    const where = ['d.organization_id=$1', 'd.branch_id=$2'];
    if (filters.query) { values.push(`%${escapeLike(filters.query.trim())}%`); where.push(`(d.code ILIKE $${values.length} ESCAPE '\\' OR COALESCE(d.name,'') ILIKE $${values.length} ESCAPE '\\')`); }
    if (filters.status) { values.push(filters.status); where.push(`d.physical_status=$${values.length}`); }
    if (filters.fuelProductId) { values.push(filters.fuelProductId); where.push(`EXISTS (SELECT 1 FROM nozzles n WHERE n.dispenser_id=d.id AND n.fuel_product_id=$${values.length} AND n.physical_status <> 'removed')`); }
    if (filters.serviceMode) { values.push(filters.serviceMode); where.push(`EXISTS (SELECT 1 FROM nozzles n WHERE n.dispenser_id=d.id AND n.service_mode=$${values.length} AND n.physical_status <> 'removed')`); }
    if (filters.cursor) { values.push(filters.cursor); where.push(`d.id>$${values.length}::uuid`); }
    const limit = Math.max(1, Math.min(200, filters.limit));
    values.push(limit + 1);
    const rows = await this.pool.query(
      `SELECT d.id,d.code,d.name,d.physical_status AS "physicalStatus",d.version,
         count(n.id)::int AS "nozzleCount",
         count(n.id) FILTER (WHERE n.physical_status='active')::int AS "activeNozzles",
         COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id',fp.id,'name',fp.display_name,'family',fp.family,'productCode',n.product_code,'serviceMode',n.service_mode)) FILTER (WHERE n.id IS NOT NULL),'[]'::jsonb) AS products
       FROM dispensers d LEFT JOIN nozzles n ON n.dispenser_id=d.id AND n.physical_status <> 'removed'
       LEFT JOIN fuel_products fp ON fp.id=n.fuel_product_id AND fp.organization_id=d.organization_id
       WHERE ${where.join(' AND ')} GROUP BY d.id ORDER BY d.id LIMIT $${values.length}`,
      values,
    );
    const hasMore = rows.rows.length > limit;
    const data = hasMore ? rows.rows.slice(0, limit) : rows.rows;
    return { data, meta: { limit, nextCursor: hasMore ? data.at(-1)!.id : null } };
  }

  async dispenserDetail(branchId: string, dispenserId: string, principal: AuthPrincipal) {
    const result = await this.pool.query(
      `SELECT d.id,d.branch_id AS "branchId",d.code,d.name,d.physical_status AS "physicalStatus",d.version,
         COALESCE(jsonb_agg(jsonb_build_object(
           'id',n.id,'code',n.code,'productCode',n.product_code,'fuelProductId',n.fuel_product_id,
           'fuelName',fp.display_name,'family',fp.family,'serviceMode',n.service_mode,
           'physicalStatus',n.physical_status,'meterUnit',n.meter_unit,'meterPrecision',n.meter_precision,
           'tankId',c.tank_id,'tankCode',t.code,'version',n.version,'meterValue',ms.last_value,
           'meterSerial',ms.meter_serial,'meterVersion',ms.version,'lastMeterReadingId',ms.last_reading_id,
           'lastMeterReadingAt',mr.captured_at
         ) ORDER BY n.code) FILTER (WHERE n.id IS NOT NULL),'[]'::jsonb) AS nozzles
       FROM dispensers d LEFT JOIN nozzles n ON n.dispenser_id=d.id AND n.physical_status <> 'removed'
       LEFT JOIN fuel_products fp ON fp.id=n.fuel_product_id AND fp.organization_id=d.organization_id
       LEFT JOIN nozzle_tank_connections c ON c.nozzle_id=n.id AND c.valid_until IS NULL
       LEFT JOIN nozzle_meter_states ms ON ms.nozzle_id=n.id
       LEFT JOIN nozzle_meter_readings mr ON mr.id=ms.last_reading_id AND mr.nozzle_id=n.id
       LEFT JOIN tanks t ON t.id=c.tank_id
       WHERE d.id=$1 AND d.branch_id=$2 AND d.organization_id=$3 GROUP BY d.id`,
      [dispenserId, branchId, principal.organizationId],
    );
    if (!result.rowCount) throw new NotFoundException('El dispensador no existe en esta sucursal.');
    return result.rows[0];
  }

  async meterReadings(branchId: string, nozzleId: string, principal: AuthPrincipal, limit = 50) {
    const nozzle = await this.pool.query('SELECT id FROM nozzles WHERE id=$1 AND branch_id=$2 AND organization_id=$3', [nozzleId,branchId,principal.organizationId]);
    if (!nozzle.rowCount) throw new NotFoundException('La manguera no existe en esta sucursal.');
    const [state, history] = await Promise.all([
      this.pool.query(`SELECT unit,last_value AS "lastValue",meter_serial AS "meterSerial",version,last_reading_id AS "lastReadingId",updated_at AS "updatedAt"
        FROM nozzle_meter_states WHERE nozzle_id=$1`, [nozzleId]),
      this.pool.query(`SELECT id,reading_type AS "readingType",value,unit,prior_value AS "priorValue",prior_meter_serial AS "priorMeterSerial",
        meter_serial AS "meterSerial",old_serial AS "oldSerial",new_serial AS "newSerial",change_reason AS "changeReason",note,source,
        captured_by AS "capturedBy",captured_at AS "capturedAt" FROM nozzle_meter_readings
        WHERE organization_id=$1 AND branch_id=$2 AND nozzle_id=$3 ORDER BY captured_at DESC,id DESC LIMIT $4`,
      [principal.organizationId,branchId,nozzleId,Math.max(1,Math.min(limit,100))]),
    ]);
    return {data:{state:state.rows[0] ?? null,readings:history.rows}};
  }

  async captureMeterBaseline(branchId:string,nozzleId:string,principal:AuthPrincipal,input:NozzleMeterBaselineDto,correlationId:string){
    return this.captureMeterEvent(branchId,nozzleId,principal,input,correlationId,'baseline');
  }

  async captureMeterReading(branchId:string,nozzleId:string,principal:AuthPrincipal,input:NozzleMeterReadingDto,correlationId:string){
    return this.captureMeterEvent(branchId,nozzleId,principal,input,correlationId,'regular');
  }

  async changeMeter(branchId:string,nozzleId:string,principal:AuthPrincipal,input:NozzleMeterChangeDto,correlationId:string){
    return this.captureMeterEvent(branchId,nozzleId,principal,input,correlationId,'meter_change');
  }

  private async captureMeterEvent(branchId:string,nozzleId:string,principal:AuthPrincipal,
    input:NozzleMeterBaselineDto|NozzleMeterReadingDto|NozzleMeterChangeDto,correlationId:string,readingType:'baseline'|'regular'|'meter_change'){
    let reading:Decimal;
    try{reading=new Decimal(input.value);}catch{throw new BadRequestException('La lectura no es válida.');}
    if(!reading.isFinite()||reading.isNegative()) throw new BadRequestException('La lectura debe ser un valor acumulado no negativo.');
    const requestPayload={branchId,nozzleId,readingType,...input,value:reading.toFixed(9)};
    const requestHash=createHash('sha256').update(JSON.stringify(requestPayload)).digest('hex');
    const client=await this.pool.connect();
    try{
      await client.query('BEGIN');
      const duplicate=await client.query<{id:string;request_hash:string;value:string;unit:string;reading_type:string}>(
        `SELECT id,request_hash,value,unit,reading_type,reading_type AS "readingType",prior_value AS "priorValue",
          prior_meter_serial AS "priorMeterSerial",meter_serial AS "meterSerial",old_serial AS "oldSerial",new_serial AS "newSerial",
          change_reason AS "changeReason",note,source,captured_by AS "capturedBy",captured_at AS "capturedAt"
         FROM nozzle_meter_readings WHERE organization_id=$1 AND command_id=$2`,[principal.organizationId,input.commandId]);
      if(duplicate.rows[0]){
        if(duplicate.rows[0].request_hash!==requestHash) throw new ConflictException('commandId ya fue utilizado para otra lectura.');
        await client.query('COMMIT');
        return {data:{...duplicate.rows[0],idempotentReplay:true}};
      }
      const found=await client.query<{unit:string;physical_status:string}>(
        `SELECT meter_unit AS unit,physical_status FROM nozzles WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`,[nozzleId,branchId,principal.organizationId]);
      const nozzle=found.rows[0];
      if(!nozzle||nozzle.physical_status==='removed') throw new NotFoundException('La manguera no existe o fue retirada.');
      const currentResult=await client.query<{unit:string;last_value:string;meter_serial:string|null;version:number;last_reading_id:string|null}>(
        'SELECT unit,last_value,meter_serial,version,last_reading_id FROM nozzle_meter_states WHERE nozzle_id=$1 FOR UPDATE',[nozzleId]);
      const current=currentResult.rows[0] ?? null;
      if(readingType==='baseline'){
        if(current||input.expectedVersion!==0) throw new ConflictException('El totalizador ya tiene línea base; no se puede reemplazar como una lectura inicial.');
      }else{
        if(!current) throw new ConflictException('Registra primero la línea base del totalizador.');
        if(input.expectedVersion!==current.version) throw new ConflictException('El totalizador cambió; vuelve a cargar su lectura.');
        if(current.unit!==nozzle.unit) throw new ConflictException('La unidad del totalizador cambió; requiere una revisión de configuración.');
        if(readingType==='regular'&&reading.lt(current.last_value)) throw new ConflictException('La lectura acumulada no puede disminuir. Registra un reemplazo/reset autorizado del medidor.');
        if(readingType==='regular'&&'meterSerial' in input&&input.meterSerial&&current.meter_serial&&input.meterSerial.trim()!==current.meter_serial) throw new ConflictException('El número de serie cambió; registra el evento de reemplazo del medidor.');
        if(readingType==='meter_change'&&current.meter_serial&&(!('oldSerial' in input)||input.oldSerial?.trim()!==current.meter_serial)) throw new ConflictException('El número de serie anterior no coincide con el medidor registrado.');
      }
      const id=randomUUID();
      const serial=readingType==='meter_change'&&'newSerial' in input?input.newSerial.trim():('meterSerial' in input?input.meterSerial?.trim()||current?.meter_serial||null:current?.meter_serial||null);
      const oldSerial=readingType==='meter_change'?('oldSerial' in input?input.oldSerial?.trim()||current?.meter_serial||null:null):null;
      const reason=readingType==='meter_change'&&'reason' in input?input.reason.trim():null;
      const note=readingType==='baseline'&&'note' in input?input.note?.trim()||null:null;
      const insert=await client.query(
        `INSERT INTO nozzle_meter_readings(id,organization_id,branch_id,nozzle_id,command_id,request_hash,reading_type,value,unit,prior_value,prior_reading_id,
          prior_meter_serial,meter_serial,old_serial,new_serial,change_reason,note,source,captured_by,correlation_id)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
         RETURNING id,reading_type AS "readingType",value,unit,prior_value AS "priorValue",meter_serial AS "meterSerial",old_serial AS "oldSerial",
           new_serial AS "newSerial",change_reason AS "changeReason",note,source,captured_at AS "capturedAt"`,
        [id,principal.organizationId,branchId,nozzleId,input.commandId,requestHash,readingType,reading.toFixed(9),nozzle.unit,current?.last_value??null,
          current?.last_reading_id??null,current?.meter_serial??null,serial,oldSerial,readingType==='meter_change'?serial:null,reason,note,input.source,principal.userId,correlationId]);
      if(current){
        await client.query(`UPDATE nozzle_meter_states SET last_value=$2,meter_serial=$3,version=version+1,last_reading_id=$4,updated_at=now() WHERE nozzle_id=$1 AND version=$5`,
          [nozzleId,reading.toFixed(9),serial,id,current.version]);
      }else{
        await client.query(`INSERT INTO nozzle_meter_states(nozzle_id,organization_id,branch_id,unit,last_value,meter_serial,last_reading_id)
          VALUES($1,$2,$3,$4,$5,$6,$7)`,[nozzleId,principal.organizationId,branchId,nozzle.unit,reading.toFixed(9),serial,id]);
      }
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:`nozzle_meter.${readingType}`,entityType:'nozzle_meter_reading',entityId:id,
        before:current?{value:current.last_value,serial:current.meter_serial,version:current.version}:null,
        after:{value:reading.toFixed(9),unit:nozzle.unit,serial,readingType,reason}});
      await client.query('COMMIT');
      return {data:{...insert.rows[0],version:(current?.version??0)+1,idempotentReplay:false}};
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUniqueViolation(error)) throw new ConflictException('La lectura ya fue guardada; usa el mismo commandId para recuperarla.');throw error;}finally{client.release();}
  }

  async createDispenseAuthorization(branchId:string,nozzleId:string,principal:AuthPrincipal,input:CreateDispenseAuthorizationDto,correlationId:string){
    const hasAmount=input.requestedAmountUsd!==undefined;
    const hasVolume=input.requestedVolume!==undefined;
    if(hasAmount===hasVolume||hasVolume!== (input.volumeUnit!==undefined)) throw new BadRequestException('Indica un importe USD o un volumen con su unidad, pero no ambos.');
    const request={branchId,nozzleId,...input};
    const requestHash=hashPayload(request);
    const client=await this.pool.connect();
    try{
      await client.query('BEGIN');
      const prior=await client.query<{id:string;request_hash:string;status:string}>(
        'SELECT id,request_hash,status FROM dispense_authorizations WHERE organization_id=$1 AND command_id=$2 FOR UPDATE',[principal.organizationId,input.commandId]);
      if(prior.rows[0]){
        if(prior.rows[0].request_hash!==requestHash) throw new ConflictException('commandId ya fue usado para otra autorización.');
        await client.query('COMMIT');
        return this.dispenseDetail(prior.rows[0].id,branchId,principal);
      }
      const nozzle=await client.query<{physical_status:string;fuel_product_id:string;service_mode:string;tank_id:string|null}>(
        `SELECT n.physical_status,n.fuel_product_id,n.service_mode,c.tank_id FROM nozzles n
          LEFT JOIN nozzle_tank_connections c ON c.nozzle_id=n.id AND c.valid_until IS NULL
          WHERE n.id=$1 AND n.branch_id=$2 AND n.organization_id=$3 FOR UPDATE OF n`,[nozzleId,branchId,principal.organizationId]);
      const currentNozzle=nozzle.rows[0];
      if(!currentNozzle||!currentNozzle.tank_id) throw new ConflictException('La manguera no existe o no tiene tanque fuente activo.');
      if(currentNozzle.physical_status!=='active') throw new ConflictException('La manguera no está habilitada para despacho.');
      await client.query(`UPDATE dispense_authorizations SET status='expired',version=version+1 WHERE nozzle_id=$1 AND status='authorized' AND expires_at<=now()`,[nozzleId]);
      const activeNozzle=await client.query('SELECT 1 FROM dispense_authorizations WHERE nozzle_id=$1 AND status IN (\'authorized\',\'dispensing\',\'unknown\',\'posting\') LIMIT 1',[nozzleId]);
      if(activeNozzle.rowCount) throw new ConflictException('La manguera ya tiene un despacho activo o pendiente de conciliación.');
      const tank=await client.query<{fuel_product_id:string;status:string;unusable_reserve_l:string}>(
        'SELECT fuel_product_id,status,unusable_reserve_l FROM tanks WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE',[currentNozzle.tank_id,branchId,principal.organizationId]);
      if(!tank.rows[0]||tank.rows[0].status!=='active'||tank.rows[0].fuel_product_id!==currentNozzle.fuel_product_id) throw new ConflictException('El tanque fuente no está activo o no corresponde a este combustible.');
      const balance=await client.query<{on_hand_l:string;valuation_quality:string}>(
        'SELECT on_hand_l,valuation_quality FROM tank_inventory_balances WHERE tank_id=$1 AND organization_id=$2 FOR UPDATE',[currentNozzle.tank_id,principal.organizationId]);
      if(!balance.rows[0]||balance.rows[0].valuation_quality==='unknown') throw new ConflictException('No se puede autorizar despacho sin saldo de inventario confiable.');
      const availability=await this.nozzleAvailability(branchId,nozzleId,principal);
      const availablePrice=availability.data.price;
      if(!availability.data.selectable||!availablePrice||availablePrice.amount===null) throw new ConflictException(availability.data.reasons.map(reason=>reason.message).join(' ')||'No hay un precio válido y vigente para autorizar el despacho.');
      const price=new Decimal(availablePrice.amount);
      const priceUnit=availablePrice.unit;
      const requestedAmount=hasAmount?new Decimal(input.requestedAmountUsd!):null;
      const requestedVolume=hasVolume?new Decimal(input.requestedVolume!):null;
      let reservedL:Decimal;
      if(requestedAmount){
        reservedL=priceUnit==='us_gallon'?requestedAmount.div(price).mul(GALLONS_TO_LITERS):requestedAmount.div(price);
      }else{
        reservedL=input.volumeUnit==='gallon_us'?requestedVolume!.mul(GALLONS_TO_LITERS):requestedVolume!;
      }
      if(!reservedL.isFinite()||!reservedL.gt(0)) throw new BadRequestException('El volumen de autorización debe ser positivo.');
      const otherReservations=await client.query<{reserved:string}>(
        `SELECT COALESCE(sum(reserved_l),0)::text AS reserved FROM dispense_authorizations WHERE tank_id=$1
          AND status IN ('authorized','dispensing','unknown','posting') AND (status<>'authorized' OR expires_at>now())`,[currentNozzle.tank_id]);
      const availableL=new Decimal(balance.rows[0].on_hand_l).minus(tank.rows[0].unusable_reserve_l).minus(otherReservations.rows[0]?.reserved??'0');
      if(reservedL.gt(availableL)) throw new ConflictException('El inventario disponible no cubre la autorización luego de descontar reserva y despachos pendientes.');
      const authorizationId=randomUUID();
      const expiresIn=input.expiresInSeconds??90;
      await client.query(
        `INSERT INTO dispense_authorizations(id,organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,price_version_id,service_mode,requested_by,command_id,request_hash,
          request_type,requested_amount_usd,requested_volume,requested_volume_unit,reserved_l,price_usd_per_unit,price_unit,expires_at)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,now()+($19::int*interval '1 second'))
         RETURNING id,status,request_type AS "requestType",reserved_l AS "reservedL",price_usd_per_unit AS "priceUsdPerUnit",price_unit AS "priceUnit",expires_at AS "expiresAt",version`,
        [authorizationId,principal.organizationId,branchId,nozzleId,currentNozzle.tank_id,currentNozzle.fuel_product_id,availablePrice.versionId,
          currentNozzle.service_mode,principal.userId,input.commandId,requestHash,hasAmount?'amount':'volume',requestedAmount?.toFixed(2)??null,requestedVolume?.toFixed(9)??null,
          input.volumeUnit??null,reservedL.toFixed(9),price.toFixed(8),priceUnit,expiresIn]);
      await this.addDispenseEvent(client,{principal,branchId,authorizationId,commandId:input.commandId,eventType:'authorized',previousStatus:null,nextStatus:'authorized',requestHash,correlationId});
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'dispense.authorized',entityType:'dispense_authorization',entityId:authorizationId,after:{nozzleId,tankId:currentNozzle.tank_id,reservedL:reservedL.toFixed(9),priceUsdPerUnit:price.toFixed(8),priceUnit}});
      await client.query('COMMIT');
      // Return the same complete representation as GET/detail so Swift clients can decode
      // a newly created authorization without a second request or a partial DTO.
      return this.dispenseDetail(authorizationId,branchId,principal);
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUniqueViolation(error)) throw new ConflictException('Ya existe un despacho activo en esta manguera o commandId duplicado.');throw error;}finally{client.release();}
  }

  async startDispense(branchId:string,authorizationId:string,principal:AuthPrincipal,input:DispenseReasonDto,correlationId:string){
    return this.dispenseTransition(branchId,authorizationId,principal,input,correlationId,'authorized','dispensing','started');
  }

  async reportDispenseProgress(branchId:string,authorizationId:string,principal:AuthPrincipal,input:DispenseProgressDto,correlationId:string){
    const client=await this.pool.connect();
    const requestHash=hashPayload({authorizationId,quantity:input.quantity,unit:input.unit,expectedVersion:input.expectedVersion});
    try{
      await client.query('BEGIN');
      const replay=await this.dispenseEventReplay(client,principal.organizationId,input.commandId,requestHash);
      if(replay){await client.query('COMMIT');return this.dispenseDetail(authorizationId,branchId,principal);}
      const found=await client.query<{status:string;version:number;reserved_l:string;progress_l:string}>(`SELECT status,version,reserved_l,progress_l FROM dispense_authorizations WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`,[authorizationId,branchId,principal.organizationId]);
      const row=found.rows[0];
      if(!row) throw new NotFoundException('La autorización no existe.');
      if(row.status!=='dispensing'||row.version!==input.expectedVersion) throw new ConflictException('El despacho cambió de estado o versión.');
      const progress=quantityToLiters(input.quantity,input.unit);
      if(progress.lt(row.progress_l)||progress.gt(row.reserved_l)) throw new ConflictException('El avance acumulado debe ser creciente y no superar el volumen autorizado.');
      await client.query('UPDATE dispense_authorizations SET progress_l=$2,version=version+1 WHERE id=$1',[authorizationId,progress.toFixed(9)]);
      await this.addDispenseEvent(client,{principal,branchId,authorizationId,commandId:input.commandId,eventType:'progress',previousStatus:'dispensing',nextStatus:'dispensing',requestHash,measuredL:progress.toFixed(9),correlationId});
      await client.query('COMMIT');
      return this.dispenseDetail(authorizationId,branchId,principal);
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
  }

  async completeDispense(branchId:string,authorizationId:string,principal:AuthPrincipal,input:DispenseCompletionDto,correlationId:string){
    const client=await this.pool.connect();
    const requestHash=hashPayload({authorizationId,quantity:input.quantity,unit:input.unit,expectedVersion:input.expectedVersion,documentReference:input.documentReference?.trim()??null});
    let nozzleId:string;
    let actualL:string;
    let priceUnit:string;
    let priceAmount:string;
    let saleAmount:string;
    try{
      await client.query('BEGIN');
      const replay=await this.dispenseEventReplay(client,principal.organizationId,input.commandId,requestHash);
      const found=await client.query<{status:string;version:number;reserved_l:string;nozzle_id:string;price_unit:string;price_usd_per_unit:string;requested_by:string;actual_l:string|null;completion_hash:string|null}>(
        `SELECT status,version,reserved_l,nozzle_id,price_unit,price_usd_per_unit,requested_by,actual_l,completion_hash
         FROM dispense_authorizations WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`,[authorizationId,branchId,principal.organizationId]);
      const authorization=found.rows[0];
      if(!authorization) throw new NotFoundException('La autorización no existe.');
      if(replay){
        if(authorization.status==='completed'){await client.query('COMMIT');return this.dispenseDetail(authorizationId,branchId,principal);}
        if(authorization.status!=='posting'){throw new ConflictException('El comando ya se usó, pero la autorización no está esperando conciliación.');}
        nozzleId=authorization.nozzle_id; actualL=authorization.actual_l!; priceUnit=authorization.price_unit; priceAmount=authorization.price_usd_per_unit;
        saleAmount=await this.calculateSaleAmount(actualL,priceUnit,priceAmount);
      }else{
        if(!['dispensing','unknown'].includes(authorization.status)||authorization.version!==input.expectedVersion) throw new ConflictException('El despacho cambió o no admite el cierre.');
        if(authorization.status==='unknown'&&!input.documentReference?.trim()) throw new ConflictException('Para conciliar un resultado desconocido, adjunta una referencia de comprobación.');
        const liters=quantityToLiters(input.quantity,input.unit);
        if(liters.gt(authorization.reserved_l)) throw new ConflictException('El volumen medido supera el volumen autorizado.');
        nozzleId=authorization.nozzle_id; actualL=liters.toFixed(9); priceUnit=authorization.price_unit; priceAmount=authorization.price_usd_per_unit;
        saleAmount=await this.calculateSaleAmount(actualL,priceUnit,priceAmount);
        await client.query(`UPDATE dispense_authorizations SET status='posting',actual_l=$2,sale_amount_usd=$3,completion_command_id=$4,completion_hash=$5,version=version+1
          WHERE id=$1 AND version=$6`,[authorizationId,actualL,saleAmount,input.commandId,requestHash,input.expectedVersion]);
        await this.addDispenseEvent(client,{principal,branchId,authorizationId,commandId:input.commandId,eventType:'completion_requested',previousStatus:authorization.status,nextStatus:'posting',requestHash,measuredL:actualL,reason:input.documentReference?.trim()??null,correlationId});
        await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'dispense.completion_requested',entityType:'dispense_authorization',entityId:authorizationId,before:{status:authorization.status,version:authorization.version},after:{status:'posting',actualL,saleAmountUsd:saleAmount}});
      }
      await client.query('COMMIT');
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUniqueViolation(error)) throw new ConflictException('La finalización ya fue enviada; repite con el mismo commandId.');throw error;}finally{client.release();}

    const movement=await this.inventory.sell(branchId,(await this.dispenseDetail(authorizationId,branchId,principal)).data.tankId,principal,{
      commandId:input.commandId,quantity:actualL,unit:'liter',volumeBasis:'observed',sourceId:authorizationId,sourceLine:nozzleId,
      documentReference:input.documentReference?.trim()||`DISP-${authorizationId}`,
    },correlationId);
    const finalize=await this.pool.connect();
    try{
      await finalize.query('BEGIN');
      const auth=await finalize.query<{status:string;version:number;completion_hash:string|null;organization_id:string;branch_id:string;requested_by:string;completion_command_id:string;completed_at:string;actual_l:string;sale_amount_usd:string;fuel_product_id:string;price_version_id:string;price_unit:string;price_usd_per_unit:string;inventory_movement_id:string}>(
        `SELECT status,version,completion_hash,organization_id,branch_id,requested_by,completion_command_id,completed_at,actual_l,sale_amount_usd,
                fuel_product_id,price_version_id,price_unit,price_usd_per_unit,inventory_movement_id
           FROM dispense_authorizations WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`,[authorizationId,branchId,principal.organizationId]);
      if(!auth.rows[0]||auth.rows[0].status!=='posting'||auth.rows[0].completion_hash!==requestHash) throw new ConflictException('La autorización no coincide con el cierre pendiente.');
      await finalize.query(`UPDATE dispense_authorizations SET status='completed',inventory_movement_id=$2,completed_at=now(),version=version+1 WHERE id=$1`,[authorizationId,movement.movement.id]);
      const completed=await finalize.query<{completed_at:string}>(`SELECT completed_at FROM dispense_authorizations WHERE id=$1`,[authorizationId]);
      const posted=auth.rows[0];
      const sale=await finalize.query<{id:string}>(
        `INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT(authorization_id) DO NOTHING RETURNING id`,
        [posted.organization_id,posted.branch_id,authorizationId,posted.completion_command_id,posted.completion_hash,posted.sale_amount_usd,posted.requested_by,completed.rows[0]!.completed_at,correlationId]);
      const saleId=sale.rows[0]?.id ?? (await finalize.query<{id:string}>('SELECT id FROM sales WHERE authorization_id=$1',[authorizationId])).rows[0]?.id;
      if(!saleId) throw new ConflictException('No se pudo registrar la venta del despacho.');
      await finalize.query(
        `INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality)
         SELECT $1,$2,$3,1,p.id,p.display_name,$4,$5,$6,$7,$8,m.id,m.cost_recognized_usd,m.unit_cost_usd_per_l,m.valuation_quality
           FROM fuel_products p JOIN inventory_movements m ON m.id=$9 AND m.organization_id=$1 AND m.branch_id=$2
          WHERE p.id=$10 AND p.organization_id=$1
         ON CONFLICT(sale_id,line_number) DO NOTHING`,
        [posted.organization_id,posted.branch_id,saleId,posted.actual_l,posted.price_usd_per_unit,posted.price_unit,posted.price_version_id,posted.sale_amount_usd,movement.movement.id,posted.fuel_product_id]);
      await this.addDispenseEvent(finalize,{principal,branchId,authorizationId,commandId:randomUUID(),eventType:'completed',previousStatus:'posting',nextStatus:'completed',requestHash:hashPayload({authorizationId,status:'completed',requestHash}),measuredL:actualL,correlationId});
      await this.audit.appendTransaction(finalize,{principal,branchId,correlationId,action:'dispense.completed',entityType:'dispense_authorization',entityId:authorizationId,after:{actualL,saleAmountUsd:saleAmount,inventoryMovementId:movement.movement.id,saleId}});
      await finalize.query('COMMIT');
      return this.dispenseDetail(authorizationId,branchId,principal);
    }catch(error){await finalize.query('ROLLBACK').catch(()=>undefined);throw error;}finally{finalize.release();}
  }

  private async calculateSaleAmount(actualLiters:string,priceUnit:string,priceAmount:string){
    const quantity=priceUnit==='us_gallon'?new Decimal(actualLiters).div(GALLONS_TO_LITERS):new Decimal(actualLiters);
    return quantity.mul(priceAmount).toDecimalPlaces(2,Decimal.ROUND_HALF_UP).toFixed(2);
  }

  async cancelDispense(branchId:string,authorizationId:string,principal:AuthPrincipal,input:DispenseReasonDto,correlationId:string){
    return this.dispenseTransition(branchId,authorizationId,principal,input,correlationId,'authorized','cancelled','cancelled');
  }

  async markDispenseUnknown(branchId:string,authorizationId:string,principal:AuthPrincipal,input:DispenseReasonDto,correlationId:string){
    return this.dispenseTransition(branchId,authorizationId,principal,input,correlationId,'dispensing','unknown','unknown');
  }

  async reconcileDispenseNoFlow(branchId:string,authorizationId:string,principal:AuthPrincipal,input:DispenseNoFlowReconciliationDto,correlationId:string){
    const evidenceReference=input.evidenceReference.trim();
    const reason=input.reason.trim();
    if(!evidenceReference||!reason) throw new BadRequestException('La conciliación requiere evidencia y motivo.');
    const requestHash=hashPayload({authorizationId,resolution:'no_flow',expectedVersion:input.expectedVersion,evidenceReference,reason});
    const client=await this.pool.connect();
    try{
      await client.query('BEGIN');
      const replay=await this.dispenseEventReplay(client,principal.organizationId,input.commandId,requestHash);
      if(replay){await client.query('COMMIT');return this.dispenseDetail(authorizationId,branchId,principal);}
      const found=await client.query<{status:string;version:number}>(
        'SELECT status,version FROM dispense_authorizations WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE',
        [authorizationId,branchId,principal.organizationId]);
      const authorization=found.rows[0];
      if(!authorization) throw new NotFoundException('La autorización no existe.');
      if(authorization.status!=='unknown'||authorization.version!==input.expectedVersion)
        throw new ConflictException('Solo se concilia sin despacho una autorización desconocida con su versión vigente.');
      await client.query("UPDATE dispense_authorizations SET status='cancelled',version=version+1 WHERE id=$1 AND version=$2",[authorizationId,input.expectedVersion]);
      await this.addDispenseEvent(client,{principal,branchId,authorizationId,commandId:input.commandId,eventType:'cancelled',previousStatus:'unknown',nextStatus:'cancelled',
        requestHash,reason:`Sin flujo confirmado. Evidencia: ${evidenceReference}. Motivo: ${reason}`,correlationId});
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'dispense.reconciled_no_flow',entityType:'dispense_authorization',entityId:authorizationId,
        before:{status:'unknown',version:authorization.version},after:{status:'cancelled',resolution:'no_flow',evidenceReference,reason}});
      await client.query('COMMIT');
      return this.dispenseDetail(authorizationId,branchId,principal);
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUniqueViolation(error)) throw new ConflictException('La conciliación ya se registró; repite con el mismo commandId.');throw error;}finally{client.release();}
  }

  async listDispenseAuthorizations(branchId:string,principal:AuthPrincipal,filters:{status?:string;cursor?:string;limit:number}){
    await this.requireBranch(this.pool,branchId,principal);
    const values:unknown[]=[principal.organizationId,branchId];
    const where=['a.organization_id=$1','a.branch_id=$2'];
    if(filters.status==='active') where.push("(a.status IN ('dispensing','unknown','posting') OR (a.status='authorized' AND a.expires_at>now()))");
    else if(filters.status==='expired') where.push("(a.status='expired' OR (a.status='authorized' AND a.expires_at<=now()))");
    else if(filters.status==='authorized') where.push("a.status='authorized' AND a.expires_at>now()");
    else if(filters.status){values.push(filters.status);where.push(`a.status=$${values.length}`);}
    if(filters.cursor){values.push(filters.cursor);where.push(`a.id<$${values.length}::uuid`);}
    const limit=Math.max(1,Math.min(100,filters.limit));
    values.push(limit+1);
    const result=await this.pool.query(`SELECT a.id,a.nozzle_id AS "nozzleId",n.code AS "nozzleCode",d.code AS "dispenserCode",fp.display_name AS "fuelName",
      a.tank_id AS "tankId",a.fuel_product_id AS "fuelProductId",
      CASE WHEN a.status='authorized' AND a.expires_at<=now() THEN 'expired' ELSE a.status END AS status,
      a.request_type AS "requestType",a.requested_amount_usd AS "requestedAmountUsd",a.requested_volume AS "requestedVolume",a.requested_volume_unit AS "requestedVolumeUnit",
      a.reserved_l AS "reservedL",a.progress_l AS "progressL",a.actual_l AS "actualL",a.price_usd_per_unit AS "priceUsdPerUnit",a.price_unit AS "priceUnit",
      a.sale_amount_usd AS "saleAmountUsd",a.version,a.expires_at AS "expiresAt",a.started_at AS "startedAt",a.completed_at AS "completedAt",
      a.inventory_movement_id AS "inventoryMovementId",COALESCE((SELECT jsonb_agg(jsonb_build_object('id',e.id,'eventType',e.event_type,'previousStatus',e.previous_status,
      'nextStatus',e.next_status,'measuredL',e.measured_l,'actorUserId',e.actor_user_id,'reason',e.reason,'occurredAt',e.occurred_at) ORDER BY e.occurred_at)
      FROM dispense_authorization_events e WHERE e.authorization_id=a.id),'[]'::jsonb) AS events
      FROM dispense_authorizations a
      JOIN nozzles n ON n.id=a.nozzle_id
      JOIN dispensers d ON d.id=n.dispenser_id
      JOIN fuel_products fp ON fp.id=a.fuel_product_id
      WHERE ${where.join(' AND ')} ORDER BY a.id DESC LIMIT $${values.length}`,values);
    const hasMore=result.rows.length>limit;
    const data=hasMore?result.rows.slice(0,limit):result.rows;
    return {data,meta:{limit,nextCursor:hasMore?data.at(-1)!.id:null}};
  }

  async dispenseDetail(authorizationId:string,branchId:string,principal:AuthPrincipal){
    const result=await this.pool.query(`SELECT a.id,a.nozzle_id AS "nozzleId",n.code AS "nozzleCode",d.code AS "dispenserCode",fp.display_name AS "fuelName",
      a.tank_id AS "tankId",a.fuel_product_id AS "fuelProductId",
      CASE WHEN a.status='authorized' AND a.expires_at<=now() THEN 'expired' ELSE a.status END AS status,
      a.request_type AS "requestType",a.requested_amount_usd AS "requestedAmountUsd",a.requested_volume AS "requestedVolume",a.requested_volume_unit AS "requestedVolumeUnit",
      a.reserved_l AS "reservedL",a.progress_l AS "progressL",a.actual_l AS "actualL",a.price_usd_per_unit AS "priceUsdPerUnit",a.price_unit AS "priceUnit",
      a.sale_amount_usd AS "saleAmountUsd",a.version,a.expires_at AS "expiresAt",a.started_at AS "startedAt",a.completed_at AS "completedAt",
      a.inventory_movement_id AS "inventoryMovementId",COALESCE((SELECT jsonb_agg(jsonb_build_object('id',e.id,'eventType',e.event_type,'previousStatus',e.previous_status,
      'nextStatus',e.next_status,'measuredL',e.measured_l,'actorUserId',e.actor_user_id,'reason',e.reason,'occurredAt',e.occurred_at) ORDER BY e.occurred_at)
      FROM dispense_authorization_events e WHERE e.authorization_id=a.id),'[]'::jsonb) AS events
      FROM dispense_authorizations a
      JOIN nozzles n ON n.id=a.nozzle_id
      JOIN dispensers d ON d.id=n.dispenser_id
      JOIN fuel_products fp ON fp.id=a.fuel_product_id
      WHERE a.id=$1 AND a.branch_id=$2 AND a.organization_id=$3`,[authorizationId,branchId,principal.organizationId]);
    if(!result.rowCount) throw new NotFoundException('La autorización no existe en esta sucursal.');
    return {data:result.rows[0]};
  }

  private async dispenseTransition(branchId:string,authorizationId:string,principal:AuthPrincipal,input:DispenseReasonDto,correlationId:string,
    expectedStatus:string,nextStatus:string,eventType:'started'|'cancelled'|'unknown'){
    const client=await this.pool.connect();
    const requestHash=hashPayload({authorizationId,expectedStatus,nextStatus,expectedVersion:input.expectedVersion,reason:input.reason?.trim()??null});
    try{
      await client.query('BEGIN');
      const replay=await this.dispenseEventReplay(client,principal.organizationId,input.commandId,requestHash);
      if(replay){await client.query('COMMIT');return this.dispenseDetail(authorizationId,branchId,principal);}
      const found=await client.query<{status:string;version:number;expires_at:Date}>(
        'SELECT status,version,expires_at FROM dispense_authorizations WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE',[authorizationId,branchId,principal.organizationId]);
      const row=found.rows[0];
      if(!row) throw new NotFoundException('La autorización no existe.');
      if(row.status!==expectedStatus||row.version!==input.expectedVersion) throw new ConflictException('La autorización cambió o no admite esta acción.');
      if(eventType==='started'&&new Date(row.expires_at).getTime()<=Date.now()) throw new ConflictException('La autorización venció; genera una nueva antes de iniciar el despacho.');
      if((eventType==='cancelled'||eventType==='unknown')&&!input.reason?.trim()) throw new BadRequestException('Indica el motivo de la cancelación o del estado desconocido.');
      await client.query(`UPDATE dispense_authorizations SET status=$2,version=version+1,
        started_at=CASE WHEN $2='dispensing' THEN now() ELSE started_at END WHERE id=$1 AND version=$3`,[authorizationId,nextStatus,input.expectedVersion]);
      await this.addDispenseEvent(client,{principal,branchId,authorizationId,commandId:input.commandId,eventType,previousStatus:expectedStatus,nextStatus,requestHash,reason:input.reason?.trim()??null,correlationId});
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:`dispense.${eventType}`,entityType:'dispense_authorization',entityId:authorizationId,before:{status:expectedStatus,version:row.version},after:{status:nextStatus,reason:input.reason?.trim()??null}});
      await client.query('COMMIT');
      return this.dispenseDetail(authorizationId,branchId,principal);
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUniqueViolation(error)) throw new ConflictException('La acción ya fue registrada; repite con el mismo commandId.');throw error;}finally{client.release();}
  }

  private async dispenseEventReplay(client:PoolClient,organizationId:string,commandId:string,requestHash:string){
    const result=await client.query<{id:string;request_hash:string;event_type:string;next_status:string;measured_l:string|null}>(
      `SELECT id,request_hash,event_type,next_status,measured_l FROM dispense_authorization_events WHERE organization_id=$1 AND command_id=$2`,[organizationId,commandId]);
    if(!result.rows[0]) return null;
    if(result.rows[0].request_hash!==requestHash) throw new ConflictException('commandId ya fue usado para otra acción de despacho.');
    return {...result.rows[0],idempotentReplay:true};
  }

  private async addDispenseEvent(client:PoolClient,input:{principal:AuthPrincipal;branchId:string;authorizationId:string;commandId:string;eventType:string;
    previousStatus:string|null;nextStatus:string;requestHash:string;measuredL?:string;reason?:string|null;correlationId:string}){
    await client.query(`INSERT INTO dispense_authorization_events(organization_id,branch_id,authorization_id,command_id,request_hash,event_type,
      previous_status,next_status,measured_l,actor_user_id,reason,correlation_id)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,[input.principal.organizationId,input.branchId,input.authorizationId,input.commandId,
      input.requestHash,input.eventType,input.previousStatus,input.nextStatus,input.measuredL??null,input.principal.userId,input.reason??null,input.correlationId]);
  }

  async nozzleAvailability(branchId: string, nozzleId: string, principal: AuthPrincipal) {
    const result = await this.pool.query<{
      id: string; code: string; nozzle_status: string; dispenser_id: string; dispenser_status: string;
      branch_status: string; offer_status: string | null; tank_id: string | null; tank_status: string | null;
      product_status: string; service_mode: string; usable_l: string | null; valuation_quality: string | null;
      reserve_l: string | null; price_id: string | null; price_usd_per_unit: string | null; price_unit: string | null;
      block_type: string | null; reason_code: string | null; reason: string | null;
    }>(
      `SELECT n.id,n.code,n.physical_status AS nozzle_status,d.id AS dispenser_id,d.physical_status AS dispenser_status,
              b.status AS branch_status,o.status AS offer_status,t.id AS tank_id,t.status AS tank_status,fp.status AS product_status,
              n.service_mode,bal.on_hand_l AS usable_l,bal.valuation_quality,t.unusable_reserve_l AS reserve_l,
              price.id AS price_id,price.price_usd_per_unit AS price_usd_per_unit,price.unit AS price_unit,
              ab.block_type,ab.reason_code,ab.reason
         FROM nozzles n JOIN dispensers d ON d.id=n.dispenser_id AND d.branch_id=n.branch_id
         JOIN branches b ON b.id=n.branch_id AND b.organization_id=n.organization_id
         JOIN fuel_products fp ON fp.id=n.fuel_product_id AND fp.organization_id=n.organization_id
         LEFT JOIN branch_fuel_offers o ON o.branch_id=n.branch_id AND o.fuel_product_id=n.fuel_product_id
         LEFT JOIN nozzle_tank_connections c ON c.nozzle_id=n.id AND c.valid_until IS NULL
         LEFT JOIN tanks t ON t.id=c.tank_id
         LEFT JOIN tank_inventory_balances bal ON bal.tank_id=t.id AND bal.organization_id=n.organization_id
         LEFT JOIN LATERAL (
           SELECT id,price_usd_per_unit,unit FROM fuel_price_versions p
            WHERE p.organization_id=n.organization_id AND p.branch_id=n.branch_id AND p.fuel_product_id=n.fuel_product_id
              AND p.service_mode=n.service_mode AND p.effective_at<=now()
            ORDER BY p.effective_at DESC,p.version DESC LIMIT 1
         ) price ON true
         LEFT JOIN asset_blocks ab ON ab.organization_id=n.organization_id AND ab.branch_id=n.branch_id AND ab.resolved_at IS NULL
           AND ((ab.asset_type='nozzle' AND ab.asset_id=n.id) OR (ab.asset_type='dispenser' AND ab.asset_id=d.id) OR (ab.asset_type='tank' AND ab.asset_id=t.id))
        WHERE n.id=$1 AND n.branch_id=$2 AND n.organization_id=$3 ORDER BY ab.created_at`,
      [nozzleId, branchId, principal.organizationId],
    );
    if (!result.rowCount) throw new NotFoundException('La manguera no existe en esta sucursal.');
    const first = result.rows[0]!;
    const reasons: Array<{ code: string; message: string; source: string }> = [];
    if (first.branch_status !== 'active') reasons.push({ code: 'BRANCH_NOT_ACTIVE', message: 'La sucursal no está activa.', source: 'branch' });
    if (first.dispenser_status !== 'active') reasons.push({ code: 'DISPENSER_NOT_ACTIVE', message: 'El dispensador está fuera de servicio.', source: 'dispenser' });
    if (first.nozzle_status !== 'active') reasons.push({ code: 'NOZZLE_NOT_ACTIVE', message: 'La manguera no está disponible.', source: 'nozzle' });
    if (first.offer_status !== 'active') reasons.push({ code: 'PRODUCT_NOT_OFFERED', message: 'El producto no está habilitado en la sucursal.', source: 'offer' });
    if (first.product_status !== 'active') reasons.push({ code: 'PRODUCT_INACTIVE', message: 'El producto está inactivo en el catálogo.', source: 'fuel_product' });
    if (!first.tank_id) reasons.push({ code: 'TANK_CONNECTION_MISSING', message: 'La manguera no tiene tanque conectado.', source: 'connection' });
    else if (first.tank_status !== 'active') reasons.push({ code: 'TANK_NOT_ACTIVE', message: 'El tanque conectado está fuera de servicio.', source: 'tank' });
    if (!first.usable_l || first.valuation_quality === null) reasons.push({ code: 'OPENING_BALANCE_MISSING', message: 'El tanque no tiene un saldo inicial confirmado.', source: 'inventory' });
    else if (first.reserve_l !== null && new Decimal(first.usable_l).lte(first.reserve_l)) reasons.push({ code: 'STOCK_AT_RESERVE', message: 'La existencia disponible llegó a la reserva no utilizable.', source: 'inventory' });
    if (!first.price_id) reasons.push({ code: 'PRICE_NOT_EFFECTIVE', message: 'No hay un precio aprobado y vigente para este combustible y modalidad.', source: 'pricing' });
    for (const row of result.rows) if (row.reason_code) reasons.push({ code: row.reason_code, message: row.reason ?? 'Activo bloqueado.', source: row.block_type ?? 'block' });
    return { data: {
      nozzleId,
      selectable: reasons.length === 0,
      reasons,
      inventory: first.usable_l === null ? null : { onHandL: first.usable_l, reserveL: first.reserve_l, valuationQuality: first.valuation_quality },
      price: first.price_id ? { versionId: first.price_id, amount: first.price_usd_per_unit, unit: first.price_unit, serviceMode: first.service_mode } : null,
      computedAt: new Date().toISOString(), source: 'configuration+blocks+ledger+pricing', inventoryCoverage: first.usable_l === null ? 'missing' : 'present',
    } };
  }

  async createAssetBlock(branchId: string, principal: AuthPrincipal, input: CreateAssetBlockDto) {
    try {
      const client = await this.pool.connect();
      try {
        await client.query('BEGIN');
        await this.requireBranch(client, branchId, principal);
        await this.requireAsset(client, branchId, principal, input.assetType, input.assetId);
        const result = await client.query(
          `INSERT INTO asset_blocks (organization_id,branch_id,asset_type,asset_id,block_type,reason_code,reason,created_by)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id,asset_type AS "assetType",asset_id AS "assetId",block_type AS "blockType",reason_code AS "reasonCode",reason,created_at AS "createdAt"`,
          [principal.organizationId, branchId, input.assetType, input.assetId, input.blockType, input.reasonCode, input.reason.trim(), principal.userId],
        );
        await client.query('COMMIT');
        return result.rows[0];
      } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
      finally { client.release(); }
    } catch (error) { throw mapConstraint(error); }
  }

  async resolveAssetBlock(branchId: string, blockId: string, principal: AuthPrincipal, input: ResolveAssetBlockDto) {
    const result = await this.pool.query(
      `UPDATE asset_blocks SET resolved_by=$4,resolved_at=now(),resolution=$5
        WHERE id=$1 AND branch_id=$2 AND organization_id=$3 AND resolved_at IS NULL
        RETURNING id,resolved_at AS "resolvedAt",resolution`,
      [blockId, branchId, principal.organizationId, principal.userId, input.resolution.trim()],
    );
    if (!result.rowCount) throw new NotFoundException('El bloqueo activo no existe en esta sucursal.');
    return result.rows[0];
  }

  async listAssetBlocks(branchId: string, principal: AuthPrincipal, filters: { status: 'active' | 'resolved' | 'all'; assetType?: string; assetId?: string; limit: number; cursor?: string }) {
    await this.requireBranch(this.pool, branchId, principal);
    const values: unknown[] = [principal.organizationId, branchId];
    const where = ['organization_id=$1','branch_id=$2'];
    if (filters.status === 'active') where.push('resolved_at IS NULL');
    if (filters.status === 'resolved') where.push('resolved_at IS NOT NULL');
    if (filters.assetType) { values.push(filters.assetType); where.push(`asset_type=$${values.length}`); }
    if (filters.assetId) { values.push(filters.assetId); where.push(`asset_id=$${values.length}`); }
    if (filters.cursor) { values.push(filters.cursor); where.push(`id>$${values.length}::uuid`); }
    const limit = Math.max(1, Math.min(200, filters.limit)); values.push(limit + 1);
    const result = await this.pool.query(
      `SELECT id,asset_type AS "assetType",asset_id AS "assetId",block_type AS "blockType",reason_code AS "reasonCode",reason,created_by AS "createdBy",created_at AS "createdAt",resolved_by AS "resolvedBy",resolved_at AS "resolvedAt",resolution
         FROM asset_blocks WHERE ${where.join(' AND ')} ORDER BY id LIMIT $${values.length}`, values,
    );
    const hasMore = result.rows.length > limit;
    const data = hasMore ? result.rows.slice(0, limit) : result.rows;
    return { data, meta: { limit, nextCursor: hasMore ? data.at(-1)!.id : null } };
  }

  async changePhysicalStatus(branchId: string, assetType: 'tank' | 'dispenser' | 'nozzle', assetId: string, principal: AuthPrincipal, input: ChangePhysicalStatusDto) {
    const table = assetType === 'tank' ? 'tanks' : assetType === 'dispenser' ? 'dispensers' : 'nozzles';
    const column = assetType === 'dispenser' ? 'physical_status' : assetType === 'nozzle' ? 'physical_status' : 'status';
    const valid = assetType === 'nozzle' ? ['active','maintenance','offline','removed'] : ['active','maintenance','offline','decommissioned'];
    if (!valid.includes(input.status)) throw new BadRequestException('Estado incompatible con el tipo de activo.');
    const result = await this.pool.query(
      `UPDATE ${table} SET ${column}=$4,version=version+1,updated_at=now()
        WHERE id=$1 AND branch_id=$2 AND organization_id=$3 AND version=$5
        RETURNING id,${column} AS status,version`,
      [assetId, branchId, principal.organizationId, input.status, input.expectedVersion],
    );
    if (!result.rowCount) throw new ConflictException('El activo cambió o no existe; actualiza la ficha antes de guardar.');
    return result.rows[0];
  }

  async branchConfiguration(branchId: string, principal: AuthPrincipal) {
    const branchResult = await this.pool.query(
      `SELECT b.id,b.code,b.name,b.zone,b.timezone,b.status,
          COALESCE(p.profile,'operational') AS profile,
          p.expected_dispenser_count AS "expectedDispenserCount",
          COALESCE(p.configuration_version,0) AS "configurationVersion",
          (SELECT count(*)::int FROM dispensers d WHERE d.branch_id=b.id AND d.physical_status<>'decommissioned') AS "configuredDispenserCount"
         FROM branches b LEFT JOIN branch_operating_profiles p ON p.branch_id=b.id
        WHERE b.id=$1 AND b.organization_id=$2`, [branchId, principal.organizationId],
    );
    if (!branchResult.rowCount) throw new NotFoundException('La sucursal no existe.');
    const [products, tanks, dispensers, openBlocks] = await Promise.all([
      this.pool.query(`SELECT p.id,p.sku,p.display_name AS "displayName",p.family,p.brand,o.status FROM branch_fuel_offers o JOIN fuel_products p ON p.id=o.fuel_product_id AND p.organization_id=o.organization_id WHERE o.branch_id=$1 AND o.organization_id=$2 ORDER BY p.display_name`, [branchId, principal.organizationId]),
      this.pool.query(`SELECT t.id,t.code,t.name,t.fuel_product_id AS "fuelProductId",p.display_name AS "fuelName",t.nominal_capacity_l AS "nominalCapacityL",t.safe_fill_limit_l AS "safeFillLimitL",t.unusable_reserve_l AS "unusableReserveL",t.status,t.version FROM tanks t JOIN fuel_products p ON p.id=t.fuel_product_id WHERE t.branch_id=$1 AND t.organization_id=$2 ORDER BY t.code`, [branchId, principal.organizationId]),
      this.pool.query(`SELECT d.id,d.code,d.name,d.physical_status AS "physicalStatus",d.version,COALESCE(jsonb_agg(jsonb_build_object('id',n.id,'code',n.code,'productCode',n.product_code,'fuelProductId',n.fuel_product_id,'serviceMode',n.service_mode,'physicalStatus',n.physical_status,'tankId',c.tank_id,'tankStatus',t.status)) FILTER (WHERE n.id IS NOT NULL),'[]'::jsonb) AS nozzles FROM dispensers d LEFT JOIN nozzles n ON n.dispenser_id=d.id AND n.physical_status<>'removed' LEFT JOIN nozzle_tank_connections c ON c.nozzle_id=n.id AND c.valid_until IS NULL LEFT JOIN tanks t ON t.id=c.tank_id WHERE d.branch_id=$1 AND d.organization_id=$2 GROUP BY d.id ORDER BY d.code`, [branchId, principal.organizationId]),
      this.pool.query('SELECT count(*)::int AS count FROM asset_blocks WHERE branch_id=$1 AND organization_id=$2 AND resolved_at IS NULL', [branchId, principal.organizationId]),
    ]);
    const branch = branchResult.rows[0]!;
    const profile = branch.profile as string;
    const issues: string[] = [];
    if (branch.expectedDispenserCount === null) issues.push('OPERATING_PROFILE_NOT_CONFIGURED');
    else if (Number(branch.configuredDispenserCount) !== Number(branch.expectedDispenserCount)) issues.push('DISPENSER_COUNT_MISMATCH');
    if (branch.status !== 'active') issues.push('BRANCH_NOT_ACTIVE');
    const families = new Set(products.rows.filter(product => product.status === 'active').map(product => product.family));
    if (profile === 'academicLab22') for (const family of ['super','regular','diesel']) if (!families.has(family)) issues.push(`FUEL_FAMILY_MISSING:${family}`);
    if (!tanks.rowCount) issues.push('TANKS_NOT_CONFIGURED');
    if (!tanks.rows.some(tank => tank.status === 'active')) issues.push('NO_ACTIVE_TANKS');
    const nozzles = dispensers.rows.flatMap(dispenser => Array.isArray(dispenser.nozzles) ? dispenser.nozzles : []);
    if (!nozzles.length) issues.push('NOZZLES_NOT_CONFIGURED');
    if (!nozzles.some(nozzle => nozzle.physicalStatus === 'active')) issues.push('NO_ACTIVE_NOZZLES');
    if (!dispensers.rows.some(dispenser => dispenser.physicalStatus === 'active')) issues.push('NO_ACTIVE_DISPENSERS');
    if (nozzles.some(nozzle => nozzle.physicalStatus === 'active' && (!nozzle.tankId || nozzle.tankStatus !== 'active'))) issues.push('NOZZLE_TANK_CONNECTION_MISSING_OR_INACTIVE');
    if (Number(openBlocks.rows[0]!.count) > 0) issues.push('ASSET_BLOCKS_ACTIVE');
    return { data: { ...branch, fuelOffers: products.rows, tanks: tanks.rows, dispensers: dispensers.rows, readiness: { ready: issues.length === 0, issues }, asOf: new Date().toISOString() } };
  }

  private async requireBranch(queryable: Pool | PoolClient, branchId: string, principal: AuthPrincipal) {
    const result = await queryable.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2', [branchId, principal.organizationId]);
    if (!result.rowCount) throw new NotFoundException('La sucursal no existe.');
  }

  private async requireAsset(client: PoolClient, branchId: string, principal: AuthPrincipal, type: string, assetId: string) {
    const table = type === 'tank' ? 'tanks' : type === 'dispenser' ? 'dispensers' : 'nozzles';
    const result = await client.query(`SELECT id FROM ${table} WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`, [assetId, branchId, principal.organizationId]);
    if (!result.rowCount) throw new NotFoundException('El activo no existe en esta sucursal.');
  }
}

function positive(value: string, label: string): Decimal {
  const result = new Decimal(value);
  if (!result.isFinite() || result.lte(0)) throw new BadRequestException(`${label} debe ser mayor que cero.`);
  return result;
}

function nonnegative(value: string, label: string): Decimal {
  const result = new Decimal(value);
  if (!result.isFinite() || result.lt(0)) throw new BadRequestException(`${label} no puede ser negativa.`);
  return result;
}

function escapeLike(value: string): string { return value.replace(/[\\%_]/g, '\\$&'); }

const GALLONS_TO_LITERS=new Decimal('3.785411784');

function quantityToLiters(quantity:string,unit:'gallon_us'|'liter'):Decimal{
  const value=new Decimal(quantity);
  if(!value.isFinite()||!value.gt(0)) throw new BadRequestException('La cantidad debe ser mayor que cero.');
  return unit==='gallon_us'?value.mul(GALLONS_TO_LITERS):value;
}

function hashPayload(value:unknown):string{return createHash('sha256').update(JSON.stringify(value)).digest('hex');}

function isUniqueViolation(error: unknown): boolean {
  return !!error && typeof error === 'object' && 'code' in error && error.code === '23505';
}

function mapConstraint(error: unknown): unknown {
  if (!error || typeof error !== 'object' || !('code' in error)) return error;
  if (error.code === '23505') return new ConflictException('El código ya está utilizado en esta organización o sucursal.');
  if (error.code === '23503') return new ConflictException('El recurso relacionado no existe o no pertenece a este ámbito.');
  if (error.code === '23514' || error.code === '22P02' || error.code === '23502') return new BadRequestException('Los datos no cumplen las restricciones del recurso.');
  if (error.code === '40001') return new ConflictException('La configuración cambió en paralelo; vuelve a cargar los datos.');
  return error;
}
