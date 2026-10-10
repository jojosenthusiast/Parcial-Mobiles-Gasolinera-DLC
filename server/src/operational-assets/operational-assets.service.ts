import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { AssignOperationalAssetDto, ChangeOperationalAssetStatusDto, CreateOperationalAssetDto, TransferOperationalAssetDto, UpdateOperationalAssetDto } from './operational-assets.dto.js';

type EventType='profile_changed'|'assignment_changed'|'status_changed'|'transferred';
type Snapshot={id:string;organization_id:string;branch_id:string;code:string;asset_type:string;name:string;description:string;
 manufacturer:string|null;model:string|null;serial_number:string|null;acquired_on:string|null;acquisition_cost_usd:string|null;
 location_label:string|null;custodian_employee_id:string|null;status:string;version:number};
const typeCodes=['payment_terminal','tire_gauge','air_hose','tool','safety_equipment','other'];

@Injectable()
export class OperationalAssetsService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}

 private async scope(branch:string,p:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(p,branch)).includes(permission))throw new ForbiddenException('Permiso de activos operativos insuficiente.');
  const r=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3',[branch,p.organizationId,'active']);
  if(!r.rows[0])throw new NotFoundException('Sucursal activa no encontrada.');
 }
 private async canReadCost(p:AuthPrincipal,branch:string){const permissions=await this.auth.capabilities(p,branch);return permissions.includes('operational_asset.cost.read')||permissions.includes('finance.cost.read');}

 async list(branch:string,p:AuthPrincipal,q:{status?:string;assetType?:string;q?:string;cursor?:string;limit?:string}={}){
  await this.scope(branch,p,'operational_asset.read');
  const status=q.status,assetType=q.assetType,term=q.q?.trim()??'',limit=q.limit===undefined?30:Number(q.limit),cursor=q.cursor;
  if(status&&!['available','assigned','under_repair','missing','retired'].includes(status)||assetType&&!typeCodes.includes(assetType)
   ||!Number.isSafeInteger(limit)||limit<1||limit>100||term.length>100||cursor!==undefined&&!uuid(cursor))
   throw new BadRequestException('Filtro de activos inválido.');
  let cursorAt:Date|null=null;
  if(cursor){const anchor=await this.pool.query<{created_at:Date}>('SELECT created_at FROM operational_assets WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[cursor,p.organizationId,branch]);if(!anchor.rows[0])throw new BadRequestException('Cursor de activos inválido.');cursorAt=anchor.rows[0].created_at;}
  const cost=await this.canReadCost(p,branch), escaped=escapeLike(term);
  const result=await this.pool.query(`SELECT a.id,a.branch_id AS "branchId",a.code,a.asset_type AS "assetType",a.name,a.description,
   a.manufacturer,a.model,a.serial_number AS "serialNumber",a.acquired_on AS "acquiredOn",
   CASE WHEN $3::boolean THEN a.acquisition_cost_usd::text ELSE NULL END AS "acquisitionCostUsd",
   a.location_label AS "locationLabel",a.custodian_employee_id AS "custodianEmployeeId",e.legal_name AS "custodianName",
   a.status,a.version,a.created_at AS "createdAt",a.updated_at AS "updatedAt"
   FROM operational_assets a LEFT JOIN employees e ON e.id=a.custodian_employee_id AND e.organization_id=a.organization_id
   WHERE a.organization_id=$1 AND a.branch_id=$2 AND ($4::text IS NULL OR a.status=$4)
    AND ($5::text IS NULL OR a.asset_type=$5)
    AND ($6::text IS NULL OR concat_ws(' ',a.code,a.name,a.asset_type,a.serial_number,a.manufacturer,a.model,a.location_label,e.legal_name) ILIKE $6 ESCAPE '!')
    AND ($7::timestamptz IS NULL OR (a.created_at,a.id)<($7::timestamptz,$8::uuid))
   ORDER BY a.created_at DESC,a.id DESC LIMIT $9`,[p.organizationId,branch,cost,status??null,assetType??null,term?`%${escaped}%`:null,cursorAt,cursor??null,limit+1]);
  const data=result.rows.slice(0,limit);return {data,meta:{limit,nextCursor:result.rows.length>limit?data.at(-1)!.id:null}};
 }

 async summary(branch:string,p:AuthPrincipal){
  await this.scope(branch,p,'operational_asset.read');
  const [statuses,types,months,incidents,total]=await Promise.all([
   this.pool.query(`SELECT status,count(*)::int AS count FROM operational_assets WHERE organization_id=$1 AND branch_id=$2 GROUP BY status`,[p.organizationId,branch]),
   this.pool.query(`SELECT asset_type AS "assetType",count(*)::int AS count FROM operational_assets WHERE organization_id=$1 AND branch_id=$2 GROUP BY asset_type`,[p.organizationId,branch]),
   this.pool.query(`SELECT to_char(months.month,'YYYY-MM') AS month,count(e.id)::int AS count FROM generate_series(date_trunc('month',now())-interval '5 months',date_trunc('month',now()),interval '1 month') months(month)
    LEFT JOIN operational_asset_events e ON e.organization_id=$1 AND e.occurred_at>=months.month AND e.occurred_at<months.month+interval '1 month'
     AND (e.from_branch_id=$2 OR e.to_branch_id=$2) GROUP BY months.month ORDER BY months.month`,[p.organizationId,branch]),
   this.pool.query(`SELECT count(*)::int AS count FROM incidents WHERE organization_id=$1 AND branch_id=$2 AND asset_type='operational_asset'
    AND category IN('equipment_damage','asset_missing') AND status NOT IN('resolved','closed')`,[p.organizationId,branch]),
   this.pool.query(`SELECT count(*)::int AS count FROM operational_assets WHERE organization_id=$1 AND branch_id=$2`,[p.organizationId,branch]),
  ]);
  const byStatus=Object.fromEntries(['available','assigned','under_repair','missing','retired'].map(status=>[status,Number(statuses.rows.find(x=>x.status===status)?.count??0)]));
  const byType=Object.fromEntries(typeCodes.map(type=>[type,Number(types.rows.find(x=>x.assetType===type)?.count??0)]));
  const active=Number(byStatus.available??0)+Number(byStatus.assigned??0);
  return {data:{total:Number(total.rows[0]?.count??0),active,byStatus,byType,openIncidents:Number(incidents.rows[0]?.count??0),eventsByMonth:months.rows}};
 }

 async create(branch:string,p:AuthPrincipal,input:CreateOperationalAssetDto,correlation:string){
  await this.scope(branch,p,'operational_asset.manage');
  if(input.acquisitionCostUsd!==undefined&&!await this.canReadCost(p,branch))throw new ForbiddenException('Permiso de costos de activos insuficiente.');
  const code=input.code.trim().toUpperCase(),name=input.name.trim(),note=input.note.trim();
  const values={branch,code,assetType:input.assetType,name,description:input.description?.trim()??'',manufacturer:input.manufacturer?.trim()||null,
   model:input.model?.trim()||null,serialNumber:input.serialNumber?.trim()||null,acquiredOn:input.acquiredOn??null,
   acquisitionCostUsd:input.acquisitionCostUsd??null,locationLabel:input.locationLabel?.trim()||null,note};
  const hash=digest({v:1,values});
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`operational-asset:${p.organizationId}:${input.commandId}`]);
   const replay=await this.replay(client,p,input.commandId,hash);
   if(replay){await client.query('COMMIT');return {data:{...replay,idempotentReplay:true}};}
   const inserted=await client.query<Snapshot>(`INSERT INTO operational_assets(organization_id,branch_id,code,asset_type,name,description,manufacturer,model,
     serial_number,acquired_on,acquisition_cost_usd,location_label,created_by)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
     RETURNING id,organization_id,branch_id,code,asset_type,name,description,manufacturer,model,serial_number,acquired_on,acquisition_cost_usd::text,location_label,custodian_employee_id,status,version`,
     [p.organizationId,branch,code,input.assetType,name,values.description,values.manufacturer,values.model,values.serialNumber,values.acquiredOn,values.acquisitionCostUsd,values.locationLabel,p.userId]);
   const asset=inserted.rows[0]!;
   await this.insertEvent(client,p,{asset,fromBranch:null,eventType:'created',fromStatus:null,toStatus:'available',fromCustodian:null,toCustodian:null,
    note,expectedVersion:null,commandId:input.commandId,requestHash:hash});
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'operational_asset.created',entityType:'operational_asset',entityId:asset.id,after:{code,assetType:asset.asset_type,name,status:'available'}});
   await client.query('COMMIT');return {data:{id:asset.id,code:asset.code,assetType:asset.asset_type,status:asset.status,version:asset.version,idempotentReplay:false}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(['23505','23514'].includes(codeOf(error)))throw new ConflictException('Código, serie o datos del activo duplicados o incompatibles.');throw error;}finally{client.release();}
 }

 async detail(branch:string,id:string,p:AuthPrincipal){
  await this.scope(branch,p,'operational_asset.read');
  if(!uuid(id))throw new BadRequestException('Identificador de activo inválido.');
  const cost=await this.canReadCost(p,branch);
  const result=await this.pool.query(`SELECT a.id,a.branch_id AS "branchId",b.name AS "branchName",a.code,a.asset_type AS "assetType",a.name,a.description,
   a.manufacturer,a.model,a.serial_number AS "serialNumber",a.acquired_on AS "acquiredOn",CASE WHEN $4::boolean THEN a.acquisition_cost_usd::text ELSE NULL END AS "acquisitionCostUsd",
   a.location_label AS "locationLabel",a.custodian_employee_id AS "custodianEmployeeId",e.legal_name AS "custodianName",a.status,a.version,a.created_at AS "createdAt",a.updated_at AS "updatedAt"
   FROM operational_assets a JOIN branches b ON b.id=a.branch_id AND b.organization_id=a.organization_id
   LEFT JOIN employees e ON e.id=a.custodian_employee_id AND e.organization_id=a.organization_id
   WHERE a.id=$1 AND a.organization_id=$2 AND (a.branch_id=$3 OR EXISTS(SELECT 1 FROM operational_asset_events x WHERE x.asset_id=a.id AND x.organization_id=a.organization_id AND (x.from_branch_id=$3 OR x.to_branch_id=$3)))`,
   [id,p.organizationId,branch,cost]);
  if(!result.rows[0])throw new NotFoundException('Activo fuera del ámbito de esta sucursal.');
  const events=await this.pool.query(`SELECT x.id,x.event_type AS "eventType",x.from_branch_id AS "fromBranchId",fb.name AS "fromBranchName",x.to_branch_id AS "toBranchId",tb.name AS "toBranchName",
   x.from_status AS "fromStatus",x.to_status AS "toStatus",x.from_custodian_employee_id AS "fromCustodianEmployeeId",fe.legal_name AS "fromCustodianName",
   x.to_custodian_employee_id AS "toCustodianEmployeeId",te.legal_name AS "toCustodianName",x.related_incident_id AS "relatedIncidentId",i.code AS "incidentCode",x.note,x.asset_version AS "assetVersion",x.actor_id AS "actorId",u.display_name AS "actorName",x.occurred_at AS "occurredAt"
   FROM operational_asset_events x LEFT JOIN branches fb ON fb.id=x.from_branch_id AND fb.organization_id=x.organization_id
   JOIN branches tb ON tb.id=x.to_branch_id AND tb.organization_id=x.organization_id
   LEFT JOIN employees fe ON fe.id=x.from_custodian_employee_id AND fe.organization_id=x.organization_id
   LEFT JOIN employees te ON te.id=x.to_custodian_employee_id AND te.organization_id=x.organization_id
   LEFT JOIN incidents i ON i.id=x.related_incident_id AND i.organization_id=x.organization_id
   JOIN users u ON u.id=x.actor_id AND u.organization_id=x.organization_id
   WHERE x.asset_id=$1 AND x.organization_id=$2 AND (x.from_branch_id=$3 OR x.to_branch_id=$3)
   ORDER BY x.occurred_at DESC,x.id DESC LIMIT 100`,[id,p.organizationId,branch]);
  return {data:{asset:result.rows[0],events:events.rows}};
 }

 async update(branch:string,id:string,p:AuthPrincipal,input:UpdateOperationalAssetDto,correlation:string){
  await this.scope(branch,p,'operational_asset.manage');
  if(input.acquisitionCostUsd!==undefined&&!await this.canReadCost(p,branch))throw new ForbiddenException('Permiso de costos de activos insuficiente.');
  const fields={name:input.name.trim(),description:input.description?.trim()??'',manufacturer:input.manufacturer?.trim()||null,model:input.model?.trim()||null,
   serialNumber:input.serialNumber?.trim()||null,acquiredOn:input.acquiredOn??null,...(input.acquisitionCostUsd===undefined?{}:{acquisitionCostUsd:input.acquisitionCostUsd??null}),locationLabel:input.locationLabel?.trim()||null,note:input.note.trim()};
  return this.mutate(branch,id,p,input.expectedVersion,input.commandId,'profile_changed',fields,fields.note,correlation,async(client,current)=>{
   const updated=await client.query<Snapshot>(`UPDATE operational_assets SET name=$4,description=$5,manufacturer=$6,model=$7,serial_number=$8,acquired_on=$9,
    acquisition_cost_usd=$10,location_label=$11,version=version+1,updated_at=clock_timestamp()
    WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND version=$12 RETURNING id,organization_id,branch_id,code,asset_type,name,description,manufacturer,model,serial_number,acquired_on,acquisition_cost_usd::text,location_label,custodian_employee_id,status,version`,
    [id,p.organizationId,branch,fields.name,fields.description,fields.manufacturer,fields.model,fields.serialNumber,fields.acquiredOn,input.acquisitionCostUsd===undefined?current.acquisition_cost_usd:input.acquisitionCostUsd??null,fields.locationLabel,input.expectedVersion]);
   if(!updated.rows[0])throw new ConflictException('La ficha cambió. Actualiza los datos antes de guardar.');
   return {asset:updated.rows[0],fromStatus:current.status,toStatus:current.status,fromCustodian:current.custodian_employee_id,toCustodian:current.custodian_employee_id};
  });
 }

 async assign(branch:string,id:string,p:AuthPrincipal,input:AssignOperationalAssetDto,correlation:string){
  await this.scope(branch,p,'operational_asset.manage');
  const custodian=input.custodianEmployeeId??null,note=input.note.trim(),data={custodianEmployeeId:custodian,note};
  return this.mutate(branch,id,p,input.expectedVersion,input.commandId,'assignment_changed',data,note,correlation,async(client,current)=>{
   if(!['available','assigned'].includes(current.status))throw new ConflictException('Solo un activo disponible puede asignarse o devolverse.');
   if(current.custodian_employee_id===custodian)throw new BadRequestException('El custodio seleccionado ya tiene este activo asignado.');
   const status=custodian?'assigned':'available';
   const changed=await client.query<Snapshot>(`UPDATE operational_assets SET custodian_employee_id=$4,status=$5,version=version+1,updated_at=clock_timestamp()
    WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND version=$6 RETURNING id,organization_id,branch_id,code,asset_type,name,description,manufacturer,model,serial_number,acquired_on,acquisition_cost_usd::text,location_label,custodian_employee_id,status,version`,
    [id,p.organizationId,branch,custodian,status,input.expectedVersion]);
   if(!changed.rows[0])throw new ConflictException('El activo cambió durante la asignación. Actualiza la ficha.');
   return {asset:changed.rows[0],fromStatus:current.status,toStatus:status,fromCustodian:current.custodian_employee_id,toCustodian:custodian};
  });
 }

 async changeStatus(branch:string,id:string,p:AuthPrincipal,input:ChangeOperationalAssetStatusDto,correlation:string){
  const permission=input.status==='available'?'operational_asset.verify':input.status==='retired'?'operational_asset.retire':'operational_asset.manage';
  await this.scope(branch,p,permission);
  const status=input.status,note=input.note.trim(),data={status,note};
  return this.mutate(branch,id,p,input.expectedVersion,input.commandId,'status_changed',data,note,correlation,async(client,current)=>{
   if(current.status==='retired'||current.status==='missing'&&status!=='retired'&&status!=='available')throw new ConflictException('El estado actual requiere revisar la incidencia o el historial del activo.');
   if(current.status==='missing'&&status==='available'&&permission!=='operational_asset.verify')throw new ForbiddenException('La recuperación de un activo perdido requiere verificación.');
   if(current.status==='assigned'&&status==='available')throw new ConflictException('Devuelve el activo desde la acción de asignación.');
   if(current.status==='available'&&status==='available'||current.status==='under_repair'&&status==='under_repair')throw new BadRequestException('El activo ya tiene ese estado.');
   const changed=await client.query<Snapshot>(`UPDATE operational_assets SET status=$4,custodian_employee_id=NULL,version=version+1,updated_at=clock_timestamp()
    WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND version=$5 RETURNING id,organization_id,branch_id,code,asset_type,name,description,manufacturer,model,serial_number,acquired_on,acquisition_cost_usd::text,location_label,custodian_employee_id,status,version`,
    [id,p.organizationId,branch,status,input.expectedVersion]);
   if(!changed.rows[0])throw new ConflictException('El estado del activo cambió. Actualiza la ficha.');
   return {asset:changed.rows[0],fromStatus:current.status,toStatus:status,fromCustodian:current.custodian_employee_id,toCustodian:null};
  });
 }

 async transfer(branch:string,id:string,p:AuthPrincipal,input:TransferOperationalAssetDto,correlation:string){
  await this.scope(branch,p,'operational_asset.transfer');
  await this.scope(input.targetBranchId,p,'operational_asset.transfer');
  if(input.targetBranchId===branch)throw new BadRequestException('Selecciona otra sucursal para transferir el activo.');
  const note=input.note.trim(),hash=digest({v:1,branch,id,targetBranchId:input.targetBranchId,expectedVersion:input.expectedVersion,note});
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`operational-asset:${p.organizationId}:${input.commandId}`]);
   const replay=await this.replay(client,p,input.commandId,hash);if(replay){await client.query('COMMIT');return {data:{...replay,idempotentReplay:true}};}
   const current=await this.current(client,id,p,branch);
   if(current.version!==input.expectedVersion)throw new ConflictException('El activo cambió. Actualiza la ficha antes de transferir.');
   if(current.status==='retired'||current.status==='missing')throw new ConflictException('Un activo perdido o retirado no se puede transferir.');
   const updated=await client.query<Snapshot>(`UPDATE operational_assets SET branch_id=$4,status='available',custodian_employee_id=NULL,version=version+1,updated_at=clock_timestamp()
    WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND version=$5 RETURNING id,organization_id,branch_id,code,asset_type,name,description,manufacturer,model,serial_number,acquired_on,acquisition_cost_usd::text,location_label,custodian_employee_id,status,version`,
    [id,p.organizationId,branch,input.targetBranchId,input.expectedVersion]);
   if(!updated.rows[0])throw new ConflictException('El activo cambió durante la transferencia.');
   await this.insertEvent(client,p,{asset:updated.rows[0],fromBranch:branch,eventType:'transferred',fromStatus:current.status,toStatus:'available',fromCustodian:current.custodian_employee_id,toCustodian:null,note,expectedVersion:current.version,commandId:input.commandId,requestHash:hash});
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'operational_asset.transferred',entityType:'operational_asset',entityId:id,before:{branchId:branch,status:current.status},after:{branchId:input.targetBranchId,status:'available'}});
   await client.query('COMMIT');return {data:{id,branchId:input.targetBranchId,status:'available',version:updated.rows[0]!.version,idempotentReplay:false}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(codeOf(error)==='23505')throw new ConflictException('El código o serie ya existe en la sucursal destino.');if(codeOf(error)==='23514')throw new ConflictException('La sucursal destino o custodia no es válida.');throw error;}finally{client.release();}
 }

 private async mutate(branch:string,id:string,p:AuthPrincipal,expectedVersion:number,commandId:string,eventType:EventType,values:Record<string,unknown>,note:string,correlation:string,
  change:(client:PoolClient,current:Snapshot)=>Promise<{asset:Snapshot;fromStatus:string;toStatus:string;fromCustodian:string|null;toCustodian:string|null}>){
  if(!uuid(id))throw new BadRequestException('Identificador de activo inválido.');
  const hash=digest({v:1,branch,id,eventType,expectedVersion,values});const client=await this.pool.connect();
  try{
   await client.query('BEGIN');await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`operational-asset:${p.organizationId}:${commandId}`]);
   const replay=await this.replay(client,p,commandId,hash);if(replay){await client.query('COMMIT');return {data:{...replay,idempotentReplay:true}};}
   const current=await this.current(client,id,p,branch);if(current.version!==expectedVersion)throw new ConflictException('La ficha cambió. Actualiza y vuelve a revisar.');
   const changed=await change(client,current);
   await this.insertEvent(client,p,{asset:changed.asset,fromBranch:branch,eventType,fromStatus:changed.fromStatus,toStatus:changed.toStatus,fromCustodian:changed.fromCustodian,toCustodian:changed.toCustodian,note,
    expectedVersion,commandId,requestHash:hash});
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:`operational_asset.${eventType}`,entityType:'operational_asset',entityId:id,before:{status:current.status,version:current.version,custodianEmployeeId:current.custodian_employee_id},after:{status:changed.asset.status,version:changed.asset.version,custodianEmployeeId:changed.asset.custodian_employee_id}});
   await client.query('COMMIT');return {data:{id,version:changed.asset.version,status:changed.asset.status,custodianEmployeeId:changed.asset.custodian_employee_id,idempotentReplay:false}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(codeOf(error)==='23514')throw new ConflictException('La persona, estado o sucursal no corresponde al activo.');throw error;}finally{client.release();}
 }

 private async current(client:PoolClient,id:string,p:AuthPrincipal,branch:string){
  const r=await client.query<Snapshot>(`SELECT id,organization_id,branch_id,code,asset_type,name,description,manufacturer,model,serial_number,acquired_on,acquisition_cost_usd::text,location_label,custodian_employee_id,status,version
   FROM operational_assets WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE`,[id,p.organizationId,branch]);
  if(!r.rows[0])throw new NotFoundException('Activo no encontrado en esta sucursal.');return r.rows[0];
 }
 private async replay(client:PoolClient,p:AuthPrincipal,commandId:string,hash:string){
  const r=await client.query<{asset_id:string;request_hash:string;actor_id:string;asset_version:number;to_status:string;to_branch_id:string;to_custodian_employee_id:string|null}>(
   `SELECT asset_id,request_hash,actor_id,asset_version,to_status,to_branch_id,to_custodian_employee_id FROM operational_asset_events WHERE organization_id=$1 AND command_id=$2`,[p.organizationId,commandId]);
  const row=r.rows[0];if(!row)return null;if(row.request_hash!==hash||row.actor_id!==p.userId)throw new ConflictException('Este comando ya se usó con otros datos.');
  return {id:row.asset_id,version:row.asset_version,status:row.to_status,branchId:row.to_branch_id,custodianEmployeeId:row.to_custodian_employee_id};
 }
 private async insertEvent(client:PoolClient,p:AuthPrincipal,x:{asset:Snapshot;fromBranch:string|null;eventType:string;fromStatus:string|null;toStatus:string;fromCustodian:string|null;toCustodian:string|null;relatedIncidentId?:string|null;note:string;expectedVersion:number|null;commandId:string;requestHash:string}){
  await client.query(`INSERT INTO operational_asset_events(organization_id,asset_id,from_branch_id,to_branch_id,event_type,from_status,to_status,from_custodian_employee_id,to_custodian_employee_id,
   related_incident_id,note,asset_version,expected_version,command_id,request_hash,actor_id)
   VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`,[p.organizationId,x.asset.id,x.fromBranch,x.asset.branch_id,x.eventType,x.fromStatus,x.toStatus,x.fromCustodian,x.toCustodian,x.relatedIncidentId??null,x.note,x.asset.version,x.expectedVersion,x.commandId,x.requestHash,p.userId]);
 }
}

function uuid(value:string){return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);}
function digest(value:unknown){return createHash('sha256').update(JSON.stringify(value)).digest('hex');}
function codeOf(error:unknown){return (error as {code?:string})?.code??'';}
function escapeLike(value:string){return value.replaceAll('!','!!').replaceAll('%','!%').replaceAll('_','!_');}
