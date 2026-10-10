import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { createHash } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';

interface PrepaymentOutcomeRow {
 id:string;tender_kind?:'captured'|'authorization_hold';tenderKind?:'captured'|'authorization_hold';method:string;mode:string;
 current_outcome?:string;currentOutcome?:string;outcome?:string;amount_usd?:string;amountUsd?:string;allocated_usd?:string;allocatedUsd?:string;
}
import type { CashMovementDto, CloseCashDto, CollectPaymentDto, CreateRegisterDto, OpenCashDto, RefundPaymentDto, RequestRefundDto, ResolvePaymentDto } from './payments.dto.js';

@Injectable()
export class PaymentsService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService) {}
 private async access(branch:string,p:AuthPrincipal,permission:string) {
  if(!(await this.auth.capabilities(p,branch)).includes(permission)) throw new ForbiddenException('No tienes permiso para esta operación en la sucursal.');
  if(!(await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2',[branch,p.organizationId])).rowCount) throw new NotFoundException('La sucursal no existe.');
 }
 private async transaction<T>(work:(c:PoolClient)=>Promise<T>) {
  const c=await this.pool.connect();
  try {await c.query('BEGIN');const result=await work(c);await c.query('COMMIT');return result;}
  catch(error){await c.query('ROLLBACK').catch(()=>undefined);const code=(error as {code?:string}).code;
   if(code==='23514'||code==='23505') throw new ConflictException('Revisa saldo, evidencia, propietario, estado de caja o repetición del comando.');
   if(code==='23503') throw new NotFoundException('El recurso no existe en esta sucursal.');
   if(code==='22003') throw new BadRequestException('El importe excede el límite admitido.');
   throw error;
  }finally{c.release();}
 }
 private hash(branch:string,p:AuthPrincipal,kind:string,body:object){return createHash('sha256').update(JSON.stringify({v:1,branch:branch.toLowerCase(),actor:p.userId,kind,...body})).digest('hex');}
 private async replay(c:PoolClient,table:string,branch:string,p:AuthPrincipal,command:string,hash:string){
  await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`financial-command:${p.organizationId}:${command.toLowerCase()}`]);
  // table is exclusively one of the hardcoded identifiers below, never request data.
  const r=await c.query<{id:string;request_hash:string;created_by:string;branch_id:string}>(`SELECT id,request_hash,${table==='cash_sessions'?'cashier_id':'created_by'} AS created_by,branch_id FROM ${table} WHERE organization_id=$1 AND command_id=$2`,[p.organizationId,command]);
  const row=r.rows[0];
  if(row&&(row.request_hash!==hash||row.created_by!==p.userId||row.branch_id!==branch.toLowerCase())) throw new ConflictException('El comando ya se usó con otros datos.');
  return row?.id;
 }
 private async auditWrite(c:PoolClient,p:AuthPrincipal,branch:string,correlationId:string,kind:string,id:string){
  await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId,action:kind,entityType:'financial_operation',entityId:id,after:{id}});
 }
 async createRegister(branch:string,p:AuthPrincipal,input:CreateRegisterDto,correlation:string){
  await this.access(branch,p,'cash.register.manage');uuid(input.commandId);
  if(typeof input.code!=='string'||!/^[-A-Z0-9_]{1,30}$/.test(input.code)) throw new BadRequestException('Código de caja no válido.');
  return this.transaction(async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`register-command:${input.commandId.toLowerCase()}`]);
   const old=await c.query('SELECT id,code,branch_id,organization_id,created_by FROM cash_registers WHERE id=$1',[input.commandId]);
   if(old.rows[0]){const r=old.rows[0];if(r.code!==input.code||r.branch_id!==branch.toLowerCase()||r.organization_id!==p.organizationId||r.created_by!==p.userId)throw new ConflictException('El comando ya identifica otra caja.');return {data:{id:r.id,code:r.code,idempotentReplay:true}};}
   await c.query('INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES($1,$2,$3,$4,$5)',[input.commandId,p.organizationId,branch,input.code,p.userId]);
   await this.auditWrite(c,p,branch,correlation,'cash.register.created',input.commandId);
   return {data:{id:input.commandId,code:input.code,idempotentReplay:false}};
  });
 }
 async registers(branch:string,p:AuthPrincipal){
  await this.access(branch,p,'cash.read');
  const r=await this.pool.query(`SELECT r.id,r.code,s.id AS "openSessionId",s.cashier_id AS "cashierId" FROM cash_registers r
   LEFT JOIN LATERAL(SELECT c.id,c.cashier_id FROM cash_sessions c WHERE c.register_id=r.id AND NOT EXISTS(SELECT 1 FROM cash_closures x WHERE x.session_id=c.id) ORDER BY c.created_at DESC LIMIT 1)s ON true
   WHERE r.organization_id=$1 AND r.branch_id=$2 ORDER BY r.code LIMIT 100`,[p.organizationId,branch]);return {data:r.rows};
 }
 async open(branch:string,p:AuthPrincipal,input:OpenCashDto,correlation:string){
  await this.access(branch,p,'cash.open');uuid(input.commandId);uuid(input.registerId);const opening=money(input.openingUsd);
  const h=this.hash(branch,p,'cash.open',{registerId:input.registerId.toLowerCase(),opening});
  return this.transaction(async c=>{let id=await this.replay(c,'cash_sessions',branch,p,input.commandId,h);const replay=!!id;
   if(!id){const r=await c.query<{id:string}>(`INSERT INTO cash_sessions(organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,[p.organizationId,branch,input.registerId,p.userId,opening,input.commandId,h,correlation]);id=r.rows[0]!.id;await this.auditWrite(c,p,branch,correlation,'cash.opened',id);}
   return {data:{id,idempotentReplay:replay}};
  });
 }
 async collect(branch:string,p:AuthPrincipal,input:CollectPaymentDto,correlation:string){
  await this.access(branch,p,'payment.collect');uuid(input.commandId);uuid(input.saleId);uuid(input.cashSessionId);const amount=money(input.amountUsd,true);
  if(!['cash','card'].includes(input.method)||!['manual','simulated'].includes(input.mode)||!['confirmed','declined','unknown'].includes(input.outcome))throw new BadRequestException('Método o resultado no válido.');
  this.mode(input.mode);
  if(input.method==='cash'&&(input.mode!=='manual'||input.outcome!=='confirmed'))throw new BadRequestException('El efectivo se confirma en la caja propia.');
  const evidence=input.method==='cash'?null:input.mode==='simulated'?`SIMULATED:${input.commandId.toLowerCase()}:${input.outcome}`:text(input.evidenceReference,200,false);
  if(input.method==='card'&&input.outcome!=='unknown'&&!evidence)throw new BadRequestException('Registra la referencia documental del terminal.');
  const h=this.hash(branch,p,'payment.collect',{saleId:input.saleId.toLowerCase(),session:input.cashSessionId.toLowerCase(),amount,method:input.method,mode:input.mode,outcome:input.outcome,evidence});
  return this.transaction(async c=>{let id=await this.replay(c,'payment_attempts',branch,p,input.commandId,h);const replay=!!id;
   if(!id){const r=await c.query<{id:string}>(`INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,[p.organizationId,branch,input.saleId,input.method,input.mode,amount,input.cashSessionId,input.commandId,h,p.userId,correlation]);id=r.rows[0]!.id;
    await c.query(`INSERT INTO payment_events(organization_id,branch_id,attempt_id,outcome,evidence_reference,command_id,request_hash,created_by,correlation_id)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[p.organizationId,branch,id,input.outcome,evidence,input.commandId,h,p.userId,correlation]);await this.auditWrite(c,p,branch,correlation,'payment.recorded',id);}
   return {data:{id,idempotentReplay:replay}};
  });
 }
 async resolve(branch:string,attempt:string,p:AuthPrincipal,input:ResolvePaymentDto,correlation:string){
  await this.access(branch,p,'payment.resolve');uuid(input.commandId);uuid(attempt);
  if(!['confirmed','declined'].includes(input.outcome))throw new BadRequestException('Resultado no válido.');
  const evidence=text(input.evidenceReference,200,true);const h=this.hash(branch,p,'payment.resolve',{attempt:attempt.toLowerCase(),outcome:input.outcome,evidence});
  return this.transaction(async c=>{
   const a=await c.query<{mode:string}>(`SELECT mode FROM payment_attempts WHERE id=$1 AND organization_id=$2 AND branch_id=$3`,[attempt,p.organizationId,branch]);
   if(!a.rows[0])throw new NotFoundException('El intento no existe.');this.mode(a.rows[0].mode);
   let id=await this.replay(c,'payment_events',branch,p,input.commandId,h);const replay=!!id;
   if(!id){const r=await c.query<{id:string}>(`INSERT INTO payment_events(organization_id,branch_id,attempt_id,outcome,evidence_reference,command_id,request_hash,created_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,[p.organizationId,branch,attempt,input.outcome,evidence,input.commandId,h,p.userId,correlation]);id=r.rows[0]!.id;await this.auditWrite(c,p,branch,correlation,'payment.resolved',id);}
   return {data:{id,idempotentReplay:replay}};
  });
 }
 async requestRefund(branch:string,event:string,p:AuthPrincipal,input:RequestRefundDto,correlation:string){
  await this.access(branch,p,'sale.refund.request');uuid(event);uuid(input.commandId);
  const amount=money(input.amountUsd,true),reason=text(input.reason,300,true),payload={amountUsd:amount,reason};
  return this.transaction(async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`refund-request:${input.commandId.toLowerCase()}`]);
   const old=await c.query('SELECT id,organization_id,branch_id,requested_by,action,entity_type,entity_id,payload,status FROM approval_requests WHERE id=$1',[input.commandId]);
   if(old.rows[0]){const r=old.rows[0];if(r.organization_id!==p.organizationId||r.branch_id!==branch.toLowerCase()||r.requested_by!==p.userId||r.action!=='sale.refund.approve'||r.entity_type!=='payment_refund'||r.entity_id!==event.toLowerCase()||r.payload.amountUsd!==amount||r.payload.reason!==reason)throw new ConflictException('El comando ya se usó con otros datos.');return {data:{id:r.id,status:r.status,idempotentReplay:true}};}
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`refund-payment:${event.toLowerCase()}`]);
   const found=await c.query<{mode:string;payment_amount_usd:string}>(`SELECT a.mode,a.amount_usd::text AS payment_amount_usd
    FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id
    WHERE e.id=$1 AND e.organization_id=$2 AND e.branch_id=$3 AND e.outcome='confirmed' FOR UPDATE OF e,a`,[event,p.organizationId,branch]);
   if(!found.rows[0])throw new NotFoundException('El pago confirmado no existe.');this.mode(found.rows[0].mode);
   const totals=await c.query<{refunded_usd:string}>(`SELECT coalesce(sum(amount_usd),0)::text AS refunded_usd FROM payment_refunds WHERE payment_event_id=$1`,[event]);
   if(cents(amount)>cents(found.rows[0].payment_amount_usd)-cents(totals.rows[0]?.refunded_usd??'0'))throw new ConflictException('El importe solicitado supera el saldo reembolsable del pago.');
   const open=await c.query<{active:boolean}>(`SELECT EXISTS(
    SELECT 1 FROM approval_requests q WHERE q.organization_id=$1 AND q.branch_id=$2
     AND q.action='sale.refund.approve' AND q.entity_type='payment_refund' AND q.entity_id=$3
     AND q.status IN ('pending','approved') AND NOT EXISTS(SELECT 1 FROM payment_refunds r WHERE r.approval_id=q.id)
   ) AS active`,[p.organizationId,branch,event.toLowerCase()]);
   if(open.rows[0]?.active)throw new ConflictException('Ya existe una solicitud de devolución pendiente o aprobada para este pago.');
   await c.query(`INSERT INTO approval_requests(id,organization_id,branch_id,action,entity_type,entity_id,requested_by,payload)
    VALUES($1,$2,$3,'sale.refund.approve','payment_refund',$4,$5,$6::jsonb)`,[input.commandId,p.organizationId,branch,event.toLowerCase(),p.userId,JSON.stringify(payload)]);
   await this.auditWrite(c,p,branch,correlation,'payment.refund.requested',input.commandId);
   return {data:{id:input.commandId,status:'pending',idempotentReplay:false}};
  });
 }
 async refund(branch:string,event:string,p:AuthPrincipal,input:RefundPaymentDto,correlation:string){
  await this.access(branch,p,'payment.refund');uuid(event);uuid(input.commandId);uuid(input.cashSessionId);uuid(input.approvalId);
  if(input.storeReturnId!==undefined)uuid(input.storeReturnId);
  const amount=money(input.amountUsd,true),reason=text(input.reason,300,true),evidence=text(input.evidenceReference,200,false);
  const h=this.hash(branch,p,'payment.refund',{approvalId:input.approvalId.toLowerCase(),event:event.toLowerCase(),session:input.cashSessionId.toLowerCase(),amount,reason,evidence,storeReturnId:input.storeReturnId?.toLowerCase()??null});
  return this.transaction(async c=>{
   const a=await c.query<{mode:string}>(`SELECT a.mode FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id WHERE e.id=$1 AND e.organization_id=$2 AND e.branch_id=$3`,[event,p.organizationId,branch]);
   if(!a.rows[0])throw new NotFoundException('El pago no existe.');this.mode(a.rows[0].mode);
   let id=await this.replay(c,'payment_refunds',branch,p,input.commandId,h);const replay=!!id;
   if(!id){const r=await c.query<{id:string}>(`INSERT INTO payment_refunds(organization_id,branch_id,payment_event_id,amount_usd,cash_session_id,evidence_reference,reason,command_id,request_hash,created_by,correlation_id,approval_id,store_return_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,[p.organizationId,branch,event,amount,input.cashSessionId,evidence,reason,input.commandId,h,p.userId,correlation,input.approvalId,input.storeReturnId??null]);id=r.rows[0]!.id;await this.auditWrite(c,p,branch,correlation,'payment.refunded',id);}
   return {data:{id,idempotentReplay:replay}};
  });
 }
 async refundRequests(branch:string,sale:string,p:AuthPrincipal){
  await this.access(branch,p,'payment.read');uuid(sale);
  if(!(await this.pool.query('SELECT id FROM sales WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[sale,p.organizationId,branch])).rowCount)throw new NotFoundException('La venta no existe.');
  const r=await this.pool.query(`SELECT q.id,e.id AS "paymentEventId",a.method,a.amount_usd::text AS "paymentAmountUsd",
   q.requested_by AS "requestedBy",q.payload->>'amountUsd' AS "amountUsd",q.payload->>'reason' AS reason,
   q.status,q.decided_by AS "decidedBy",q.decided_at AS "decidedAt",q.reason AS "decisionReason",q.created_at AS "createdAt",
   x.id AS "refundId",x.created_at AS "refundedAt"
   FROM approval_requests q JOIN payment_events e ON e.id::text=q.entity_id
   JOIN payment_attempts a ON a.id=e.attempt_id
   LEFT JOIN payment_refunds x ON x.approval_id=q.id
   WHERE q.organization_id=$1 AND q.branch_id=$2 AND q.action='sale.refund.approve'
    AND q.entity_type='payment_refund' AND a.sale_id=$3
   ORDER BY q.created_at DESC,q.id DESC LIMIT 100`,[p.organizationId,branch,sale]);
  return {data:r.rows};
 }
 async requestAdvanceRefund(branch:string,advance:string,p:AuthPrincipal,input:RequestRefundDto,correlation:string){
  await this.access(branch,p,'sale.refund.request');uuid(advance);uuid(input.commandId);
  const amount=money(input.amountUsd,true),reason=text(input.reason,300,true);
  const payload={amountUsd:amount,reason};
  return this.transaction(async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`refund-request:${input.commandId.toLowerCase()}`]);
   const old=await c.query('SELECT id,organization_id,branch_id,requested_by,action,entity_type,entity_id,payload,status FROM approval_requests WHERE id=$1',[input.commandId]);
   if(old.rows[0]){const r=old.rows[0];if(r.organization_id!==p.organizationId||r.branch_id!==branch.toLowerCase()||r.requested_by!==p.userId||r.action!=='sale.refund.approve'||r.entity_type!=='payment_refund'||r.entity_id!==advance.toLowerCase()||r.payload.amountUsd!==amount||r.payload.reason!==reason)throw new ConflictException('El comando ya se usó con otros datos.');return {data:{id:r.id,status:r.status,idempotentReplay:true}};}
   const a=await c.query<PrepaymentOutcomeRow>(`SELECT a.id,a.tender_kind,a.method,a.mode,prepayment_current_outcome(a.id) AS current_outcome,
     a.amount_usd::text AS amount_usd,coalesce((SELECT sum(x.amount_usd) FROM prepayment_allocations x WHERE x.advance_id=a.id),0)::text AS allocated_usd
    FROM prepayment_advances a WHERE a.id=$1 AND a.organization_id=$2 AND a.branch_id=$3 FOR UPDATE`,[advance,p.organizationId,branch]);
   const row=a.rows[0];if(!row)throw new NotFoundException('El anticipo no existe.');
   const remaining=formatCents(cents(row.amount_usd??row.amountUsd??'0')-cents(row.allocated_usd??row.allocatedUsd??'0'));
   if((row.tender_kind??row.tenderKind)!=='captured'||(row.current_outcome??row.currentOutcome??row.outcome)!=='confirmed'||amount!==remaining)throw new ConflictException('Solo se reembolsa el remanente exacto de un anticipo capturado confirmado.');
   await c.query(`INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,command_id,request_hash,created_by,correlation_id)
    VALUES($1,$2,$3,'refundPending','refund',$4,$5,$6,$7,$8)`,[p.organizationId,branch,advance,amount,input.commandId,this.hash(branch,p,'sale.refund.request',{advance:advance.toLowerCase(),amountUsd:amount,reason}),p.userId,correlation]);
   await c.query(`INSERT INTO approval_requests(id,organization_id,branch_id,action,entity_type,entity_id,requested_by,payload)
    VALUES($1,$2,$3,'sale.refund.approve','payment_refund',$4,$5,$6::jsonb)`,[input.commandId,p.organizationId,branch,advance.toLowerCase(),p.userId,JSON.stringify(payload)]);
   await this.auditWrite(c,p,branch,correlation,'payment.refund.requested',input.commandId);
   return {data:{id:input.commandId,status:'pending',idempotentReplay:false}};
  });
 }
 async refundAdvance(branch:string,advance:string,p:AuthPrincipal,input:RefundPaymentDto,correlation:string){
  await this.access(branch,p,'payment.refund');uuid(advance);uuid(input.commandId);uuid(input.cashSessionId);uuid(input.approvalId);
  const amount=money(input.amountUsd,true),reason=text(input.reason,300,true),evidence=text(input.evidenceReference,200,true);
  const h=this.hash(branch,p,'payment.refund',{approvalId:input.approvalId.toLowerCase(),advance:advance.toLowerCase(),session:input.cashSessionId.toLowerCase(),amount,reason,evidence});
  return this.transaction(async c=>{
   const a=await c.query<PrepaymentOutcomeRow>(`SELECT a.id,a.tender_kind,a.method,a.mode,prepayment_current_outcome(a.id) AS current_outcome,
     a.amount_usd::text AS amount_usd,coalesce((SELECT sum(x.amount_usd) FROM prepayment_allocations x WHERE x.advance_id=a.id),0)::text AS allocated_usd
    FROM prepayment_advances a WHERE a.id=$1 AND a.organization_id=$2 AND a.branch_id=$3 FOR UPDATE`,[advance,p.organizationId,branch]);
   const row=a.rows[0];if(!row)throw new NotFoundException('El anticipo no existe.');
   let id=await this.replay(c,'payment_refunds',branch,p,input.commandId,h);const replay=!!id;
   if(!id){
    const remaining=formatCents(cents(row.amount_usd??row.amountUsd??'0')-cents(row.allocated_usd??row.allocatedUsd??'0'));
    if((row.tender_kind??row.tenderKind)!=='captured'||(row.current_outcome??row.currentOutcome??row.outcome)!=='confirmed'||amount!==remaining)throw new ConflictException('El reembolso debe coincidir con la disposición aprobada y el remanente exacto.');
    const result=await c.query<{id:string}>(`INSERT INTO payment_refunds(organization_id,branch_id,advance_id,amount_usd,cash_session_id,evidence_reference,reason,command_id,request_hash,created_by,correlation_id,approval_id)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,[p.organizationId,branch,advance,amount,input.cashSessionId,evidence,reason,input.commandId,h,p.userId,correlation,input.approvalId]);
    id=result.rows[0]!.id;
    await c.query(`INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,confirmation_reference,command_id,request_hash,created_by,correlation_id)
     VALUES($1,$2,$3,'refunded','refund',$4,$5,$6,$7,$8,$9)`,[p.organizationId,branch,advance,amount,evidence,input.commandId,h,p.userId,correlation]);
    await this.auditWrite(c,p,branch,correlation,'payment.refunded',id);
   }
   return {data:{id,idempotentReplay:replay}};
  });
 }
 async move(branch:string,session:string,p:AuthPrincipal,input:CashMovementDto,correlation:string){
  await this.access(branch,p,'cash.move');uuid(session);uuid(input.commandId);const amount=money(input.amountUsd,true),reason=text(input.reason,300,true);
  if(!['cash_in','withdrawal','deposit'].includes(input.kind))throw new BadRequestException('Tipo de movimiento no válido.');
  const h=this.hash(branch,p,'cash.move',{session:session.toLowerCase(),amount,kind:input.kind,reason});
  return this.transaction(async c=>{let id=await this.replay(c,'cash_movements',branch,p,input.commandId,h);const replay=!!id;
   if(!id){const r=await c.query<{id:string}>(`INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,reason,command_id,request_hash,created_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,[p.organizationId,branch,session,input.kind,input.kind==='cash_in'?amount:'-'+amount,reason,input.commandId,h,p.userId,correlation]);id=r.rows[0]!.id;await this.auditWrite(c,p,branch,correlation,'cash.moved',id);}
   return {data:{id,idempotentReplay:replay}};
  });
 }
 async close(branch:string,session:string,p:AuthPrincipal,input:CloseCashDto,correlation:string){
  await this.access(branch,p,'cash.close');uuid(session);uuid(input.commandId);const cash=money(input.countedCashUsd),card=money(input.settledCardUsd,false,true),reason=text(input.reason,300,false);
  const h=this.hash(branch,p,'cash.close',{session:session.toLowerCase(),cash,card,reason});
  return this.transaction(async c=>{let id=await this.replay(c,'cash_closures',branch,p,input.commandId,h);const replay=!!id;
   if(!id){const r=await c.query<{id:string}>(`INSERT INTO cash_closures(organization_id,branch_id,session_id,counted_cash_usd,settled_card_usd,expected_cash_usd,expected_card_usd,variance_cash_usd,variance_card_usd,review_status,reason,command_id,request_hash,created_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,0,0,0,0,'balanced',$6,$7,$8,$9,$10) RETURNING id`,[p.organizationId,branch,session,cash,card,reason,input.commandId,h,p.userId,correlation]);id=r.rows[0]!.id;await this.auditWrite(c,p,branch,correlation,'cash.closed',id);}
   const r=await c.query(`SELECT id,expected_cash_usd::text AS "expectedCashUsd",expected_card_usd::text AS "expectedCardUsd",variance_cash_usd::text AS "varianceCashUsd",variance_card_usd::text AS "varianceCardUsd",review_status AS "reviewStatus" FROM cash_closures WHERE id=$1`,[id]);
   return {data:{...r.rows[0],idempotentReplay:replay}};
  });
 }
 async session(branch:string,session:string,p:AuthPrincipal){
  await this.access(branch,p,'cash.read');uuid(session);
  const r=await this.pool.query(`SELECT s.id,s.register_id AS "registerId",s.cashier_id AS "cashierId",s.opening_usd::text AS "openingUsd",s.created_at AS "openedAt",
   (s.opening_usd+coalesce((SELECT sum(delta_usd) FROM cash_movements WHERE session_id=s.id),0))::text AS "expectedCashUsd",
   x.id AS "closureId",x.review_status AS "reviewStatus" FROM cash_sessions s LEFT JOIN cash_closures x ON x.session_id=s.id
   WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3`,[session,p.organizationId,branch]);
  if(!r.rows[0])throw new NotFoundException('La sesión no existe.');return {data:r.rows[0]};
 }
 async cashReview(branch:string,session:string,p:AuthPrincipal){
  await this.access(branch,p,'cash.read');uuid(session);
  const r=await this.pool.query(`SELECT closure_id AS "closureId",session_id AS "sessionId",cashier_id AS "cashierId",closed_at AS "closedAt",
   expected_cash_usd::text AS "expectedCashUsd",counted_cash_usd::text AS "countedCashUsd",variance_cash_usd::text AS "varianceCashUsd",
   expected_card_usd::text AS "expectedCardUsd",settled_card_usd::text AS "settledCardUsd",variance_card_usd::text AS "varianceCardUsd",
   cashier_reason AS "cashierReason",approval_id AS "approvalId",status,decided_by AS "decidedBy",decided_at AS "decidedAt",decision_reason AS "decisionReason"
   FROM cash_closure_reviews WHERE session_id=$1 AND organization_id=$2 AND branch_id=$3`,[session,p.organizationId,branch]);
  if(!r.rows[0])throw new NotFoundException('El cierre de caja no existe en esta sucursal.');
  return {data:r.rows[0]};
 }
 async cashReviews(branch:string,p:AuthPrincipal,status?:string){
  await this.access(branch,p,'cash.read');
  if(status!==undefined&&!['pending','approved','rejected','balanced'].includes(status))throw new BadRequestException('Estado de revisión no válido.');
  const r=await this.pool.query(`SELECT closure_id AS "closureId",session_id AS "sessionId",cashier_id AS "cashierId",closed_at AS "closedAt",
   variance_cash_usd::text AS "varianceCashUsd",variance_card_usd::text AS "varianceCardUsd",
   approval_id AS "approvalId",status FROM cash_closure_reviews
   WHERE organization_id=$1 AND branch_id=$2 AND ($3::text IS NULL OR status=$3)
   ORDER BY closed_at DESC,closure_id DESC LIMIT 100`,[p.organizationId,branch,status??null]);
  return {data:r.rows};
 }
 async cashMovements(branch:string,session:string,p:AuthPrincipal,query:{kind?:string;limit?:string;beforeAt?:string;beforeId?:string}){
  await this.access(branch,p,'cash.read');uuid(session);
  if(query.kind!==undefined&&!['collection','refund','deposit','cash_in','withdrawal'].includes(query.kind))throw new BadRequestException('Tipo de movimiento no válido.');
  if(query.limit!==undefined&&!/^[1-9][0-9]?$|^100$/.test(query.limit))throw new BadRequestException('Límite entre 1 y 100 requerido.');
  if((query.beforeAt===undefined)!==(query.beforeId===undefined))throw new BadRequestException('El cursor requiere fecha e identificador.');
  if(query.beforeId!==undefined)uuid(query.beforeId);
  if(query.beforeAt!==undefined&&(!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(query.beforeAt)||!Number.isFinite(Date.parse(query.beforeAt))))throw new BadRequestException('Fecha del cursor no válida.');
  const owner=await this.pool.query('SELECT id FROM cash_sessions WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[session,p.organizationId,branch]);
  if(!owner.rowCount)throw new NotFoundException('La sesión no existe en esta sucursal.');
  const limit=Number(query.limit??'30');
  const r=await this.pool.query(`SELECT m.id,m.kind,m.delta_usd::text AS "deltaUsd",m.reason,m.created_at AS "createdAt",
   m.payment_event_id AS "paymentEventId",m.advance_id AS "advanceId",m.refund_id AS "refundId",m.created_by AS "createdBy"
   FROM cash_movements m WHERE m.session_id=$1 AND m.organization_id=$2 AND m.branch_id=$3
    AND ($4::text IS NULL OR m.kind=$4)
    AND ($5::timestamptz IS NULL OR (m.created_at,m.id)<($5::timestamptz,$6::uuid))
   ORDER BY m.created_at DESC,m.id DESC LIMIT $7`,[session,p.organizationId,branch,query.kind??null,query.beforeAt??null,query.beforeId??null,limit+1]);
  const rows=r.rows.slice(0,limit);
  const last=rows.at(-1);
  return {data:rows,nextCursor:r.rows.length>limit&&last?{beforeAt:last.createdAt,beforeId:last.id}:null};
 }
 async payments(branch:string,sale:string,p:AuthPrincipal){
  await this.access(branch,p,'payment.read');uuid(sale);
  if(!(await this.pool.query('SELECT id FROM sales WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[sale,p.organizationId,branch])).rowCount)throw new NotFoundException('La venta no existe.');
  const r=await this.pool.query(`SELECT a.id,a.method,a.mode,a.amount_usd::text AS "amountUsd",a.cash_session_id AS "cashSessionId",a.created_at AS "createdAt",
   coalesce(e.outcome,'pending') AS status,e.id AS "paymentEventId",e.evidence_reference AS "evidenceReference",
   coalesce((SELECT sum(amount_usd) FROM payment_refunds WHERE payment_event_id=e.id),0)::text AS "refundedUsd"
   FROM payment_attempts a LEFT JOIN LATERAL(SELECT * FROM payment_events WHERE attempt_id=a.id ORDER BY (outcome<>'unknown') DESC,created_at DESC,id DESC LIMIT 1)e ON true
   WHERE a.sale_id=$1 AND a.organization_id=$2 AND a.branch_id=$3 ORDER BY a.created_at,a.id LIMIT 100`,[sale,p.organizationId,branch]);return {data:r.rows};
 }
 private mode(mode:string){if(mode==='simulated'&&process.env.NODE_ENV==='production')throw new ConflictException('Pagos simulados no disponibles en producción.');}
}
function uuid(value:unknown):asserts value is string{if(typeof value!=='string'||! /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))throw new BadRequestException('Identificador no válido.');}
function cents(value:string):bigint{const [whole,fraction='']=value.split('.');return BigInt(whole!)*100n+BigInt(fraction.padEnd(2,'0'));}
function formatCents(value:bigint):string{return `${value/100n}.${(value%100n).toString().padStart(2,'0')}`;}
function text(value:unknown,max:number,required:boolean){if(value===undefined||value===null){if(required)throw new BadRequestException('Falta evidencia o motivo.');return null;}if(typeof value!=='string'||!value.trim()||value.trim().length>max)throw new BadRequestException('Evidencia o motivo no válido.');return value.trim();}
function money(value:unknown,positive=false,signed=false){if(typeof value!=='string'||!(signed?/^-?(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/:/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/).test(value))throw new BadRequestException('Importe no válido.');const negative=value.startsWith('-');const [whole,fraction='']=value.replace(/^-/, '').split('.');const cents=BigInt(whole!)*100n+BigInt(fraction.padEnd(2,'0'));if(positive&&cents===0n)throw new BadRequestException('El importe debe ser positivo.');return (negative&&cents!==0n?'-':'')+(cents/100n).toString()+'.'+(cents%100n).toString().padStart(2,'0');}
