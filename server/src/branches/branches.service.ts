import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { ActivateBranchDto, CreateBranchDraftDto, SaveBranchOnboardingStepDto } from './branch-onboarding.dto.js';

const CURSOR = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

@Injectable()
export class BranchesService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly audit: AuditService) {}

  async createDraft(principal: AuthPrincipal, input: CreateBranchDraftDto, correlationId: string) {
    const code = input.code.trim().toUpperCase();
    const name = input.name.trim().replace(/\s+/g, ' ');
    const countryCode = normalizeCountryCode(input.countryCode);
    const profile = input.profile ?? 'operational';
    const expectedDispenserCount = input.expectedDispenserCount;
    if (!name || !code) throw new BadRequestException('Nombre y código son obligatorios.');
    if (profile === 'academicLab22' && expectedDispenserCount !== undefined && expectedDispenserCount !== 6) {
      throw new BadRequestException('El perfil académico requiere exactamente seis dispensadores.');
    }
    if (profile === 'operational' && expectedDispenserCount === undefined) {
      throw new BadRequestException('Indica cuántos dispensadores están construidos para el perfil operativo.');
    }
    const dispenserCount = profile === 'academicLab22' ? 6 : expectedDispenserCount!;
    try { new Intl.DateTimeFormat('en-US', { timeZone: input.timezone }); }
    catch { throw new BadRequestException('La zona horaria debe ser un identificador IANA válido.'); }
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const inserted = await client.query(
        `INSERT INTO branches (organization_id,code,name,zone,timezone,country_code,onboarding_data)
         VALUES ($1,$2,$3,$4,$5,$8,jsonb_build_object('identity',jsonb_build_object('code',$2::text,'name',$3::text,'zone',$4::text,'timezone',$5::text,'countryCode',$8::text),'template',$6::text,'expectedDispenserCount',$7::int))
         RETURNING id,code,name,zone,timezone,country_code AS "countryCode",status,onboarding_data AS "onboardingData",onboarding_version AS "onboardingVersion",created_at AS "createdAt",updated_at AS "updatedAt"`,
        [principal.organizationId, code, name, input.zone, input.timezone, profile, dispenserCount, countryCode],
      );
      const branch = inserted.rows[0]!;
      await client.query(
        `INSERT INTO branch_operating_profiles(branch_id,organization_id,profile,expected_dispenser_count,updated_by)
         VALUES($1,$2,$3,$4,$5)`,
        [branch.id, principal.organizationId, profile, dispenserCount, principal.userId],
      );
      await this.audit.appendTransaction(client, { principal, branchId: branch.id, correlationId, action: 'branch.draft.create', entityType: 'branch', entityId: branch.id, after: { code, zone: input.zone, countryCode, status: 'draft' } });
      await client.query('COMMIT');
      return branch;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (isUnique(error)) throw new ConflictException('Ya existe una sucursal con ese código en la organización.');
      throw error;
    } finally { client.release(); }
  }

  async list(principal: AuthPrincipal, options: { query?: string; status?: string; branchId?: string; countryCode?: string; cursor?: string; limit: number }) {
    const values: unknown[] = [principal.organizationId];
    const where = ['organization_id=$1'];
    if (options.query?.trim()) { values.push(`%${escapeLike(options.query.trim())}%`); where.push(`(name ILIKE $${values.length} ESCAPE '\\' OR code ILIKE $${values.length} ESCAPE '\\' OR zone ILIKE $${values.length} ESCAPE '\\')`); }
    if (options.status) { values.push(options.status); where.push(`status=$${values.length}`); }
    if (options.branchId) { values.push(options.branchId); where.push(`id=$${values.length}::uuid`); }
    if (options.countryCode) { values.push(normalizeCountryCode(options.countryCode)); where.push(`country_code=$${values.length}`); }
    if (options.cursor) { if (!CURSOR.test(options.cursor)) throw new BadRequestException('cursor debe ser UUID.'); values.push(options.cursor); where.push(`id>$${values.length}::uuid`); }
    const limit = Math.max(1, Math.min(100, options.limit));
    values.push(limit + 1);
    const result = await this.pool.query(
      `SELECT id,code,name,zone,timezone,country_code AS "countryCode",status,onboarding_version AS "onboardingVersion",updated_at AS "updatedAt"
         FROM branches WHERE ${where.join(' AND ')} ORDER BY id LIMIT $${values.length}`, values,
    );
    const hasMore = result.rows.length > limit;
    const data = hasMore ? result.rows.slice(0, limit) : result.rows;
    return { data, meta: { limit, nextCursor: hasMore ? data.at(-1)!.id : null } };
  }

  async detail(branchId: string, principal: AuthPrincipal) {
    const result = await this.pool.query(
      `SELECT id,code,name,zone,timezone,country_code AS "countryCode",status,onboarding_data AS "onboardingData",
              onboarding_version AS "onboardingVersion",configured_at AS "configuredAt",
              activated_at AS "activatedAt",created_at AS "createdAt",updated_at AS "updatedAt"
         FROM branches WHERE id=$1 AND organization_id=$2`, [branchId, principal.organizationId],
    );
    if (!result.rowCount) throw new NotFoundException('La sucursal no existe.');
    return result.rows[0];
  }

  async saveStep(branchId: string, principal: AuthPrincipal, input: SaveBranchOnboardingStepDto, correlationId: string) {
    validateStepData(input.data);
    if (input.step === 'staff') {
      const allowed = new Set(['status','employeeCount']);
      const employeeCount = input.data.employeeCount;
      if (Object.keys(input.data).some(field => !allowed.has(field))
        || !['confirmed','deferred'].includes(String(input.data.status))
        || typeof employeeCount !== 'number' || !Number.isSafeInteger(employeeCount) || employeeCount < 0
        || input.data.status === 'confirmed' && Number(employeeCount) < 1) {
        throw new BadRequestException('La revisión de personal requiere un estado válido y el número de colaboradores activos revisados.');
      }
    }
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const current = await client.query<{ onboarding_version: number; status: string; onboarding_data: Record<string, unknown>; code: string; name: string; zone: string; timezone: string; country_code: string }>(
        'SELECT onboarding_version,status,onboarding_data,code,name,zone,timezone,country_code FROM branches WHERE id=$1 AND organization_id=$2 FOR UPDATE', [branchId, principal.organizationId],
      );
      const row = current.rows[0];
      if (!row) throw new NotFoundException('La sucursal no existe.');
      if (row.status !== 'draft') throw new ConflictException('Solo se puede editar un alta que permanece como borrador.');
      if (row.onboarding_version !== input.expectedVersion) throw new ConflictException('El borrador cambió en otro dispositivo; recárgalo antes de guardar.');
      let code = row.code;
      let name = row.name;
      let zone = row.zone;
      let timezone = row.timezone;
      let countryCode = row.country_code;
      let dataToSave: Record<string, unknown> = input.data;
      if (input.step === 'identity') {
        const allowed = new Set(['code','name','zone','timezone','countryCode']);
        if (Object.keys(input.data).some(field => !allowed.has(field))) throw new BadRequestException('El paso identidad solo admite código, nombre, zona, país y zona horaria.');
        if (input.data.code !== undefined) {
          code = requiredString(input.data.code, 'code', 24).toUpperCase();
          if (!/^[A-Z0-9][A-Z0-9_-]*$/.test(code)) throw new BadRequestException('code contiene caracteres no permitidos.');
        }
        if (input.data.name !== undefined) name = requiredString(input.data.name, 'name', 120).replace(/\s+/g, ' ');
        if (input.data.zone !== undefined) {
          if (!['occidental','central','oriental','other'].includes(String(input.data.zone))) throw new BadRequestException('zone no es válida.');
          zone = String(input.data.zone);
        }
        if (input.data.timezone !== undefined) {
          timezone = requiredString(input.data.timezone, 'timezone', 64);
          try { new Intl.DateTimeFormat('en-US', { timeZone: timezone }); }
          catch { throw new BadRequestException('La zona horaria debe ser un identificador IANA válido.'); }
        }
        if (input.data.countryCode !== undefined) countryCode = normalizeCountryCode(requiredString(input.data.countryCode, 'countryCode', 2));
        dataToSave = { ...input.data, code, name, zone, timezone, countryCode };
      }
      const updated = await client.query(
        `UPDATE branches SET code=$6,name=$7,zone=$8,timezone=$9,country_code=$10,
           onboarding_data=onboarding_data || jsonb_build_object($3::text,$4::jsonb),
           onboarding_version=onboarding_version+1,updated_at=now()
         WHERE id=$1 AND organization_id=$2 AND onboarding_version=$5
         RETURNING id,status,onboarding_data AS "onboardingData",onboarding_version AS "onboardingVersion",updated_at AS "updatedAt"`,
        [branchId, principal.organizationId, input.step, JSON.stringify(dataToSave), input.expectedVersion, code, name, zone, timezone, countryCode],
      );
      if (!updated.rowCount) throw new ConflictException('El borrador cambió; vuelve a cargarlo.');
      await this.audit.appendTransaction(client, { principal, branchId, correlationId, action: 'branch.onboarding.step.save', entityType: 'branch', entityId: branchId, before: { step: input.step, version: row.onboarding_version }, after: { step: input.step, version: updated.rows[0]!.onboardingVersion, fields: Object.keys(input.data) } });
      await client.query('COMMIT');
      return updated.rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (isUnique(error)) throw new ConflictException('Ya existe una sucursal con ese código en la organización.');
      throw error;
    }
    finally { client.release(); }
  }

  async readiness(branchId: string, principal: AuthPrincipal) {
    const branchResult = await this.pool.query(
      `SELECT id,status,onboarding_data AS "onboardingData",onboarding_version AS "onboardingVersion"
         FROM branches WHERE id=$1 AND organization_id=$2`, [branchId, principal.organizationId],
    );
    const branch = branchResult.rows[0];
    if (!branch) throw new NotFoundException('La sucursal no existe.');
    const blockers: Array<{ code: string; step: string; message: string }> = [];
    const profile = await this.pool.query('SELECT profile,expected_dispenser_count FROM branch_operating_profiles WHERE branch_id=$1 AND organization_id=$2', [branchId, principal.organizationId]);
    if (!profile.rowCount) blockers.push({ code: 'PROFILE_MISSING', step: 'dispensers', message: 'Configura el perfil operativo y el número esperado de dispensadores.' });
    const offers = await this.pool.query("SELECT count(*)::int AS count FROM branch_fuel_offers WHERE branch_id=$1 AND organization_id=$2 AND status='active'", [branchId, principal.organizationId]);
    if (!offers.rows[0]?.count) blockers.push({ code: 'FUEL_OFFER_MISSING', step: 'products', message: 'Asigna al menos un combustible a la sucursal.' });
    const tanks = await this.pool.query("SELECT count(*)::int AS count FROM tanks WHERE branch_id=$1 AND organization_id=$2 AND status='active'", [branchId, principal.organizationId]);
    if (!tanks.rows[0]?.count) blockers.push({ code: 'TANK_MISSING', step: 'tanks', message: 'Registra por lo menos un tanque activo.' });
    const dispensers = await this.pool.query("SELECT count(*)::int AS count FROM dispensers WHERE branch_id=$1 AND organization_id=$2 AND physical_status='active'", [branchId, principal.organizationId]);
    const expected = profile.rows[0]?.expected_dispenser_count as number | undefined;
    if (!dispensers.rows[0]?.count || (expected !== undefined && Number(dispensers.rows[0].count) !== Number(expected))) {
      blockers.push({ code: 'DISPENSER_COUNT_MISMATCH', step: 'dispensers', message: 'El número de dispensadores activos debe coincidir con el perfil.' });
    }
    const unconnected = await this.pool.query(
      `SELECT count(*)::int AS count FROM nozzles n LEFT JOIN nozzle_tank_connections c ON c.nozzle_id=n.id AND c.valid_until IS NULL
        WHERE n.branch_id=$1 AND n.organization_id=$2 AND n.physical_status='active' AND c.id IS NULL`, [branchId, principal.organizationId],
    );
    if (Number(unconnected.rows[0]?.count ?? 0) > 0) blockers.push({ code: 'NOZZLE_WITHOUT_TANK', step: 'dispensers', message: 'Conecta cada manguera activa a un tanque del mismo combustible.' });
    const emptyDispensers = await this.pool.query(
      `SELECT count(*)::int AS count FROM dispensers d WHERE d.branch_id=$1 AND d.organization_id=$2 AND d.physical_status='active'
         AND NOT EXISTS (SELECT 1 FROM nozzles n WHERE n.dispenser_id=d.id AND n.physical_status='active')`, [branchId, principal.organizationId],
    );
    if (Number(emptyDispensers.rows[0]?.count ?? 0) > 0) blockers.push({ code: 'DISPENSER_WITHOUT_NOZZLE', step: 'dispensers', message: 'Cada dispensador activo necesita al menos una manguera configurada.' });
    const steps = branch.onboardingData as Record<string, unknown>;
    const employeeCount = await this.pool.query<{ count: number }>(
      "SELECT count(*)::int AS count FROM employees WHERE organization_id=$1 AND branch_id=$2 AND status='active'",
      [principal.organizationId, branchId],
    );
    const activeEmployeeCount = Number(employeeCount.rows[0]?.count ?? 0);
    const staffReview = steps.staff as { status?: unknown; employeeCount?: unknown } | undefined;
    if (activeEmployeeCount < 1) blockers.push({ code: 'ACTIVE_EMPLOYEE_MISSING', step: 'staff', message: 'Registra al menos una persona activa en la sucursal.' });
    if (staffReview?.status !== 'confirmed' || staffReview.employeeCount !== activeEmployeeCount) {
      blockers.push({ code: 'STAFF_REVIEW_PENDING', step: 'staff', message: 'Revisa el personal activo y confirma la cantidad actual antes de activar.' });
    }
    const missingOpenings = await this.pool.query(
      `SELECT count(*)::int AS count FROM tanks t WHERE t.branch_id=$1 AND t.organization_id=$2 AND t.status='active'
         AND NOT EXISTS (SELECT 1 FROM inventory_movements m WHERE m.tank_id=t.id AND m.organization_id=t.organization_id AND m.movement_type='opening')`, [branchId, principal.organizationId],
    );
    if (Number(missingOpenings.rows[0]?.count ?? 0) > 0) blockers.push({ code: 'OPENING_BALANCE_MISSING', step: 'openingBalances', message: 'Registra el saldo inicial de cada tanque activo.' });
    const unpriced = await countUnavailableNozzles((sql, values) => this.pool.query<{ missing_price: number; other_unavailable: number }>(sql, values), branchId, principal.organizationId);
    if (unpriced.price > 0) blockers.push({ code: 'PRICE_NOT_EFFECTIVE', step: 'prices', message: 'Configura un precio aprobado y vigente para cada combustible y modalidad de despacho.' });
    if (unpriced.other > 0) blockers.push({ code: 'NOZZLE_NOT_READY', step: 'review', message: 'Resuelve conexiones, saldos, estados o bloqueos de cada manguera activa.' });
    return { branchId, status: blockers.length ? 'blocked' : 'ready', canActivate: blockers.length === 0, onboardingVersion: branch.onboardingVersion, activeEmployeeCount, blockers };
  }

  async activate(branchId: string, principal: AuthPrincipal, input: ActivateBranchDto, correlationId: string) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const branchResult = await client.query<{ onboarding_version: number; status: string; onboarding_data: Record<string, unknown> }>(
        'SELECT onboarding_version,status,onboarding_data FROM branches WHERE id=$1 AND organization_id=$2 FOR UPDATE', [branchId, principal.organizationId],
      );
      const branch = branchResult.rows[0];
      if (!branch) throw new NotFoundException('La sucursal no existe.');
      if (branch.status !== 'draft') throw new ConflictException('La sucursal ya no está en borrador.');
      if (branch.onboarding_version !== input.expectedVersion) throw new ConflictException('La configuración cambió; vuelve a cargar el borrador.');
      const check = await this.readinessWithClient(client, branchId, principal, branch.onboarding_version, branchResult.rows[0]!.onboarding_data);
      if (check.blockers.length) throw new ConflictException({ code: 'BRANCH_NOT_READY', message: 'La sucursal conserva requisitos pendientes.', details: check.blockers });
      const changed = await client.query(
        `UPDATE branches SET status='active',activated_at=now(),updated_at=now()
         WHERE id=$1 AND organization_id=$2 AND status='draft' AND onboarding_version=$3 RETURNING id,status,activated_at AS "activatedAt"`,
        [branchId, principal.organizationId, input.expectedVersion],
      );
      if (!changed.rowCount) throw new ConflictException('La configuración cambió durante la activación.');
      await this.audit.appendTransaction(client, { principal, branchId, correlationId, action: 'branch.activate', entityType: 'branch', entityId: branchId, after: changed.rows[0] });
      await client.query('COMMIT');
      return changed.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  private async readinessWithClient(client: PoolClient, branchId: string, principal: AuthPrincipal, version: number, onboardingData: Record<string, unknown>) {
    const blockers: Array<{ code: string; step: string; message: string }> = [];
    const profile = await client.query('SELECT expected_dispenser_count FROM branch_operating_profiles WHERE branch_id=$1 AND organization_id=$2', [branchId, principal.organizationId]);
    if (!profile.rowCount) blockers.push({ code: 'PROFILE_MISSING', step: 'dispensers', message: 'Configura el perfil operativo y el número esperado de dispensadores.' });
    const offers = await client.query("SELECT count(*)::int AS count FROM branch_fuel_offers WHERE branch_id=$1 AND organization_id=$2 AND status='active'", [branchId, principal.organizationId]);
    if (!offers.rows[0]?.count) blockers.push({ code: 'FUEL_OFFER_MISSING', step: 'products', message: 'Asigna al menos un combustible a la sucursal.' });
    const tanks = await client.query("SELECT count(*)::int AS count FROM tanks WHERE branch_id=$1 AND organization_id=$2 AND status='active'", [branchId, principal.organizationId]);
    if (!tanks.rows[0]?.count) blockers.push({ code: 'TANK_MISSING', step: 'tanks', message: 'Registra por lo menos un tanque activo.' });
    const dispensers = await client.query("SELECT count(*)::int AS count FROM dispensers WHERE branch_id=$1 AND organization_id=$2 AND physical_status='active'", [branchId, principal.organizationId]);
    const expected = profile.rows[0]?.expected_dispenser_count as number | undefined;
    if (!dispensers.rows[0]?.count || (expected !== undefined && Number(dispensers.rows[0].count) !== Number(expected))) blockers.push({ code: 'DISPENSER_COUNT_MISMATCH', step: 'dispensers', message: 'El número de dispensadores activos debe coincidir con el perfil.' });
    const unconnected = await client.query(
      `SELECT count(*)::int AS count FROM nozzles n LEFT JOIN nozzle_tank_connections c ON c.nozzle_id=n.id AND c.valid_until IS NULL
        WHERE n.branch_id=$1 AND n.organization_id=$2 AND n.physical_status='active' AND c.id IS NULL`, [branchId, principal.organizationId],
    );
    if (Number(unconnected.rows[0]?.count ?? 0) > 0) blockers.push({ code: 'NOZZLE_WITHOUT_TANK', step: 'dispensers', message: 'Conecta cada manguera activa a un tanque del mismo combustible.' });
    const emptyDispensers = await client.query(
      `SELECT count(*)::int AS count FROM dispensers d WHERE d.branch_id=$1 AND d.organization_id=$2 AND d.physical_status='active'
         AND NOT EXISTS (SELECT 1 FROM nozzles n WHERE n.dispenser_id=d.id AND n.physical_status='active')`, [branchId, principal.organizationId],
    );
    if (Number(emptyDispensers.rows[0]?.count ?? 0) > 0) blockers.push({ code: 'DISPENSER_WITHOUT_NOZZLE', step: 'dispensers', message: 'Cada dispensador activo necesita al menos una manguera configurada.' });
    const employeeCount = await client.query<{ count: number }>(
      "SELECT count(*)::int AS count FROM employees WHERE organization_id=$1 AND branch_id=$2 AND status='active'",
      [principal.organizationId, branchId],
    );
    const activeEmployeeCount = Number(employeeCount.rows[0]?.count ?? 0);
    const staffReview = onboardingData.staff as { status?: unknown; employeeCount?: unknown } | undefined;
    if (activeEmployeeCount < 1) blockers.push({ code: 'ACTIVE_EMPLOYEE_MISSING', step: 'staff', message: 'Registra al menos una persona activa en la sucursal.' });
    if (staffReview?.status !== 'confirmed' || staffReview.employeeCount !== activeEmployeeCount) {
      blockers.push({ code: 'STAFF_REVIEW_PENDING', step: 'staff', message: 'Revisa el personal activo y confirma la cantidad actual antes de activar.' });
    }
    const missingOpenings = await client.query(
      `SELECT count(*)::int AS count FROM tanks t WHERE t.branch_id=$1 AND t.organization_id=$2 AND t.status='active'
         AND NOT EXISTS (SELECT 1 FROM inventory_movements m WHERE m.tank_id=t.id AND m.organization_id=t.organization_id AND m.movement_type='opening')`, [branchId, principal.organizationId],
    );
    if (Number(missingOpenings.rows[0]?.count ?? 0) > 0) blockers.push({ code: 'OPENING_BALANCE_MISSING', step: 'openingBalances', message: 'Registra el saldo inicial de cada tanque activo.' });
    const unpriced = await countUnavailableNozzles((sql, values) => client.query<{ missing_price: number; other_unavailable: number }>(sql, values), branchId, principal.organizationId);
    if (unpriced.price > 0) blockers.push({ code: 'PRICE_NOT_EFFECTIVE', step: 'prices', message: 'Configura un precio aprobado y vigente para cada combustible y modalidad de despacho.' });
    if (unpriced.other > 0) blockers.push({ code: 'NOZZLE_NOT_READY', step: 'review', message: 'Resuelve conexiones, saldos, estados o bloqueos de cada manguera activa.' });
    return { branchId, status: blockers.length ? 'blocked' : 'ready', canActivate: blockers.length === 0, onboardingVersion: version, activeEmployeeCount, blockers };
  }
}

