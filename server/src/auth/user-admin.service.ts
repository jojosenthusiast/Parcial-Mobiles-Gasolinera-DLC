import { createHash, randomBytes } from 'node:crypto';
import { ConflictException, Inject, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Pool } from 'pg';
import * as argon2 from 'argon2';
import { PG_POOL } from '../database/database.module.js';
import type { AuthPrincipal } from './auth.types.js';
import { AuditService } from '../audit/audit.service.js';

@Injectable()
export class UserAdminService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly audit: AuditService) {}

  async list(actor: AuthPrincipal, options: { branchId?: string; query?: string; status?: string; cursor?: string; limit?: number } = {}) {
    const client = await this.pool.connect();
    try {
      await assertCanManageAtScope(client, actor, options.branchId ?? null);
    } finally { client.release(); }
    const branchId = options.branchId ?? null;
    const query = options.query?.trim().normalize('NFKC') ?? '';
    const status = options.status ?? '';
    const cursor = options.cursor ?? null;
    const limit = Math.max(1,Math.min(200,options.limit ?? 100));
    const result = await this.pool.query(`
      SELECT u.id,u.display_name AS "displayName",u.email_normalized AS email,u.status,
             u.created_at AS "createdAt",u.last_login_at AS "lastLoginAt",
             COALESCE(jsonb_agg(DISTINCT jsonb_build_object('roleId',r.id,'roleCode',r.code,'roleName',r.name,'branchId',ura.branch_id))
               FILTER(WHERE r.id IS NOT NULL), '[]'::jsonb) AS roles
        FROM users u
        LEFT JOIN user_role_assignments ura ON ura.user_id=u.id AND ura.organization_id=u.organization_id
          AND ura.valid_from<=now() AND (ura.valid_until IS NULL OR ura.valid_until>now())
          AND ($2::uuid IS NULL OR ura.branch_id=$2)
        LEFT JOIN roles r ON r.id=ura.role_id AND r.organization_id=ura.organization_id
       WHERE u.organization_id=$1 AND ($2::uuid IS NULL OR EXISTS(
          SELECT 1 FROM user_role_assignments scope WHERE scope.user_id=u.id AND scope.organization_id=u.organization_id
            AND scope.branch_id=$2 AND scope.valid_from<=now() AND (scope.valid_until IS NULL OR scope.valid_until>now())))
         AND ($3='' OR u.display_name ILIKE '%'||$3||'%' OR u.email_normalized ILIKE '%'||$3||'%')
         AND ($4='' OR u.status=$4) AND ($5::uuid IS NULL OR u.id>$5)
       GROUP BY u.id ORDER BY u.id LIMIT $6`,
      [actor.organizationId, branchId, query, status, cursor, limit+1]);
    const hasMore=result.rows.length>limit;
    const data=hasMore?result.rows.slice(0,limit):result.rows;
    return { data, meta: { limit, nextCursor: hasMore ? data.at(-1)!.id : null } };
  }

  async listRoles(actor: AuthPrincipal) {
    const result = await this.pool.query(
      'SELECT id, code, name FROM roles WHERE organization_id = $1 ORDER BY name', [actor.organizationId],
    );
    return { data: result.rows };
  }

  async invite(input: {
    actor: AuthPrincipal; email: string; displayName: string; roleId: string;
    branchId?: string | null; employeeId?: string | null; correlationId: string;
  }): Promise<{ userId: string; activationToken: string; expiresAt: string }> {
    if (!manualAccountDeliveryAllowed()) throw new ServiceUnavailableException('La entrega segura de invitaciones no está configurada.');
    const email = input.email.trim().normalize('NFKC').toLowerCase();
    const activationToken = randomBytes(32).toString('base64url');
    const initialHash = await argon2.hash(randomBytes(32), { type: argon2.argon2id });
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const role = await client.query(
        'SELECT id FROM roles WHERE id = $1 AND organization_id = $2', [input.roleId, input.actor.organizationId],
      );
      if (!role.rowCount) throw new NotFoundException('El rol no existe en la organización.');
      await assertCanManageAtScope(client, input.actor, input.branchId ?? null);
      await assertCanGrantRole(client, input.actor, input.roleId, input.branchId ?? null);
      const created = await client.query<{ id: string }>(
        `INSERT INTO users (organization_id, employee_id, email_normalized, display_name, password_hash, status)
         VALUES ($1,$2,$3,$4,$5,'invited') RETURNING id`,
        [input.actor.organizationId, input.employeeId ?? null, email, input.displayName.trim(), initialHash],
      );
      const userId = created.rows[0]!.id;
      await client.query(
        `INSERT INTO user_role_assignments (organization_id, user_id, role_id, branch_id, assigned_by)
         VALUES ($1,$2,$3,$4,$5)`,
        [input.actor.organizationId, userId, input.roleId, input.branchId ?? null, input.actor.userId],
      );
      const tokenHash = hashToken(activationToken);
      const token = await client.query<{ expires_at: Date }>(
        `INSERT INTO account_action_tokens (token_hash, user_id, token_type, expires_at)
         VALUES ($1,$2,'invite',now() + interval '72 hours') RETURNING expires_at`, [tokenHash, userId],
      );
      await this.audit.appendTransaction(client, { principal: input.actor, branchId: input.branchId ?? null, correlationId: input.correlationId, action: 'user.invite', entityType: 'user', entityId: userId, after: { status: 'invited', email, roleId: input.roleId, branchId: input.branchId ?? null } });
      await client.query('COMMIT');
      return { userId, activationToken, expiresAt: token.rows[0]!.expires_at.toISOString() };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (isUniqueViolation(error)) throw new ConflictException('Ya existe una cuenta con ese correo.');
      throw error;
    } finally {
      client.release();
    }
  }

  async issuePasswordReset(userId: string, actor: AuthPrincipal, correlationId: string): Promise<{ resetToken: string; expiresAt: string }> {
    if (!manualAccountDeliveryAllowed()) throw new ServiceUnavailableException('La entrega segura de restablecimiento no está configurada.');
    const resetToken = randomBytes(32).toString('base64url');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const user = await client.query<{ id: string }>(
        'SELECT id FROM users WHERE id = $1 AND organization_id = $2 AND status <> $3 FOR UPDATE',
        [userId, actor.organizationId, 'terminated'],
      );
      if (!user.rowCount) throw new NotFoundException('La cuenta no existe.');
      await client.query(
        `UPDATE account_action_tokens SET consumed_at = now()
          WHERE user_id = $1 AND token_type = 'password_reset' AND consumed_at IS NULL`, [userId],
      );
      const result = await client.query<{ expires_at: Date }>(
        `INSERT INTO account_action_tokens (token_hash, user_id, token_type, expires_at)
         VALUES ($1,$2,'password_reset',now() + interval '30 minutes') RETURNING expires_at`,
        [hashToken(resetToken), userId],
      );
      await client.query('UPDATE users SET permission_version = permission_version + 1, updated_at = now() WHERE id = $1', [userId]);
      await client.query("UPDATE auth_sessions SET revoked_at = now(), revoke_reason = 'password_reset_issued' WHERE user_id = $1 AND revoked_at IS NULL", [userId]);
      await this.audit.appendTransaction(client, { principal: actor, correlationId, action: 'user.password_reset.issue', entityType: 'user', entityId: userId, after: { resetIssued: true } });
      await client.query('COMMIT');
      return { resetToken, expiresAt: result.rows[0]!.expires_at.toISOString() };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async setStatus(userId: string, actor: AuthPrincipal, status: 'active' | 'suspended', correlationId: string): Promise<void> {
    if (userId === actor.userId && status === 'suspended') throw new ConflictException('No puedes suspender tu propia cuenta.');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const updated = await client.query<{ id: string }>(
        `UPDATE users SET status = $3, permission_version = permission_version + 1, updated_at = now()
          WHERE id = $1 AND organization_id = $2 AND status IN ('active','suspended') RETURNING id`,
        [userId, actor.organizationId, status],
      );
      if (!updated.rowCount) throw new NotFoundException('La cuenta no existe o su estado no permite esta operación.');
      await client.query(
        `UPDATE auth_sessions SET revoked_at = now(), revoke_reason = $2
          WHERE user_id = $1 AND revoked_at IS NULL`, [userId, `user_${status}`],
      );
      await this.audit.appendTransaction(client, { principal: actor, correlationId, action: `user.${status}`, entityType: 'user', entityId: userId, after: { status } });
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async reassignRole(input: { actor: AuthPrincipal; userId: string; roleId: string; branchId: string | null; correlationId: string }): Promise<void> {
    if (input.userId === input.actor.userId) throw new ConflictException('No puedes cambiar tus propios permisos.');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const current = await client.query<{ branch_id: string | null }>(
        `SELECT branch_id FROM user_role_assignments WHERE user_id = $1 AND organization_id = $2
          AND role_id = $3 AND valid_from <= now() AND (valid_until IS NULL OR valid_until > now())
          FOR UPDATE`, [input.userId, input.actor.organizationId, input.roleId],
      );
      if (!current.rowCount) throw new NotFoundException('La asignación vigente no existe.');
      const scopes = new Set<string | null>([input.branchId, ...current.rows.map(row => row.branch_id)]);
      for (const scope of scopes) await assertCanManageAtScope(client, input.actor, scope);
      await assertCanGrantRole(client, input.actor, input.roleId, input.branchId);
      await client.query(
        `UPDATE user_role_assignments SET valid_until = now()
          WHERE user_id = $1 AND organization_id = $2 AND role_id = $3
            AND valid_from <= now() AND (valid_until IS NULL OR valid_until > now())`,
        [input.userId, input.actor.organizationId, input.roleId],
      );
      await client.query(
        `INSERT INTO user_role_assignments (organization_id, user_id, role_id, branch_id, assigned_by)
         VALUES ($1,$2,$3,$4,$5)`,
        [input.actor.organizationId, input.userId, input.roleId, input.branchId, input.actor.userId],
      );
      await client.query('UPDATE users SET permission_version = permission_version + 1, updated_at = now() WHERE id = $1', [input.userId]);
      await client.query("UPDATE auth_sessions SET revoked_at = now(), revoke_reason = 'role_reassigned' WHERE user_id = $1 AND revoked_at IS NULL", [input.userId]);
      await this.audit.appendTransaction(client, { principal: input.actor, branchId: input.branchId, correlationId: input.correlationId, action: 'user.role.reassign', entityType: 'user', entityId: input.userId, after: { roleId: input.roleId, branchId: input.branchId } });
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async activateOrReset(token: string, password: string, expectedType: 'invite' | 'password_reset', correlationId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const found = await client.query<{ user_id: string; organization_id: string; token_type: 'invite' | 'password_reset'; consumed_at: Date | null; expires_at: Date; status: string }>(
        `SELECT t.user_id, u.organization_id, t.token_type, t.consumed_at, t.expires_at, u.status
           FROM account_action_tokens t JOIN users u ON u.id = t.user_id
          WHERE t.token_hash = $1 FOR UPDATE OF t, u`, [hashToken(token)],
      );
      const row = found.rows[0];
      if (!row || row.token_type !== expectedType || row.consumed_at || row.expires_at <= new Date() || (row.token_type === 'invite' && row.status !== 'invited')) {
        throw new ConflictException('El enlace venció o ya fue utilizado. Solicita uno nuevo.');
      }
      const passwordHash = await argon2.hash(password, { type: argon2.argon2id });
      await client.query('UPDATE account_action_tokens SET consumed_at = now() WHERE token_hash = $1', [hashToken(token)]);
      await client.query(
        `UPDATE users SET password_hash = $2, status = 'active', must_change_password = false,
                          failed_login_count = 0, locked_until = NULL,
                          permission_version = permission_version + 1, updated_at = now()
          WHERE id = $1`, [row.user_id, passwordHash],
      );
      await client.query("UPDATE auth_sessions SET revoked_at = now(), revoke_reason = 'credential_changed' WHERE user_id = $1 AND revoked_at IS NULL", [row.user_id]);
      await client.query(
        `INSERT INTO audit_events (organization_id, actor_user_id, correlation_id, action, entity_type, entity_id, after_data)
         VALUES ($1,NULL,$2,$3,'user',$4,$5::jsonb)`,
        [row.organization_id, correlationId, expectedType === 'invite' ? 'user.activated' : 'user.password_reset.complete', row.user_id, JSON.stringify({ status: 'active' })],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }
}

/**
 * Without an email provider, invitations and password resets are delivered by the signed-in administrator
 * (the one-time token is returned in the response). Production keeps this off unless the operator opts in
 * with ALLOW_MANUAL_ACCOUNT_DELIVERY=true; outside production it is always allowed.
 */
export function manualAccountDeliveryAllowed(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.NODE_ENV !== 'production' || env.ALLOW_MANUAL_ACCOUNT_DELIVERY === 'true';
}

function hashToken(token: string): Buffer {
  return createHash('sha256').update(token, 'utf8').digest();
}

function isUniqueViolation(error: unknown): boolean {
  return Boolean(error && typeof error === 'object' && 'code' in error && error.code === '23505');
}

async function assertCanManageAtScope(client: import('pg').PoolClient, actor: AuthPrincipal, branchId: string | null): Promise<void> {
  const result = await client.query(
    `SELECT 1 FROM user_role_assignments ura
      JOIN role_permissions rp ON rp.role_id = ura.role_id AND rp.organization_id = ura.organization_id
     WHERE ura.user_id = $1 AND ura.organization_id = $2 AND rp.permission_code = 'user.manage'
       AND ura.valid_from <= now() AND (ura.valid_until IS NULL OR ura.valid_until > now())
       AND (ura.branch_id IS NULL OR ($3::uuid IS NOT NULL AND ura.branch_id = $3)) LIMIT 1`,
    [actor.userId, actor.organizationId, branchId],
  );
  if (!result.rowCount) throw new ConflictException('No puedes administrar cuentas en una de las sucursales afectadas.');
}

async function assertCanGrantRole(client: import('pg').PoolClient, actor: AuthPrincipal, roleId: string, branchId: string | null): Promise<void> {
  const result = await client.query<{ missing: string | null }>(
    `SELECT rp.permission_code AS missing FROM role_permissions rp
      WHERE rp.role_id = $1 AND rp.organization_id = $2
        AND NOT EXISTS (
          SELECT 1 FROM user_role_assignments ura
            JOIN role_permissions actor_rp ON actor_rp.role_id = ura.role_id AND actor_rp.organization_id = ura.organization_id
           WHERE ura.user_id = $3 AND ura.organization_id = $2
             AND ura.valid_from <= now() AND (ura.valid_until IS NULL OR ura.valid_until > now())
             AND actor_rp.permission_code = rp.permission_code
             AND (ura.branch_id IS NULL OR ($4::uuid IS NOT NULL AND ura.branch_id = $4))
        ) LIMIT 1`,
    [roleId, actor.organizationId, actor.userId, branchId],
  );
  if (result.rowCount) throw new ConflictException('Solo puedes asignar roles con permisos que ya tienes en ese ámbito.');
}
