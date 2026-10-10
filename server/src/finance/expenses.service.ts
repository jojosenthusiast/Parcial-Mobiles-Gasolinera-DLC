import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { Decimal } from 'decimal.js';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { CreateExpenseCategoryDto, CreateExpenseDto, DecideExpenseDto, PayExpenseDto } from './expenses.dto.js';

@Injectable()
export class ExpensesService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}
 private async access(branch:string,p:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(p,branch)).includes(permission))throw new ForbiddenException('Permiso financiero insuficiente.');
  const r=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3',[branch,p.organizationId,'active']);
  if(!r.rows[0])throw new NotFoundException('Sucursal fuera de tu ámbito.');
 }
 private async write(branch:string,p:AuthPrincipal,correlation:string,action:string,type:string,
  fn:(c:PoolClient)=>Promise<{id:string;data:object;replay?:boolean}>){
  const c=await this.pool.connect();
  try{
   await c.query('BEGIN');const value=await fn(c);
   if(!value.replay)await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,action,entityType:type,entityId:value.id,after:value.data});
   await c.query('COMMIT');return {data:{...value.data,idempotentReplay:!!value.replay}};
  }catch(error){
   await c.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514','40001','55000'].includes((error as {code?:string}).code??''))throw new ConflictException('Gasto duplicado, estado o saldo incompatible.');
   if((error as {code?:string}).code==='23503')throw new NotFoundException('Referencia fuera de la organización.');
   throw error;
  }finally{c.release();}
 }
 async category(branch:string,p:AuthPrincipal,input:CreateExpenseCategoryDto,correlation:string){
  await this.access(branch,p,'expense.create');
  if(!/^[A-Z0-9_]{2,30}$/.test(input.code)||!validText(input.name,2,100)||!['operating','capital','financial'].includes(input.class))
   throw new BadRequestException('Categoría inválida.');
  return this.write(branch,p,correlation,'expense.category.created','expense_category',async c=>{
   const r=await c.query<{id:string}>(`INSERT INTO expense_categories(organization_id,code,name,class,created_by)
    VALUES($1,$2,$3,$4,$5) RETURNING id`,[p.organizationId,input.code,input.name.trim(),input.class,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,code:input.code,name:input.name.trim(),class:input.class}};
  });
 }
 async categories(branch:string,p:AuthPrincipal){
  await this.access(branch,p,'finance.cost.read');
  const r=await this.pool.query('SELECT id,code,name,class,active FROM expense_categories WHERE organization_id=$1 ORDER BY code',[p.organizationId]);
  return {data:r.rows};
 }
 async results(branch:string,p:AuthPrincipal,from:string,to:string){
  await this.access(branch,p,'finance.margin.read');
  if(!date(from)||!date(to)||from>to||Date.parse(to)-Date.parse(from)>366*86400000)
   throw new BadRequestException('Periodo de resultados inválido (máximo 366 días).');
  const scope=[p.organizationId,branch,from,to];
  const [sales,returns,expenses,fuelLoss,storeLoss,recoveries,serviceMaterials,pendingServices]=await Promise.all([
   this.pool.query(`SELECT l.kind,sum(l.total_usd)::text AS revenue,
    sum(l.cost_usd) FILTER(WHERE l.cost_quality='known')::text AS known_cost,
    count(*) FILTER(WHERE l.cost_quality<>'known')::integer AS unknown_cost_lines,
    count(*)::integer AS lines
    FROM sale_lines l JOIN sales s ON s.id=l.sale_id WHERE s.organization_id=$1 AND s.branch_id=$2
     AND (s.occurred_at AT TIME ZONE 'America/El_Salvador')::date BETWEEN $3 AND $4 GROUP BY l.kind`,scope),
   this.pool.query(`SELECT coalesce(sum(r.amount_eligible_usd),0)::text AS amount,
    sum(round(r.quantity_units*l.unit_cost_usd,2)) FILTER(WHERE l.unit_cost_usd IS NOT NULL)::text AS known_cost,
    count(*) FILTER(WHERE l.unit_cost_usd IS NULL)::integer AS unknown_cost_lines
    FROM store_returns r JOIN pos_stock_lots l ON l.id=r.source_lot_id
    WHERE r.organization_id=$1 AND r.branch_id=$2
    AND (r.accepted_at AT TIME ZONE 'America/El_Salvador')::date BETWEEN $3 AND $4`,scope),
   this.pool.query(`SELECT c.class,sum(e.amount_usd)::text AS amount,count(*)::integer AS claims
    FROM expense_claims e JOIN expense_decisions d ON d.expense_id=e.id AND d.outcome='approved'
    JOIN expense_categories c ON c.id=e.category_id
    WHERE e.organization_id=$1 AND e.branch_id=$2 AND e.incurred_on BETWEEN $3 AND $4 GROUP BY c.class`,scope),
   this.pool.query(`SELECT coalesce(sum(a.historical_cost_usd),0)::text AS known_cost,
    count(*) FILTER(WHERE a.cost_quality<>'known')::integer AS unknown_cost_lines
    FROM incident_loss_approvals x JOIN incident_impact_assessments a ON a.id=x.assessment_id
    WHERE x.organization_id=$1 AND x.branch_id=$2 AND (x.approved_at AT TIME ZONE 'America/El_Salvador')::date BETWEEN $3 AND $4
     AND x.movement_id IS NOT NULL`,scope),
   this.pool.query(`SELECT coalesce(sum(cost_usd),0)::text AS known_cost,
    count(*) FILTER(WHERE cost_quality<>'known')::integer AS unknown_cost_lines
    FROM store_stock_loss_classifications WHERE organization_id=$1 AND branch_id=$2
     AND (classified_at AT TIME ZONE 'America/El_Salvador')::date BETWEEN $3 AND $4`,scope),
   this.pool.query(`SELECT coalesce(sum(amount_usd),0)::text AS amount FROM incident_recovery_receipts
    WHERE organization_id=$1 AND branch_id=$2
    AND (received_at AT TIME ZONE 'America/El_Salvador')::date BETWEEN $3 AND $4`,scope),
   this.pool.query(`SELECT coalesce(sum(-m.delta_units*l.unit_cost_usd) FILTER(WHERE l.unit_cost_usd IS NOT NULL),0)::text AS known_cost,
    count(*) FILTER(WHERE l.unit_cost_usd IS NULL)::integer AS unknown_cost_lines
    FROM pos_stock_movements m JOIN service_fulfillments f ON f.id=m.service_fulfillment_id
    JOIN pos_stock_lots l ON l.id=m.lot_id WHERE m.kind='service_use' AND m.organization_id=$1 AND m.branch_id=$2
    AND (f.fulfilled_at AT TIME ZONE 'America/El_Salvador')::date BETWEEN $3 AND $4`,scope),
   this.pool.query(`SELECT count(DISTINCT l.id)::integer AS count FROM sale_lines l JOIN sales s ON s.id=l.sale_id
    JOIN service_material_requirements req ON req.offer_version_id=l.offer_version_id
    LEFT JOIN service_fulfillments f ON f.sale_line_id=l.id
    WHERE s.organization_id=$1 AND s.branch_id=$2
     AND (s.occurred_at AT TIME ZONE 'America/El_Salvador')::date BETWEEN $3 AND $4 AND l.kind='service'
     AND f.id IS NULL`,scope),
  ]);
  const sum=(v:unknown)=>new Decimal(String(v??'0'));
  const byKind=Object.fromEntries(sales.rows.map(x=>[x.kind,{revenueUsd:String(x.revenue),knownCostUsd:String(x.known_cost??'0'),
   unknownCostLines:Number(x.unknown_cost_lines),lines:Number(x.lines)}]));
  const grossRevenue=sales.rows.reduce((a,x)=>a.plus(sum(x.revenue)),new Decimal(0));
  const knownCogs=sales.rows.reduce((a,x)=>a.plus(sum(x.known_cost)),new Decimal(0)).minus(sum(returns.rows[0]?.known_cost));
  const netRevenue=grossRevenue.minus(sum(returns.rows[0]?.amount));
  const operatingExpenses=expenses.rows.filter(x=>x.class==='operating').reduce((a,x)=>a.plus(sum(x.amount)),new Decimal(0));
  const fuelLossCost=sum(fuelLoss.rows[0]?.known_cost),storeLossCost=sum(storeLoss.rows[0]?.known_cost),recovered=sum(recoveries.rows[0]?.amount);
  const unknownCostLines=sales.rows.reduce((a,x)=>a+Number(x.unknown_cost_lines),0)+Number(returns.rows[0]?.unknown_cost_lines??0)
   +Number(fuelLoss.rows[0]?.unknown_cost_lines??0)+Number(storeLoss.rows[0]?.unknown_cost_lines??0)
   +Number(serviceMaterials.rows[0]?.unknown_cost_lines??0)+Number(pendingServices.rows[0]?.count??0);
  const serviceMaterialCost=sum(serviceMaterials.rows[0]?.known_cost);
  const knownOperatingResult=netRevenue.minus(knownCogs).minus(serviceMaterialCost).minus(operatingExpenses).minus(fuelLossCost).minus(storeLossCost).plus(recovered);
  return {data:{branchId:branch,from,to,currency:'USD',basis:'sales_accrual',
   byKind,grossRevenueUsd:grossRevenue.toFixed(2),acceptedStoreReturnsUsd:sum(returns.rows[0]?.amount).toFixed(2),
   netRevenueUsd:netRevenue.toFixed(2),knownCostOfGoodsUsd:knownCogs.toFixed(2),
   grossMarginKnownUsd:unknownCostLines===0?netRevenue.minus(knownCogs).minus(serviceMaterialCost).toFixed(2):null,
   operatingExpensesUsd:operatingExpenses.toFixed(2),
   capitalOutlaysUsd:expenses.rows.filter(x=>x.class==='capital').reduce((a,x)=>a.plus(sum(x.amount)),new Decimal(0)).toFixed(2),
   financialExpensesUsd:expenses.rows.filter(x=>x.class==='financial').reduce((a,x)=>a.plus(sum(x.amount)),new Decimal(0)).toFixed(2),
   serviceMaterialsKnownCostUsd:serviceMaterialCost.toFixed(2),pendingServiceMaterialLines:Number(pendingServices.rows[0]?.count??0),
   fuelLossKnownCostUsd:fuelLossCost.toFixed(2),storeLossKnownCostUsd:storeLossCost.toFixed(2),recoveriesReceivedUsd:recovered.toFixed(2),
   unknownCostLines,operatingResultUsd:unknownCostLines===0?knownOperatingResult.toFixed(2):null,
   partialKnownResultUsd:knownOperatingResult.toFixed(2),
   taxStatus:'unconfigured',paymentStatus:'separate_from_accrual'}};
 }
 async create(branch:string,p:AuthPrincipal,input:CreateExpenseDto,correlation:string){
  await this.access(branch,p,'expense.create');
  if(!uuid(input.commandId)||!uuid(input.categoryId)||!validText(input.costCenter,2,80)||!validText(input.invoiceReference,3,120)
   ||!money(input.amountUsd)||input.taxUsd!==undefined&&!nonnegativeMoney(input.taxUsd)
   ||Number(input.taxUsd??0)>Number(input.amountUsd)||!date(input.incurredOn)||input.dueOn!==undefined&&!date(input.dueOn)
   ||!['other','maintenance','incident','purchase_fee'].includes(input.sourceKind)
   ||(input.sourceKind==='other'?input.sourceId!==undefined:!uuid(input.sourceId))
   ||input.supplierId!==undefined&&!uuid(input.supplierId)||!validText(input.description,10,500)||!validText(input.evidenceReference,3,300))
   throw new BadRequestException('Datos del gasto inválidos.');
  const normalized={branch,categoryId:input.categoryId,costCenter:input.costCenter.trim(),supplierId:input.supplierId??null,
   invoiceReference:input.invoiceReference.trim(),amountUsd:input.amountUsd,taxUsd:input.taxUsd??null,
   incurredOn:input.incurredOn,dueOn:input.dueOn??null,sourceKind:input.sourceKind,sourceId:input.sourceId??null,
   description:input.description.trim(),evidenceReference:input.evidenceReference.trim()};
  const hash=digest(normalized);
  return this.write(branch,p,correlation,'expense.claim.created','expense_claim',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['expense-command:'+p.organizationId+':'+input.commandId]);
   const old=await c.query<{id:string;request_hash:string;created_by:string;branch_id:string}>('SELECT id,request_hash,created_by,branch_id FROM expense_claims WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].created_by!==p.userId||old.rows[0].branch_id!==branch)throw new ConflictException('Comando de gasto reutilizado.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id,status:'pending'},replay:true};
   }
   const r=await c.query<{id:string}>(`INSERT INTO expense_claims(organization_id,branch_id,category_id,cost_center,supplier_id,invoice_reference,
    amount_usd,tax_usd,incurred_on,due_on,source_kind,source_id,description,evidence_reference,command_id,request_hash,created_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18) RETURNING id`,
    [p.organizationId,branch,normalized.categoryId,normalized.costCenter,normalized.supplierId,normalized.invoiceReference,
     normalized.amountUsd,normalized.taxUsd,normalized.incurredOn,normalized.dueOn,normalized.sourceKind,normalized.sourceId,
     normalized.description,normalized.evidenceReference,input.commandId,hash,p.userId,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,status:'pending',amountUsd:normalized.amountUsd}};
  });
 }
 async list(branch:string,p:AuthPrincipal,q:{from?:string;to?:string;status?:string;q?:string;cursor?:string;limit?:string}){
  await this.access(branch,p,'finance.cost.read');
  const from=q.from??'1970-01-01',to=q.to??'9999-12-31',limit=q.limit===undefined?25:Number(q.limit);
  const term=q.q?.trim()??'';
  const escapedTerm=term.replaceAll('!','!!').replaceAll('%','!%').replaceAll('_','!_');
  if(!date(from)||!date(to)||from>to||!Number.isInteger(limit)||limit<1||limit>100||q.cursor!==undefined&&!uuid(q.cursor)
   ||q.status!==undefined&&!['pending','approved','rejected'].includes(q.status)||term.length>100)throw new BadRequestException('Filtro inválido.');
  const r=await this.pool.query(`SELECT e.id,e.incurred_on AS "incurredOn",e.invoice_reference AS "invoiceReference",e.amount_usd AS "amountUsd",
   e.cost_center AS "costCenter",c.name AS "category",coalesce(d.outcome,'pending') AS status,
   coalesce((SELECT sum(x.amount_usd) FROM expense_disbursements x WHERE x.expense_id=e.id),0) AS "recordedDisbursementsUsd"
   FROM expense_claims e JOIN expense_categories c ON c.id=e.category_id LEFT JOIN expense_decisions d ON d.expense_id=e.id
   WHERE e.organization_id=$1 AND e.branch_id=$2 AND e.incurred_on BETWEEN $3 AND $4
    AND ($5::text IS NULL OR coalesce(d.outcome,'pending')=$5) AND ($6::uuid IS NULL OR e.id>$6)
    AND ($7::text IS NULL OR concat_ws(' ',e.invoice_reference,e.cost_center,e.description,c.name) ILIKE $7 ESCAPE '!')
   ORDER BY e.id LIMIT $8`,[p.organizationId,branch,from,to,q.status??null,q.cursor??null,term?`%${escapedTerm}%`:null,limit+1]);
  const data=r.rows.slice(0,limit);return {data,meta:{limit,nextCursor:r.rows.length>limit?data.at(-1)!.id:null}};
 }
 async detail(branch:string,id:string,p:AuthPrincipal){
  await this.access(branch,p,'finance.cost.read');
  if(!uuid(id))throw new BadRequestException('Identificador inválido.');
  const e=await this.pool.query(`SELECT e.*,c.code AS category_code,c.name AS category_name,d.outcome,d.reason AS decision_reason,
   d.decided_by,d.decided_at FROM expense_claims e JOIN expense_categories c ON c.id=e.category_id
   LEFT JOIN expense_decisions d ON d.expense_id=e.id WHERE e.id=$1 AND e.organization_id=$2 AND e.branch_id=$3`,[id,p.organizationId,branch]);
  if(!e.rows[0])throw new NotFoundException('Gasto fuera de sucursal.');
  const payments=await this.pool.query(`SELECT id,amount_usd,method,cash_session_id,evidence_reference,recorded_by,recorded_at
   FROM expense_disbursements WHERE expense_id=$1 ORDER BY recorded_at,id`,[id]);
  return {data:{...e.rows[0],disbursements:payments.rows}};
 }
 async decide(branch:string,id:string,p:AuthPrincipal,input:DecideExpenseDto,correlation:string){
  await this.access(branch,p,'expense.approve');
  if(!uuid(id)||!uuid(input.commandId)||!['approved','rejected'].includes(input.outcome)||!validText(input.reason,10,500))
   throw new BadRequestException('Decisión inválida.');
  const hash=digest({branch,id,outcome:input.outcome,reason:input.reason.trim()});
  return this.write(branch,p,correlation,'expense.claim.decided','expense_decision',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['expense-decision:'+p.organizationId+':'+input.commandId]);
   const old=await c.query<{expense_id:string;request_hash:string;decided_by:string;branch_id:string;outcome:string}>('SELECT expense_id,request_hash,decided_by,branch_id,outcome FROM expense_decisions WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].decided_by!==p.userId||old.rows[0].branch_id!==branch||old.rows[0].expense_id!==id)throw new ConflictException('Comando de aprobación reutilizado.');
    return {id,data:{id,status:old.rows[0].outcome},replay:true};
   }
   await c.query(`INSERT INTO expense_decisions(expense_id,organization_id,branch_id,outcome,reason,command_id,request_hash,decided_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[id,p.organizationId,branch,input.outcome,input.reason.trim(),input.commandId,hash,p.userId,correlation]);
   return {id,data:{id,status:input.outcome}};
  });
 }
 async pay(branch:string,id:string,p:AuthPrincipal,input:PayExpenseDto,correlation:string){
  await this.access(branch,p,'expense.pay');
  if(!uuid(id)||!uuid(input.commandId)||!money(input.amountUsd)||!['cash','bank_reported'].includes(input.method)
   ||(input.method==='cash'?!uuid(input.cashSessionId):input.cashSessionId!==undefined||!validText(input.evidenceReference,3,200)))
   throw new BadRequestException('Desembolso inválido.');
  const normalized={branch,id,amountUsd:input.amountUsd,method:input.method,cashSessionId:input.cashSessionId??null,evidenceReference:input.evidenceReference?.trim()??null};
  const hash=digest(normalized);
  return this.write(branch,p,correlation,'expense.disbursement.recorded','expense_disbursement',async c=>{
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['expense-pay-command:'+p.organizationId+':'+input.commandId]);
   const old=await c.query<{id:string;request_hash:string;recorded_by:string;branch_id:string}>('SELECT id,request_hash,recorded_by,branch_id FROM expense_disbursements WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].recorded_by!==p.userId||old.rows[0].branch_id!==branch)throw new ConflictException('Comando de pago reutilizado.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id,expenseId:id},replay:true};
   }
   const r=await c.query<{id:string}>(`INSERT INTO expense_disbursements(organization_id,branch_id,expense_id,amount_usd,method,cash_session_id,
    evidence_reference,command_id,request_hash,recorded_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
    [p.organizationId,branch,id,normalized.amountUsd,normalized.method,normalized.cashSessionId,normalized.evidenceReference,input.commandId,hash,p.userId,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,expenseId:id,amountUsd:normalized.amountUsd,method:normalized.method}};
  });
 }
}
function uuid(v:unknown):v is string{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);}
function validText(v:unknown,min:number,max:number){return typeof v==='string'&&v.trim().length>=min&&v.trim().length<=max;}
function money(v:unknown){return typeof v==='string'&&/^[1-9][0-9]{0,8}(\.[0-9]{1,2})?$/.test(v);}
function nonnegativeMoney(v:unknown){return typeof v==='string'&&/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/.test(v);}
function date(v:unknown){return typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&!Number.isNaN(Date.parse(v))&&new Date(v).toISOString().slice(0,10)===v;}
function digest(v:unknown){return createHash('sha256').update(JSON.stringify(v)).digest('hex');}
