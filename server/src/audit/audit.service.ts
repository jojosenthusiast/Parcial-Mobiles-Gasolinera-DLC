import { Inject, Injectable } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import type { AuthPrincipal } from '../auth/auth.types.js';

const secretField = /password|token|secret|authorization|cookie|credential/i;

export interface AuditEventInput {
  principal: AuthPrincipal;
  branchId?: string | null;
  correlationId: string;
  action: string;
  entityType: string;
  entityId: string;
  before?: unknown;
  after?: unknown;
  metadata?: Record<string, unknown>;
}

@Injectable()
export class AuditService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async append(input: AuditEventInput): Promise<void> {
    await this.pool.query(
      auditInsert, auditValues(input),
    );
  }

  async appendTransaction(client: PoolClient, input: AuditEventInput): Promise<void> {
    await client.query(auditInsert, auditValues(input));
  }
}

const auditInsert = `INSERT INTO audit_events
  (organization_id, branch_id, actor_user_id, correlation_id, action, entity_type, entity_id, before_data, after_data, metadata)
  VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9::jsonb,$10::jsonb)`;

function auditValues(input: AuditEventInput): unknown[] {
  return [input.principal.organizationId, input.branchId ?? null, input.principal.userId,
    input.correlationId, input.action, input.entityType, input.entityId,
    jsonOrNull(redact(input.before)), jsonOrNull(redact(input.after)), JSON.stringify(redact(input.metadata ?? {}))];
}

function jsonOrNull(value: unknown): string | null {
  return value === undefined ? null : JSON.stringify(value) ?? 'null';
}

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, secretField.test(key) ? '[REDACTED]' : redact(entry)]));
  }
  return value;
}
