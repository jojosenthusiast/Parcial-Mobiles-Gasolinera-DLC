import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { createHash } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';

interface AllocationAdvanceRow {
 id:string;authorization_id?:string;authorizationId?:string;amount_usd?:string;amountUsd?:string;tender_kind?:'captured'|'authorization_hold';tenderKind?:'captured'|'authorization_hold';
 current_outcome?:string;currentOutcome?:string;outcome?:string;allocated_usd?:string;allocatedUsd?:string;disposition_selected?:boolean;dispositionSelected?:boolean;
}
interface AllocationSaleRow {
 id:string;authorization_id?:string;authorizationId?:string;total_usd?:string;totalUsd?:string;status:string;
 active_payment_attempts_usd?:string;activePaymentAttemptsUsd?:string;captured_allocations_usd?:string;capturedAllocationsUsd?:string;
}
interface PaymentEventRow { id:string;outcome:string;sale_id?:string;saleId?:string;amount_usd?:string;amountUsd?:string;method:string;mode:string }
interface PrepaymentDispositionRow {
 id:string;tender_kind:'captured'|'authorization_hold';method:string;mode:string;
 amount_usd?:string;amountUsd?:string;current_outcome?:string;currentOutcome?:string;outcome?:string;allocated_usd?:string;allocatedUsd?:string;
}
import type { AllocatePrepaymentDto, CollectPrepaymentDto, ConfirmReleaseDto, RequestReleaseDto, ResolvePrepaymentDto } from './prepayments.dto.js';

