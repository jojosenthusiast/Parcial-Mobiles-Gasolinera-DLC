import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { AddCommercialBuyerDto, ChangeCommercialBuyerDto, ChargeCommercialSaleDto, CommercialCustomerEventDto, CreateCommercialCustomerDto, ReceiveCommercialCreditDto, VerifyCommercialBankDto } from './credit.dto.js';
@Injectable()
export class CreditService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}
 private async access(b:string,p:AuthPrincipal,cap:string){
  if(!(await this.auth.capabilities(p,b)).includes(cap))throw new ForbiddenException('Permiso de crédito insuficiente.');
  const row=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3',[b,p.organizationId,'active']);
  if(!row.rows[0])throw new NotFoundException('Sucursal fuera de tu ámbito.');
 }
 private async write(b:string,p:AuthPrincipal,correlation:string,action:string,type:string,fn:(c:PoolClient)=>Promise<{id:string;data:object;replay?:boolean}>){
  const c=await this.pool.connect();
  try{await c.query('BEGIN');const value=await fn(c);
   if(!value.replay)await this.audit.appendTransaction(c,{principal:p,branchId:b,correlationId:correlation,action,entityType:type,entityId:value.id,after:value.data});
   await c.query('COMMIT');return {data:{...value.data,idempotentReplay:!!value.replay}};
  }catch(error){await c.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514','40001','55000'].includes((error as {code?:string}).code??''))throw new ConflictException('Límite, saldo, estado o comprobante en conflicto.');
   if((error as {code?:string}).code==='23503')throw new NotFoundException('Referencia fuera de sucursal.');
   throw error;
  }finally{c.release();}
 }
 async create(b:string,p:AuthPrincipal,x:CreateCommercialCustomerDto,correlation:string){
  await this.access(b,p,'credit.customer.manage');
  if(!/^[A-Z0-9_-]{2,30}$/.test(x.code)||!txt(x.legalName,3,160)||!money(x.creditLimitUsd)
   ||!Number.isInteger(Number(x.termsDays))||Number(x.termsDays)<1||Number(x.termsDays)>120)
   throw new BadRequestException('Cliente o política de crédito inválidos.');
  return this.write(b,p,correlation,'credit.customer.created','commercial_customer',async c=>{
   const r=await c.query<{id:string}>(`INSERT INTO commercial_customers(organization_id,code,legal_name,tax_reference,credit_limit_usd,terms_days,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`,[p.organizationId,x.code,x.legalName.trim(),x.taxReference?.trim()??null,x.creditLimitUsd,x.termsDays,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,code:x.code,active:false}};
  });
 }
 async customers(b:string,p:AuthPrincipal,q?:string){
  await this.access(b,p,'credit.statement.read');if(q&&q.length>100)throw new BadRequestException('Búsqueda inválida.');
  const r=await this.pool.query(`SELECT c.id,c.code,c.legal_name AS "legalName",c.credit_limit_usd AS "creditLimitUsd",
   c.terms_days AS "termsDays",c.active,coalesce(sum(s.outstanding_usd),0) AS "outstandingUsd"
   FROM commercial_customers c LEFT JOIN commercial_account_statement s ON s.customer_id=c.id
   WHERE c.organization_id=$1 AND ($2::text IS NULL OR c.code ILIKE '%'||$2||'%' OR c.legal_name ILIKE '%'||$2||'%')
   GROUP BY c.id ORDER BY c.code LIMIT 100`,[p.organizationId,q?.trim()||null]);return {data:r.rows};
 }
 async event(b:string,id:string,p:AuthPrincipal,x:CommercialCustomerEventDto,correlation:string){
  await this.access(b,p,'credit.customer.manage');
  if(!uuid(id)||!uuid(x.commandId)||!['activate','suspend','limit','terms'].includes(x.kind)||!txt(x.reason,10,500)
   ||(x.kind==='limit'? !money(x.newLimitUsd)||x.newTermsDays!==undefined:
      x.kind==='terms'?!positiveInt(x.newTermsDays)||Number(x.newTermsDays)>120||x.newLimitUsd!==undefined:
      x.newLimitUsd!==undefined||x.newTermsDays!==undefined))
   throw new BadRequestException('Cambio de cuenta inválido.');
  const hash=digest({id,kind:x.kind,limit:x.newLimitUsd??null,terms:x.newTermsDays??null,reason:x.reason.trim()});
  return this.write(b,p,correlation,'credit.customer.changed','commercial_customer_event',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['credit-event:'+p.organizationId+':'+x.commandId]);
   const old=await c.query<{id:string;customer_id:string;request_hash:string;changed_by:string}>('SELECT id,customer_id,request_hash,changed_by FROM commercial_customer_events WHERE organization_id=$1 AND command_id=$2',[p.organizationId,x.commandId]);
   if(old.rows[0]){
    if(old.rows[0].customer_id!==id||old.rows[0].request_hash!==hash||old.rows[0].changed_by!==p.userId)throw new ConflictException('Comando de cuenta reutilizado.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id,customerId:id},replay:true};
   }
   const r=await c.query<{id:string}>(`INSERT INTO commercial_customer_events(organization_id,customer_id,kind,new_limit_usd,new_terms_days,reason,command_id,request_hash,changed_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
    [p.organizationId,id,x.kind,x.newLimitUsd??null,x.newTermsDays??null,x.reason.trim(),x.commandId,hash,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,customerId:id,kind:x.kind}};
  });
 }
 async buyer(b:string,id:string,p:AuthPrincipal,x:AddCommercialBuyerDto,correlation:string){
  await this.access(b,p,'credit.customer.manage');
  if(!uuid(id)||!(/^[A-Z0-9_-]{2,30}$/).test(x.buyerCode)||!txt(x.fullName,3,160))throw new BadRequestException('Comprador inválido.');
  return this.write(b,p,correlation,'credit.buyer.added','commercial_authorized_buyer',async c=>{
   const r=await c.query<{id:string}>(`INSERT INTO commercial_authorized_buyers(organization_id,customer_id,buyer_code,full_name,created_by)
    VALUES($1,$2,$3,$4,$5) RETURNING id`,[p.organizationId,id,x.buyerCode,x.fullName.trim(),p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,customerId:id,buyerCode:x.buyerCode}};
  });
 }
 async buyerAccess(b:string,id:string,buyer:string,p:AuthPrincipal,x:ChangeCommercialBuyerDto,correlation:string){
  await this.access(b,p,'credit.customer.manage');
  if(!uuid(id)||!uuid(buyer)||!uuid(x.commandId)||typeof x.active!=='boolean'||!txt(x.reason,10,500))
   throw new BadRequestException('Acceso del comprador inválido.');
  const hash=digest({id,buyer,active:x.active,reason:x.reason.trim()});
  return this.write(b,p,correlation,'credit.buyer.access_changed','commercial_buyer_event',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['buyer-access:'+p.organizationId+':'+x.commandId]);
   const old=await c.query<{id:string;customer_id:string;buyer_id:string;request_hash:string;changed_by:string}>('SELECT id,customer_id,buyer_id,request_hash,changed_by FROM commercial_buyer_events WHERE organization_id=$1 AND command_id=$2',[p.organizationId,x.commandId]);
   if(old.rows[0]){
    if(old.rows[0].customer_id!==id||old.rows[0].buyer_id!==buyer||old.rows[0].request_hash!==hash||old.rows[0].changed_by!==p.userId)
     throw new ConflictException('Comando de comprador reutilizado.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id,buyerId:buyer,active:x.active},replay:true};
   }
   const r=await c.query<{id:string}>(`INSERT INTO commercial_buyer_events(organization_id,customer_id,buyer_id,active,reason,command_id,request_hash,changed_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
    [p.organizationId,id,buyer,x.active,x.reason.trim(),x.commandId,hash,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,buyerId:buyer,active:x.active}};
  });
 }
 async statement(b:string,id:string,p:AuthPrincipal){
  await this.access(b,p,'credit.statement.read');if(!uuid(id))throw new BadRequestException('Cuenta inválida.');
  const c=await this.pool.query('SELECT id,code,legal_name,credit_limit_usd,terms_days,active FROM commercial_customers WHERE id=$1 AND organization_id=$2',[id,p.organizationId]);
  if(!c.rows[0])throw new NotFoundException('Cuenta fuera de organización.');
  const charges=await this.pool.query(`SELECT s.id,s.sale_id AS "saleId",s.branch_id AS "branchId",s.amount_usd AS "amountUsd",
   s.received_usd AS "receivedUsd",s.outstanding_usd AS "outstandingUsd",s.due_on AS "dueOn",s.charged_at AS "chargedAt"
   FROM commercial_account_statement s WHERE s.customer_id=$1 ORDER BY s.charged_at DESC,s.id DESC LIMIT 200`,[id]);
  const receipts=await this.pool.query(`SELECT r.id,r.charge_id AS "chargeId",r.amount_usd AS "amountUsd",r.method,
   r.evidence_reference AS "evidenceReference",r.recorded_at AS "recordedAt",
   CASE WHEN r.method='cash' THEN 'confirmed' ELSE coalesce(v.outcome,'pending') END AS status
   FROM commercial_credit_receipts r JOIN commercial_credit_charges c ON c.id=r.charge_id
   LEFT JOIN commercial_bank_verifications v ON v.receipt_id=r.id
   WHERE c.customer_id=$1 ORDER BY r.recorded_at DESC,r.id DESC LIMIT 200`,[id]);
  const buyers=await this.pool.query('SELECT id,buyer_code AS "buyerCode",full_name AS "fullName",active FROM commercial_authorized_buyers WHERE customer_id=$1 ORDER BY buyer_code',[id]);
  return {data:{...c.rows[0],charges:charges.rows,receipts:receipts.rows,buyers:buyers.rows}};
 }
 async charge(b:string,sale:string,p:AuthPrincipal,x:ChargeCommercialSaleDto,correlation:string){
  await this.access(b,p,'credit.sale.charge');
  if(!uuid(sale)||!uuid(x.commandId)||!uuid(x.customerId)||!uuid(x.buyerId)||!txt(x.buyerEvidence,5,200))
   throw new BadRequestException('Cargo a crédito inválido.');
  const hash=digest({b,sale,customer:x.customerId,buyer:x.buyerId,evidence:x.buyerEvidence.trim()});
  return this.write(b,p,correlation,'credit.sale.charged','commercial_credit_charge',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['credit-charge-command:'+p.organizationId+':'+x.commandId]);
   const old=await c.query<{id:string;request_hash:string;charged_by:string;branch_id:string}>('SELECT id,request_hash,charged_by,branch_id FROM commercial_credit_charges WHERE organization_id=$1 AND command_id=$2',[p.organizationId,x.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].charged_by!==p.userId||old.rows[0].branch_id!==b)throw new ConflictException('Comando de cargo reutilizado.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id,saleId:sale},replay:true};
   }
   const r=await c.query<{id:string}>(`INSERT INTO commercial_credit_charges(organization_id,branch_id,customer_id,buyer_id,sale_id,amount_usd,due_on,buyer_evidence,command_id,request_hash,charged_by,correlation_id)
    SELECT $1,$2,$3,$4,s.id,s.total_usd,(s.occurred_at AT TIME ZONE 'America/El_Salvador')::date+c.terms_days,$5,$6,$7,$8,$9
    FROM sales s JOIN commercial_customers c ON c.id=$3 AND c.organization_id=$1
    WHERE s.id=$10 AND s.organization_id=$1 AND s.branch_id=$2 RETURNING id`,
    [p.organizationId,b,x.customerId,x.buyerId,x.buyerEvidence.trim(),x.commandId,hash,p.userId,correlation,sale]);
   if(!r.rows[0])throw new NotFoundException('Venta fuera de sucursal.');
   return {id:r.rows[0].id,data:{id:r.rows[0].id,saleId:sale,customerId:x.customerId}};
  });
 }
 async receipt(b:string,id:string,p:AuthPrincipal,x:ReceiveCommercialCreditDto,correlation:string){
  await this.access(b,p,'credit.receipt.record');
  if(!uuid(id)||!uuid(x.commandId)||!money(x.amountUsd)||!['cash','bank_reported'].includes(x.method)
   ||(x.method==='cash'?!uuid(x.cashSessionId):x.cashSessionId!==undefined)||!txt(x.evidenceReference,5,200))
   throw new BadRequestException('Abono inválido.');
  const hash=digest({b,id,amount:x.amountUsd,method:x.method,session:x.cashSessionId??null,evidence:x.evidenceReference.trim()});
  return this.write(b,p,correlation,'credit.receipt.recorded','commercial_credit_receipt',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['credit-receipt-command:'+p.organizationId+':'+x.commandId]);
   const old=await c.query<{id:string;request_hash:string;recorded_by:string;branch_id:string}>('SELECT id,request_hash,recorded_by,branch_id FROM commercial_credit_receipts WHERE organization_id=$1 AND command_id=$2',[p.organizationId,x.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].recorded_by!==p.userId||old.rows[0].branch_id!==b)throw new ConflictException('Comando de abono reutilizado.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id,chargeId:id},replay:true};
   }
   const r=await c.query<{id:string}>(`INSERT INTO commercial_credit_receipts(organization_id,branch_id,charge_id,amount_usd,method,cash_session_id,evidence_reference,command_id,request_hash,recorded_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
    [p.organizationId,b,id,x.amountUsd,x.method,x.cashSessionId??null,x.evidenceReference.trim(),x.commandId,hash,p.userId,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,chargeId:id,amountUsd:x.amountUsd,method:x.method}};
  });
 }
 async verify(b:string,id:string,p:AuthPrincipal,x:VerifyCommercialBankDto,correlation:string){
  await this.access(b,p,'credit.bank.verify');
  if(!uuid(id)||!uuid(x.commandId)||!['confirmed','rejected'].includes(x.outcome)||!txt(x.reason,10,500))
   throw new BadRequestException('Verificación bancaria inválida.');
  const hash=digest({b,id,outcome:x.outcome,reason:x.reason.trim()});
  return this.write(b,p,correlation,'credit.bank.verified','commercial_bank_verification',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['credit-bank-command:'+p.organizationId+':'+x.commandId]);
   const old=await c.query<{receipt_id:string;request_hash:string;verified_by:string;branch_id:string}>('SELECT receipt_id,request_hash,verified_by,branch_id FROM commercial_bank_verifications WHERE organization_id=$1 AND command_id=$2',[p.organizationId,x.commandId]);
   if(old.rows[0]){
    if(old.rows[0].receipt_id!==id||old.rows[0].request_hash!==hash||old.rows[0].verified_by!==p.userId||old.rows[0].branch_id!==b)
     throw new ConflictException('Comando de verificación reutilizado.');
    return {id,data:{receiptId:id,outcome:x.outcome},replay:true};
   }
   await c.query(`INSERT INTO commercial_bank_verifications(receipt_id,organization_id,branch_id,outcome,reason,command_id,request_hash,verified_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[id,p.organizationId,b,x.outcome,x.reason.trim(),x.commandId,hash,p.userId,correlation]);
   return {id,data:{receiptId:id,outcome:x.outcome}};
  });
 }
}
function uuid(v:unknown):v is string{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);}
function txt(v:unknown,min:number,max:number){return typeof v==='string'&&v.trim().length>=min&&v.trim().length<=max;}
function money(v:unknown){return typeof v==='string'&&/^[1-9][0-9]{0,8}(\.[0-9]{1,2})?$/.test(v);}
function positiveInt(v:unknown){return typeof v==='string'&&/^[1-9][0-9]{0,2}$/.test(v);}
function digest(v:unknown){return createHash('sha256').update(JSON.stringify(v)).digest('hex');}
