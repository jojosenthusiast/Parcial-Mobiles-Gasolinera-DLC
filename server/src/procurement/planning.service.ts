import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Decimal } from 'decimal.js';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { ComparePurchaseDto, DecidePurchaseScenarioDto, DemandQueryDto, PublishSupplierQuoteDto, SavePurchaseScenarioDto } from './planning.dto.js';
@Injectable()
export class PlanningService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}
 async publishQuote(branch:string,p:AuthPrincipal,x:PublishSupplierQuoteDto,correlation:string){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.quote.manage'))throw new ForbiddenException('No puedes registrar cotizaciones.');
  const b=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3',[branch,p.organizationId,'active']);
  if(!b.rows[0])throw new NotFoundException('Sucursal fuera de tu ámbito.');
  if(!uuid(x.supplierId)||!uuid(x.fuelProductId)||!['liter','us_gallon'].includes(x.unit)
   ||!positiveDecimal(x.unitPriceUsd,8)||!nonnegativeDecimal(x.transportUsd,2)||!nonnegativeDecimal(x.financingUsd,2)
   ||!nonnegativeDecimal(x.minimumDeliveryL,3)||!Number.isInteger(Number(x.leadDays))||Number(x.leadDays)>120
   ||!['confirmed','indicative'].includes(x.confidence)||!x.documentReference?.trim()
   ||!Number.isFinite(Date.parse(x.validFrom))||!Number.isFinite(Date.parse(x.validUntil))
   ||Date.parse(x.validUntil)<=Date.parse(x.validFrom))throw new BadRequestException('Cotización inválida.');
  const c=await this.pool.connect();
  try{await c.query('BEGIN');
   const last=await c.query<{version:number}>(`SELECT version FROM supplier_fuel_quotes WHERE supplier_id=$1
    AND fuel_product_id=$2 AND organization_id=$3 ORDER BY version DESC LIMIT 1`,[x.supplierId,x.fuelProductId,p.organizationId]);
   const r=await c.query<{id:string}>(`INSERT INTO supplier_fuel_quotes(organization_id,supplier_id,fuel_product_id,version,unit,unit_price_usd,
    transport_usd,financing_usd,minimum_delivery_l,lead_days,valid_from,valid_until,confidence,document_reference,recorded_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING id`,
    [p.organizationId,x.supplierId,x.fuelProductId,(last.rows[0]?.version??0)+1,x.unit,x.unitPriceUsd,x.transportUsd,
     x.financingUsd,x.minimumDeliveryL,x.leadDays,x.validFrom,x.validUntil,x.confidence,x.documentReference.trim(),p.userId]);
   await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,action:'purchase.quote.published',
    entityType:'supplier_fuel_quote',entityId:r.rows[0]!.id,after:{supplierId:x.supplierId,fuelProductId:x.fuelProductId,confidence:x.confidence}});
   await c.query('COMMIT');return {data:{id:r.rows[0]!.id,version:(last.rows[0]?.version??0)+1}};
  }catch(error){await c.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514'].includes((error as {code?:string}).code??''))throw new ConflictException('Proveedor, versión o vigencia de cotización incompatible.');
   throw error;
  }finally{c.release();}
 }
 async quotes(branch:string,p:AuthPrincipal,fuel:string){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.read'))throw new ForbiddenException('No puedes consultar cotizaciones.');
  if(!uuid(fuel))throw new BadRequestException('Combustible inválido.');
  const b=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3',[branch,p.organizationId,'active']);
  if(!b.rows[0])throw new NotFoundException('Sucursal fuera de tu ámbito.');
  const r=await this.pool.query(`SELECT q.*,s.legal_name AS "supplierName" FROM supplier_fuel_quotes q
   JOIN suppliers s ON s.id=q.supplier_id WHERE q.organization_id=$1 AND q.fuel_product_id=$2
    AND EXISTS(SELECT 1 FROM branch_fuel_offers o WHERE o.branch_id=$3 AND o.fuel_product_id=q.fuel_product_id AND o.status='active')
   ORDER BY q.recorded_at DESC,q.id DESC LIMIT 100`,[p.organizationId,fuel,branch]);
  return {data:r.rows};
 }
 async compare(branch:string,p:AuthPrincipal,x:ComparePurchaseDto){
  if(!uuid(x.currentQuoteId)||x.futureQuoteId!==undefined&&!uuid(x.futureQuoteId)||!uuid(x.tankId)
   ||!uuid(x.fuelProductId)||!positiveDecimal(x.quantityLiters,3)
   ||!['7','14','30'].includes(x.days)||!Number.isInteger(Number(x.safetyDays))||Number(x.safetyDays)>120)
   throw new BadRequestException('Escenario de compra inválido.');
  const q=await this.pool.query<{id:string;supplier_id:string;fuel_product_id:string;unit:string;unit_price_usd:string;
   transport_usd:string;financing_usd:string;minimum_delivery_l:string;lead_days:number;valid_from:string;valid_until:string;confidence:string}>(`SELECT id,supplier_id,fuel_product_id,unit,unit_price_usd,transport_usd,financing_usd,minimum_delivery_l,
    lead_days,valid_from,valid_until,confidence FROM supplier_fuel_quotes WHERE organization_id=$1 AND id=ANY($2::uuid[])`,
   [p.organizationId,[x.currentQuoteId,...(x.futureQuoteId?[x.futureQuoteId]:[])]]);
  const current=q.rows.find(v=>v.id===x.currentQuoteId),future=q.rows.find(v=>v.id===x.futureQuoteId);
  if(!current||current.fuel_product_id!==x.fuelProductId||x.futureQuoteId&&!future||future&&future.fuel_product_id!==x.fuelProductId)
   throw new NotFoundException('Cotización fuera de producto u organización.');
  const tank=await this.pool.query<{safe_fill_limit_l:string;on_hand_l:string|null;status:string}>(`SELECT t.safe_fill_limit_l,bal.on_hand_l,t.status
   FROM tanks t LEFT JOIN tank_inventory_balances bal ON bal.tank_id=t.id
   WHERE t.id=$1 AND t.organization_id=$2 AND t.branch_id=$3 AND t.fuel_product_id=$4`,
   [x.tankId,p.organizationId,branch,x.fuelProductId]);
  if(!tank.rows[0]||tank.rows[0].status!=='active'||tank.rows[0].on_hand_l===null)
   throw new ConflictException('Tanque sin inventario válido o fuera de servicio.');
  const quantity=new Decimal(x.quantityLiters),capacity=new Decimal(tank.rows[0].safe_fill_limit_l).minus(tank.rows[0].on_hand_l);
  if(quantity.gt(capacity))throw new ConflictException('La cantidad excede la capacidad segura libre del tanque.');
  const demand=await this.demand(branch,p,{fuelProductId:x.fuelProductId,days:x.days,supplierLeadDays:String(current.lead_days),safetyDays:x.safetyDays});
  const avg=demand.data.averageDailyLiters===null?null:new Decimal(demand.data.averageDailyLiters),usable=demand.data.stock.usableLiters===null?null:new Decimal(demand.data.stock.usableLiters);
  const now=Date.now();
  const calc=(quote:NonNullable<typeof current>)=>{
   const earliest=Math.max(now,Date.parse(quote.valid_from)),arrival=earliest+quote.lead_days*86400000;
   const valid=earliest<Date.parse(quote.valid_until)&&quantity.gte(quote.minimum_delivery_l);
   const cost=quantity.div(quote.unit==='us_gallon'?'3.785411784':'1').mul(quote.unit_price_usd)
    .plus(quote.transport_usd).plus(quote.financing_usd);
   const daysToArrival=(arrival-now)/86400000;
   const remaining=avg===null||usable===null?null:usable.minus(avg.mul(daysToArrival+Number(x.safetyDays)));
   return {quoteId:quote.id,supplierId:quote.supplier_id,confidence:quote.confidence,valid,leadDays:quote.lead_days,
    arrivalEstimate:new Date(arrival).toISOString(),minimumDeliveryLiters:quote.minimum_delivery_l,
    totalKnownUsd:cost.toFixed(2),remainingAtArrivalWithSafetyLiters:remaining?.toFixed(3)??null,
    stockoutRisk:remaining===null?'unknown':remaining.lte(0)?'high':'low'};
  };
  const buyNow=calc(current),buyLater=future?calc(future):null;
  buyNow.valid=buyNow.valid&&Date.parse(current.valid_from)<=now&&now<Date.parse(current.valid_until);
  const savings=buyLater?new Decimal(buyNow.totalKnownUsd).minus(buyLater.totalKnownUsd):null;
  const recommendation=!buyNow.valid?'no_valid_current_quote':buyNow.confidence!=='confirmed'?'verify_current_quote':
   buyNow.stockoutRisk==='high'?'expedite_delivery_both_options_risky':
   !buyLater?'buy_now_or_review':!buyLater.valid||buyLater.confidence!=='confirmed'?'future_unconfirmed':
   buyLater.stockoutRisk==='high'?'buy_now_supply_risk':buyLater.stockoutRisk==='unknown'?'insufficient_demand':
   savings?.gt(0)?'future_cheaper_if_conditions_hold':'buy_now_no_future_savings';
  return {data:{branchId:branch,fuelProductId:x.fuelProductId,tankId:x.tankId,quantityLiters:x.quantityLiters,
   capacityFreeLiters:capacity.toFixed(3),buyNow,buyLater,knownSavingsIfWaitUsd:savings?.toFixed(2)??null,
   recommendation,consumerReferenceNotUsed:true,demandCoveragePercent:demand.data.coveragePercent,
   demandQuality:demand.data.quality,lastSourceAt:demand.data.lastSourceAt}};
 }
 async save(branch:string,p:AuthPrincipal,x:SavePurchaseScenarioDto,correlation:string){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.create'))throw new ForbiddenException('No puedes registrar escenarios.');
  if(!uuid(x.commandId)||!uuid(x.quoteId)||!uuid(x.tankId)||!uuid(x.fuelProductId)||!positiveDecimal(x.quantityLiters,3)
   ||!['7','14','30'].includes(x.days)||!Number.isInteger(Number(x.safetyDays))||Number(x.safetyDays)>120)
   throw new BadRequestException('Escenario inválido.');
  const hash=digest({branch,quoteId:x.quoteId,tankId:x.tankId,fuelProductId:x.fuelProductId,
   quantityLiters:x.quantityLiters,days:x.days,safetyDays:x.safetyDays});
  const old=await this.pool.query<{id:string;request_hash:string;created_by:string;branch_id:string}>(`SELECT id,request_hash,created_by,branch_id
   FROM purchase_scenarios WHERE organization_id=$1 AND command_id=$2`,[p.organizationId,x.commandId]);
  if(old.rows[0]){
   if(old.rows[0].request_hash!==hash||old.rows[0].created_by!==p.userId||old.rows[0].branch_id!==branch)
    throw new ConflictException('Comando de escenario reutilizado.');
   return {data:{id:old.rows[0].id,idempotentReplay:true}};
  }
  const comparison=await this.compare(branch,p,{fuelProductId:x.fuelProductId,currentQuoteId:x.quoteId,
   tankId:x.tankId,quantityLiters:x.quantityLiters,days:x.days,safetyDays:x.safetyDays});
  if(!comparison.data.buyNow.valid||comparison.data.buyNow.confidence!=='confirmed')
   throw new ConflictException('La cotización confirmada no está vigente.');
  const c=await this.pool.connect();
  try{await c.query('BEGIN');
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['purchase-scenario:'+p.organizationId+':'+x.commandId]);
   const again=await c.query<{id:string;request_hash:string;created_by:string;branch_id:string}>(`SELECT id,request_hash,created_by,branch_id
    FROM purchase_scenarios WHERE organization_id=$1 AND command_id=$2`,[p.organizationId,x.commandId]);
   if(again.rows[0]){
    if(again.rows[0].request_hash!==hash||again.rows[0].created_by!==p.userId||again.rows[0].branch_id!==branch)
     throw new ConflictException('Comando de escenario reutilizado.');
    await c.query('COMMIT');return {data:{id:again.rows[0].id,idempotentReplay:true}};
   }
   const quote=await c.query<{valid_until:string}>(`SELECT valid_until FROM supplier_fuel_quotes WHERE id=$1 AND organization_id=$2`,[x.quoteId,p.organizationId]);
   const result=await c.query<{id:string}>(`INSERT INTO purchase_scenarios(organization_id,branch_id,fuel_product_id,tank_id,quote_id,quantity_l,
    snapshot,valid_until,command_id,request_hash,created_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$10,$11,$12) RETURNING id`,
    [p.organizationId,branch,x.fuelProductId,x.tankId,x.quoteId,x.quantityLiters,JSON.stringify(comparison.data),
     quote.rows[0]?.valid_until,x.commandId,hash,p.userId,correlation]);
   await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,
    action:'purchase.scenario.created',entityType:'purchase_scenario',entityId:result.rows[0]!.id,
    after:{quoteId:x.quoteId,quantityLiters:x.quantityLiters,recommendation:comparison.data.recommendation}});
   await c.query('COMMIT');return {data:{id:result.rows[0]!.id,idempotentReplay:false}};
  }catch(error){await c.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514'].includes((error as {code?:string}).code??''))throw new ConflictException('Capacidad o cotización cambiaron; actualiza el escenario.');
   throw error;
  }finally{c.release();}
 }
 async scenarios(branch:string,p:AuthPrincipal){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.read'))throw new ForbiddenException('No puedes consultar escenarios.');
  const r=await this.pool.query(`SELECT s.id,s.fuel_product_id AS "fuelProductId",s.tank_id AS "tankId",
   s.quantity_l AS "quantityLiters",s.valid_until AS "validUntil",s.created_at AS "createdAt",
   coalesce(a.outcome,'pending') AS status,so.order_id AS "purchaseOrderId"
   FROM purchase_scenarios s LEFT JOIN purchase_scenario_approvals a ON a.scenario_id=s.id
   LEFT JOIN purchase_scenario_orders so ON so.scenario_id=s.id
   WHERE s.organization_id=$1 AND s.branch_id=$2 ORDER BY s.created_at DESC,s.id DESC LIMIT 100`,
   [p.organizationId,branch]);return {data:r.rows};
 }
 async scenario(branch:string,id:string,p:AuthPrincipal){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.read'))throw new ForbiddenException('No puedes consultar escenarios.');
  if(!uuid(id))throw new BadRequestException('Escenario inválido.');
  const r=await this.pool.query(`SELECT s.*,q.supplier_id,q.unit,q.unit_price_usd,q.confidence,
   a.outcome AS decision,a.reason AS decision_reason,a.approved_by,so.order_id
   FROM purchase_scenarios s JOIN supplier_fuel_quotes q ON q.id=s.quote_id
   LEFT JOIN purchase_scenario_approvals a ON a.scenario_id=s.id
   LEFT JOIN purchase_scenario_orders so ON so.scenario_id=s.id
   WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3`,[id,p.organizationId,branch]);
  if(!r.rows[0])throw new NotFoundException('Escenario fuera de sucursal.');
  return {data:r.rows[0]};
 }
 async decide(branch:string,id:string,p:AuthPrincipal,x:DecidePurchaseScenarioDto,correlation:string){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.scenario.approve'))
   throw new ForbiddenException('No puedes aprobar escenarios.');
  if(!uuid(id)||!uuid(x.commandId)||!['approved','rejected'].includes(x.outcome)||typeof x.reason!=='string'
   ||x.reason.trim().length<10||x.reason.trim().length>500)throw new BadRequestException('Decisión inválida.');
  const hash=digest({branch,id,outcome:x.outcome,reason:x.reason.trim()});
  const c=await this.pool.connect();
  try{await c.query('BEGIN');
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['scenario-decision:'+p.organizationId+':'+x.commandId]);
   const old=await c.query<{scenario_id:string;request_hash:string;approved_by:string;branch_id:string}>(`SELECT scenario_id,request_hash,approved_by,branch_id
    FROM purchase_scenario_approvals WHERE organization_id=$1 AND command_id=$2`,[p.organizationId,x.commandId]);
   if(old.rows[0]){
    if(old.rows[0].scenario_id!==id||old.rows[0].request_hash!==hash||old.rows[0].approved_by!==p.userId||old.rows[0].branch_id!==branch)
     throw new ConflictException('Comando de decisión reutilizado.');
    await c.query('COMMIT');return {data:{id,status:x.outcome,idempotentReplay:true}};
   }
   await c.query(`INSERT INTO purchase_scenario_approvals(scenario_id,organization_id,branch_id,outcome,reason,command_id,request_hash,approved_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[id,p.organizationId,branch,x.outcome,x.reason.trim(),x.commandId,hash,p.userId,correlation]);
   await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,
    action:'purchase.scenario.'+x.outcome,entityType:'purchase_scenario',entityId:id,after:{outcome:x.outcome,reason:x.reason.trim()}});
   await c.query('COMMIT');return {data:{id,status:x.outcome,idempotentReplay:false}};
  }catch(error){await c.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514'].includes((error as {code?:string}).code??''))throw new ConflictException('Escenario vencido o decisión duplicada.');
   throw error;
  }finally{c.release();}
 }
 async convert(branch:string,id:string,p:AuthPrincipal,correlation:string){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.create'))throw new ForbiddenException('No puedes crear órdenes.');
  if(!uuid(id))throw new BadRequestException('Escenario inválido.');
  const c=await this.pool.connect();
  try{await c.query('BEGIN');
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['scenario-order:'+p.organizationId+':'+id]);
   const old=await c.query<{order_id:string}>(`SELECT order_id FROM purchase_scenario_orders
    WHERE scenario_id=$1 AND organization_id=$2 AND branch_id=$3`,[id,p.organizationId,branch]);
   if(old.rows[0]){await c.query('COMMIT');return {data:{scenarioId:id,purchaseOrderId:old.rows[0].order_id,idempotentReplay:true}};}
   const r=await c.query<{quote_id:string;fuel_product_id:string;tank_id:string;quantity_l:string;valid_until:string;
    supplier_id:string;unit:string;unit_price_usd:string;minimum_delivery_l:string;lead_days:number;confidence:string;valid_from:string;quote_valid_until:string}>(`SELECT s.quote_id,s.fuel_product_id,s.tank_id,s.quantity_l,s.valid_until,
    q.supplier_id,q.unit,q.unit_price_usd,q.minimum_delivery_l,q.lead_days,q.confidence,q.valid_from,q.valid_until AS quote_valid_until
    FROM purchase_scenarios s JOIN supplier_fuel_quotes q ON q.id=s.quote_id
    JOIN purchase_scenario_approvals a ON a.scenario_id=s.id AND a.outcome='approved'
    WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3`,[id,p.organizationId,branch]);
   const plan=r.rows[0];
   if(!plan||Date.parse(plan.valid_until)<=Date.now()||Date.parse(plan.valid_from)>Date.now()
    ||Date.parse(plan.quote_valid_until)<=Date.now()||plan.confidence!=='confirmed')
    throw new ConflictException('Escenario no aprobado o cotización vencida.');
   const available=await c.query<{free_l:string}>(`SELECT (t.safe_fill_limit_l-bal.on_hand_l)::text AS free_l FROM tanks t
    JOIN tank_inventory_balances bal ON bal.tank_id=t.id
    WHERE t.id=$1 AND t.organization_id=$2 AND t.branch_id=$3 AND t.status='active'`,[plan.tank_id,p.organizationId,branch]);
   if(!available.rows[0]||new Decimal(plan.quantity_l).gt(available.rows[0].free_l))
    throw new ConflictException('La capacidad cambió; recalcula la compra.');
   const supplier=await c.query('SELECT 1 FROM suppliers WHERE id=$1 AND organization_id=$2 AND status=$3',
    [plan.supplier_id,p.organizationId,'active']);
   if(!supplier.rows[0])throw new ConflictException('Proveedor no disponible.');
   const orderNumber='PLAN-'+id.replaceAll('-','').toUpperCase();
   const po=await c.query<{id:string}>(`INSERT INTO purchase_orders(organization_id,branch_id,supplier_id,order_number,status,notes,created_by)
    VALUES($1,$2,$3,$4,'draft',$5,$6) RETURNING id`,
    [p.organizationId,branch,plan.supplier_id,orderNumber,'Escenario '+id+' · cotización '+plan.quote_id,p.userId]);
   const ordered=new Decimal(plan.quantity_l).div(plan.unit==='us_gallon'?'3.785411784':'1').toDecimalPlaces(3);
   await c.query(`INSERT INTO purchase_order_lines(organization_id,purchase_order_id,branch_id,fuel_product_id,quantity_ordered,unit,agreed_unit_price_usd,tank_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,
    [p.organizationId,po.rows[0]!.id,branch,plan.fuel_product_id,ordered.toFixed(3),plan.unit,plan.unit_price_usd,plan.tank_id]);
   await c.query(`INSERT INTO purchase_scenario_orders(scenario_id,organization_id,branch_id,order_id,linked_by)
    VALUES($1,$2,$3,$4,$5)`,[id,p.organizationId,branch,po.rows[0]!.id,p.userId]);
   await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,
    action:'purchase.scenario.converted',entityType:'purchase_order',entityId:po.rows[0]!.id,
    after:{scenarioId:id,status:'draft',quoteId:plan.quote_id,quantityLiters:plan.quantity_l}});
   await c.query('COMMIT');return {data:{scenarioId:id,purchaseOrderId:po.rows[0]!.id,status:'draft',idempotentReplay:false}};
  }catch(error){await c.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514'].includes((error as {code?:string}).code??''))throw new ConflictException('Orden duplicada o escenario desactualizado.');
   throw error;
  }finally{c.release();}
 }
 async demand(branch:string,p:AuthPrincipal,q:DemandQueryDto){
  if(!(await this.auth.capabilities(p,branch)).includes('purchase.read'))throw new ForbiddenException('No puedes consultar abastecimiento.');
  const period=Number(q.days),lead=Number(q.supplierLeadDays??0),safety=Number(q.safetyDays??1);
  if(!uuid(q.fuelProductId)||![7,14,30].includes(period)||!Number.isInteger(lead)||lead<0||lead>120
   ||!Number.isInteger(safety)||safety<0||safety>120)throw new BadRequestException('Parámetros de demanda inválidos.');
  const branchRow=await this.pool.query<{id:string;today:string;timezone:string}>(`SELECT b.id,b.timezone,
   (clock_timestamp() AT TIME ZONE b.timezone)::date::text AS today FROM branches b
   WHERE b.id=$1 AND b.organization_id=$2 AND b.status='active'`,[branch,p.organizationId]);
  if(!branchRow.rows[0])throw new NotFoundException('Sucursal fuera de tu ámbito.');
  const offer=await this.pool.query('SELECT 1 FROM branch_fuel_offers WHERE branch_id=$1 AND organization_id=$2 AND fuel_product_id=$3 AND status=$4',
   [branch,p.organizationId,q.fuelProductId,'active']);
  if(!offer.rows[0])throw new NotFoundException('Combustible fuera de sucursal.');
  const {today,timezone}=branchRow.rows[0];
  const [cuts,stock,reserved]=await Promise.all([
   this.pool.query<{operational_date:string;slot:number;status:string;closure_id:string|null;closed_at:string|null;product_summary:Array<{fuelProductId:string;soldLiters:string}>|null}>(`SELECT c.operational_date::text,c.slot,c.status,cl.id AS closure_id,cl.closed_at,p.product_summary
    FROM operational_cuts c LEFT JOIN operational_cut_preparations p ON p.cut_id=c.id
    LEFT JOIN operational_cut_closures cl ON cl.cut_id=c.id AND cl.preparation_id=p.id
    WHERE c.organization_id=$1 AND c.branch_id=$2 AND c.operational_date >= $3::date-$4::integer
     AND c.operational_date<$3::date ORDER BY c.operational_date,c.slot`,[p.organizationId,branch,today,period]),
   this.pool.query<{tank_id:string;status:string;on_hand_l:string|null;unusable_reserve_l:string;safe_fill_limit_l:string;updated_at:string|null}>(`SELECT t.id AS tank_id,t.status,bal.on_hand_l,t.unusable_reserve_l,t.safe_fill_limit_l,bal.updated_at
    FROM tanks t LEFT JOIN tank_inventory_balances bal ON bal.tank_id=t.id
    WHERE t.organization_id=$1 AND t.branch_id=$2 AND t.fuel_product_id=$3 AND t.status<>'decommissioned'
    ORDER BY t.code`,[p.organizationId,branch,q.fuelProductId]),
   this.pool.query<{liters:string}>(`SELECT coalesce(sum(reserved_l),0)::text AS liters
    FROM dispense_authorizations WHERE organization_id=$1 AND branch_id=$2 AND fuel_product_id=$3
     AND status IN('authorized','dispensing','unknown','posting')`,[p.organizationId,branch,q.fuelProductId]),
  ]);
  const grouped=new Map<string,typeof cuts.rows>();
  for(const c of cuts.rows)grouped.set(c.operational_date,[...(grouped.get(c.operational_date)??[]),c]);
  const daily:Array<{date:string;liters:string|null;coverage:'closed'|'incomplete'}>=[];
  const first=new Date(today+'T00:00:00Z');
  for(let i=period;i>=1;i--){
   const date=new Date(first.getTime()-i*86400000).toISOString().slice(0,10),rows=grouped.get(date)??[];
   const complete=rows.length===2&&new Set(rows.map(r=>r.slot)).size===2&&rows.every(r=>r.status==='closed'&&r.closure_id!==null&&Array.isArray(r.product_summary));
   const liters=complete?rows.reduce((a,r)=>a.plus((r.product_summary??[]).filter(v=>v.fuelProductId===q.fuelProductId)
    .reduce((b,v)=>b.plus(new Decimal(v.soldLiters??0)),new Decimal(0))),new Decimal(0)):null;
   daily.push({date,liters:liters?.toFixed(3)??null,coverage:complete?'closed':'incomplete'});
  }
  const valid=daily.filter(x=>x.liters!==null),coverage=valid.length/period;
  const quality=valid.length<3||coverage<0.7?'insufficient':'sufficient';
  const average=quality==='sufficient'?valid.reduce((a,x)=>a.plus(x.liters!),new Decimal(0)).div(valid.length):null;
  const active=stock.rows.filter(x=>x.status==='active');
  const missingBaseline=active.length===0||active.some(x=>x.on_hand_l===null);
  const onHand=missingBaseline?null:active.reduce((a,x)=>a.plus(x.on_hand_l!),new Decimal(0));
  const unusable=active.reduce((a,x)=>a.plus(x.unusable_reserve_l),new Decimal(0));
  const reservations=new Decimal(reserved.rows[0]?.liters??0);
  const usable=onHand===null?null:Decimal.max(0,onHand.minus(unusable).minus(reservations));
  const safeCapacity=active.reduce((a,x)=>a.plus(x.safe_fill_limit_l),new Decimal(0));
  const freeCapacity=onHand===null?null:Decimal.max(0,safeCapacity.minus(onHand));
  const autonomy=average===null||average.lte(0)||usable===null?null:usable.div(average);
  const threshold=lead+safety;
  const remainingOnArrival=average===null||usable===null?null:usable.minus(average.mul(threshold));
  const recent=valid.slice(-Math.min(3,valid.length)).reduce((a,x)=>a.plus(x.liters!),new Decimal(0));
  const lastSource=[...cuts.rows.map(x=>x.closed_at),...stock.rows.map(x=>x.updated_at)]
   .filter((x):x is string=>!!x).map(x=>new Date(x).toISOString()).sort().at(-1)??null;
  return {data:{branchId:branch,fuelProductId:q.fuelProductId,periodDays:period,timezone,asOf:today,
   source:'two_closed_operational_cuts_per_day',sampleDays:valid.length,incompleteDays:period-valid.length,
   coveragePercent:Math.round(coverage*100),quality,daily,averageDailyLiters:average?.toFixed(3)??null,
   recentClosedDaysLiters:valid.length?recent.toFixed(3):null,
   stock:{activeTankCount:active.length,excludedTankCount:stock.rows.length-active.length,
    onHandLiters:onHand?.toFixed(3)??null,unusableReserveLiters:unusable.toFixed(3),
    openDispenseReservationsLiters:reservations.toFixed(3),usableLiters:usable?.toFixed(3)??null,
    freeSafeCapacityLiters:freeCapacity?.toFixed(3)??null},
   autonomyDays:autonomy?.toDecimalPlaces(1).toString()??null,
   autonomyReason:average===null?'insufficient_coverage':average.eq(0)?'zero_observed_demand':usable===null?'missing_inventory_baseline':null,
   supplierLeadDays:lead,safetyDays:safety,remainingAtLeadPlusSafetyLiters:remainingOnArrival?.toFixed(3)??null,
   replenishmentRisk:remainingOnArrival===null?'unknown':remainingOnArrival.lte(0)?'before_threshold':'after_threshold',
   lastSourceAt:lastSource}};
 }
}
function uuid(v:unknown):v is string{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);}
function positiveDecimal(v:unknown,scale:number){return typeof v==='string'&&new RegExp('^[1-9][0-9]{0,8}(\\.[0-9]{1,'+scale+'})?$').test(v);}
function nonnegativeDecimal(v:unknown,scale:number){return typeof v==='string'&&new RegExp('^(0|[1-9][0-9]{0,8})(\\.[0-9]{1,'+scale+'})?$').test(v);}
function digest(v:unknown){return createHash('sha256').update(JSON.stringify(v)).digest('hex');}
