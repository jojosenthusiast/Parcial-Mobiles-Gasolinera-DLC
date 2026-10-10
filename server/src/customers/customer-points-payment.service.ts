import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'node:crypto';
import { Decimal } from 'decimal.js';
import { Pool } from 'pg';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import { PG_POOL } from '../database/database.module.js';
import type { CustomerIdentity } from './customer-auth.guard.js';
import type { CreateCustomerPointQuoteDto } from './customer-points-payment.dto.js';

@Injectable()
export class CustomerPointsPaymentService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly auth: AuthService,
    private readonly audit: AuditService, private readonly config: ConfigService) {}

  async quote(branchId: string, saleId: string, principal: AuthPrincipal,
    input: CreateCustomerPointQuoteDto, correlationId: string) {
    if (!(await this.auth.capabilities(principal, branchId)).includes('payment.collect')) {
      throw new ForbiddenException('No tienes permiso para solicitar un cobro en esta sucursal.');
    }
    assertUuid(input.commandId); assertUuid(input.cashSessionId); assertUuid(saleId);
    if (!Number.isSafeInteger(input.points) || input.points < 1 || input.points > 2_000_000_000) {
      throw new BadRequestException('Indica una cantidad válida de puntos.');
    }
    const payload = { branchId: branchId.toLowerCase(), saleId: saleId.toLowerCase(),
      cashSessionId: input.cashSessionId.toLowerCase(), points: input.points, actor: principal.userId };
    const requestHash = digest(payload);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
        [`point-quote-command:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
      const previous = await client.query<{ id: string; request_hash: string; requested_by: string; status: string; amount_usd: string; expires_at: Date }>(
        `SELECT id,request_hash,requested_by,status,amount_usd::text,expires_at FROM customer_point_payment_quotes
         WHERE organization_id=$1 AND command_id=$2`, [principal.organizationId, input.commandId]);
      if (previous.rows[0]) {
        const row = previous.rows[0];
        if (row.request_hash !== requestHash || row.requested_by !== principal.userId) throw new ConflictException('El comando ya se usó con otros datos.');
        await client.query('COMMIT');
        return { data: { id: row.id, status: row.status, amountUsd: row.amount_usd,
          expiresAt: row.expires_at, idempotentReplay: true } };
      }
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`sale-collection:${saleId.toLowerCase()}`]);
      await client.query(`UPDATE customer_point_payment_quotes SET status='expired'
        WHERE organization_id=$1 AND sale_id=$2 AND status='pending' AND expires_at<=clock_timestamp()`, [principal.organizationId, saleId]);
      const sale = await client.query<{ customer_id: string; collection_status: string; outstanding_usd: string; reserved_usd: string }>(
        `SELECT l.customer_id,b.collection_status,b.outstanding_usd::text,b.reserved_usd::text
         FROM sales s JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
         JOIN customer_sale_links l ON l.sale_id=s.id AND l.organization_id=s.organization_id AND l.branch_id=s.branch_id
         WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3 FOR UPDATE OF s`,
        [saleId, principal.organizationId, branchId]);
      if (!sale.rows[0]) throw new NotFoundException('La venta no existe o no tiene un Cliente vinculado.');
      if (sale.rows[0].collection_status === 'paid' || sale.rows[0].collection_status === 'on_credit'
        || new Decimal(sale.rows[0].outstanding_usd).minus(sale.rows[0].reserved_usd).lte(0)) {
        throw new ConflictException('La venta no tiene saldo disponible para pagar con puntos.');
      }
      const session = await client.query(`SELECT id FROM cash_sessions WHERE id=$1 AND organization_id=$2 AND branch_id=$3
        AND cashier_id=$4 AND NOT EXISTS(SELECT 1 FROM cash_closures WHERE session_id=cash_sessions.id) FOR UPDATE`,
        [input.cashSessionId, principal.organizationId, branchId, principal.userId]);
      if (!session.rowCount) throw new ConflictException('Abre un turno de caja propio antes de crear la solicitud.');
      const program = await client.query<{ id: string; redemption_usd_per_point: string }>(
        `SELECT id,redemption_usd_per_point::text FROM customer_loyalty_programs
         WHERE organization_id=$1 AND status='active' AND redemption_usd_per_point>0 ORDER BY version DESC LIMIT 1 FOR SHARE`,
        [principal.organizationId]);
      if (!program.rows[0]) throw new ConflictException('El pago con puntos no está habilitado por la política aprobada.');
      const balance = await client.query<{ balance: string }>(
        `SELECT coalesce(sum(points_delta),0)::text AS balance FROM customer_points_ledger
         WHERE organization_id=$1 AND customer_id=$2`, [principal.organizationId, sale.rows[0].customer_id]);
      if (BigInt(input.points) > BigInt(balance.rows[0]?.balance ?? '0')) throw new ConflictException('El saldo actual no alcanza para esa cantidad de puntos.');
      const amount = new Decimal(input.points).mul(program.rows[0].redemption_usd_per_point)
        .toDecimalPlaces(2, Decimal.ROUND_DOWN).toFixed(2);
      if (new Decimal(amount).lte(0)) throw new BadRequestException('Esa cantidad de puntos no alcanza el mínimo de USD 0.01.');
      if (new Decimal(amount).gt(new Decimal(sale.rows[0].outstanding_usd).minus(sale.rows[0].reserved_usd))) {
        throw new ConflictException('El valor de los puntos excede el saldo disponible de la venta.');
      }
      const created = await client.query<{ id: string; expires_at: Date }>(
        `INSERT INTO customer_point_payment_quotes(organization_id,branch_id,sale_id,customer_id,cash_session_id,program_id,
          points,amount_usd,redemption_usd_per_point,expires_at,command_id,request_hash,requested_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,clock_timestamp()+interval '120 seconds',$10,$11,$12)
         RETURNING id,expires_at`,
        [principal.organizationId, branchId, saleId, sale.rows[0].customer_id, input.cashSessionId,
          program.rows[0].id, input.points, amount, program.rows[0].redemption_usd_per_point, input.commandId, requestHash, principal.userId]);
      const quote = created.rows[0]!;
      await this.audit.appendTransaction(client, { principal, branchId, correlationId, action: 'loyalty.payment_quote.created',
        entityType: 'customer_point_payment_quote', entityId: quote.id,
        after: { saleId, customerId: sale.rows[0].customer_id, points: input.points, amountUsd: amount, expiresAt: quote.expires_at } });
      await client.query('COMMIT');
      return { data: { id: quote.id, status: 'pending', points: input.points, amountUsd: amount,
        expiresAt: quote.expires_at, idempotentReplay: false } };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      const code = (error as { code?: string }).code;
      if (code === '23514' || code === '23505') throw new ConflictException('La cotización venció o cambió el saldo de la venta/puntos. Actualiza e inténtalo de nuevo.');
      if (code === '23503') throw new NotFoundException('El recurso no existe en esta organización o sucursal.');
      throw error;
    } finally { client.release(); }
  }

  async pending(identity: CustomerIdentity) {
    const customerId = await this.customerId(identity);
    const result = await this.pool.query(
      `SELECT q.id,q.branch_id AS "branchId",b.name AS "branchName",q.sale_id AS "saleId",s.total_usd::text AS "saleTotalUsd",
        q.points::text AS points,q.amount_usd::text AS "amountUsd",q.expires_at AS "expiresAt",q.created_at AS "createdAt"
       FROM customer_point_payment_quotes q JOIN sales s ON s.id=q.sale_id AND s.organization_id=q.organization_id AND s.branch_id=q.branch_id
       JOIN branches b ON b.id=q.branch_id AND b.organization_id=q.organization_id
       WHERE q.organization_id=$1 AND q.customer_id=$2 AND q.status='pending' AND q.expires_at>clock_timestamp()
       ORDER BY q.created_at,q.id LIMIT 20`, [this.organizationId(), customerId]);
    return { data: result.rows };
  }

  async confirm(identity: CustomerIdentity, quoteId: string, commandId: string) {
    assertUuid(quoteId); assertUuid(commandId);
    const customerId = await this.customerId(identity);
    const organizationId = this.organizationId();
    const requestHash = digest({ quoteId: quoteId.toLowerCase(), customerId, decision: 'confirm' });
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
        [`point-payment-command:${organizationId}:${commandId.toLowerCase()}`]);
      const replay = await client.query<{ id: string; request_hash: string; customer_id: string; quote_id: string; sale_id: string; points: string; amount_usd: string }>(
        `SELECT id,request_hash,customer_id,quote_id,sale_id,points::text,amount_usd::text FROM customer_point_payments
          WHERE organization_id=$1 AND command_id=$2`, [organizationId, commandId]);
      if (replay.rows[0]) {
        const row = replay.rows[0];
        if (row.request_hash !== requestHash || row.customer_id !== customerId || row.quote_id !== quoteId.toLowerCase()) throw new ConflictException('El comando de confirmación ya se usó con otros datos.');
        await client.query('COMMIT');
        return { data: { id: row.id, saleId: row.sale_id, points: row.points, amountUsd: row.amount_usd, status: 'confirmed', idempotentReplay: true } };
      }
      const reference = await client.query<{ sale_id: string }>(
        `SELECT sale_id FROM customer_point_payment_quotes WHERE id=$1 AND organization_id=$2 AND customer_id=$3`,
        [quoteId, organizationId, customerId]);
      if (!reference.rows[0]) throw new NotFoundException('La solicitud no existe en tu cuenta.');
      const saleId = reference.rows[0].sale_id;
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`sale-collection:${saleId}`]);
      const found = await client.query<QuoteRow>(
        `SELECT id,organization_id,branch_id,sale_id,customer_id,cash_session_id,program_id,points::text,
          amount_usd::text,redemption_usd_per_point::text,status,expires_at,decision_command_id
         FROM customer_point_payment_quotes WHERE id=$1 AND organization_id=$2 AND customer_id=$3 FOR UPDATE`,
        [quoteId, organizationId, customerId]);
      const quote = found.rows[0];
      if (!quote) throw new NotFoundException('La solicitud ya no existe.');
      if (quote.status === 'confirmed') {
        if (quote.decision_command_id !== commandId.toLowerCase()) {
          throw new ConflictException('La solicitud ya fue confirmada con un comando distinto.');
        }
        const payment = await client.query<{ id: string }>('SELECT id FROM customer_point_payments WHERE quote_id=$1', [quoteId]);
        if (!payment.rows[0]) throw new ConflictException('La solicitud figura confirmada sin su asiento de puntos.');
        await client.query('COMMIT');
        return { data: { id: payment.rows[0].id, saleId, points: quote.points, amountUsd: quote.amount_usd, status: 'confirmed', idempotentReplay: true } };
      }
      if (quote.status !== 'pending') throw new ConflictException('La solicitud ya fue resuelta.');
      if (new Date(quote.expires_at).getTime() <= Date.now()) {
        await client.query(`UPDATE customer_point_payment_quotes SET status='expired' WHERE id=$1`, [quoteId]);
        await client.query('COMMIT');
        return { data: { id: quoteId, saleId, status: 'expired', idempotentReplay: false } };
      }
      const account = await client.query(`SELECT id FROM customer_accounts WHERE id=$1 AND organization_id=$2 AND status='active' FOR UPDATE`, [customerId, organizationId]);
      if (!account.rowCount) throw new NotFoundException('La cuenta de Cliente no está activa.');
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO customer_point_payments(organization_id,branch_id,sale_id,customer_id,quote_id,program_id,points,
          amount_usd,redemption_usd_per_point,command_id,request_hash)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
        [organizationId, quote.branch_id, saleId, customerId, quoteId, quote.program_id, quote.points,
          quote.amount_usd, quote.redemption_usd_per_point, commandId, requestHash]);
      const paymentId = inserted.rows[0]!.id;
      await client.query(`INSERT INTO customer_points_ledger(organization_id,customer_id,program_id,event_type,points_delta,
          source_type,source_id,command_id,reason)
        VALUES($1,$2,$3,'redeem',-$4::bigint,'sale_point_payment',$5,$6,'Pago de venta confirmado por el Cliente')`,
        [organizationId, customerId, quote.program_id, quote.points, paymentId, commandId]);
      const decisionHash = digest({ quoteId, decision: 'confirm', customerId });
      await client.query(`UPDATE customer_point_payment_quotes SET status='confirmed',confirmed_at=clock_timestamp(),
        decision_command_id=$2,decision_hash=$3,decided_by_customer_id=$4 WHERE id=$1`, [quoteId, commandId, decisionHash, customerId]);
      await client.query('COMMIT');
      return { data: { id: paymentId, saleId, points: quote.points, amountUsd: quote.amount_usd, status: 'confirmed', idempotentReplay: false } };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      const code = (error as { code?: string }).code;
      if (code === '23514' || code === '23505') throw new ConflictException('El saldo o el estado de la venta cambió. Actualiza la solicitud antes de confirmar.');
      if (code === '23503') throw new NotFoundException('El recurso ya no existe.');
      throw error;
    } finally { client.release(); }
  }

  async decline(identity: CustomerIdentity, quoteId: string, commandId: string) {
    assertUuid(quoteId); assertUuid(commandId);
    const customerId = await this.customerId(identity);
    const organizationId = this.organizationId();
    const normalizedQuoteId = quoteId.toLowerCase();
    const normalizedCommandId = commandId.toLowerCase();
    const requestHash = digest({ quoteId: normalizedQuoteId, customerId, decision: 'decline' });
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
        [`point-payment-command:${organizationId}:${normalizedCommandId}`]);
      const found = await client.query<{ id: string; sale_id: string; status: string; expires_at: Date; decision_command_id: string | null; decision_hash: string | null }>(
        `SELECT id,sale_id,status,expires_at,decision_command_id,decision_hash FROM customer_point_payment_quotes
         WHERE id=$1 AND organization_id=$2 AND customer_id=$3 FOR UPDATE`,
        [normalizedQuoteId, organizationId, customerId]);
      const quote = found.rows[0];
      if (!quote) throw new NotFoundException('La solicitud no existe en tu cuenta.');
      if (quote.decision_command_id === normalizedCommandId) {
        if (quote.decision_hash !== requestHash || quote.status !== 'declined') {
          throw new ConflictException('El comando ya se usó para resolver esta solicitud de otra forma.');
        }
        await client.query('COMMIT');
        return { data: { id: quote.id, saleId: quote.sale_id, status: quote.status, idempotentReplay: true } };
      }
      if (quote.status !== 'pending') throw new ConflictException('La solicitud venció o ya fue resuelta.');
      if (await client.query('SELECT 1 FROM customer_point_payment_quotes WHERE organization_id=$1 AND decision_command_id=$2',
        [organizationId, normalizedCommandId]).then(r => r.rowCount)) {
        throw new ConflictException('El comando ya fue usado en otra solicitud.');
      }
      if (new Date(quote.expires_at).getTime() <= Date.now()) throw new ConflictException('La solicitud venció.');
      const updated = await client.query(
        `UPDATE customer_point_payment_quotes SET status='declined',decision_command_id=$4,decision_hash=$5,
          decided_by_customer_id=$3
         WHERE id=$1 AND organization_id=$2 AND customer_id=$3 AND status='pending' AND expires_at>clock_timestamp()
         RETURNING id,sale_id AS "saleId",status`,
        [normalizedQuoteId, organizationId, customerId, normalizedCommandId, requestHash]);
      if (!updated.rows[0]) throw new ConflictException('La solicitud venció o ya fue resuelta.');
      await client.query('COMMIT');
      return { data: { ...updated.rows[0], idempotentReplay: false } };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally { client.release(); }
  }

  private async customerId(identity: CustomerIdentity) {
    const result = await this.pool.query<{ id: string }>(
      `SELECT id FROM customer_accounts WHERE organization_id=$1 AND auth_user_id=$2 AND status='active'`,
      [this.organizationId(), identity.authUserId]);
    if (!result.rows[0]) throw new NotFoundException('Completa tu perfil para activar tu cuenta.');
    return result.rows[0].id;
  }

  private organizationId() {
    const id = this.config.get<string>('CUSTOMER_ORGANIZATION_ID')?.trim();
    if (!id || !isUuid(id)) throw new NotFoundException('El dominio de pagos por puntos no está configurado.');
    return id;
  }
}

interface QuoteRow {
  id: string; organization_id: string; branch_id: string; sale_id: string; customer_id: string;
  cash_session_id: string; program_id: string; points: string; amount_usd: string;
  redemption_usd_per_point: string; status: string; expires_at: Date; decision_command_id: string | null;
}
function digest(value: unknown) { return createHash('sha256').update(JSON.stringify(value)).digest('hex'); }
function isUuid(value: string) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function assertUuid(value: unknown): asserts value is string {
  if (typeof value !== 'string' || !isUuid(value)) throw new BadRequestException('Identificador no válido.');
}