function validateStepData(data: Record<string, unknown>): void {
  const json = JSON.stringify(data);
  if (!json || Buffer.byteLength(json, 'utf8') > 262_144) throw new BadRequestException('El paso supera el límite de 256 KiB.');
  const visit = (value: unknown, depth: number): void => {
    if (depth > 12) throw new BadRequestException('La estructura del paso es demasiado profunda.');
    if (Array.isArray(value)) { for (const entry of value) visit(entry, depth + 1); return; }
    if (!value || typeof value !== 'object') return;
    for (const [key, entry] of Object.entries(value)) {
      if (['__proto__','prototype','constructor'].includes(key)) throw new BadRequestException('El paso contiene una clave no permitida.');
      visit(entry, depth + 1);
    }
  };
  visit(data, 0);
}

const DEFAULT_COUNTRY_CODE = 'SV';
function normalizeCountryCode(value: unknown): string {
  if (value === undefined || value === null) return DEFAULT_COUNTRY_CODE;
  const code = typeof value === 'string' ? value.trim().toUpperCase() : '';
  if (!/^[A-Z]{2}$/.test(code)) throw new BadRequestException(`countryCode debe ser un código de país ISO 3166-1 alpha-2 de dos letras.`);
  return code;
}
function escapeLike(value: string): string { return value.replace(/[\\%_]/g, '\\$&'); }
function isUnique(error: unknown): boolean { return Boolean(error && typeof error === 'object' && 'code' in error && error.code === '23505'); }
function requiredString(value: unknown, field: string, max: number): string {
  if (typeof value !== 'string') throw new BadRequestException(`${field} debe ser texto.`);
  const text = value.trim();
  if (!text || text.length > max) throw new BadRequestException(`${field} debe tener entre 1 y ${max} caracteres.`);
  return text;
}