@Injectable()
export class PrepaymentsService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly auth: AuthService, private readonly audit: AuditService) {}

  private async access(branch: string, principal: AuthPrincipal, permission: string) {
    if (!isUuid(branch) || !isUuid(principal.organizationId) || !isUuid(principal.userId)) throw new BadRequestException('Ámbito no válido.');
    if (!(await this.auth.capabilities(principal, branch)).includes(permission)) throw new ForbiddenException('No tienes permiso para esta operación en la sucursal.');
    if (!(await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2', [branch, principal.organizationId])).rowCount) {
      throw new NotFoundException('La sucursal no existe.');
    }
  }

  async list(branch: string, principal: AuthPrincipal) {
    await this.access(branch, principal, 'payment.read');
    const result = await this.pool.query(`
      SELECT a.id,a.authorization_id AS "authorizationId",a.method,a.mode,a.tender_kind AS "tenderKind",
        prepayment_current_outcome(a.id) AS outcome,a.amount_usd::text AS "amountUsd",
        coalesce(alloc.allocated_usd,0)::text AS "allocatedUsd",
        greatest(a.amount_usd-coalesce(alloc.allocated_usd,0),0)::text AS "remainingUsd",
        CASE WHEN q.id IS NULL AND disposition.disposition IS NULL AND a.tender_kind='captured' AND prepayment_current_outcome(a.id)='confirmed'
          THEN greatest(a.amount_usd-coalesce(alloc.allocated_usd,0),0) ELSE 0 END::text AS "refundableUsd",
        a.evidence_reference AS "evidenceReference",a.created_by AS "createdBy",a.created_at AS "createdAt",
        disposition.disposition,
        CASE WHEN disposition.disposition='release' THEN
          CASE WHEN EXISTS(SELECT 1 FROM prepayment_events released
            WHERE released.advance_id=a.id AND released.event_type='released' AND released.disposition='release')
          THEN 'released' ELSE 'pending' END
        ELSE NULL END AS "releaseStatus",
        q.id AS "approvalId",q.requested_by AS "requestedBy",q.payload->>'amountUsd' AS "requestAmountUsd",
        q.payload->>'reason' AS reason,q.status AS "requestStatus",q.decided_by AS "decidedBy",
        q.decided_at AS "decidedAt",q.reason AS "decisionReason",r.id AS "refundId",r.created_at AS "refundedAt"
      FROM prepayment_advances a
      LEFT JOIN LATERAL (
        SELECT sum(x.amount_usd) AS allocated_usd FROM prepayment_allocations x
        WHERE x.advance_id=a.id AND x.organization_id=a.organization_id AND x.branch_id=a.branch_id
      ) alloc ON true
      LEFT JOIN LATERAL (
        SELECT e.disposition FROM prepayment_events e WHERE e.advance_id=a.id AND e.event_type='refundPending'
        ORDER BY e.created_at DESC,e.id DESC LIMIT 1
      ) disposition ON true
      LEFT JOIN LATERAL (
        SELECT req.* FROM approval_requests req WHERE req.organization_id=a.organization_id AND req.branch_id=a.branch_id
          AND req.action='sale.refund.approve' AND req.entity_type='payment_refund' AND req.entity_id=a.id::text
        ORDER BY req.created_at DESC,req.id DESC LIMIT 1
      ) q ON true
      LEFT JOIN payment_refunds r ON r.approval_id=q.id AND r.advance_id=a.id
        AND r.organization_id=a.organization_id AND r.branch_id=a.branch_id
      WHERE a.organization_id=$1 AND a.branch_id=$2
      ORDER BY a.created_at DESC,a.id DESC LIMIT 100`, [principal.organizationId, branch]);
    return { data: result.rows };
  }

  private async transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      const code = (error as { code?: string }).code;
      if (code === '23514' || code === '23505') throw new ConflictException('Revisa saldo, evidencia, propietario, estado de caja o repetición del comando.');
      if (code === '23503') throw new NotFoundException('El recurso no existe en esta sucursal.');
      if (code === '22003') throw new BadRequestException('El importe excede el límite admitido.');
      throw error;
    } finally { client.release(); }
  }

  private hash(branch: string, principal: AuthPrincipal, kind: string, body: object) {
    return createHash('sha256').update(JSON.stringify({ v: 1, branch: branch.toLowerCase(), actor: principal.userId, kind, ...body })).digest('hex');
  }

  private async replay(client: PoolClient, table: 'prepayment_advances' | 'prepayment_allocations' | 'prepayment_events', branch: string, principal: AuthPrincipal, commandId: string, hash: string) {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`financial-command:${principal.organizationId}:${commandId.toLowerCase()}`]);
    const result = await client.query<{ id: string; request_hash: string; created_by: string; branch_id: string }>(
      `SELECT id,request_hash,created_by,branch_id FROM ${table} WHERE organization_id=$1 AND command_id=$2`, [principal.organizationId, commandId]);
    const row = result.rows[0];
    if (row && (row.request_hash !== hash || row.created_by !== principal.userId || row.branch_id !== branch.toLowerCase())) throw new ConflictException('El comando ya se usó con otros datos.');
    return row?.id;
  }

  private async auditWrite(client: PoolClient, principal: AuthPrincipal, branch: string, correlation: string, action: string, id: string) {
    await this.audit.appendTransaction(client, { principal, branchId: branch, correlationId: correlation, action, entityType: 'prepayment_advance', entityId: id, after: { id } });
  }

  async collect(branch: string, authorizationId: string, principal: AuthPrincipal, input: CollectPrepaymentDto, correlation: string) {
    await this.access(branch, principal, 'payment.collect');
    uuid(authorizationId); uuid(input.commandId); uuid(input.cashSessionId);
    const amount = money(input.amountUsd);
    const currency = input.currency ?? 'USD';
    if (input.mode !== 'manual' || !['cash', 'card'].includes(input.method) || !['captured', 'authorization_hold'].includes(input.tenderKind) || !['confirmed', 'declined', 'unknown'].includes(input.outcome)) throw new BadRequestException('Método, modo, tipo de tender o resultado no válido.');
    if (input.tenderKind === 'authorization_hold' && input.method !== 'card') throw new BadRequestException('Solo una tarjeta manual puede registrar una autorización retenida.');
    const evidence = text(input.evidenceReference, 200, false);
    if (input.method === 'card' && input.outcome !== 'unknown' && !evidence) throw new BadRequestException('Registra la referencia documental del terminal.');
    if (input.tenderKind === 'authorization_hold' && input.outcome !== 'unknown' && !evidence) throw new BadRequestException('Una retención conocida requiere referencia documental.');
    const hash = this.hash(branch, principal, 'payment.collect', { authorizationId: authorizationId.toLowerCase(), session: input.cashSessionId.toLowerCase(), amount, currency, method: input.method, mode: input.mode, tenderKind: input.tenderKind, outcome: input.outcome, evidence });
    return this.transaction(async client => {
      const existingId = await this.replay(client, 'prepayment_advances', branch, principal, input.commandId, hash);
      if (existingId) return { data: { id: existingId, idempotentReplay: true } };
      const authorization = await client.query('SELECT id FROM dispense_authorizations WHERE id=$1 AND organization_id=$2 AND branch_id=$3', [authorizationId, principal.organizationId, branch]);
      if (!authorization.rowCount) throw new NotFoundException('La autorización de despacho no existe en esta sucursal.');
      const session = await client.query(`SELECT s.id FROM cash_sessions s WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3 AND s.cashier_id=$4 AND NOT EXISTS(SELECT 1 FROM cash_closures c WHERE c.session_id=s.id)`, [input.cashSessionId, principal.organizationId, branch, principal.userId]);
      if (!session.rowCount) throw new ConflictException('La sesión de caja debe estar abierta y pertenecer al operador.');
      const inserted = await client.query<{ id: string }>(`INSERT INTO prepayment_advances(organization_id,branch_id,authorization_id,method,mode,tender_kind,outcome,amount_usd,currency,cash_session_id,evidence_reference,command_id,request_hash,created_by,correlation_id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING id`,
      [principal.organizationId, branch, authorizationId, input.method, input.mode, input.tenderKind, input.outcome, amount, currency, input.cashSessionId, evidence, input.commandId, hash, principal.userId, correlation]);
      const id = inserted.rows[0]!.id;
      if (input.outcome === 'confirmed') {
        await client.query(`INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,amount_usd,command_id,request_hash,created_by,correlation_id)
          VALUES($1,$2,$3,'received',$4,$5,$6,$7,$8)`, [principal.organizationId, branch, id, amount, input.commandId, hash, principal.userId, correlation]);
      }
      await this.auditWrite(client, principal, branch, correlation, 'payment.prepayment.recorded', id);
      return { data: { id, idempotentReplay: false } };
    });
  }

  async allocate(branch: string, advanceId: string, principal: AuthPrincipal, input: AllocatePrepaymentDto, correlation: string) {
    await this.access(branch, principal, 'payment.collect');
    uuid(advanceId); uuid(input.saleId); uuid(input.commandId);
    if (input.paymentEventId !== undefined) uuid(input.paymentEventId);
    const amount = money(input.amountUsd);
    const hash = this.hash(branch, principal, 'payment.allocate', {
      advanceId: advanceId.toLowerCase(), saleId: input.saleId.toLowerCase(), amount,
      paymentEventId: input.paymentEventId?.toLowerCase() ?? null,
    });
    return this.transaction(async client => {
      const advanceResult = await client.query<AllocationAdvanceRow>(`SELECT id,authorization_id,amount_usd::text AS amount_usd,tender_kind,
          prepayment_current_outcome(id) AS current_outcome,
          coalesce((SELECT sum(al.amount_usd) FROM prepayment_allocations al WHERE al.advance_id=prepayment_advances.id),0)::text AS allocated_usd,
          EXISTS(SELECT 1 FROM prepayment_events e WHERE e.advance_id=prepayment_advances.id AND e.event_type='refundPending') AS disposition_selected
        FROM prepayment_advances WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE`,
      [advanceId, principal.organizationId, branch]);
      const advance = advanceResult.rows[0];
      if (!advance) throw new NotFoundException('El anticipo no existe en esta sucursal.');
      const existingId = await this.replay(client, 'prepayment_allocations', branch, principal, input.commandId, hash);
      const amountUsd = advance.amount_usd ?? advance.amountUsd ?? '0';
      const tenderKind = advance.tender_kind ?? advance.tenderKind;
      const allocatedCents = cents(advance.allocated_usd ?? advance.allocatedUsd ?? '0');
      const remainingUsd = formatCents(cents(amountUsd) - allocatedCents - (existingId ? 0n : cents(amount)));
      const resultData = (id: string, idempotentReplay: boolean) => ({
        id, advanceId, saleId: input.saleId, amountUsd: amount, remainingUsd,
        remainderStatus: cents(remainingUsd) > 0n ? 'refundPending' : null, idempotentReplay,
      });
      if (existingId) return { data: resultData(existingId, true) };
      if ((advance.disposition_selected ?? advance.dispositionSelected ?? false) || (advance.current_outcome ?? advance.currentOutcome ?? advance.outcome) !== 'confirmed') {
        throw new ConflictException('El anticipo debe estar confirmado y sin disposición seleccionada para asignarse.');
      }

      const saleResult = await client.query<AllocationSaleRow>(`SELECT s.id,s.authorization_id,s.total_usd::text AS total_usd,da.status AS status,
          coalesce((SELECT sum(pa.amount_usd) FROM payment_attempts pa WHERE pa.sale_id=s.id
            AND NOT EXISTS(SELECT 1 FROM payment_events pe WHERE pe.attempt_id=pa.id AND pe.outcome='declined')),0)::text AS active_payment_attempts_usd,
          coalesce((SELECT sum(al.amount_usd) FROM prepayment_allocations al JOIN prepayment_advances aa ON aa.id=al.advance_id
            WHERE al.sale_id=s.id AND aa.tender_kind='captured' AND prepayment_current_outcome(aa.id)='confirmed'),0)::text AS captured_allocations_usd
        FROM sales s JOIN dispense_authorizations da ON da.id=s.authorization_id AND da.organization_id=s.organization_id AND da.branch_id=s.branch_id
        WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3 FOR UPDATE OF s,da`,
      [input.saleId, principal.organizationId, branch]);
      const sale = saleResult.rows[0];
      if (!sale) throw new NotFoundException('La venta no existe en esta sucursal.');
      const dispatchResult = await client.query<{ id: string; status: string }>(
        'SELECT id,status FROM dispense_authorizations WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE',
        [advance.authorization_id, principal.organizationId, branch]);
      const dispatch = dispatchResult.rows[0];
      if (!dispatch || dispatch.status !== 'completed' || sale.status !== 'completed' || (sale.authorization_id ?? sale.authorizationId) !== dispatch.id) {
        throw new ConflictException('La venta debe pertenecer al despacho original completado del anticipo.');
      }
      const advanceCents = cents(amountUsd);
      const allocationCents = cents(amount);
      const totalCents = cents(sale.total_usd ?? sale.totalUsd ?? '0');
      const occupied = cents(sale.active_payment_attempts_usd ?? sale.activePaymentAttemptsUsd ?? '0') + cents(sale.captured_allocations_usd ?? sale.capturedAllocationsUsd ?? '0');
      if (allocationCents > advanceCents - allocatedCents) throw new ConflictException('La asignación excede el saldo del anticipo.');
      if (tenderKind === 'captured' && allocationCents > totalCents - occupied) throw new ConflictException('La asignación excede el saldo disponible de la venta.');

      if (tenderKind === 'captured') {
        if (input.paymentEventId) throw new BadRequestException('Un anticipo capturado no admite paymentEventId.');
      } else if (tenderKind === 'authorization_hold') {
        if (!input.paymentEventId) throw new BadRequestException('La retención requiere el evento de pago confirmado de la venta.');
        const payment = await client.query<PaymentEventRow>(`SELECT e.id,e.outcome,pa.sale_id,pa.amount_usd::text AS amount_usd,pa.method,pa.mode
          FROM payment_events e JOIN payment_attempts pa ON pa.id=e.attempt_id
          WHERE e.id=$1 AND e.organization_id=$2 AND e.branch_id=$3 FOR UPDATE OF e,pa`,
        [input.paymentEventId, principal.organizationId, branch]);
        const event = payment.rows[0];
        if (!event || event.outcome !== 'confirmed' || (event.sale_id ?? event.saleId) !== input.saleId ||
            cents(event.amount_usd ?? event.amountUsd ?? '0') !== allocationCents || event.method !== 'card' || event.mode !== 'manual') {
          throw new ConflictException('La retención debe enlazar el pago confirmado manual de tarjeta por el importe exacto de esta venta.');
        }
      } else throw new ConflictException('El tipo de tender del anticipo no es válido.');

      const inserted = await client.query<{ id: string }>(`INSERT INTO prepayment_allocations
          (organization_id,branch_id,advance_id,sale_id,payment_event_id,amount_usd,command_id,request_hash,created_by,correlation_id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
      [principal.organizationId, branch, advanceId, input.saleId, input.paymentEventId ?? null, amount, input.commandId, hash, principal.userId, correlation]);
      const allocationId = inserted.rows[0]!.id;
      await client.query(`INSERT INTO prepayment_events
          (organization_id,branch_id,advance_id,allocation_id,event_type,amount_usd,command_id,request_hash,created_by,correlation_id)
        VALUES($1,$2,$3,$4,'allocated',$5,$6,$7,$8,$9)`,
      [principal.organizationId, branch, advanceId, allocationId, amount, input.commandId, hash, principal.userId, correlation]);
      await this.auditWrite(client, principal, branch, correlation, 'payment.prepayment.allocated', advanceId);
      return { data: resultData(allocationId, false) };
    });
  }

  async requestRelease(branch: string, advanceId: string, principal: AuthPrincipal, input: RequestReleaseDto, correlation: string) {
    await this.access(branch, principal, 'payment.resolve');
    uuid(advanceId); uuid(input.commandId);
    const amount = money(input.amountUsd);
    const hash = this.hash(branch, principal, 'payment.resolve.release-request', { advanceId: advanceId.toLowerCase(), amount });
    return this.transaction(async client => {
      const advanceResult = await client.query<PrepaymentDispositionRow>(`SELECT id,tender_kind,method,mode,amount_usd::text AS amount_usd,
          prepayment_current_outcome(id) AS current_outcome,
          coalesce((SELECT sum(al.amount_usd) FROM prepayment_allocations al WHERE al.advance_id=prepayment_advances.id),0)::text AS allocated_usd
        FROM prepayment_advances WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE`,
      [advanceId, principal.organizationId, branch]);
      const advance = advanceResult.rows[0];
      if (!advance) throw new NotFoundException('El anticipo no existe en esta sucursal.');
      const existingId = await this.replay(client, 'prepayment_events', branch, principal, input.commandId, hash);
      if (existingId) return { data: { id: existingId, amountUsd: amount, remainderStatus: 'refundPending', idempotentReplay: true } };
      const remaining = formatCents(cents(advance.amount_usd ?? advance.amountUsd ?? '0') - cents(advance.allocated_usd ?? advance.allocatedUsd ?? '0'));
      if (advance.tender_kind !== 'authorization_hold' || advance.method !== 'card' || advance.mode !== 'manual' ||
          (advance.current_outcome ?? advance.currentOutcome ?? advance.outcome) !== 'confirmed' || cents(remaining) <= 0n || amount !== remaining) {
        throw new ConflictException('Solo se libera el remanente exacto de una retención manual de tarjeta confirmada.');
      }
      const inserted = await client.query<{ id: string }>(`INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,command_id,request_hash,created_by,correlation_id)
        VALUES($1,$2,$3,'refundPending','release',$4,$5,$6,$7,$8) RETURNING id`,
      [principal.organizationId, branch, advanceId, amount, input.commandId, hash, principal.userId, correlation]);
      const id = inserted.rows[0]!.id;
      await this.auditWrite(client, principal, branch, correlation, 'payment.prepayment.release_requested', advanceId);
      return { data: { id, amountUsd: amount, remainderStatus: 'refundPending', idempotentReplay: false } };
    });
  }

  async confirmRelease(branch: string, advanceId: string, principal: AuthPrincipal, input: ConfirmReleaseDto, correlation: string) {
    await this.access(branch, principal, 'payment.resolve');
    uuid(advanceId); uuid(input.commandId);
    const confirmationReference = text(input.confirmationReference, 200, true)!;
    const hash = this.hash(branch, principal, 'payment.resolve.release-confirmation', { advanceId: advanceId.toLowerCase(), confirmationReference });
    return this.transaction(async client => {
      const advanceResult = await client.query<PrepaymentDispositionRow>(`SELECT id,tender_kind,method,mode,amount_usd::text AS amount_usd,
          prepayment_current_outcome(id) AS current_outcome,
          coalesce((SELECT sum(al.amount_usd) FROM prepayment_allocations al WHERE al.advance_id=prepayment_advances.id),0)::text AS allocated_usd
        FROM prepayment_advances WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE`,
      [advanceId, principal.organizationId, branch]);
      const advance = advanceResult.rows[0];
      if (!advance) throw new NotFoundException('El anticipo no existe en esta sucursal.');
      const remaining = formatCents(cents(advance.amount_usd ?? advance.amountUsd ?? '0') - cents(advance.allocated_usd ?? advance.allocatedUsd ?? '0'));
      if (advance.tender_kind !== 'authorization_hold' || advance.method !== 'card' || advance.mode !== 'manual' ||
          (advance.current_outcome ?? advance.currentOutcome ?? advance.outcome) !== 'confirmed' || cents(remaining) <= 0n) {
        throw new ConflictException('Solo se confirma la liberación de una retención manual de tarjeta confirmada.');
      }
      const existingId = await this.replay(client, 'prepayment_events', branch, principal, input.commandId, hash);
      if (existingId) return { data: { id: advanceId, remainderStatus: 'released', eventId: existingId, idempotentReplay: true } };
      const inserted = await client.query<{ id: string }>(`INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,confirmation_reference,command_id,request_hash,created_by,correlation_id)
        VALUES($1,$2,$3,'released','release',$4,$5,$6,$7,$8,$9) RETURNING id`,
      [principal.organizationId, branch, advanceId, remaining, confirmationReference, input.commandId, hash, principal.userId, correlation]);
      const id = inserted.rows[0]!.id;
      await this.auditWrite(client, principal, branch, correlation, 'payment.prepayment.released', advanceId);
      return { data: { id: advanceId, remainderStatus: 'released', eventId: id, idempotentReplay: false } };
    });
  }

  async resolve(branch: string, advanceId: string, principal: AuthPrincipal, input: ResolvePrepaymentDto, correlation: string) {
    await this.access(branch, principal, 'payment.resolve');
    uuid(advanceId); uuid(input.commandId);
    if (!['confirmed', 'declined'].includes(input.outcome)) throw new BadRequestException('Resultado no válido.');
    const evidence = text(input.evidenceReference, 200, true);
    const hash = this.hash(branch, principal, 'payment.resolve', { advanceId: advanceId.toLowerCase(), outcome: input.outcome, evidence });
    return this.transaction(async client => {
      const advance = await client.query<{ outcome: string }>('SELECT outcome FROM prepayment_advances WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE', [advanceId, principal.organizationId, branch]);
      if (!advance.rows[0]) throw new NotFoundException('El anticipo no existe en esta sucursal.');
      const existingId = await this.replay(client, 'prepayment_events', branch, principal, input.commandId, hash);
      if (existingId) return { data: { id: advanceId, outcome: input.outcome, idempotentReplay: true } };
      if (advance.rows[0].outcome !== 'unknown') throw new ConflictException('Solo se puede resolver un anticipo con resultado desconocido.');
      const inserted = await client.query<{ id: string }>(`INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,outcome,outcome_reference,command_id,request_hash,created_by,correlation_id)
        VALUES($1,$2,$3,'outcomeResolved',$4,$5,$6,$7,$8,$9) RETURNING id`, [principal.organizationId, branch, advanceId, input.outcome, evidence, input.commandId, hash, principal.userId, correlation]);
      const id = inserted.rows[0]!.id;
      await this.auditWrite(client, principal, branch, correlation, 'payment.prepayment.resolved', advanceId);
      return { data: { id: advanceId, outcome: input.outcome, eventId: id, idempotentReplay: false } };
    });
  }
}

function isUuid(value: unknown): value is string { return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value); }
function uuid(value: unknown): asserts value is string { if (!isUuid(value)) throw new BadRequestException('Identificador no válido.'); }
function text(value: unknown, max: number, required: boolean): string | null { if (value === undefined || value === null) { if (required) throw new BadRequestException('Falta evidencia.'); return null; } if (typeof value !== 'string' || !value.trim() || value.trim().length > max) throw new BadRequestException('Evidencia no válida.'); return value.trim(); }
function cents(value: string): bigint { const [whole, fraction = ''] = value.split('.'); return BigInt(whole!) * 100n + BigInt(fraction.padEnd(2, '0')); }
function formatCents(value: bigint): string { return `${value / 100n}.${(value % 100n).toString().padStart(2, '0')}`; }
function money(value: unknown): string { if (typeof value !== 'string' || !/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/.test(value)) throw new BadRequestException('Importe no válido.'); const normalized = formatCents(cents(value)); if (cents(normalized) <= 0n) throw new BadRequestException('El importe debe ser positivo.'); return normalized; }
