import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { AuditService } from '../audit/audit.service.js';
import { PG_POOL } from '../database/database.module.js';
import type { CustomerIdentity } from './customer-auth.guard.js';
import type { CustomerProfileDto, LinkCustomerSaleDto } from './customer.dto.js';

@Injectable()
export class CustomerService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly config: ConfigService, private readonly audit: AuditService) {}

  async profile(identity: CustomerIdentity, input: CustomerProfileDto) {
    if (!input.termsAccepted) throw new BadRequestException('Debes aceptar las condiciones vigentes para crear el perfil.');
    const termsVersion = this.config.get<string>('CUSTOMER_TERMS_VERSION')?.trim() || 'qa-draft-v1';
    if (input.termsVersion !== termsVersion) throw new ConflictException('Las condiciones cambiaron. Actualiza la app y vuelve a revisar el texto vigente.');
    const organizationId = this.organizationId();
    const result = await this.pool.query(
      `INSERT INTO customer_accounts (organization_id, auth_user_id, email_normalized, full_name, phone, terms_version, communications_consent)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (organization_id, auth_user_id) DO UPDATE SET
         email_normalized=EXCLUDED.email_normalized, full_name=EXCLUDED.full_name, phone=EXCLUDED.phone,
         terms_version=EXCLUDED.terms_version, terms_accepted_at=now(), communications_consent=EXCLUDED.communications_consent,
         updated_at=now()
       WHERE customer_accounts.status='active'
       RETURNING id, full_name AS "fullName", email_normalized AS email, phone, terms_version AS "termsVersion", communications_consent AS "communicationsConsent", created_at AS "createdAt"`,
      [organizationId, identity.authUserId, identity.email, input.fullName.trim(), input.phone?.trim() || null, termsVersion, input.communicationsConsent],
    );
    if (!result.rows[0]) { await this.rejectBlockedAccount(identity); throw new NotFoundException('La cuenta no está disponible.'); }
    return result.rows[0];
  }

  async me(identity: CustomerIdentity) {
    const row = await this.pool.query(
      `SELECT id, full_name AS "fullName", email_normalized AS email, phone, terms_version AS "termsVersion",
              communications_consent AS "communicationsConsent", created_at AS "createdAt"
         FROM customer_accounts WHERE organization_id=$1 AND auth_user_id=$2 AND status='active'`,
      [this.organizationId(), identity.authUserId],
    );
    if (!row.rows[0]) { await this.rejectBlockedAccount(identity); throw new NotFoundException('Completa tu perfil para activar tu cuenta.'); }
    return row.rows[0];
  }

  async loyalty(identity: CustomerIdentity) {
    const account = await this.accountId(identity);
    const totals = await this.pool.query<{ balance: string; earned_program: boolean; redemption_rate: string | null; available_value: string }>(
      `WITH balance AS (
         SELECT COALESCE(sum(points_delta),0)::numeric AS points
           FROM customer_points_ledger WHERE organization_id=$1 AND customer_id=$2
       ), active_program AS (
         SELECT redemption_usd_per_point AS rate FROM customer_loyalty_programs
          WHERE organization_id=$1 AND status='active' ORDER BY version DESC LIMIT 1
       )
       SELECT balance.points::text AS balance,
              EXISTS(SELECT 1 FROM active_program) AS earned_program,
              COALESCE(active_program.rate,0)::text AS redemption_rate,
              (floor(balance.points * COALESCE(active_program.rate,0) * 100) / 100)::numeric(20,2)::text AS available_value
         FROM balance LEFT JOIN active_program ON true`,
      [this.organizationId(), account.id],
    );
    const row = totals.rows[0];
    const balance = row?.balance ?? '0';
    const earnedProgram = row?.earned_program ?? false;
    const redemptionUsdPerPoint = row?.redemption_rate ?? '0';
    const canRedeem = earnedProgram && Number(redemptionUsdPerPoint) > 0;
    return {
      pointsBalance: balance,
      earnedProgram,
      canRedeem,
      redemptionUsdPerPoint,
      availableValueUsd: row?.available_value ?? '0.00',
      message: earnedProgram
        ? 'Los puntos se acreditan sobre la parte elegible pagada con dinero; la parte cubierta con puntos no genera puntos.'
        : 'El programa de puntos todavía no está activo en esta organización.',
    };
  }

  async points(identity: CustomerIdentity, cursor?: string) {
    const account = await this.accountId(identity);
    const parsed = cursor ? decodeCursor(cursor) : null;
    const rows = await this.pool.query(
      `SELECT id, event_type AS type, points_delta AS "pointsDelta", reason, created_at AS "createdAt"
         FROM customer_points_ledger WHERE organization_id=$1 AND customer_id=$2
           AND ($3::timestamptz IS NULL OR (created_at,id)<($3::timestamptz,$4::uuid))
         ORDER BY created_at DESC,id DESC LIMIT 21`,
      [this.organizationId(), account.id, parsed?.createdAt ?? null, parsed?.id ?? null],
    );
    const hasMore = rows.rows.length > 20;
    const items = rows.rows.slice(0, 20);
    return { items, nextCursor: hasMore ? encodeCursor(items.at(-1) as { createdAt: Date; id: string }) : null };
  }

  async notifications(identity: CustomerIdentity, cursor?: string) {
    const account = await this.accountId(identity);
    const parsed = cursor ? decodeCursor(cursor) : null;
    const [rows, unread] = await Promise.all([
      this.pool.query(
        `SELECT id,event_type AS type,title,body,image_url AS "imageUrl",target_type AS "targetType",target_id AS "targetId",created_at AS "createdAt",read_at AS "readAt"
           FROM customer_notification_inbox WHERE organization_id=$1 AND customer_id=$2
            AND ($3::timestamptz IS NULL OR (created_at,id)<($3::timestamptz,$4::uuid))
          ORDER BY created_at DESC,id DESC LIMIT 21`,
        [this.organizationId(), account.id, parsed?.createdAt ?? null, parsed?.id ?? null],
      ),
      this.pool.query<{ unreadCount: string }>(`SELECT count(*)::text AS "unreadCount" FROM customer_notification_inbox WHERE organization_id=$1 AND customer_id=$2 AND read_at IS NULL`, [this.organizationId(), account.id]),
    ]);
    const hasMore = rows.rows.length > 20;
    const items = rows.rows.slice(0, 20);
    return { items, unreadCount: unread.rows[0]?.unreadCount ?? '0', nextCursor: hasMore ? encodeCursor(items.at(-1) as { createdAt: Date; id: string }) : null };
  }

  async markNotificationRead(identity: CustomerIdentity, notificationId: string) {
    const account = await this.accountId(identity);
    const result = await this.pool.query(
      `UPDATE customer_notification_inbox SET read_at=COALESCE(read_at,now()) WHERE id=$1 AND organization_id=$2 AND customer_id=$3 RETURNING id,read_at AS "readAt"`,
      [notificationId, this.organizationId(), account.id],
    );
    if (!result.rows[0]) throw new NotFoundException('La notificación no existe.');
    return result.rows[0];
  }

  async qr(identity: CustomerIdentity) {
    const account = await this.accountId(identity);
    const result = await this.pool.query<{ public_code: string }>(`SELECT public_code FROM customer_accounts WHERE id=$1 AND organization_id=$2`, [account.id, this.organizationId()]);
    return { code: result.rows[0]!.public_code, purpose: 'identity_only', message: 'Este código identifica tu cuenta. No autoriza pagos ni canjea recompensas.' };
  }

  async rewards() {
    const result = await this.pool.query(
      `SELECT id, code, title, description, image_url AS "imageUrl", points_cost AS "pointsCost", stock_quantity AS "stockQuantity", starts_at AS "startsAt", ends_at AS "endsAt"
         FROM customer_rewards WHERE organization_id=$1 AND status='published' AND starts_at<=now() AND (ends_at IS NULL OR ends_at>now())
         ORDER BY starts_at,id LIMIT 100`, [this.organizationId()],
    );
    return result.rows;
  }

  async campaigns() {
    const result = await this.pool.query(
      `SELECT id, title, body, image_url AS "imageUrl", image_alt AS "imageAlt", branch_id AS "branchId", starts_at AS "startsAt", ends_at AS "endsAt"
         FROM customer_campaigns WHERE organization_id=$1 AND status='published' AND starts_at<=now() AND ends_at>now()
          AND (branch_id IS NULL OR EXISTS (SELECT 1 FROM branches b WHERE b.id=customer_campaigns.branch_id AND b.organization_id=customer_campaigns.organization_id AND b.status='active'))
         ORDER BY priority DESC,starts_at,id LIMIT 100`, [this.organizationId()],
    );
    return result.rows;
  }

  async branches() {
    const result = await this.pool.query(
      `SELECT id, code, name, zone, timezone, country_code AS "countryCode" FROM branches WHERE organization_id=$1 AND status='active' ORDER BY name,id`, [this.organizationId()],
    );
    return result.rows;
  }

  async services() {
    const result = await this.pool.query(
      `SELECT b.id AS "branchId", b.name AS "branchName", p.id, p.sku, o.description, o.price_usd::text AS "priceUsd"
         FROM branches b JOIN pos_products p ON p.organization_id=b.organization_id AND p.branch_id=b.id AND p.kind='service'
         JOIN LATERAL (SELECT description,price_usd,active FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1) o ON o.active
        WHERE b.organization_id=$1 AND b.status='active' ORDER BY b.name,o.description LIMIT 200`, [this.organizationId()],
    );
    return result.rows;
  }

  async linkSale(branchId: string, saleId: string, principal: AuthPrincipal, input: LinkCustomerSaleDto, correlationId: string) {
    if (!isUuid(input.commandId) || !isUuid(input.customerCode)) throw new ConflictException('El comando o el código de Cliente no es válido.');
    const requestHash = createHash('sha256').update(JSON.stringify({ branchId: branchId.toLowerCase(), saleId: saleId.toLowerCase(), customerCode: input.customerCode.toLowerCase() })).digest('hex');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`customer-sale-command:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`customer-sale:${principal.organizationId}:${saleId.toLowerCase()}`]);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`sale-collection:${saleId.toLowerCase()}`]);
      const old = await client.query<{ id: string; request_hash: string; linked_by: string }>(
        'SELECT id,request_hash,linked_by FROM customer_sale_links WHERE organization_id=$1 AND command_id=$2', [principal.organizationId, input.commandId]);
      if (old.rows[0]) {
        if (old.rows[0].request_hash !== requestHash || old.rows[0].linked_by !== principal.userId) throw new ConflictException('El comando ya se usó para otro vínculo.');
        await client.query('COMMIT');
        return { id: old.rows[0].id, idempotentReplay: true };
      }
      const sale = await client.query<{ id: string; status: string }>(
        `SELECT s.id,b.collection_status AS status FROM sales s JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
          WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3 FOR UPDATE OF s`, [saleId, principal.organizationId, branchId]);
      if (!sale.rows[0]) throw new NotFoundException('La venta no existe en esta sucursal.');
      if (sale.rows[0].status !== 'pending_collection') throw new ConflictException('El cliente debe vincularse antes de cobrar la venta.');
      const customer = await client.query<{ id: string }>(
        `SELECT id FROM customer_accounts WHERE organization_id=$1 AND public_code=$2 AND status='active' FOR SHARE`, [principal.organizationId, input.customerCode]);
      if (!customer.rows[0]) throw new NotFoundException('No se encontró un código de Cliente activo.');
      const existingLink = await client.query<{ id: string; customer_id: string }>(
        'SELECT id,customer_id FROM customer_sale_links WHERE organization_id=$1 AND sale_id=$2', [principal.organizationId, saleId]);
      if (existingLink.rows[0]) {
        if (existingLink.rows[0].customer_id !== customer.rows[0].id) throw new ConflictException('La venta ya tiene otra cuenta de Cliente vinculada.');
        await client.query('COMMIT');
        return { id: existingLink.rows[0].id, idempotentReplay: true };
      }
      const linked = await client.query<{ id: string }>(
        `INSERT INTO customer_sale_links(organization_id,branch_id,sale_id,customer_id,command_id,request_hash,linked_by)
         VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`, [principal.organizationId, branchId, saleId, customer.rows[0].id, input.commandId, requestHash, principal.userId]);
      const id = linked.rows[0]!.id;
      await this.audit.appendTransaction(client, { principal, branchId, correlationId, action: 'customer.sale.linked', entityType: 'customer_sale_link', entityId: id, after: { saleId, customerId: customer.rows[0].id } });
      await client.query('COMMIT');
      return { id, idempotentReplay: false };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if ((error as { code?: string }).code === '23505') throw new ConflictException('La venta ya tiene un Cliente vinculado o el comando está duplicado.');
      if ((error as { code?: string }).code === '23514') throw new ConflictException('La venta ya se cobró o la cuenta de Cliente no está activa.');
      if (error instanceof NotFoundException || error instanceof ConflictException) throw error;
      throw error;
    } finally { client.release(); }
  }

  private async accountId(identity: CustomerIdentity): Promise<{ id: string }> {
    const result = await this.pool.query<{ id: string }>(`SELECT id FROM customer_accounts WHERE organization_id=$1 AND auth_user_id=$2 AND status='active'`, [this.organizationId(), identity.authUserId]);
    if (!result.rows[0]) throw new NotFoundException('Completa tu perfil para activar tu cuenta.');
    return result.rows[0];
  }

  private async rejectBlockedAccount(identity: CustomerIdentity): Promise<void> {
    const result = await this.pool.query<{ status: string }>(
      `SELECT status FROM customer_accounts WHERE organization_id=$1 AND auth_user_id=$2`, [this.organizationId(), identity.authUserId],
    );
    if (result.rows[0]?.status === 'blocked') throw new ForbiddenException('La cuenta de Cliente está bloqueada. Contacta a soporte.');
  }

  private organizationId(): string {
    const value = this.config.get<string>('CUSTOMER_ORGANIZATION_ID')?.trim();
    if (!value || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
      throw new ServiceUnavailableException('El dominio de Clientes no está configurado para una organización.');
    }
    return value;
  }
}

function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }

function encodeCursor(row: { createdAt: Date; id: string }): string { return Buffer.from(JSON.stringify([new Date(row.createdAt).toISOString(), row.id])).toString('base64url'); }
function decodeCursor(value: string): { createdAt: string; id: string } {
  try {
    const parsed: unknown = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
    if (!Array.isArray(parsed) || parsed.length !== 2 || typeof parsed[0] !== 'string' || typeof parsed[1] !== 'string' || !Number.isFinite(Date.parse(parsed[0])) || !/^[0-9a-f-]{36}$/i.test(parsed[1])) throw new Error();
    return { createdAt: new Date(parsed[0]).toISOString(), id: parsed[1] };
  } catch { throw new NotFoundException('El cursor de historial no es válido.'); }
}