async function countUnavailableNozzles(
  query: (sql: string, values: unknown[]) => Promise<{ rows: Array<{ missing_price: number; other_unavailable: number }> }>,
  branchId: string,
  organizationId: string,
): Promise<{ price: number; other: number }> {
  const result = await query(
    `SELECT count(*) FILTER (WHERE price.id IS NULL)::int AS missing_price,
            count(*) FILTER (WHERE price.id IS NOT NULL AND (
              d.physical_status <> 'active' OR c.id IS NULL OR t.status <> 'active' OR fp.status <> 'active' OR o.status <> 'active'
              OR bal.tank_id IS NULL OR bal.on_hand_l <= t.unusable_reserve_l
              OR EXISTS (SELECT 1 FROM asset_blocks ab WHERE ab.organization_id=n.organization_id AND ab.branch_id=n.branch_id AND ab.resolved_at IS NULL
                AND ((ab.asset_type='nozzle' AND ab.asset_id=n.id) OR (ab.asset_type='dispenser' AND ab.asset_id=d.id) OR (ab.asset_type='tank' AND ab.asset_id=t.id)))
            ))::int AS other_unavailable
       FROM nozzles n
       JOIN dispensers d ON d.id=n.dispenser_id AND d.branch_id=n.branch_id
       JOIN fuel_products fp ON fp.id=n.fuel_product_id AND fp.organization_id=n.organization_id
       LEFT JOIN branch_fuel_offers o ON o.branch_id=n.branch_id AND o.fuel_product_id=n.fuel_product_id
       LEFT JOIN nozzle_tank_connections c ON c.nozzle_id=n.id AND c.valid_until IS NULL
       LEFT JOIN tanks t ON t.id=c.tank_id AND t.branch_id=n.branch_id AND t.fuel_product_id=n.fuel_product_id
       LEFT JOIN tank_inventory_balances bal ON bal.tank_id=t.id AND bal.organization_id=n.organization_id
       LEFT JOIN LATERAL (
         SELECT id FROM fuel_price_versions p WHERE p.organization_id=n.organization_id AND p.branch_id=n.branch_id
           AND p.fuel_product_id=n.fuel_product_id AND p.service_mode=n.service_mode AND p.effective_at<=now()
         ORDER BY p.effective_at DESC,p.version DESC LIMIT 1
       ) price ON true
      WHERE n.branch_id=$1 AND n.organization_id=$2 AND n.physical_status='active'`,
    [branchId, organizationId],
  );
  return { price: Number(result.rows[0]?.missing_price ?? 0), other: Number(result.rows[0]?.other_unavailable ?? 0) };
}
