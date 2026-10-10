import { createHash, createHmac, randomBytes } from 'node:crypto';
import { ForbiddenException, HttpException, HttpStatus, Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, type PoolClient } from 'pg';
import * as argon2 from 'argon2';
import { PG_POOL } from '../database/database.module.js';
import type { AuthPrincipal, AuthTokens } from './auth.types.js';
import { AuditService } from '../audit/audit.service.js';

interface UserRow {
  id: string;
  organization_id: string;
  employee_id: string | null;
  display_name: string;
  password_hash: string;
  status: string;
  permission_version: number;
  failed_login_count: number;
  locked_until: Date | null;
}

interface TokenRow extends UserRow {
  session_id: string;
  token_type: string;
  expires_at: Date;
  consumed_at: Date | null;
  revoked_at: Date | null;
  session_expires_at: Date;
}

const ACCESS_MS = 15 * 60 * 1000;
const SESSION_MS = 14 * 24 * 60 * 60 * 1000;
const MAX_FAILED = 5;

@Injectable()
export class AuthService {
  private readonly dummyHash: Promise<string>;

  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly config: ConfigService,
    private readonly audit: AuditService,
  ) {
    this.dummyHash = argon2.hash(randomBytes(32), { type: argon2.argon2id });
  }

  async login(email: string, password: string, deviceLabel: string | undefined, clientIp: string | undefined, correlationId: string): Promise<AuthTokens> {
    const normalizedEmail = email.trim().normalize('NFKC').toLowerCase();
    await this.enforceLoginRateLimit(normalizedEmail, clientIp);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query<UserRow>(
        `SELECT id, organization_id, employee_id, display_name, password_hash, status,
                permission_version, failed_login_count, locked_until
           FROM users WHERE email_normalized = $1 FOR UPDATE`, [normalizedEmail],
      );
      const user = result.rows[0];
      const candidateHash = user?.password_hash ?? await this.dummyHash;
      const passwordMatches = await argon2.verify(candidateHash, password).catch(() => false);
      const available = user?.status === 'active' && (!user.locked_until || user.locked_until <= new Date());
      if (!user || !passwordMatches || !available) {
        if (user && user.status === 'active') {
          const failures = user.failed_login_count + 1;
          const lockSeconds = failures >= MAX_FAILED ? Math.min(900, 60 * 2 ** Math.min(failures - MAX_FAILED, 4)) : null;
          await client.query(
            `UPDATE users SET failed_login_count = $2,
               locked_until = CASE WHEN $3::int IS NULL THEN locked_until ELSE now() + ($3::text || ' seconds')::interval END,
               updated_at = now() WHERE id = $1`, [user.id, failures, lockSeconds],
          );
        }
        await client.query('COMMIT');
        throw new UnauthorizedException('Credenciales inválidas o cuenta no disponible.');
      }
      if (user.employee_id && !(await this.hasActiveWorkShift(client, user.organization_id, user.employee_id))) {
        throw new ForbiddenException('No tienes un turno laboral activo en este momento.');
      }
      await client.query('UPDATE users SET failed_login_count = 0, locked_until = NULL, last_login_at = now(), updated_at = now() WHERE id = $1', [user.id]);
      const tokens = await this.createSession(client, user, deviceLabel, correlationId);
      await client.query('COMMIT');
      return tokens;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async refresh(refreshToken: string, correlationId: string): Promise<AuthTokens> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const tokenHash = hashToken(refreshToken);
      const result = await client.query<TokenRow>(
        `SELECT t.token_type, t.expires_at, t.consumed_at,
                s.id AS session_id, s.expires_at AS session_expires_at, s.revoked_at,
                u.id, u.organization_id, u.display_name, u.password_hash, u.status,
                u.permission_version, u.failed_login_count, u.locked_until
           FROM auth_tokens t
           JOIN auth_sessions s ON s.id = t.session_id
           JOIN users u ON u.id = s.user_id AND u.organization_id = s.organization_id
          WHERE t.token_hash = $1
            AND (u.employee_id IS NULL OR EXISTS (
              SELECT 1 FROM employees e JOIN employee_work_shifts ws ON ws.employee_id=e.id
               WHERE e.id=u.employee_id AND e.organization_id=u.organization_id AND e.status='active'
                 AND ws.organization_id=u.organization_id AND ws.branch_id=e.branch_id AND ws.status='scheduled'
                 AND ws.starts_at<=clock_timestamp() AND ws.ends_at>clock_timestamp()
            ))
          FOR UPDATE OF t, s, u`, [tokenHash],
      );
      const row = result.rows[0];
      if (row?.consumed_at && row.token_type === 'refresh') {
        await client.query("UPDATE auth_sessions SET revoked_at = now(), revoke_reason = 'refresh_reuse' WHERE id = $1 AND revoked_at IS NULL", [row.session_id]);
        await client.query('COMMIT');
        throw new UnauthorizedException('La sesión venció. Inicia sesión nuevamente.');
      }
      if (!row || row.token_type !== 'refresh' || row.status !== 'active' || row.revoked_at || row.expires_at <= new Date() || row.session_expires_at <= new Date()) {
        throw new UnauthorizedException('La sesión venció. Inicia sesión nuevamente.');
      }
      await client.query('UPDATE auth_tokens SET consumed_at = now() WHERE token_hash = $1 AND consumed_at IS NULL', [tokenHash]);
      const tokens = await this.issueTokens(client, row.session_id, row);
      await client.query('UPDATE auth_sessions SET last_seen_at = now(), permission_version = $2 WHERE id = $1', [row.session_id, row.permission_version]);
      await this.audit.appendTransaction(client, { principal: { userId: row.id, organizationId: row.organization_id, sessionId: row.session_id, permissionVersion: row.permission_version }, correlationId, action: 'auth.refresh', entityType: 'session', entityId: row.session_id, after: { rotated: true } });
      await client.query('COMMIT');
      return tokens;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  private async hasActiveWorkShift(client: PoolClient, organizationId: string, employeeId: string): Promise<boolean> {
    const result = await client.query<{ active: boolean }>(
      `SELECT EXISTS (
         SELECT 1 FROM employees e JOIN employee_work_shifts ws ON ws.employee_id = e.id
          WHERE e.id = $2 AND e.organization_id = $1 AND e.status = 'active'
            AND ws.organization_id = e.organization_id AND ws.branch_id = e.branch_id
            AND ws.status = 'scheduled' AND ws.starts_at <= clock_timestamp()
            AND ws.ends_at > clock_timestamp()
       ) AS active`, [organizationId, employeeId],
    );
    return result.rows[0]?.active === true;
  }

  async authenticate(accessToken: string): Promise<AuthPrincipal | null> {
    const result = await this.pool.query<{
      user_id: string; organization_id: string; session_id: string; permission_version: number;
    }>(
      `SELECT u.id AS user_id, u.organization_id, s.id AS session_id, u.permission_version
         FROM auth_tokens t JOIN auth_sessions s ON s.id = t.session_id
         JOIN users u ON u.id = s.user_id AND u.organization_id = s.organization_id
        WHERE t.token_hash = $1 AND t.token_type = 'access' AND t.consumed_at IS NULL
          AND t.expires_at > now() AND s.expires_at > now() AND s.revoked_at IS NULL
          AND u.status = 'active' AND u.permission_version = s.permission_version
          AND (u.employee_id IS NULL OR EXISTS (
            SELECT 1 FROM employees e JOIN employee_work_shifts ws ON ws.employee_id=e.id
             WHERE e.id=u.employee_id AND e.organization_id=u.organization_id AND e.status='active'
               AND ws.organization_id=u.organization_id AND ws.branch_id=e.branch_id AND ws.status='scheduled'
               AND ws.starts_at<=clock_timestamp() AND ws.ends_at>clock_timestamp()
          ))`,
      [hashToken(accessToken)],
    );
    const row = result.rows[0];
    return row ? { userId: row.user_id, organizationId: row.organization_id, sessionId: row.session_id, permissionVersion: row.permission_version } : null;
  }

  async logout(principal: AuthPrincipal, correlationId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `UPDATE auth_sessions SET revoked_at = now(), revoke_reason = 'user_logout'
          WHERE id = $1 AND user_id = $2 AND organization_id = $3 AND revoked_at IS NULL`,
        [principal.sessionId, principal.userId, principal.organizationId],
      );
      await this.audit.appendTransaction(client, { principal, correlationId, action: 'auth.logout', entityType: 'session', entityId: principal.sessionId, after: { revoked: true } });
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async me(principal: AuthPrincipal): Promise<Record<string, unknown>> {
    const result = await this.pool.query(
      `SELECT u.id, u.organization_id AS "organizationId", u.display_name AS "displayName", u.email_normalized AS email,
              COALESCE(jsonb_agg(DISTINCT jsonb_build_object('code', r.code, 'name', r.name, 'branchId', ura.branch_id))
                FILTER (WHERE r.id IS NOT NULL), '[]'::jsonb) AS roles
         FROM users u LEFT JOIN user_role_assignments ura ON ura.user_id = u.id
          AND ura.organization_id = u.organization_id AND ura.valid_from <= now()
          AND (ura.valid_until IS NULL OR ura.valid_until > now())
         LEFT JOIN roles r ON r.id = ura.role_id AND r.organization_id = ura.organization_id
        WHERE u.id = $1 AND u.organization_id = $2 GROUP BY u.id`,
      [principal.userId, principal.organizationId],
    );
    return result.rows[0] ?? {};
  }

  async capabilities(principal: AuthPrincipal, branchId?: string): Promise<string[]> {
    const result = await this.pool.query<{ permission_code: string }>(
      `SELECT DISTINCT rp.permission_code
         FROM user_role_assignments ura
         JOIN role_permissions rp ON rp.role_id = ura.role_id AND rp.organization_id = ura.organization_id
        WHERE ura.user_id = $1 AND ura.organization_id = $2
          AND ura.valid_from <= now() AND (ura.valid_until IS NULL OR ura.valid_until > now())
          AND (ura.branch_id IS NULL OR ura.branch_id = $3)`,
      [principal.userId, principal.organizationId, branchId ?? null],
    );
    return result.rows.map(row => row.permission_code);
  }

  private async createSession(client: PoolClient, user: UserRow, deviceLabel: string | undefined, correlationId: string): Promise<AuthTokens> {
    const session = await client.query<{ id: string }>(
      `INSERT INTO auth_sessions (organization_id, user_id, permission_version, device_label, expires_at)
       VALUES ($1, $2, $3, $4, now() + ($5::text || ' milliseconds')::interval) RETURNING id`,
      [user.organization_id, user.id, user.permission_version, deviceLabel?.trim().slice(0, 120) ?? null, SESSION_MS],
    );
    const tokens = await this.issueTokens(client, session.rows[0]!.id, user);
    await this.audit.appendTransaction(client, {
      principal: { userId: user.id, organizationId: user.organization_id, sessionId: session.rows[0]!.id, permissionVersion: user.permission_version },
      correlationId, action: 'auth.login', entityType: 'session', entityId: session.rows[0]!.id, after: { deviceLabel: deviceLabel?.trim().slice(0, 120) ?? null },
    });
    return tokens;
  }

  private async enforceLoginRateLimit(email: string, clientIp: string | undefined): Promise<void> {
    const secret = this.config.getOrThrow<string>('AUTH_RATE_LIMIT_KEY');
    const keys = [
      { value: createHmac('sha256', secret).update(`email:${email}`).digest(), limit: 10 },
      { value: createHmac('sha256', secret).update(`ip:${clientIp}`).digest(), limit: 60 },
    ].sort((a, b) => Buffer.compare(a.value, b.value));
    for (const key of keys) {
      const result = await this.pool.query<{ attempt_count: number }>(
        `INSERT INTO auth_login_rate_limits (fingerprint_hash, window_started_at, attempt_count)
         VALUES ($1, now(), 1)
         ON CONFLICT (fingerprint_hash) DO UPDATE SET
           attempt_count = CASE
             WHEN auth_login_rate_limits.window_started_at <= now() - interval '15 minutes' THEN 1
             ELSE auth_login_rate_limits.attempt_count + 1 END,
           window_started_at = CASE
             WHEN auth_login_rate_limits.window_started_at <= now() - interval '15 minutes' THEN now()
             ELSE auth_login_rate_limits.window_started_at END,
           updated_at = now()
         RETURNING attempt_count`, [key.value],
      );
      if (result.rows[0]!.attempt_count > key.limit) {
        throw new HttpException('Demasiados intentos. Espera antes de volver a intentar.', HttpStatus.TOO_MANY_REQUESTS);
      }
    }
  }

  private async issueTokens(client: PoolClient, sessionId: string, user: UserRow): Promise<AuthTokens> {
    const accessToken = randomBytes(32).toString('base64url');
    const refreshToken = randomBytes(48).toString('base64url');
    const accessExpiresAt = new Date(Date.now() + ACCESS_MS).toISOString();
    await client.query(
      `INSERT INTO auth_tokens (token_hash, session_id, token_type, expires_at)
       VALUES ($1, $3, 'access', $4), ($2, $3, 'refresh', now() + interval '14 days')`,
      [hashToken(accessToken), hashToken(refreshToken), sessionId, accessExpiresAt],
    );
    await client.query('UPDATE auth_sessions SET permission_version = $2 WHERE id = $1', [sessionId, user.permission_version]);
    return { accessToken, refreshToken, accessExpiresAt, sessionId };
  }
}

function hashToken(token: string): Buffer {
  return createHash('sha256').update(token, 'utf8').digest();
}
