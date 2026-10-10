import { ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';

@Injectable()
export class ApprovalService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly auth: AuthService, private readonly audit: AuditService) {}

  async request(input: {
    principal: AuthPrincipal; branchId?: string | null; action: string;
    entityType: string; entityId: string; payload: Record<string, unknown>;
  }): Promise<{ id: string; status: 'pending' }> {
    const permission = await this.pool.query('SELECT 1 FROM permissions WHERE code = $1', [input.action]);
    if (!permission.rowCount) throw new ConflictException('La acción de aprobación no está asociada a un permiso válido.');
    const result = await this.pool.query<{ id: string }>(
      `INSERT INTO approval_requests
        (organization_id, branch_id, action, entity_type, entity_id, requested_by, payload)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb) RETURNING id`,
      [input.principal.organizationId, input.branchId ?? null, input.action, input.entityType,
       input.entityId, input.principal.userId, JSON.stringify(input.payload)],
    );
    return { id: result.rows[0]!.id, status: 'pending' };
  }

  async decide(id: string, approver: AuthPrincipal, decision: 'approved' | 'rejected', reason: string, requestedBranchId: string | null, correlationId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const found = await client.query<{ requested_by: string; status: string; branch_id: string | null; action: string }>(
        `SELECT requested_by, status, branch_id, action FROM approval_requests
          WHERE id = $1 AND organization_id = $2 FOR UPDATE`, [id, approver.organizationId],
      );
      const request = found.rows[0];
      if (!request) throw new NotFoundException('La solicitud no existe.');
      if (request.branch_id !== requestedBranchId) throw new NotFoundException('La solicitud no existe en ese ámbito.');
      if (request.status !== 'pending') throw new ConflictException('La solicitud ya fue resuelta.');
      const capabilities = await this.auth.capabilities(approver, request.branch_id ?? undefined);
      if (!capabilities.includes(request.action)) throw new ConflictException('No tienes el permiso específico para aprobar esta acción.');
      const policyResult = await client.query<{ require_different_approver: boolean }>(
        `SELECT require_different_approver FROM approval_policies
          WHERE organization_id = $1 AND action = $2
            AND enabled = true AND (branch_id = $3 OR branch_id IS NULL)
          ORDER BY (branch_id IS NOT NULL) DESC LIMIT 1`,
        [approver.organizationId, request.action, request.branch_id],
      );
      const segregated = policyResult.rows[0]?.require_different_approver ?? true;
      if (segregated && request.requested_by === approver.userId) {
        throw new ConflictException('La política requiere que otra persona apruebe esta solicitud.');
      }
      await client.query(
        `UPDATE approval_requests SET status = $2, decided_by = $3, decided_at = now(), reason = $4
          WHERE id = $1`, [id, decision, approver.userId, reason.trim().slice(0, 1000)],
      );
      await this.audit.appendTransaction(client, { principal: approver, branchId: request.branch_id, correlationId, action: `approval.${decision}`, entityType: 'approval', entityId: id, after: { decision, reason: reason.trim().slice(0, 1000) } });
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }
}
