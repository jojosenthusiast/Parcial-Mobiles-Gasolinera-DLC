import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import { Decimal } from 'decimal.js';
import { PG_POOL } from '../database/database.module.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { MarketPriceReferenceDto, PriceDecisionDto, FuelPriceProposalDto } from './pricing.dto.js';

@Injectable()
export class PricingService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly audit: AuditService) {}

  async createMarketReference(principal: AuthPrincipal, input: MarketPriceReferenceDto, correlationId: string) {
    if (input.referencePrice !== undefined && !new Decimal(input.referencePrice).isFinite()) throw new BadRequestException('El precio de referencia no es válido.');
    const product = await this.pool.query("SELECT 1 FROM fuel_products WHERE id=$1 AND organization_id=$2 AND status='active'", [input.fuelProductId, principal.organizationId]);
    if (!product.rowCount) throw new NotFoundException('El producto de combustible no existe o está inactivo.');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(
        `INSERT INTO fuel_market_references(organization_id,fuel_product_id,zone,announced_at,effective_at,direction,reference_price,unit,source_name,source_reference,note,created_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
         RETURNING id,fuel_product_id AS "fuelProductId",zone,announced_at AS "announcedAt",effective_at AS "effectiveAt",direction,reference_price AS "referencePrice",currency,unit,source_name AS "sourceName",source_reference AS "sourceReference",note,created_at AS "createdAt"`,
        [principal.organizationId,input.fuelProductId,input.zone,input.announcedAt,input.effectiveAt ?? null,input.direction,input.referencePrice ?? null,input.unit,input.sourceName.trim(),input.sourceReference?.trim() ?? null,input.note?.trim() ?? null,principal.userId],
      );
      await this.audit.appendTransaction(client, { principal, correlationId, action: 'fuel_market_reference.create', entityType: 'fuel_market_reference', entityId: result.rows[0]!.id, after: { productId: input.fuelProductId, zone: input.zone, direction: input.direction, sourceName: input.sourceName } });
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  async listMarketReferences(principal: AuthPrincipal, options: { zone?: string; productId?: string; limit: number }) {
    const values: unknown[] = [principal.organizationId]; const where = ['organization_id=$1'];
    if (options.zone) { values.push(options.zone); where.push(`zone=$${values.length}`); }
    if (options.productId) { values.push(options.productId); where.push(`fuel_product_id=$${values.length}`); }
    values.push(Math.min(100,Math.max(1,options.limit)));
    const result = await this.pool.query(
      `SELECT id,fuel_product_id AS "fuelProductId",zone,announced_at AS "announcedAt",effective_at AS "effectiveAt",direction,reference_price AS "referencePrice",currency,unit,source_name AS "sourceName",source_reference AS "sourceReference",note,created_at AS "createdAt"
         FROM fuel_market_references WHERE ${where.join(' AND ')} ORDER BY announced_at DESC,id DESC LIMIT $${values.length}`, values,
    );
    return { data: result.rows, meta: { limit: Math.min(100,Math.max(1,options.limit)) } };
  }

  async createProposal(branchId: string, principal: AuthPrincipal, input: FuelPriceProposalDto, correlationId: string) {
    const effective = Date.parse(input.effectiveAt);
    if (!Number.isFinite(effective) || effective < Date.now()) throw new BadRequestException('La vigencia no puede aplicarse retroactivamente.');
    const price = new Decimal(input.priceUsdPerUnit);
    if (!price.isFinite() || !price.gt(0)) throw new BadRequestException('El precio propuesto debe ser mayor que cero.');
    const product = await this.pool.query(
      `SELECT 1 FROM branch_fuel_offers WHERE branch_id=$1 AND organization_id=$2 AND fuel_product_id=$3 AND status='active'`,
      [branchId,principal.organizationId,input.fuelProductId],
    );
    if (!product.rowCount) throw new ConflictException('El combustible no está habilitado en esta sucursal.');
    if (input.marketReferenceId) {
      const reference = await this.pool.query(
        `SELECT r.zone,b.zone AS "branchZone" FROM fuel_market_references r JOIN branches b ON b.id=$4 AND b.organization_id=r.organization_id
          WHERE r.id=$1 AND r.organization_id=$2 AND r.fuel_product_id=$3`,
        [input.marketReferenceId,principal.organizationId,input.fuelProductId,branchId],
      );
      if (!reference.rowCount) throw new BadRequestException('La referencia de mercado no corresponde al combustible, sucursal u organización.');
      if (reference.rows[0]!.zone !== reference.rows[0]!.branchZone) throw new BadRequestException('La referencia de mercado corresponde a otra zona.');
    }
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(
        `INSERT INTO fuel_price_proposals(organization_id,branch_id,fuel_product_id,service_mode,proposed_price_usd_per_unit,unit,effective_at,market_reference_id,reason,created_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         RETURNING id,branch_id AS "branchId",fuel_product_id AS "fuelProductId",service_mode AS "serviceMode",proposed_price_usd_per_unit AS "priceUsdPerUnit",unit,effective_at AS "effectiveAt",market_reference_id AS "marketReferenceId",reason,status,version,created_by AS "createdBy",created_at AS "createdAt"`,
        [principal.organizationId,branchId,input.fuelProductId,input.serviceMode,price.toFixed(8),input.unit,input.effectiveAt,input.marketReferenceId ?? null,input.reason.trim(),principal.userId],
      );
      const proposal = result.rows[0]!;
      await this.audit.appendTransaction(client, { principal, branchId, correlationId, action: 'fuel_price.propose', entityType: 'fuel_price_proposal', entityId: proposal.id, after: { fuelProductId: input.fuelProductId, serviceMode: input.serviceMode, price: price.toFixed(8), unit: input.unit, effectiveAt: input.effectiveAt, marketReferenceId: input.marketReferenceId ?? null } });
      await client.query('COMMIT');
      return proposal;
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  async decide(proposalId: string, principal: AuthPrincipal, input: PriceDecisionDto, decision: 'approve' | 'reject', correlationId: string) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const current = await client.query<{ organization_id: string; branch_id: string; created_by: string; status: string; version: number }>(
        'SELECT organization_id,branch_id,created_by,status,version FROM fuel_price_proposals WHERE id=$1 AND organization_id=$2 FOR UPDATE', [proposalId,principal.organizationId],
      );
      const proposal = current.rows[0];
      if (!proposal) throw new NotFoundException('La propuesta de precio no existe.');
      if (proposal.status !== 'pending_approval') throw new ConflictException('La propuesta ya fue resuelta.');
      if (proposal.version !== input.expectedVersion) throw new ConflictException('La propuesta cambió; vuelve a cargarla.');
      if (proposal.created_by === principal.userId) throw new ConflictException('Quien propone el precio no puede aprobarlo o rechazarlo.');
      if (decision === 'reject' && !input.reason?.trim()) throw new BadRequestException('Rechaza la propuesta con una razón.');
      const status = decision === 'approve' ? 'approved' : 'rejected';
      const column = decision === 'approve' ? 'approved_by' : 'rejected_by';
      const updated = await client.query(
        `UPDATE fuel_price_proposals SET status=$2,${column}=$3,${decision === 'approve' ? 'approved_at=now()' : 'rejected_at=now()'},version=version+1
         WHERE id=$1 AND version=$4 RETURNING id,status,version,approved_by AS "approvedBy",approved_at AS "approvedAt"`,
        [proposalId,status,principal.userId,input.expectedVersion],
      );
      await this.audit.appendTransaction(client, { principal, branchId: proposal.branch_id, correlationId, action: `fuel_price.${decision}`, entityType: 'fuel_price_proposal', entityId: proposalId, after: { status, reason: input.reason ?? null, version: updated.rows[0]!.version } });
      await client.query('COMMIT');
      return updated.rows[0];
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  async schedule(proposalId: string, principal: AuthPrincipal, input: PriceDecisionDto, correlationId: string) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const current = await client.query<{
        id: string; organization_id: string; branch_id: string; fuel_product_id: string; service_mode: string; proposed_price_usd_per_unit: string;
        unit: string; effective_at: Date; status: string; version: number;
      }>(
        `SELECT id,organization_id,branch_id,fuel_product_id,service_mode,proposed_price_usd_per_unit,unit,effective_at,status,version
           FROM fuel_price_proposals WHERE id=$1 AND organization_id=$2 FOR UPDATE`, [proposalId,principal.organizationId],
      );
      const proposal = current.rows[0];
      if (!proposal) throw new NotFoundException('La propuesta de precio no existe.');
      if (proposal.status !== 'approved') throw new ConflictException('Aprueba la propuesta con otro usuario antes de programarla.');
      if (proposal.version !== input.expectedVersion) throw new ConflictException('La propuesta cambió; vuelve a cargarla.');
      if (proposal.effective_at.getTime() < Date.now()) throw new ConflictException('La fecha efectiva ya pasó; crea una nueva propuesta con una fecha futura.');
      const branchLock = await client.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 FOR UPDATE', [proposal.branch_id,proposal.organization_id]);
      if (!branchLock.rowCount) throw new NotFoundException('La sucursal no existe.');
      const offer = await client.query("SELECT 1 FROM branch_fuel_offers WHERE branch_id=$1 AND organization_id=$2 AND fuel_product_id=$3 AND status='active'", [proposal.branch_id,proposal.organization_id,proposal.fuel_product_id]);
      if (!offer.rowCount) throw new ConflictException('El combustible dejó de estar habilitado en esta sucursal.');
      const latest = await client.query<{ next_version: number }>(
        `SELECT COALESCE(max(version),0)+1 AS next_version FROM fuel_price_versions WHERE organization_id=$1 AND branch_id=$2 AND fuel_product_id=$3 AND service_mode=$4`,
        [proposal.organization_id,proposal.branch_id,proposal.fuel_product_id,proposal.service_mode],
      );
      const nextVersion = Number(latest.rows[0]?.next_version ?? 1);
      const inserted = await client.query(
        `INSERT INTO fuel_price_versions(organization_id,branch_id,fuel_product_id,service_mode,version,price_usd_per_unit,unit,effective_at,proposal_id,created_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         RETURNING id,branch_id AS "branchId",fuel_product_id AS "fuelProductId",service_mode AS "serviceMode",version,price_usd_per_unit AS "priceUsdPerUnit",unit,effective_at AS "effectiveAt"`,
        [proposal.organization_id,proposal.branch_id,proposal.fuel_product_id,proposal.service_mode,nextVersion,proposal.proposed_price_usd_per_unit,proposal.unit,proposal.effective_at,proposal.id,principal.userId],
      );
      const updated = await client.query("UPDATE fuel_price_proposals SET status='scheduled',version=version+1 WHERE id=$1 AND version=$2 RETURNING version",[proposal.id,input.expectedVersion]);
      if (!updated.rowCount) throw new ConflictException('La propuesta cambió durante la programación.');
      await this.audit.appendTransaction(client, { principal, branchId: proposal.branch_id, correlationId, action: 'fuel_price.schedule', entityType: 'fuel_price_version', entityId: inserted.rows[0]!.id, after: { proposalId, version: nextVersion, effectiveAt: proposal.effective_at, price: proposal.proposed_price_usd_per_unit, unit: proposal.unit } });
      await client.query('COMMIT');
      return inserted.rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (isUnique(error)) throw new ConflictException('Ya existe un precio para ese producto, modalidad y vigencia.');
      throw error;
    } finally { client.release(); }
  }

  async prices(branchId: string, principal: AuthPrincipal, productId?: string, serviceMode?: string) {
    const values: unknown[] = [principal.organizationId,branchId]; const where=['v.organization_id=$1','v.branch_id=$2'];
    if (productId) { values.push(productId); where.push(`v.fuel_product_id=$${values.length}`); }
    if (serviceMode) { values.push(serviceMode); where.push(`v.service_mode=$${values.length}`); }
    const result = await this.pool.query(
      `SELECT DISTINCT ON (v.fuel_product_id,v.service_mode) v.id,v.fuel_product_id AS "fuelProductId",p.display_name AS "productName",v.service_mode AS "serviceMode",v.version,v.price_usd_per_unit AS "priceUsdPerUnit",v.unit,v.effective_at AS "effectiveAt"
         FROM fuel_price_versions v JOIN fuel_products p ON p.id=v.fuel_product_id AND p.organization_id=v.organization_id
        WHERE ${where.join(' AND ')} AND v.effective_at<=now() ORDER BY v.fuel_product_id,v.service_mode,v.effective_at DESC,v.version DESC`, values,
    );
    const upcoming = await this.pool.query(
      `SELECT v.id,v.fuel_product_id AS "fuelProductId",p.display_name AS "productName",v.service_mode AS "serviceMode",v.version,v.price_usd_per_unit AS "priceUsdPerUnit",v.unit,v.effective_at AS "effectiveAt"
         FROM fuel_price_versions v JOIN fuel_products p ON p.id=v.fuel_product_id AND p.organization_id=v.organization_id
        WHERE ${where.join(' AND ')} AND v.effective_at>now() ORDER BY v.effective_at`, values,
    );
    return { current: result.rows, upcoming: upcoming.rows };
  }

  async proposals(branchId: string, principal: AuthPrincipal, status?: string) {
    const values: unknown[] = [principal.organizationId,branchId];
    const statusFilter = status ? ' AND p.status=$3' : '';
    if (status) values.push(status);
    const result = await this.pool.query(
      `SELECT p.id,p.fuel_product_id AS "fuelProductId",fp.display_name AS "productName",p.service_mode AS "serviceMode",
              p.proposed_price_usd_per_unit AS "priceUsdPerUnit",p.unit,p.effective_at AS "effectiveAt",p.market_reference_id AS "marketReferenceId",
              p.reason,p.status,p.version,p.created_by AS "createdBy",p.approved_by AS "approvedBy",p.rejected_by AS "rejectedBy",
              p.created_at AS "createdAt",p.approved_at AS "approvedAt",p.rejected_at AS "rejectedAt"
         FROM fuel_price_proposals p JOIN fuel_products fp ON fp.id=p.fuel_product_id AND fp.organization_id=p.organization_id
        WHERE p.organization_id=$1 AND p.branch_id=$2${statusFilter} ORDER BY p.created_at DESC,p.id DESC`, values,
    );
    return { data: result.rows };
  }

  async priceHistory(branchId: string, principal: AuthPrincipal, productId: string) {
    const result = await this.pool.query(
      `SELECT id,fuel_product_id AS "fuelProductId",service_mode AS "serviceMode",version,price_usd_per_unit AS "priceUsdPerUnit",unit,effective_at AS "effectiveAt",proposal_id AS "proposalId",created_by AS "createdBy",created_at AS "createdAt"
         FROM fuel_price_versions WHERE organization_id=$1 AND branch_id=$2 AND fuel_product_id=$3 ORDER BY service_mode,effective_at DESC,version DESC`, [principal.organizationId,branchId,productId],
    );
    return { data: result.rows };
  }
}

function isUnique(error: unknown): boolean { return Boolean(error && typeof error === 'object' && 'code' in error && error.code === '23505'); }
