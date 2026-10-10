import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import { FuelInventoryService } from '../inventory/fuel-inventory.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { AdvanceIncidentDto, ApproveIncidentLossDto, AssessIncidentDto, CreateIncidentDto, CreateRecoveryClaimDto, ReceiveRecoveryDto, ReviewAnomalyDto } from './incidents.dto.js';

@Injectable()
export class IncidentsService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService,private readonly inventory:FuelInventoryService) {}
 private async scope(branch:string,p:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(p,branch)).includes(permission))throw new ForbiddenException('No puedes acceder a incidencias de esta sucursal.');
  const r=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3',[branch,p.organizationId,'active']);
  if(!r.rows[0])throw new NotFoundException('Sucursal activa no encontrada.');
 }
 async create(branch:string,p:AuthPrincipal,input:CreateIncidentDto,correlation:string){
  await this.scope(branch,p,'incident.create');
  if(input.category==='wrong_tank_delivery')throw new BadRequestException('Registra una descarga en tanque equivocado desde Compras → Descarga contaminante para capturar producto, cantidad real, pérdidas y conciliación.');
  if((input.assetType==='branch')!==!input.assetId||!input.description?.trim()||!Number.isFinite(Date.parse(input.occurredAt))||Date.parse(input.occurredAt)>Date.now()+300000)
   throw new BadRequestException('Recurso, descripción o fecha de incidencia inválidos.');
  const canonical=[input.category,input.severity,input.assetType,input.assetId??null,input.description.trim(),new Date(input.occurredAt).toISOString()];
  const hash=createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
  const code='INC-'+new Date(input.occurredAt).toISOString().slice(0,10).replaceAll('-','')+'-'+input.commandId.slice(0,8).toUpperCase();
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query<{id:string;code:string}>(`INSERT INTO incidents(organization_id,branch_id,code,category,severity,asset_type,asset_id,description,occurred_at,reported_by,command_id,request_hash)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    ON CONFLICT (organization_id,command_id) DO NOTHING RETURNING id,code`,
    [p.organizationId,branch,code,input.category,input.severity,input.assetType,input.assetId??null,input.description.trim(),input.occurredAt,p.userId,input.commandId,hash]);
   let row=r.rows[0];
   if(!row){const replay=await client.query<{id:string;code:string;request_hash:string;branch_id:string}>(
    'SELECT id,code,request_hash,branch_id FROM incidents WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
    if(!replay.rows[0]||replay.rows[0].request_hash!==hash||replay.rows[0].branch_id!==branch)throw new ConflictException('Comando repetido con otros datos.');
    row=replay.rows[0];
   }else{
    await client.query(`INSERT INTO incident_events(organization_id,branch_id,incident_id,to_status,note,actor_id)
      VALUES($1,$2,$3,'reported','Incidencia registrada', $4)`,[p.organizationId,branch,row.id,p.userId]);
    if(['equipment_damage','fuel_spill','wrong_tank_delivery','safety'].includes(input.category) &&
       ['high','critical'].includes(input.severity) && ['nozzle','dispenser','tank'].includes(input.assetType)){
     await client.query(`INSERT INTO asset_blocks(organization_id,branch_id,asset_type,asset_id,block_type,reason_code,reason,created_by,incident_id)
      VALUES($1,$2,$3,$4,'safety','incident_reported',$5,$6,$7)`,
      [p.organizationId,branch,input.assetType,input.assetId,'Incidencia '+row.code+': inspección antes de liberar equipo',p.userId,row.id]);
    }
    await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'incident.reported',entityType:'incident',entityId:row.id,after:{code,category:input.category,severity:input.severity,assetType:input.assetType,assetId:input.assetId??null}});
   }
   await client.query('COMMIT');return {data:{id:row.id,code:row.code,status:'reported'}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if((error as {code?:string}).code==='23514')throw new ConflictException('El recurso no pertenece a esta sucursal.');throw error;
  }finally{client.release();}
 }
 async list(branch:string,p:AuthPrincipal,q:{status?:string;severity?:string;q?:string;cursor?:string;limit?:string}={}){
  await this.scope(branch,p,'incident.read');
  const status=q.status,severity=q.severity,term=q.q?.trim()??'',limit=q.limit===undefined?30:Number(q.limit),cursor=q.cursor;
  if(status&&!['reported','assessed','in_progress','resolved','closed'].includes(status))throw new BadRequestException('Estado inválido.');
  if(severity&&!['low','medium','high','critical'].includes(severity))throw new BadRequestException('Severidad inválida.');
  if(!Number.isSafeInteger(limit)||limit<1||limit>100||term.length>100||cursor!==undefined&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(cursor))throw new BadRequestException('Filtro inválido.');
  const escapedTerm=term.replaceAll('!','!!').replaceAll('%','!%').replaceAll('_','!_');
  let cursorAt:Date|null=null;if(cursor){const anchor=await this.pool.query<{reported_at:Date}>('SELECT reported_at FROM incidents WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[cursor,p.organizationId,branch]);if(!anchor.rows[0])throw new BadRequestException('Cursor de incidencia inválido.');cursorAt=anchor.rows[0].reported_at;}
  const r=await this.pool.query(`SELECT id,code,category,severity,asset_type AS "assetType",asset_id AS "assetId",
   description,occurred_at AS "occurredAt",reported_at AS "reportedAt",status,assignee_id AS "assigneeId",due_at AS "dueAt",version
   FROM incidents i WHERE organization_id=$1 AND branch_id=$2 AND ($3::text IS NULL OR status=$3)
    AND ($4::text IS NULL OR severity=$4)
    AND ($5::text IS NULL OR concat_ws(' ',code,category,asset_type,description,status,severity) ILIKE $5 ESCAPE '!')
    AND ($6::timestamptz IS NULL OR (i.reported_at,i.id)<($6::timestamptz,$7::uuid))
   ORDER BY i.reported_at DESC,i.id DESC LIMIT $8`,[p.organizationId,branch,status??null,severity??null,term?`%${escapedTerm}%`:null,cursorAt,cursor??null,limit+1]);
  const data=r.rows.slice(0,limit);return {data,meta:{limit,nextCursor:r.rows.length>limit?data.at(-1)!.id:null}};
 }
 async detail(branch:string,id:string,p:AuthPrincipal){
  await this.scope(branch,p,'incident.read');
  const r=await this.pool.query('SELECT * FROM incidents WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[id,p.organizationId,branch]);
  if(!r.rows[0])throw new NotFoundException('Incidencia fuera de tu sucursal.');
  const events=await this.pool.query(`SELECT from_status AS "fromStatus",to_status AS "toStatus",note,actor_id AS "actorId",occurred_at AS "occurredAt"
   FROM incident_events WHERE incident_id=$1 ORDER BY occurred_at,id`,[id]);
  const assessments=await this.pool.query(`SELECT a.id,a.impact_type AS "impactType",a.tank_id AS "tankId",a.quantity_l AS "quantityL",
   a.historical_cost_usd AS "historicalCostUsd",a.commercial_reference_usd AS "commercialReferenceUsd",
   a.cost_quality AS "costQuality",a.repair_estimate_usd AS "repairEstimateUsd",a.third_party_estimate_usd AS "thirdPartyEstimateUsd",
   a.note,a.assessed_at AS "assessedAt",l.approved_by AS "lossApprovedBy",l.approved_at AS "lossApprovedAt",l.movement_id AS "lossMovementId"
   FROM incident_impact_assessments a LEFT JOIN incident_loss_approvals l ON l.assessment_id=a.id
   WHERE a.incident_id=$1 ORDER BY a.assessed_at,a.id`,[id]);
  const recoveries=await this.pool.query(`SELECT b.claim_id AS "claimId",b.claimed_usd AS "claimedUsd",b.recovered_usd AS "recoveredUsd",
   b.outstanding_usd AS "outstandingUsd",c.counterparty_type AS "counterpartyType",c.reference
   FROM incident_recovery_balances b JOIN incident_recovery_claims c ON c.id=b.claim_id
   WHERE b.incident_id=$1 AND b.branch_id=$2 AND b.organization_id=$3 ORDER BY c.filed_at DESC`,[id,branch,p.organizationId]);
  return {data:{incident:r.rows[0],events:events.rows,assessments:assessments.rows,recoveries:recoveries.rows}};
 }
 async advance(branch:string,id:string,p:AuthPrincipal,input:AdvanceIncidentDto,correlation:string){
  await this.scope(branch,p,['assessed','in_progress'].includes(input.nextStatus)?'incident.assign':'incident.resolve');
  if(!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1||input.note?.trim().length<5)
   throw new BadRequestException('Versión o nota inválida.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query('SELECT * FROM advance_incident($1,$2,$3,$4,$5,$6,$7,$8,$9)',
    [p.organizationId,branch,id,p.userId,input.expectedVersion,input.nextStatus,input.assigneeId??null,input.dueAt??null,input.note.trim()]);
   const row=r.rows[0];if(!row)throw new ConflictException('Incidencia no actualizada.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'incident.'+input.nextStatus,entityType:'incident',entityId:id,after:row});
   await client.query('COMMIT');return {data:{id,status:row.status,version:row.version}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','40001'].includes((error as {code?:string}).code??''))throw new ConflictException('Transición inválida, responsable ausente o versión desactualizada.');throw error;
  }finally{client.release();}
 }
 async assess(branch:string,id:string,p:AuthPrincipal,input:AssessIncidentDto,correlation:string){
  await this.scope(branch,p,'incident.assign');
  const decimal=/^(0|[1-9]\d{0,8})(\.\d{1,9})?$/;
  const money=/^(0|[1-9]\d{0,8})(\.\d{1,2})?$/;
  if(input.impactType==='fuel_loss'
   ? (!input.tankId||!input.serviceMode||!input.quantityL||!decimal.test(input.quantityL)||Number(input.quantityL)<=0||input.estimateUsd!==undefined)
   : (input.tankId!==undefined||input.serviceMode!==undefined||input.quantityL!==undefined||!input.estimateUsd||!money.test(input.estimateUsd)))
   throw new BadRequestException('El impacto de combustible exige tanque y litros; daños requieren una estimación separada.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query('SELECT * FROM assess_incident_impact($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',
    [p.organizationId,branch,id,p.userId,input.impactType,input.tankId??null,input.quantityL??null,input.serviceMode??null,input.estimateUsd??null,input.note.trim()]);
   const row=r.rows[0];if(!row)throw new ConflictException('No se calculó el impacto.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'incident.impact.assessed',entityType:'incident_impact_assessment',entityId:row.assessment_id,after:row});
   await client.query('COMMIT');return {data:{id:row.assessment_id,historicalCostUsd:row.historical_cost_usd,commercialReferenceUsd:row.commercial_reference_usd,costQuality:row.cost_quality}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514'].includes((error as {code?:string}).code??''))throw new ConflictException('Impacto duplicado, inventario histórico insuficiente o recurso incompatible.');throw error;
  }finally{client.release();}
 }
 async approveLoss(branch:string,incidentId:string,assessmentId:string,p:AuthPrincipal,input:ApproveIncidentLossDto,correlation:string){
  await this.scope(branch,p,'loss.approve');
  if(!input.reason||input.reason.trim().length<8||input.reason.length>500)throw new BadRequestException('Justifica la pérdida aprobada.');
  const belongs=await this.pool.query(`SELECT a.id FROM incident_impact_assessments a WHERE a.id=$1 AND a.incident_id=$2
    AND a.branch_id=$3 AND a.organization_id=$4 AND a.impact_type='fuel_loss'`,[assessmentId,incidentId,branch,p.organizationId]);
  if(!belongs.rows[0])throw new NotFoundException('La evaluación de pérdida no pertenece a esta incidencia.');
  const client=await this.pool.connect();let approved:{approval_id:string;tank_id:string;quantity_l:string;movement_id:string|null};
  try{
   await client.query('BEGIN');
   const r=await client.query<typeof approved>('SELECT * FROM approve_incident_loss($1,$2,$3,$4,$5,$6)',
    [p.organizationId,branch,assessmentId,p.userId,input.commandId,input.reason.trim()]);
   approved=r.rows[0]!;
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'incident.loss.approved',entityType:'incident_loss_approval',entityId:approved.approval_id,after:{assessmentId,commandId:input.commandId}});
   await client.query('COMMIT');
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514'].includes((error as {code?:string}).code??''))throw new ConflictException('La pérdida necesita una evaluación y aprobación independiente.');throw error;
  }finally{client.release();}
  if(approved!.movement_id)return {data:{approvalId:approved!.approval_id,movementId:approved!.movement_id,idempotentReplay:true}};
  const posted=await this.inventory.lose(branch,approved!.tank_id,p,{
   commandId:input.commandId,quantity:approved!.quantity_l,unit:'liter',volumeBasis:'observed',
   reasonCode:'incident_approved',reason:input.reason.trim(),sourceId:assessmentId,sourceLine:'fuel_loss'
  },correlation);
  const movementId=posted.movement.id as string;
  await this.pool.query('SELECT link_incident_loss($1,$2,$3,$4,$5,$6)',
   [p.organizationId,branch,assessmentId,p.userId,input.commandId,movementId]);
  return {data:{approvalId:approved!.approval_id,movementId,idempotentReplay:posted.idempotentReplay}};
 }
 async createClaim(branch:string,incidentId:string,p:AuthPrincipal,input:CreateRecoveryClaimDto,correlation:string){
  await this.scope(branch,p,'incident.resolve');
  if(!/^(0|[1-9]\d{0,8})(\.\d{1,2})?$/.test(input.claimedUsd)||Number(input.claimedUsd)<=0)throw new BadRequestException('Importe reclamado inválido.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query<{id:string}>(`INSERT INTO incident_recovery_claims(organization_id,branch_id,incident_id,counterparty_type,counterparty_name,reference,claimed_usd,filed_by)
    SELECT $1,$2,id,$4,$5,$6,$7,$8 FROM incidents WHERE id=$3 AND organization_id=$1 AND branch_id=$2 RETURNING id`,
    [p.organizationId,branch,incidentId,input.counterpartyType,input.counterpartyName.trim(),input.reference.trim(),input.claimedUsd,p.userId]);
   if(!r.rows[0])throw new NotFoundException('Incidencia fuera de tu sucursal.');const id=r.rows[0].id;
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'incident.recovery.claimed',entityType:'incident_recovery_claim',entityId:id,after:{incidentId,amountUsd:input.claimedUsd}});
   await client.query('COMMIT');return {data:{id,claimedUsd:input.claimedUsd,outstandingUsd:input.claimedUsd}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if((error as {code?:string}).code==='23505')throw new ConflictException('Referencia de reclamo duplicada.');throw error;}finally{client.release();}
 }
 async receiveRecovery(branch:string,incidentId:string,claimId:string,p:AuthPrincipal,input:ReceiveRecoveryDto,correlation:string){
  await this.scope(branch,p,'incident.resolve');
  if(!/^(0|[1-9]\d{0,8})(\.\d{1,2})?$/.test(input.amountUsd)||Number(input.amountUsd)<=0)throw new BadRequestException('Importe recibido inválido.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query<{id:string}>(`INSERT INTO incident_recovery_receipts(organization_id,branch_id,claim_id,amount_usd,method,evidence_reference,command_id,received_by)
    SELECT $1,$2,id,$5,$6,$7,$8,$9 FROM incident_recovery_claims
    WHERE id=$3 AND incident_id=$4 AND organization_id=$1 AND branch_id=$2 RETURNING id`,
    [p.organizationId,branch,claimId,incidentId,input.amountUsd,input.method,input.evidenceReference.trim(),input.commandId,p.userId]);
   if(!r.rows[0])throw new NotFoundException('Reclamo fuera de tu sucursal.');const id=r.rows[0].id;
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'incident.recovery.received',entityType:'incident_recovery_receipt',entityId:id,after:{claimId,amountUsd:input.amountUsd,method:input.method}});
   const balance=await client.query('SELECT outstanding_usd FROM incident_recovery_balances WHERE claim_id=$1',[claimId]);
   await client.query('COMMIT');return {data:{id,claimId,outstandingUsd:balance.rows[0]?.outstanding_usd}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505'].includes((error as {code?:string}).code??''))throw new ConflictException('Recibo duplicado o importe superior al saldo por recuperar.');throw error;
  }finally{client.release();}
 }
 async anomalies(branch:string,p:AuthPrincipal,status?:string){
  await this.scope(branch,p,'incident.read');
  if(status&&!['open','investigating','dismissed','confirmed_loss'].includes(status))throw new BadRequestException('Estado de alerta inválido.');
  const r=await this.pool.query(`SELECT id,cut_id AS "cutId",rule_code AS "ruleCode",asset_key AS "assetKey",
   observation,status,created_at AS "createdAt",reviewed_by AS "reviewedBy",reviewed_at AS "reviewedAt",review_note AS "reviewNote"
   FROM anomaly_alerts WHERE organization_id=$1 AND branch_id=$2 AND ($3::text IS NULL OR status=$3)
   ORDER BY created_at DESC,id DESC LIMIT 100`,[p.organizationId,branch,status??null]);return {data:r.rows};
 }
 async reviewAnomaly(branch:string,id:string,p:AuthPrincipal,input:ReviewAnomalyDto,correlation:string){
  await this.scope(branch,p,'incident.resolve');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query('SELECT review_anomaly($1,$2,$3,$4,$5,$6,$7) AS id',
    [p.organizationId,branch,id,p.userId,input.expectedStatus,input.nextStatus,input.note.trim()]);
   if(!r.rows[0]?.id)throw new ConflictException('La alerta no cambió.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'anomaly.'+input.nextStatus,entityType:'anomaly_alert',entityId:id,after:{status:input.nextStatus,note:input.note.trim()}});
   await client.query('COMMIT');return {data:{id,status:input.nextStatus}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['40001','23514'].includes((error as {code?:string}).code??''))throw new ConflictException('La alerta cambió o la transición no es válida.');throw error;
  }finally{client.release();}
 }
}
