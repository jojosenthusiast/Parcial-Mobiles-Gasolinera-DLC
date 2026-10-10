import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import { PG_POOL } from '../database/database.module.js';
import type { CreateLoyaltyProgramDto, LoyaltyProgramDecisionDto } from './loyalty-program.dto.js';

@Injectable()
export class LoyaltyProgramService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly auth: AuthService, private readonly audit: AuditService) {}

  async list(principal: AuthPrincipal) {
    await this.require(principal, 'loyalty.program.read');
    const rows = await this.pool.query(
        `SELECT id,version,status,points_per_eligible_usd AS "pointsPerEligibleUsd",minimum_eligible_usd AS "minimumEligibleUsd",
              redemption_usd_per_point AS "redemptionUsdPerPoint",
              points_expire_after_days AS "pointsExpireAfterDays",created_by AS "createdBy",created_at AS "createdAt",
              submitted_by AS "submittedBy",submitted_at AS "submittedAt",decision_by AS "decisionBy",decision_at AS "decisionAt",decision_reason AS "decisionReason"
         FROM customer_loyalty_programs WHERE organization_id=$1 ORDER BY version DESC`, [principal.organizationId],
    );
    return { data: rows.rows };
  }

  async create(principal: AuthPrincipal, input: CreateLoyaltyProgramDto, correlationId: string) {
    await this.require(principal, 'loyalty.program.manage');
    const normalized = {
      pointsPerEligibleUsd: input.pointsPerEligibleUsd,
      minimumEligibleUsd: input.minimumEligibleUsd,
      redemptionUsdPerPoint: input.redemptionUsdPerPoint,
    };
    const hash = digest(normalized);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`loyalty-command:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
      const replay = await this.replay(client, principal, input.commandId, hash);
      if (replay) { await client.query('COMMIT'); return replay; }
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`loyalty-program:${principal.organizationId}`]);
      const afterLockReplay = await this.replay(client, principal, input.commandId, hash);
      if (afterLockReplay) { await client.query('COMMIT'); return afterLockReplay; }
      const version = await client.query<{ version: number }>(
        'SELECT COALESCE(max(version),0)+1 AS version FROM customer_loyalty_programs WHERE organization_id=$1', [principal.organizationId]);
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO customer_loyalty_programs(organization_id,version,status,points_per_eligible_usd,minimum_eligible_usd,
           redemption_usd_per_point,created_by,command_id,request_hash)
         VALUES($1,$2,'draft',$3,$4,$5,$6,$7,$8) RETURNING id`,
        [principal.organizationId, version.rows[0]!.version, normalized.pointsPerEligibleUsd, normalized.minimumEligibleUsd,
          normalized.redemptionUsdPerPoint, principal.userId, input.commandId, hash]);
      const id = inserted.rows[0]!.id;
      await this.event(client, principal, id, input.commandId, hash, 'created', normalized);
      await this.audit.appendTransaction(client, { principal, correlationId, action: 'loyalty.program.created', entityType: 'customer_loyalty_program', entityId: id, after: { version: version.rows[0]!.version, ...normalized } });
      await client.query('COMMIT');
      return { data: { id, version: version.rows[0]!.version, status: 'draft', ...normalized } };
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  async submit(id: string, principal: AuthPrincipal, commandId: string, correlationId: string) {
    await this.require(principal, 'loyalty.program.manage');
    return this.transition(id, principal, commandId, digest({ id, action: 'submit' }), correlationId, async (client, row) => {
      if (row.status !== 'draft') throw new ConflictException('Solo una propuesta en borrador puede enviarse a aprobación.');
      await client.query(`UPDATE customer_loyalty_programs SET status='pending_approval',submitted_by=$2,submitted_at=now() WHERE id=$1`, [id, principal.userId]);
      return { event: 'submitted', action: 'loyalty.program.submitted', data: {} };
    });
  }

  async decide(id: string, principal: AuthPrincipal, input: LoyaltyProgramDecisionDto, correlationId: string) {
    await this.require(principal, 'loyalty.program.approve');
    if (input.decision !== 'approve' && input.decision !== 'reject') throw new BadRequestException('La decisión debe ser approve o reject.');
    if (input.decision === 'reject' && !input.reason?.trim()) throw new BadRequestException('Indica el motivo del rechazo.');
    const reason = input.reason?.trim() || null;
    const hash = digest({ id, decision: input.decision, reason });
    return this.transition(id, principal, input.commandId, hash, correlationId, async (client, row) => {
      if (row.status !== 'pending_approval') throw new ConflictException('La propuesta ya no está pendiente de aprobación.');
      if (row.created_by === principal.userId || row.submitted_by === principal.userId) throw new ForbiddenException('Quien preparó la política no puede aprobarla.');
      if (input.decision === 'reject') {
        await client.query(`UPDATE customer_loyalty_programs SET status='rejected',decision_by=$2,decision_at=now(),decision_reason=$3 WHERE id=$1`, [id, principal.userId, reason]);
        return { event: 'rejected', action: 'loyalty.program.rejected', data: { reason } };
      }
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`loyalty-program:${principal.organizationId}`]);
      await client.query(`UPDATE customer_loyalty_programs SET status='retired' WHERE organization_id=$1 AND status='active'`, [principal.organizationId]);
      await client.query(`UPDATE customer_loyalty_programs SET status='active',decision_by=$2,decision_at=now(),approved_by=$2,approved_at=now(),decision_reason=NULL WHERE id=$1`, [id, principal.userId]);
      return { event: 'approved', action: 'loyalty.program.approved', data: {} };
    });
  }

  async retire(id: string, principal: AuthPrincipal, commandId: string, correlationId: string) {
    await this.require(principal, 'loyalty.program.approve');
    return this.transition(id, principal, commandId, digest({ id, action: 'retire' }), correlationId, async (client, row) => {
      if (row.status !== 'active') throw new ConflictException('Solo se puede retirar una política activa.');
      await client.query(`UPDATE customer_loyalty_programs SET status='retired' WHERE id=$1`, [id]);
      return { event: 'retired', action: 'loyalty.program.retired', data: {} };
    });
  }

  private async transition(id: string, principal: AuthPrincipal, commandId: string, hash: string, correlationId: string,
    apply: (client: PoolClient, row: ProgramRow) => Promise<{ event: string; action: string; data: Record<string, unknown> }>) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`loyalty-command:${principal.organizationId}:${commandId.toLowerCase()}`]);
      const replay = await this.replay(client, principal, commandId, hash);
      if (replay) { await client.query('COMMIT'); return replay; }
      const found = await client.query<ProgramRow>(`SELECT id,organization_id,status,version,created_by,submitted_by FROM customer_loyalty_programs
        WHERE id=$1 AND organization_id=$2 FOR UPDATE`, [id, principal.organizationId]);
      const row = found.rows[0];
      if (!row) throw new NotFoundException('La política de puntos no existe.');
      const result = await apply(client, row);
      await this.event(client, principal, id, commandId, hash, result.event, result.data);
      await this.audit.appendTransaction(client, { principal, correlationId, action: result.action, entityType: 'customer_loyalty_program', entityId: id, before: { status: row.status }, after: { status: result.event === 'submitted' ? 'pending_approval' : result.event === 'approved' ? 'active' : result.event === 'rejected' ? 'rejected' : 'retired', ...result.data } });
      await client.query('COMMIT');
      return { data: { id, status: result.event === 'submitted' ? 'pending_approval' : result.event === 'approved' ? 'active' : result.event === 'rejected' ? 'rejected' : 'retired' } };
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  private async replay(client: PoolClient, principal: AuthPrincipal, commandId: string, hash: string) {
    const existing = await client.query<{ program_id: string; request_hash: string; event_type: string }>(
      `SELECT program_id,request_hash,event_type FROM customer_loyalty_program_events WHERE organization_id=$1 AND command_id=$2`, [principal.organizationId, commandId]);
    if (!existing.rows[0]) return null;
    if (existing.rows[0].request_hash !== hash) throw new ConflictException('El commandId ya se utilizó con otros datos.');
    const program = await client.query(`SELECT id,version,status FROM customer_loyalty_programs WHERE id=$1 AND organization_id=$2`, [existing.rows[0].program_id, principal.organizationId]);
    return { data: program.rows[0] };
  }

  private async event(client: PoolClient, principal: AuthPrincipal, programId: string, commandId: string, hash: string, eventType: string, payload: Record<string, unknown>) {
    await client.query(`INSERT INTO customer_loyalty_program_events(organization_id,program_id,command_id,actor_id,event_type,request_hash,payload)
      VALUES($1,$2,$3,$4,$5,$6,$7::jsonb)`, [principal.organizationId, programId, commandId, principal.userId, eventType, hash, JSON.stringify(payload)]);
  }

  private async require(principal: AuthPrincipal, permission: string) {
    if (!(await this.auth.capabilities(principal)).includes(permission)) throw new ForbiddenException('Se requiere permiso de administración general para esta política.');
  }
}

interface ProgramRow { id: string; organization_id: string; status: string; version: number; created_by: string; submitted_by: string | null; }
function digest(value: unknown) { return createHash('sha256').update(JSON.stringify(value)).digest('hex'); }
