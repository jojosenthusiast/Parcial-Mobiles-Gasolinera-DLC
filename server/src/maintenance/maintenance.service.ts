import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { createHash } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { AdvanceWorkOrderDto, AssetIntervalDto, CreateMaintenancePlanDto, CreateWorkOrderDto, GenerateMaintenanceDto, ObservationDto, RegisterAssetDto, ReleaseBlockDto, UseMaintenancePartDto, WorkTaskDto } from './maintenance.dto.js';

@Injectable()
export class MaintenanceService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService) {}
 private async scope(branch:string,p:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(p,branch)).includes(permission))throw new ForbiddenException('Permiso de mantenimiento insuficiente.');
  const r=await this.pool.query('SELECT 1 FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3',[branch,p.organizationId,'active']);
  if(!r.rows[0])throw new NotFoundException('Sucursal activa fuera de tu ámbito.');
 }
 private async transaction<T>(p:AuthPrincipal,branch:string,correlation:string,action:string,entityType:string,
  callback:(client:PoolClient)=>Promise<{id:string;data:T}>){
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');const result=await callback(client);
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action,entityType,entityId:result.id,after:result.data});
   await client.query('COMMIT');return {data:result.data};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505','40001'].includes((error as {code?:string}).code??''))throw new ConflictException('Equipo, estado, vínculo o versión de mantenimiento incompatible.');throw error;
  }finally{client.release();}
 }
 async registerAsset(branch:string,p:AuthPrincipal,input:RegisterAssetDto,correlation:string){
  await this.scope(branch,p,'maintenance.plan');
  return this.transaction(p,branch,correlation,'maintenance.asset.registered','maintenance_asset_profile',async client=>{
   const r=await client.query<{id:string}>(`INSERT INTO maintenance_asset_profiles(organization_id,branch_id,asset_type,asset_id,manufacturer,model,serial_number,location_label,supplier_id,criticality,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,[p.organizationId,branch,input.assetType,input.assetId,input.manufacturer??null,
    input.model??null,input.serialNumber??null,input.locationLabel??null,input.supplierId??null,input.criticality,p.userId]);
   const blocked=await client.query<{block_type:string}>(`SELECT block_type FROM asset_blocks WHERE organization_id=$1 AND branch_id=$2
     AND asset_type=$3 AND asset_id=$4 AND resolved_at IS NULL ORDER BY created_at LIMIT 1`,
     [p.organizationId,branch,input.assetType,input.assetId]);
   if(blocked.rows[0]){
    const reason=blocked.rows[0].block_type==='inventory'?'no_product':blocked.rows[0].block_type==='operational'?'closed':'technical_failure';
    await client.query('SELECT transition_asset_interval($1,$2,$3,$4,$5,clock_timestamp(),NULL)',[p.organizationId,branch,r.rows[0]!.id,p.userId,reason]);
   }
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,assetType:input.assetType,assetId:input.assetId,criticality:input.criticality}};
  });
 }
 async assets(branch:string,p:AuthPrincipal){
  await this.scope(branch,p,'maintenance.plan');
  const r=await this.pool.query(`SELECT a.id,a.asset_type AS "assetType",a.asset_id AS "assetId",a.criticality,
   a.manufacturer,a.model,a.serial_number AS "serialNumber",a.location_label AS "locationLabel",a.created_at AS "createdAt",
   CASE a.asset_type WHEN 'tank' THEN t.code WHEN 'dispenser' THEN d.code WHEN 'nozzle' THEN n.code END AS "assetCode",
   CASE a.asset_type WHEN 'tank' THEN ft.display_name WHEN 'nozzle' THEN fn.display_name END AS "fuelName"
   FROM maintenance_asset_profiles a
   LEFT JOIN tanks t ON a.asset_type='tank' AND t.id=a.asset_id AND t.branch_id=a.branch_id
   LEFT JOIN fuel_products ft ON ft.id=t.fuel_product_id AND ft.organization_id=a.organization_id
   LEFT JOIN dispensers d ON a.asset_type='dispenser' AND d.id=a.asset_id AND d.branch_id=a.branch_id
   LEFT JOIN nozzles n ON a.asset_type='nozzle' AND n.id=a.asset_id AND n.branch_id=a.branch_id
   LEFT JOIN fuel_products fn ON fn.id=n.fuel_product_id AND fn.organization_id=a.organization_id
   WHERE a.organization_id=$1 AND a.branch_id=$2 ORDER BY a.criticality DESC,a.created_at DESC,a.id`,[p.organizationId,branch]);
  return {data:r.rows};
 }
 async plan(branch:string,p:AuthPrincipal,input:CreateMaintenancePlanDto,correlation:string){
  await this.scope(branch,p,'maintenance.plan');
  if(!(input.cadenceDays&&input.nextDueAt)&&!(input.cadenceUsage&&input.usageUnit&&input.nextDueUsage))throw new BadRequestException('Indica fecha o uso de próxima intervención.');
  return this.transaction(p,branch,correlation,'maintenance.plan.created','maintenance_plan',async client=>{
   const r=await client.query<{id:string}>(`INSERT INTO maintenance_plans(organization_id,branch_id,asset_profile_id,code,description,cadence_days,cadence_usage,usage_unit,next_due_at,next_due_usage,created_by)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,[p.organizationId,branch,input.assetProfileId,input.code,input.description,
     input.cadenceDays??null,input.cadenceUsage??null,input.usageUnit??null,input.nextDueAt??null,input.nextDueUsage??null,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,assetProfileId:input.assetProfileId,nextDueAt:input.nextDueAt??null}};
  });
 }
 async order(branch:string,p:AuthPrincipal,input:CreateWorkOrderDto,correlation:string){
  await this.scope(branch,p,'maintenance.plan');
  if(input.estimateUsd&&!/^(0|[1-9]\d{0,8})(\.\d{1,2})?$/.test(input.estimateUsd))throw new BadRequestException('Estimación inválida.');
  return this.transaction(p,branch,correlation,'maintenance.order.created','maintenance_work_order',async client=>{
   const r=await client.query<{id:string}>(`INSERT INTO maintenance_work_orders(organization_id,branch_id,asset_profile_id,plan_id,incident_id,target_block_id,kind,due_key,description,assigned_to,due_at,estimate_usd,created_by)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,[p.organizationId,branch,input.assetProfileId,input.planId??null,input.incidentId??null,input.targetBlockId??null,
     input.kind,input.dueKey,input.description,input.assignedTo??null,input.dueAt??null,input.estimateUsd??null,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,assetProfileId:input.assetProfileId,status:'planned'}};
  });
 }
 async task(branch:string,id:string,p:AuthPrincipal,input:WorkTaskDto,correlation:string){
  await this.scope(branch,p,'maintenance.work');
  if(input.laborEstimateUsd&&!/^(0|[1-9]\d{0,8})(\.\d{1,2})?$/.test(input.laborEstimateUsd))throw new BadRequestException('Estimación inválida.');
  return this.transaction(p,branch,correlation,'maintenance.task.completed','maintenance_order_task',async client=>{
   const r=await client.query<{id:string}>(`INSERT INTO maintenance_order_tasks(organization_id,branch_id,order_id,description,result,labor_minutes,labor_estimate_usd,completed_by)
    SELECT $1,$2,id,$4,$5,$6,$7,$8 FROM maintenance_work_orders WHERE id=$3 AND organization_id=$1 AND branch_id=$2 AND status='in_progress' RETURNING id`,
    [p.organizationId,branch,id,input.description,input.result,input.laborMinutes??null,input.laborEstimateUsd??null,p.userId]);
   if(!r.rows[0])throw new ConflictException('La orden debe estar en ejecución.');return {id:r.rows[0].id,data:{id:r.rows[0].id,orderId:id}};
  });
 }
 async observe(branch:string,p:AuthPrincipal,input:ObservationDto,correlation:string){
  await this.scope(branch,p,'maintenance.work');
  if(input.outcome==='unknown'&&input.value!==undefined||input.source==='device'&&!input.instrumentReference||
   input.value!==undefined&&!/^-?\d{1,12}(\.\d{1,9})?$/.test(input.value)||input.value!==undefined&&!input.unit)
   throw new BadRequestException('Una lectura ausente no equivale a cero; indica fuente, unidad e instrumento.');
  return this.transaction(p,branch,correlation,'maintenance.observation.recorded','equipment_observation',async client=>{
   const r=await client.query<{id:string}>(`INSERT INTO equipment_observations(organization_id,branch_id,asset_profile_id,work_order_id,metric,value,unit,outcome,source,instrument_reference,evidence_reference,observed_at,recorded_by)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,
     [p.organizationId,branch,input.assetProfileId,input.workOrderId??null,input.metric,input.value??null,input.unit??null,
      input.outcome,input.source,input.instrumentReference??null,input.evidenceReference??null,input.observedAt,p.userId]);
   if(input.metric==='usage_counter'&&input.value!==undefined)
    await client.query('SELECT * FROM generate_usage_maintenance_orders($1,$2,$3,$4)',[p.organizationId,branch,r.rows[0]!.id,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,metric:input.metric,value:input.value??null,source:input.source}};
  });
 }
 async advance(branch:string,id:string,p:AuthPrincipal,input:AdvanceWorkOrderDto,correlation:string){
  await this.scope(branch,p,input.nextStatus==='verified'?'maintenance.verify':'maintenance.work');
  if(!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1)throw new BadRequestException('Versión inválida.');
  return this.transaction(p,branch,correlation,'maintenance.order.'+input.nextStatus,'maintenance_work_order',async client=>{
   const r=await client.query<{order_id:string;status:string;version:number}>(
    'SELECT * FROM advance_work_order($1,$2,$3,$4,$5,$6,$7)',[p.organizationId,branch,id,p.userId,input.expectedVersion,input.nextStatus,input.diagnosis??null]);
   return {id,data:{id,status:r.rows[0]!.status,version:r.rows[0]!.version}};
  });
 }
 async release(branch:string,id:string,p:AuthPrincipal,input:ReleaseBlockDto,correlation:string){
  await this.scope(branch,p,'maintenance.release');
  return this.transaction(p,branch,correlation,'maintenance.block.released','asset_block',async client=>{
   const r=await client.query<{block_id:string;remaining_blocks:number;can_operate:boolean}>(
    'SELECT * FROM release_maintenance_block($1,$2,$3,$4,$5,$6)',[p.organizationId,branch,id,input.blockId,p.userId,input.reason]);
   const row=r.rows[0]!;return {id:input.blockId,data:{blockId:row.block_id,remainingBlocks:row.remaining_blocks,canOperate:row.can_operate}};
  });
 }
 async usePart(branch:string,orderId:string,p:AuthPrincipal,input:UseMaintenancePartDto,correlation:string){
  await this.scope(branch,p,'maintenance.part.use');
  if(!/^[0-9a-f-]{36}$/i.test(orderId)||!input.commandId||!input.lotId||!/^[1-9][0-9]{0,8}$/.test(input.quantity)
   ||typeof input.taskReference!=='string'||input.taskReference.trim().length<5||input.taskReference.trim().length>300)
   throw new BadRequestException('Repuesto, cantidad o referencia no válida.');
  const reference=input.taskReference.trim();
  const hash=createHash('sha256').update(JSON.stringify({v:1,branch,orderId,lotId:input.lotId,quantity:input.quantity,reference})).digest('hex');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const existing=await client.query('SELECT id FROM maintenance_part_consumptions WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   const result=await client.query<{id:string}>('SELECT use_maintenance_part($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) AS id',
    [p.organizationId,branch,p.userId,orderId,input.lotId,Number(input.quantity),reference,input.commandId,hash,correlation]);
   const id=result.rows[0]!.id;
   if(!existing.rows[0])await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'maintenance.part_consumed',entityType:'maintenance_part_consumption',entityId:id,after:{orderId,lotId:input.lotId,quantity:input.quantity}});
   await client.query('COMMIT');return {data:{id,idempotentReplay:!!existing.rows[0]}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505'].includes((error as {code?:string}).code??''))throw new ConflictException('La orden, el lote o la existencia cambió.');throw error;
  }finally{client.release();}
 }
 async list(branch:string,p:AuthPrincipal,q:{status?:string;q?:string;cursor?:string;limit?:string}={}){
  await this.scope(branch,p,'maintenance.plan');
  const status=q.status,term=q.q?.trim()??'',cursor=q.cursor,limit=q.limit===undefined?50:Number(q.limit);
  if(status&&!['planned','in_progress','completed','verified','cancelled'].includes(status))throw new BadRequestException('Estado inválido.');
  if(!Number.isInteger(limit)||limit<1||limit>100||term.length>100||cursor!==undefined&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(cursor))throw new BadRequestException('Filtro inválido.');
  const escapedTerm=term.replaceAll('!','!!').replaceAll('%','!%').replaceAll('_','!_');let cursorAt:Date|null=null;
  if(cursor){const anchor=await this.pool.query<{created_at:Date}>('SELECT created_at FROM maintenance_work_orders WHERE id=$1 AND branch_id=$2 AND organization_id=$3',[cursor,branch,p.organizationId]);if(!anchor.rows[0])throw new BadRequestException('Cursor de orden inválido.');cursorAt=anchor.rows[0].created_at;}
  const r=await this.pool.query(`SELECT w.id,w.asset_profile_id AS "assetProfileId",a.asset_type AS "assetType",a.asset_id AS "assetId",
    w.kind,w.status,w.description,w.due_at AS "dueAt",w.created_at AS "createdAt",w.assigned_to AS "assignedTo",w.version,
    w.target_block_id AS "targetBlockId" FROM maintenance_work_orders w JOIN maintenance_asset_profiles a ON a.id=w.asset_profile_id
    WHERE w.branch_id=$1 AND w.organization_id=$2 AND ($3::text IS NULL OR w.status=$3)
     AND ($4::text IS NULL OR concat_ws(' ',a.asset_type,a.asset_id,w.kind,w.status,w.due_key,w.description) ILIKE $4 ESCAPE '!')
     AND ($5::timestamptz IS NULL OR (w.created_at,w.id)<($5::timestamptz,$6::uuid))
    ORDER BY w.created_at DESC,w.id DESC LIMIT $7`,[branch,p.organizationId,status??null,term?`%${escapedTerm}%`:null,cursorAt,cursor??null,limit+1]);
  const data=r.rows.slice(0,limit);return {data,meta:{limit,nextCursor:r.rows.length>limit?data.at(-1)!.id:null}};
 }
 async detail(branch:string,id:string,p:AuthPrincipal){
  await this.scope(branch,p,'maintenance.plan');
  const r=await this.pool.query('SELECT * FROM maintenance_work_orders WHERE id=$1 AND branch_id=$2 AND organization_id=$3',[id,branch,p.organizationId]);
  if(!r.rows[0])throw new NotFoundException('Orden fuera de tu sucursal.');
  const capabilities=await this.auth.capabilities(p,branch);
  const [tasks,observations,parts,consumptions]=await Promise.all([
   this.pool.query('SELECT * FROM maintenance_order_tasks WHERE order_id=$1 ORDER BY completed_at,id',[id]),
   this.pool.query('SELECT * FROM equipment_observations WHERE work_order_id=$1 ORDER BY observed_at,id',[id]),
   this.pool.query('SELECT * FROM maintenance_order_parts WHERE order_id=$1 ORDER BY recorded_at,id',[id]),
   this.pool.query(`SELECT id,lot_id AS "lotId",quantity_units AS "quantityUnits",task_reference AS "taskReference",
     cost_quality AS "costQuality",CASE WHEN $2 THEN cost_usd::text END AS "costUsd",used_by AS "usedBy",used_at AS "usedAt"
     FROM maintenance_part_consumptions WHERE order_id=$1 ORDER BY used_at,id`,[id,capabilities.includes('finance.cost.read')])]);
  return {data:{order:r.rows[0],tasks:tasks.rows,observations:observations.rows,parts:parts.rows,consumptions:consumptions.rows}};
 }
 async generate(branch:string,p:AuthPrincipal,input:GenerateMaintenanceDto,correlation:string){
  await this.scope(branch,p,'maintenance.plan');
  if(!Number.isFinite(Date.parse(input.asOf))||Date.parse(input.asOf)>Date.now()+86400000)throw new BadRequestException('Fecha de generación inválida.');
  return this.transaction(p,branch,correlation,'maintenance.plans.generated','branch',async client=>{
   const r=await client.query('SELECT * FROM generate_due_maintenance_orders($1,$2,$3,$4)',[p.organizationId,branch,input.asOf,p.userId]);
   return {id:branch,data:{orders:r.rows}};
  });
 }
 async interval(branch:string,id:string,p:AuthPrincipal,input:AssetIntervalDto,correlation:string){
  await this.scope(branch,p,'maintenance.plan');
  if(!Number.isFinite(Date.parse(input.effectiveAt)))throw new BadRequestException('Fecha inválida.');
  return this.transaction(p,branch,correlation,'maintenance.asset.interval','asset_operating_interval',async client=>{
   const r=await client.query<{id:string}>('SELECT transition_asset_interval($1,$2,$3,$4,$5,$6,$7) AS id',
    [p.organizationId,branch,id,p.userId,input.reason,input.effectiveAt,input.sourceOrderId??null]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,assetProfileId:id,reason:input.reason,effectiveAt:input.effectiveAt}};
  });
 }
 async availability(branch:string,id:string,p:AuthPrincipal,from:string,to:string){
  await this.scope(branch,p,'maintenance.plan');
  if(!Number.isFinite(Date.parse(from))||!Number.isFinite(Date.parse(to))||Date.parse(to)<=Date.parse(from))throw new BadRequestException('Periodo inválido.');
  const r=await this.pool.query('SELECT * FROM asset_availability($1,$2,$3,$4,$5)',[p.organizationId,branch,id,from,to]);
  return {data:{assetProfileId:id,period:{from,to},availableSeconds:r.rows[0]?.available_seconds,
   coveredSeconds:r.rows[0]?.covered_seconds,unknownSeconds:r.rows[0]?.unknown_seconds,
   availabilityPct:r.rows[0]?.availability_pct}};
 }
}
