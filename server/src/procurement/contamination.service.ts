import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import { Decimal } from 'decimal.js';
import { createHash, randomUUID } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { ContaminationDto, ContaminationApprovalDto, ContaminationDisposalDto } from './contamination.dto.js';

@Injectable()
export class ContaminationService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService) {}
 private async scope(branch:string,p:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(p,branch)).includes(permission))throw new ForbiddenException('Sin permiso para esta sucursal.');
 }
 async tank(branch:string,tank:string,p:AuthPrincipal){
  await this.scope(branch,p,'purchase.receive');
  const result=await this.pool.query(`SELECT t.id,t.code,t.fuel_product_id AS "fuelProductId",b.on_hand_l AS "priorQuantityL",
   b.inventory_value_usd AS "priorCostUsd",b.valuation_quality AS "costQuality",b.version AS "balanceVersion",
   t.safe_fill_limit_l AS "safeFillLimitL" FROM tanks t JOIN tank_inventory_balances b ON b.tank_id=t.id
   WHERE t.id=$1 AND t.branch_id=$2 AND t.organization_id=$3`,[tank,branch,p.organizationId]);
  if(!result.rows[0])throw new NotFoundException('Tanque sin saldo inicial o fuera de sucursal.');
  return {data:result.rows[0]};
 }
 async list(branch:string,order:string,p:AuthPrincipal){
  await this.scope(branch,p,'purchase.read');
  return {data:(await this.pool.query(`SELECT d.*,t.code AS tank_code,t.name AS tank_name,
   original_fuel.display_name AS original_fuel_name,incoming_fuel.display_name AS incoming_fuel_name,
   reporter.display_name AS reporter_name,
   a.id AS incoming_loss_approval_id,a.approved_by AS incoming_loss_approved_by,
   approver.display_name AS incoming_loss_approver_name,a.amount_usd AS incoming_loss_approved_amount_usd,
   a.reason AS incoming_loss_approval_reason,a.created_at AS incoming_loss_approved_at,
   prior_loss.approval_id AS prior_loss_approval_id,prior_loss.approved_by AS prior_loss_approved_by,
   prior_loss.approver_name AS prior_loss_approver_name,prior_loss.amount_usd AS prior_loss_approved_amount_usd,
   prior_loss.reason AS prior_loss_approval_reason,prior_loss.approved_at AS prior_loss_approved_at,
   x.id AS disposal_id,x.verified_by AS disposal_verified_by,verifier.display_name AS disposal_verifier_name,
   x.measured_l AS disposed_l,x.evidence_reference AS disposal_evidence_reference,
   x.note AS disposal_note,x.created_at AS disposal_verified_at
   FROM contaminated_deliveries d JOIN tanks t ON t.id=d.tank_id
   JOIN fuel_products original_fuel ON original_fuel.id=d.original_product_id
   JOIN fuel_products incoming_fuel ON incoming_fuel.id=d.incoming_product_id
   JOIN users reporter ON reporter.id=d.reported_by
   LEFT JOIN contamination_incoming_loss_approvals a ON a.contamination_id=d.id
   LEFT JOIN users approver ON approver.id=a.approved_by
   LEFT JOIN LATERAL (SELECT ila.id AS approval_id,ila.approved_by,ila.reason,ila.approved_at,u.display_name AS approver_name,
    ia.historical_cost_usd AS amount_usd FROM incident_impact_assessments ia
    JOIN incident_loss_approvals ila ON ila.assessment_id=ia.id AND ila.movement_id IS NOT NULL
    JOIN users u ON u.id=ila.approved_by WHERE ia.incident_id=d.incident_id AND ia.tank_id=d.tank_id
      AND ia.impact_type='fuel_loss' ORDER BY ila.approved_at DESC LIMIT 1) prior_loss ON true
   LEFT JOIN contamination_disposals x ON x.contamination_id=d.id
   LEFT JOIN users verifier ON verifier.id=x.verified_by
   WHERE d.organization_id=$1 AND d.branch_id=$2 AND d.purchase_order_id=$3 ORDER BY d.created_at DESC`,[p.organizationId,branch,order])).rows};
 }
 async resolve(branch:string,id:string,p:AuthPrincipal,input:ContaminationApprovalDto|ContaminationDisposalDto,correlation:string,disposal:boolean){
  await this.scope(branch,p,disposal?'incident.resolve':'loss.approve');
  const c=await this.pool.connect();
  try{
   await c.query('BEGIN');
   const found=await c.query('SELECT * FROM contaminated_deliveries WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE',[id,branch,p.organizationId]);
   const d=found.rows[0];if(!d)throw new NotFoundException('Descarga fuera de sucursal.');
   if(d.reported_by===p.userId)throw new ForbiddenException('Requiere una persona distinta al reportante.');
   const table=disposal?'contamination_disposals':'contamination_incoming_loss_approvals';
   const prior=await c.query(`SELECT * FROM ${table} WHERE contamination_id=$1`,[id]);
   if(prior.rows[0]){
    const row=prior.rows[0];const same=disposal
     ? row.verified_by===p.userId&&row.evidence_reference===(input as ContaminationDisposalDto).evidenceReference.trim()&&row.note===(input as ContaminationDisposalDto).note.trim()&&new Decimal(row.measured_l).eq((input as ContaminationDisposalDto).measuredLiters)
     : row.approved_by===p.userId&&row.reason===(input as ContaminationApprovalDto).reason.trim();
    if(row.command_id!==input.commandId||!same)throw new ConflictException('Decisión ya registrada con otros datos.');
    await c.query('COMMIT');return {data:row,idempotentReplay:true};
   }
   const data=disposal?input as ContaminationDisposalDto:input as ContaminationApprovalDto;
   const result=disposal?await c.query(`INSERT INTO contamination_disposals(contamination_id,organization_id,branch_id,command_id,verified_by,measured_l,evidence_reference,note)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,[id,p.organizationId,branch,input.commandId,p.userId,(data as ContaminationDisposalDto).measuredLiters,(data as ContaminationDisposalDto).evidenceReference.trim(),(data as ContaminationDisposalDto).note.trim()])
    :await c.query(`INSERT INTO contamination_incoming_loss_approvals(contamination_id,organization_id,branch_id,command_id,approved_by,amount_usd,reason)
     VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *`,[id,p.organizationId,branch,input.commandId,p.userId,d.incoming_cost_usd,(data as ContaminationApprovalDto).reason.trim()]);
   await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,action:disposal?'purchase.contamination.disposal_verified':'purchase.contamination.incoming_loss_approved',entityType:table,entityId:result.rows[0].id,after:result.rows[0]});
   await c.query('COMMIT');return {data:result.rows[0],idempotentReplay:false};
  }catch(e){await c.query('ROLLBACK').catch(()=>undefined);if(['23514','23505'].includes((e as {code?:string}).code??''))throw new ConflictException('Las pérdidas deben aprobarse antes del retiro; verifica la decisión y sus requisitos.');throw e;}finally{c.release();}
 }
 async report(branch:string,order:string,p:AuthPrincipal,input:ContaminationDto,correlation:string){
  await this.scope(branch,p,'purchase.receive');
  const quantity=new Decimal(input.actualQuantity);
  if(!quantity.isFinite()||quantity.lte(0)||input.description.trim().length<12||input.documentReference.trim().length<3)throw new BadRequestException('Cantidad, descripción o documento inválidos.');
  const payload={branch,order,...input,actor:p.userId};
  const hash=createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  const c=await this.pool.connect();
  try{
   await c.query('BEGIN');
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`contamination:${p.organizationId}:${input.commandId}`]);
   const previous=await c.query('SELECT * FROM contaminated_deliveries WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   if(previous.rows[0]){if(previous.rows[0].request_hash!==hash)throw new ConflictException('Comando usado con otros datos.');await c.query('COMMIT');return {data:previous.rows[0],idempotentReplay:true};}
   const po=await c.query('SELECT id,status FROM purchase_orders WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE',[order,branch,p.organizationId]);
   if(!po.rows[0]||!['ordered','partially_received'].includes(po.rows[0].status))throw new ConflictException('Orden no disponible para descarga.');
   const lines=await c.query('SELECT * FROM purchase_order_lines WHERE id=$1 AND purchase_order_id=$2 AND organization_id=$3 FOR UPDATE',[input.purchaseOrderLineId,order,p.organizationId]);
   const line=lines.rows[0];if(!line)throw new NotFoundException('Línea fuera de orden.');
   if(line.unit!==input.unit)throw new BadRequestException('Usa la unidad acordada en la compra.');
   const tanks=await c.query('SELECT * FROM tanks WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE',[input.tankId,branch,p.organizationId]);
   const tank=tanks.rows[0];if(!tank)throw new NotFoundException('Tanque fuera de sucursal.');
   if(tank.fuel_product_id===line.fuel_product_id)throw new BadRequestException('El combustible de la orden coincide con el tanque; usa la recepción normal y no registres una pérdida por contaminación.');
   const quarantined=await c.query(`SELECT 1 FROM asset_blocks b JOIN contaminated_deliveries d ON d.incident_id=b.incident_id
    WHERE b.asset_id=$1 AND b.organization_id=$2 AND b.branch_id=$3 AND b.resolved_at IS NULL LIMIT 1`,[tank.id,p.organizationId,branch]);
   if(quarantined.rows[0])throw new ConflictException('El tanque ya tiene una descarga contaminante abierta; concilia esa incidencia antes de registrar otra.');
   const balances=await c.query('SELECT * FROM tank_inventory_balances WHERE tank_id=$1 AND organization_id=$2 FOR UPDATE',[input.tankId,p.organizationId]);
   const balance=balances.rows[0];if(!balance||balance.version!==input.expectedBalanceVersion)throw new ConflictException('El saldo cambió; revisa de nuevo el tanque.');
   const pending=await c.query(`SELECT COALESCE(sum(accepted_quantity),0)::text AS quantity FROM purchase_deliveries WHERE purchase_order_line_id=$1 AND status='processing'`,[line.id]);
   const losses=await c.query('SELECT COALESCE(sum(actual_quantity),0)::text AS quantity FROM contaminated_deliveries WHERE purchase_order_line_id=$1',[line.id]);
   const remaining=new Decimal(line.quantity_ordered).minus(line.received_quantity).minus(pending.rows[0].quantity).minus(losses.rows[0].quantity);
   if(quantity.gt(remaining))throw new ConflictException('La descarga excede el saldo del pedido.');
   const liters=quantity.mul(input.unit==='us_gallon'?'3.785411784':'1');
   // Accidents may physically overfill. Record the real event instead of hiding it with a capacity rejection.
   const incident=randomUUID(),id=randomUUID();
   await c.query(`INSERT INTO incidents(id,organization_id,branch_id,code,category,severity,asset_type,asset_id,description,occurred_at,reported_by,command_id,request_hash)
    VALUES($1,$2,$3,$4,'wrong_tank_delivery','critical','tank',$5,$6,clock_timestamp(),$7,$8,$9)`,[incident,p.organizationId,branch,'INC-CONT-'+id.slice(0,12).toUpperCase(),tank.id,input.description.trim(),p.userId,input.commandId,hash]);
   await c.query(`INSERT INTO incident_events(organization_id,branch_id,incident_id,to_status,note,actor_id) VALUES($1,$2,$3,'reported','Descarga contaminante: tanque en cuarentena',$4)`,[p.organizationId,branch,incident,p.userId]);
   await c.query(`INSERT INTO asset_blocks(organization_id,branch_id,asset_type,asset_id,block_type,reason_code,reason,created_by,incident_id)
    VALUES($1,$2,'tank',$3,'safety','contaminated_delivery','Tanque contaminado: requiere retiro e inspección independiente',$4,$5)`,[p.organizationId,branch,tank.id,p.userId,incident]);
   if(new Decimal(balance.on_hand_l).gt(0)) await c.query(`INSERT INTO incident_impact_assessments(organization_id,branch_id,incident_id,impact_type,tank_id,fuel_product_id,
    quantity_l,unit_cost_usd_per_l,historical_cost_usd,cost_quality,note,assessed_by)
    VALUES($1,$2,$3,'fuel_loss',$4,$5,$6,$7,$8,$9,'Contenido previo contaminado: saldo congelado al detectar descarga',$10)`,
    [p.organizationId,branch,incident,tank.id,tank.fuel_product_id,balance.on_hand_l,
     balance.valuation_quality==='known'?balance.average_cost_per_l_usd:null,
     balance.valuation_quality==='known'?balance.inventory_value_usd:null,balance.valuation_quality==='known'?'known':'unknown',p.userId]);
   const result=await c.query(`INSERT INTO contaminated_deliveries(id,organization_id,branch_id,purchase_order_id,purchase_order_line_id,incident_id,tank_id,
    original_product_id,incoming_product_id,prior_quantity_l,actual_quantity,unit,incoming_quantity_l,prior_cost_usd,incoming_cost_usd,
    remaining_order_quantity,balance_version,document_reference,description,command_id,request_hash,reported_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22) RETURNING *`,
    [id,p.organizationId,branch,order,line.id,incident,tank.id,tank.fuel_product_id,line.fuel_product_id,balance.on_hand_l,
     quantity.toFixed(9),input.unit,liters.toFixed(9),balance.valuation_quality==='known'?balance.inventory_value_usd:null,
     quantity.mul(line.agreed_unit_price_usd).toFixed(8),remaining.minus(quantity).toFixed(9),balance.version,input.documentReference.trim(),input.description.trim(),input.commandId,hash,p.userId]);
   await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,action:'purchase.delivery.contaminated',entityType:'contaminated_delivery',entityId:id,after:result.rows[0]});
   await c.query('COMMIT');return {data:result.rows[0],idempotentReplay:false};
  }catch(e){await c.query('ROLLBACK').catch(()=>undefined);throw e;}finally{c.release();}
 }
}
