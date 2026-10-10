import { BadRequestException, ConflictException, ForbiddenException, HttpException, HttpStatus, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import { JobsStore } from '../jobs/jobs.store.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { serializeReportCsv } from './csv-report.js';
import { serializeReportPdf, serializeReportXlsx, type ReportDocument } from './export-documents.js';

type ReportType='closed_cuts'|'fuel_sales'|'tank_movements'|'incidents'|'purchase_orders'|'fuel_prices'|'expenses'|'cash_closures'|'store_stock'|'maintenance_orders'|'staff_shifts'|'operational_assets';
type ServiceMode='full_service'|'self_service';
type ReportGroupBy='day'|'fuel'|'dispenser'|'service_mode';
type Filters={type:ReportType;from:string;to:string;productId?:string;dispenserId?:string;serviceMode?:ServiceMode;groupBy?:ReportGroupBy;status?:string;commandId:string};
type ReportFilters={type:ReportType;from:string;to:string;productId:string|null;dispenserId:string|null;serviceMode:ServiceMode|null;groupBy:ReportGroupBy|null;status:string|null};
interface ReportRunRow {
 id:string;branch_id:string;organization_id:string;created_by:string;report_type:ReportType;
 filter_snapshot:ReportFilters;rows_externalized:boolean;rows_snapshot:Array<Record<string,unknown>>;
 row_count:number;as_of:Date;source_watermark:Date|null;timezone:string;unit:string;currency:string;
 snapshot_complete:boolean|null;expires_at:Date;
}
class ExportCancelledError extends Error {}
const MAX_REPORT_EXPORT_SOURCE_BYTES=64*1024*1024;
export function appendReportRowsWithinMemoryLimit(target:Array<Record<string,unknown>>,batch:Array<Record<string,unknown>>,
 totalBytes:number,limit=MAX_REPORT_EXPORT_SOURCE_BYTES):number{
 let nextBytes=totalBytes;
 for(const row of batch){nextBytes+=Buffer.byteLength(JSON.stringify(row)??'null');
  if(nextBytes>limit)throw new BadRequestException('El reporte supera el límite de 64 MiB de datos fuente. Reduce el periodo o aplica filtros.');}
 target.push(...batch);return nextBytes;
}
const allowed:Record<ReportType,string>={closed_cuts:'cut.read',fuel_sales:'sale.read',tank_movements:'inventory.read',incidents:'incident.read',purchase_orders:'purchase.read',fuel_prices:'price.read',expenses:'finance.cost.read',cash_closures:'cash.read',store_stock:'pos.catalog.read',maintenance_orders:'maintenance.plan',staff_shifts:'staff.read',operational_assets:'operational_asset.read'};
const units:Record<ReportType,string>={closed_cuts:'liter',fuel_sales:'usd',tank_movements:'liter',incidents:'record',purchase_orders:'record',fuel_prices:'usd',expenses:'usd',cash_closures:'usd',store_stock:'record',maintenance_orders:'record',staff_shifts:'record',operational_assets:'event'};
const columns:Record<ReportType,string[]>={
 closed_cuts:['operationalDate','slot','status','closedAt','closedBy','salesUsd','reviewRequired','productSummary'],
 fuel_sales:['id','occurredAt','dispenserCode','fuelName','liters','totalUsd','paymentStatus'],
 tank_movements:['id','occurredAt','tankCode','fuelName','movementType','deltaLiters','balanceLiters','costQuality'],
 incidents:['id','code','occurredAt','category','severity','status','description'],
 purchase_orders:['id','orderNumber','createdAt','supplierName','status','lineCount'],
 fuel_prices:['effectiveAt','fuelName','serviceMode','price','unit','version','status'],
 expenses:['id','incurredOn','category','costCenter','amountUsd','status','sourceKind'],
 cash_closures:['id','createdAt','reviewStatus','expectedCashUsd','countedCashUsd','varianceCashUsd','expectedCardUsd','settledCardUsd','varianceCardUsd'],
 store_stock:['productName','kind','movementCount','receivedUnits','soldUnits','netUnits','latestMovementAt'],
 maintenance_orders:['id','kind','status','assetType','assetLabel','dueAt','estimateUsd','createdAt'],
 staff_shifts:['date','position','status','shiftCount','plannedHours'],
 operational_assets:['occurredAt','code','assetType','assetName','eventType','fromStatus','toStatus','fromBranch','toBranch','custodian','incidentCode','note'],
};
function columnsFor(type:ReportType,filters?:ReportFilters):string[]{
 return type==='fuel_sales'&&filters?.groupBy?['groupBy','groupValue','saleCount','liters','totalUsd']:columns[type];
}
@Injectable()
export class ReportsService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService,
  private readonly jobs:JobsStore){}
 private async scope(p:AuthPrincipal,branch:string,type:ReportType,exporting=false){
  const permissions=await this.auth.capabilities(p,branch);
  if(!permissions.includes('report.read')||!permissions.includes(allowed[type])
   ||type==='closed_cuts'&&!permissions.includes('sale.read')
   ||exporting&&!permissions.includes('report.export'))
   throw new ForbiddenException('Permiso de reporte insuficiente.');
  const b=await this.pool.query<{timezone:string}>(`SELECT timezone FROM branches WHERE id=$1 AND organization_id=$2`,[branch,p.organizationId]);
  if(!b.rows[0])throw new NotFoundException('Sucursal fuera del ámbito.');
  return b.rows[0].timezone;
 }
 private validate(x:Filters){
  if(!Object.hasOwn(allowed,x.type)||!uuid(x.commandId)||!date(x.from)||!date(x.to)||x.from>x.to
   ||Date.parse(x.to)-Date.parse(x.from)>366*86400000||x.productId!==undefined&&!uuid(x.productId)
   ||x.dispenserId!==undefined&&!uuid(x.dispenserId)||x.status!==undefined&&!/^[a-z_]{2,40}$/.test(x.status)
   ||x.serviceMode!==undefined&&!['full_service','self_service'].includes(x.serviceMode)
   ||x.groupBy!==undefined&&!['day','fuel','dispenser','service_mode'].includes(x.groupBy))
   throw new BadRequestException('Filtro de reporte inválido (máximo 366 días).');
  if(x.dispenserId&&x.type!=='fuel_sales'||x.productId&& !['fuel_sales','tank_movements'].includes(x.type)
   ||x.serviceMode&&x.type!=='fuel_sales'||x.groupBy&&x.type!=='fuel_sales'
   ||x.status&& !['incidents','purchase_orders','expenses','cash_closures','maintenance_orders','staff_shifts','operational_assets'].includes(x.type))
   throw new BadRequestException('Filtro incompatible con la plantilla.');
  if(x.status&&x.type==='incidents'&&!['reported','assessed','in_progress','resolved','closed'].includes(x.status)
   ||x.status&&x.type==='purchase_orders'&&!['draft','pending_approval','approved','ordered','partially_received','received','rejected','cancelled'].includes(x.status))
   throw new BadRequestException('Estado no válido para el reporte.');
  if(x.status&&x.type==='operational_assets'&&!['available','assigned','under_repair','missing','retired'].includes(x.status))
   throw new BadRequestException('Estado no válido para el reporte de activos.');
  if(x.status&&x.type==='expenses'&&!['pending','approved','rejected','paid','partially_paid'].includes(x.status)
   ||x.status&&x.type==='cash_closures'&&!['balanced','pending_review'].includes(x.status)
   ||x.status&&x.type==='maintenance_orders'&&!['planned','in_progress','completed','verified','cancelled'].includes(x.status)
   ||x.status&&x.type==='staff_shifts'&&!['scheduled','cancelled'].includes(x.status))
   throw new BadRequestException('Estado no válido para el reporte.');
 }
 async create(branch:string,p:AuthPrincipal,x:Filters,correlation:string){
  this.validate(x);const timezone=await this.scope(p,branch,x.type);
  const filters={type:x.type,from:x.from,to:x.to,productId:x.productId??null,dispenserId:x.dispenserId??null,
   serviceMode:x.serviceMode??null,groupBy:x.groupBy??null,status:x.status??null};
  const hash=createHash('sha256').update(JSON.stringify({branch,filters})).digest('hex');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   await client.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['report-run:'+p.organizationId+':'+x.commandId]);
   const old=await client.query<{id:string;request_hash:string;created_by:string;branch_id:string}>(`SELECT id,request_hash,created_by,branch_id FROM report_runs WHERE organization_id=$1 AND command_id=$2`,[p.organizationId,x.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].created_by!==p.userId||old.rows[0].branch_id!==branch)
     throw new ConflictException('El identificador de solicitud pertenece a otro reporte.');
    await client.query('COMMIT');return {data:{id:old.rows[0].id,idempotentReplay:true}};
   }
   const asOf=await client.query<{as_of:Date}>(`SELECT clock_timestamp() AS as_of`);
   const created=await client.query<{id:string}>(`INSERT INTO report_runs(organization_id,branch_id,report_type,filter_snapshot,rows_snapshot,
    row_count,as_of,source_watermark,timezone,unit,created_by,command_id,request_hash,rows_externalized,snapshot_complete)
    VALUES($1,$2,$3,$4::jsonb,'[]'::jsonb,0,$5,NULL,$6,$7,$8,$9,$10,true,false) RETURNING id`,
    [p.organizationId,branch,x.type,JSON.stringify(filters),asOf.rows[0]!.as_of,timezone,units[x.type],p.userId,x.commandId,hash]);
   const runID=created.rows[0]!.id,batchSize=500;let offset=0,watermark:string|null=null;
   while(true){
    const rows=await this.query(client,p,branch,timezone,filters,offset,batchSize);
    if(!rows.length)break;
    if(offset+rows.length>100000)throw new BadRequestException('El reporte supera 100,000 filas. Acota el periodo o aplica filtros.');
    const timestamps=rows.map(row=>row.sourceAt).filter((value):value is string|Date=>typeof value==='string'||value instanceof Date)
      .map(value=>new Date(value).toISOString()).sort();
    if(timestamps.length&&(!watermark||timestamps.at(-1)!>watermark))watermark=timestamps.at(-1)!;
    await client.query(`INSERT INTO report_run_rows(report_run_id,organization_id,row_index,row_data)
      SELECT $1,$2,$3+(entry.ordinality::integer-1),entry.row
      FROM jsonb_array_elements($4::jsonb) WITH ORDINALITY AS entry(row,ordinality)`,
      [runID,p.organizationId,offset,JSON.stringify(rows)]);
    offset+=rows.length;if(rows.length<batchSize)break;
   }
   await client.query(`UPDATE report_runs SET row_count=$2,source_watermark=$3,snapshot_complete=true
     WHERE id=$1 AND snapshot_complete=false`,[runID,offset,watermark]);
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,
    action:'report.run.created',entityType:'report_run',entityId:runID,after:{type:x.type,filters,rowCount:offset}});
   await client.query('COMMIT');return {data:{id:runID,rowCount:offset,idempotentReplay:false}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
 }
 async list(branch:string,p:AuthPrincipal){
  const permissions=await this.auth.capabilities(p,branch);
  if(!permissions.includes('report.read'))throw new ForbiddenException('Permiso de reporte insuficiente.');
  const visible=Object.entries(allowed).filter(([type,permission])=>permissions.includes(permission)
   &&(type!=='closed_cuts'||permissions.includes('sale.read'))).map(([type])=>type);
  const r=await this.pool.query(`SELECT id,report_type AS type,filter_snapshot AS filters,row_count AS "rowCount",
   as_of AS "asOf",source_watermark AS "sourceWatermark",created_at AS "createdAt",expires_at AS "expiresAt"
   FROM report_runs WHERE organization_id=$1 AND branch_id=$2 AND created_by=$3 AND report_type=ANY($4::text[])
   ORDER BY created_at DESC,id DESC LIMIT 100`,[p.organizationId,branch,p.userId,visible]);return {data:r.rows};
 }
 async savedFilters(branch:string,p:AuthPrincipal){
  const permissions=await this.auth.capabilities(p,branch);
  if(!permissions.includes('report.read'))throw new ForbiddenException('Permiso de reporte insuficiente.');
  const visible=Object.entries(allowed).filter(([type,permission])=>permissions.includes(permission)
   &&(type!=='closed_cuts'||permissions.includes('sale.read'))).map(([type])=>type);
  const r=await this.pool.query(`SELECT id,name,report_type AS type,filters,version,updated_at AS "updatedAt"
   FROM saved_report_filters WHERE organization_id=$1 AND branch_id=$2 AND user_id=$3
   AND report_type=ANY($4::text[]) ORDER BY updated_at DESC,id DESC LIMIT 100`,
   [p.organizationId,branch,p.userId,visible]);return {data:r.rows};
 }
 async saveFilter(branch:string,p:AuthPrincipal,input:{name:string;type:ReportType;from:string;to:string;
  productId?:string;dispenserId?:string;serviceMode?:ServiceMode;groupBy?:ReportGroupBy;status?:string},correlation:string){
  this.validate({...input,commandId:'11111111-1111-4111-8111-111111111111'});
  await this.scope(p,branch,input.type);
  const name=input.name?.trim();if(!name||name.length<2||name.length>80)throw new BadRequestException('Nombre de filtro inválido.');
  const filters={from:input.from,to:input.to,productId:input.productId??null,dispenserId:input.dispenserId??null,
   serviceMode:input.serviceMode??null,groupBy:input.groupBy??null,status:input.status??null};
  const c=await this.pool.connect();
  try{await c.query('BEGIN');
   const result=await c.query<{id:string}>(`INSERT INTO saved_report_filters(organization_id,branch_id,user_id,name,report_type,filters)
    VALUES($1,$2,$3,$4,$5,$6::jsonb) ON CONFLICT(organization_id,user_id,branch_id,name) DO NOTHING RETURNING id`,
    [p.organizationId,branch,p.userId,name,input.type,JSON.stringify(filters)]);
   let id=result.rows[0]?.id;let replay=false;
   if(!id){const old=await c.query<{id:string;matches:boolean}>(`SELECT id,report_type=$5 AND filters=$6::jsonb AS matches FROM saved_report_filters
    WHERE organization_id=$1 AND branch_id=$2 AND user_id=$3 AND name=$4`,
    [p.organizationId,branch,p.userId,name,input.type,JSON.stringify(filters)]);
    if(!old.rows[0]?.matches)
     throw new ConflictException('Ya existe un filtro con ese nombre y otros valores.');
    id=old.rows[0].id;replay=true;
   }
   if(!replay)await this.audit.appendTransaction(c,{principal:p,branchId:branch,correlationId:correlation,
    action:'report.filter.saved',entityType:'saved_report_filter',entityId:id!,after:{name,type:input.type,filters}});
   await c.query('COMMIT');return {data:{id,name,type:input.type,filters,idempotentReplay:replay}};
  }catch(error){await c.query('ROLLBACK').catch(()=>undefined);throw error;}finally{c.release();}
 }
 async deleteFilter(branch:string,id:string,p:AuthPrincipal,correlation:string){
  if(!uuid(id))throw new BadRequestException('Filtro inválido.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const found=await client.query<{id:string;report_type:ReportType;name:string}>(
    `SELECT id,report_type,name FROM saved_report_filters
      WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND user_id=$4 FOR UPDATE`,
    [id,p.organizationId,branch,p.userId]);
   const filter=found.rows[0];
   if(!filter)throw new NotFoundException('Filtro no encontrado.');
   await this.scope(p,branch,filter.report_type);
   await client.query('DELETE FROM saved_report_filters WHERE id=$1',[id]);
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,
    action:'report.filter.deleted',entityType:'saved_report_filter',entityId:id,before:{name:filter.name,type:filter.report_type}});
   await client.query('COMMIT');return {data:{id,deleted:true}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
 }
 private async run(branch:string,id:string,p:AuthPrincipal,exporting=false){
  if(!uuid(id))throw new BadRequestException('Reporte inválido.');
  const r=await this.pool.query<ReportRunRow>(`SELECT * FROM report_runs WHERE id=$1 AND branch_id=$2 AND organization_id=$3
   AND created_by=$4 AND expires_at>clock_timestamp()`,[id,branch,p.organizationId,p.userId]);
  if(!r.rows[0])throw new NotFoundException('Reporte vencido o fuera de la sesión.');
  if(r.rows[0].snapshot_complete===false)throw new ConflictException('El reporte todavía se está finalizando.');
  await this.scope(p,branch,r.rows[0].report_type,exporting);
  return r.rows[0];
 }
 private async snapshotRows(run:ReportRunRow,p:AuthPrincipal,offset:number,limit:number):Promise<Array<Record<string,unknown>>>{
  if(!run.rows_externalized)return run.rows_snapshot.slice(offset,offset+limit);
  const result=await this.pool.query<{row_data:Record<string,unknown>}>(`SELECT row_data FROM report_run_rows
   WHERE report_run_id=$1 AND organization_id=$2 AND row_index>=$4 ORDER BY row_index LIMIT $3`,[run.id,p.organizationId,limit,offset]);
  return result.rows.map(row=>row.row_data);
 }
 private async allSnapshotRows(run:ReportRunRow,p:AuthPrincipal):Promise<Array<Record<string,unknown>>>{
  if(!run.rows_externalized){const legacy:Array<Record<string,unknown>>=[];
   appendReportRowsWithinMemoryLimit(legacy,run.rows_snapshot,0);return legacy;}
  if(!Number.isSafeInteger(Number(run.row_count))||Number(run.row_count)<0||Number(run.row_count)>100000)
   throw new BadRequestException('El reporte supera el límite de 100,000 filas.');
  const rows:Array<Record<string,unknown>>=[];let bytes=0;
  for(let offset=0;offset<Number(run.row_count);offset+=1000)
   bytes=appendReportRowsWithinMemoryLimit(rows,await this.snapshotRows(run,p,offset,1000),bytes);
  return rows;
 }
 async page(branch:string,id:string,p:AuthPrincipal,offsetRaw?:string){
  const r=await this.run(branch,id,p);
  const reportColumns=columnsFor(r.report_type as ReportType,r.filter_snapshot as ReportFilters);
  const offset=offsetRaw===undefined?0:Number(offsetRaw);
  if(!Number.isSafeInteger(offset)||offset<0||offset>r.row_count)throw new BadRequestException('Página inválida.');
  const pageRows=await this.snapshotRows(r,p,offset,100);
  return {data:{id:r.id,type:r.report_type,filters:r.filter_snapshot,rowCount:r.row_count,asOf:r.as_of,
   sourceWatermark:r.source_watermark,timezone:r.timezone,unit:r.unit,currency:r.currency,
   columns:reportColumns,
   rows:pageRows.map((row:Record<string,unknown>)=>Object.fromEntries(
    reportColumns.map(name=>[name,row[name]===null||row[name]===undefined?'':
     typeof row[name]==='object'?JSON.stringify(row[name]):String(row[name])]))),
   nextOffset:offset+100<r.row_count?offset+100:null}};
 }
 async csv(branch:string,id:string,p:AuthPrincipal,onProgress?:(completed:number,total:number)=>Promise<void>){
  const r=await this.run(branch,id,p,true),names=columnsFor(r.report_type as ReportType,r.filter_snapshot as ReportFilters);
  return {filename:`${r.report_type}-${r.id}.csv`,body:await serializeReportCsv(names,await this.allSnapshotRows(r,p),onProgress)};
 }
 private document(run:ReportRunRow):ReportDocument{
  const filters=run.filter_snapshot as ReportFilters;
  return {title:`Reporte ${run.report_type}`,period:`${filters.from} a ${filters.to}`,
   asOf:run.as_of,sourceWatermark:run.source_watermark,timezone:run.timezone,
   rowCount:run.row_count,columns:columnsFor(run.report_type as ReportType,filters)};
 }
 async xlsx(branch:string,id:string,p:AuthPrincipal,onProgress?:(completed:number,total:number)=>Promise<void>){
  const r=await this.run(branch,id,p,true),document=this.document(r);
  return {filename:`${r.report_type}-${r.id}.xlsx`,body:await serializeReportXlsx(document,await this.allSnapshotRows(r,p),onProgress)};
 }
 async pdf(branch:string,id:string,p:AuthPrincipal,onProgress?:(completed:number,total:number)=>Promise<void>){
  const r=await this.run(branch,id,p,true),document=this.document(r);
  return {filename:`${r.report_type}-${r.id}.pdf`,body:await serializeReportPdf(document,await this.allSnapshotRows(r,p),onProgress)};
 }
 async requestExport(branch:string,runID:string,p:AuthPrincipal,input:{format:'csv'|'xlsx'|'pdf';commandId:string},correlation:string){
  const report=await this.run(branch,runID,p,true);
  if(!uuid(input.commandId))throw new BadRequestException('Identificador de exportación inválido.');
  const requestHash=createHash('sha256').update(JSON.stringify({branch,runID,format:input.format,user:p.userId})).digest('hex');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['report-export:'+p.organizationId+':'+input.commandId]);
   const existing=await client.query<{id:string;request_hash:string;requested_by:string;branch_id:string}>(
    `SELECT id,request_hash,requested_by,branch_id FROM report_export_jobs WHERE organization_id=$1 AND command_id=$2`,
    [p.organizationId,input.commandId]);
   if(existing.rows[0]){
    const old=existing.rows[0];
    if(old.request_hash!==requestHash||old.requested_by!==p.userId||old.branch_id!==branch)
     throw new ConflictException('El identificador pertenece a otra exportación.');
    await client.query('COMMIT');return {data:{id:old.id,idempotentReplay:true}};
   }
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
    [`report-export-quota:${p.organizationId}:${branch}:${p.userId}`]);
   const active=await client.query<{count:string}>(`SELECT count(*)::text AS count FROM report_export_jobs
    WHERE organization_id=$1 AND branch_id=$2 AND requested_by=$3 AND state IN('queued','running')
      AND expires_at>clock_timestamp()`,[p.organizationId,branch,p.userId]);
   if(Number(active.rows[0]?.count??0)>=5)throw new HttpException('Ya tienes cinco exportaciones en proceso. Espera a que terminen antes de iniciar otra.',HttpStatus.TOO_MANY_REQUESTS);
   const created=await client.query<{id:string}>(`INSERT INTO report_export_jobs
    (organization_id,branch_id,report_run_id,requested_by,session_id,format,command_id,request_hash,progress_total)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
    [p.organizationId,branch,runID,p.userId,p.sessionId,input.format,input.commandId,requestHash,report.row_count]);
   const exportID=created.rows[0]!.id;
   await this.jobs.enqueue(client,'report.export.generate',`${p.organizationId}:report-export:${input.commandId}`,{exportId:exportID});
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,
    action:'report.export.queued',entityType:'report_export',entityId:exportID,after:{runID,format:input.format}});
   await client.query('COMMIT');return {data:{id:exportID,state:'queued',idempotentReplay:false}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
 }
 private async exportJob(branch:string,id:string,p:AuthPrincipal){
  if(!uuid(id))throw new BadRequestException('Exportación inválida.');
  const result=await this.pool.query(`SELECT j.*,r.report_type FROM report_export_jobs j
   JOIN report_runs r ON r.id=j.report_run_id WHERE j.id=$1 AND j.organization_id=$2
   AND j.branch_id=$3 AND j.requested_by=$4 AND j.expires_at>clock_timestamp()`,
   [id,p.organizationId,branch,p.userId]);
  if(!result.rows[0])throw new NotFoundException('Exportación vencida o fuera de la sesión.');
  await this.scope(p,branch,result.rows[0].report_type,true);
  return result.rows[0];
 }
 async exportStatus(branch:string,id:string,p:AuthPrincipal){
  const job=await this.exportJob(branch,id,p);
  const total=Number(job.progress_total??0),completed=Number(job.progress_rows??0);
  const percent=job.state==='succeeded'?100:total>0?Math.min(99,Math.floor(completed*100/total)):0;
  return {data:{id:job.id,state:job.state,format:job.format,filename:job.filename,
   error:job.state==='failed'?job.error_message:null,createdAt:job.created_at,completedAt:job.completed_at,
   progress:{completed,total,percent}}};
 }
 async exportDownload(branch:string,id:string,p:AuthPrincipal){
  const job=await this.exportJob(branch,id,p);
  if(job.state!=='succeeded')throw new ConflictException('La exportación todavía no está lista.');
  return {filename:job.filename,contentType:job.content_type,body:job.content};
 }
 async cancelExport(branch:string,id:string,p:AuthPrincipal,correlation:string){
  const visible=await this.exportJob(branch,id,p);
  if(!['queued','running'].includes(visible.state))return {data:{id,state:visible.state,cancelled:false}};
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const changed=await client.query(`UPDATE report_export_jobs SET state='cancelled',completed_at=clock_timestamp(),
    error_message='Cancelada por el usuario.' WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND requested_by=$4
      AND state IN('queued','running') RETURNING id`,[id,p.organizationId,branch,p.userId]);
   if(changed.rowCount===1)await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,
    action:'report.export.cancelled',entityType:'report_export',entityId:id,before:{state:visible.state},after:{state:'cancelled'}});
   const current=await client.query<{state:string}>('SELECT state FROM report_export_jobs WHERE id=$1',[id]);
   await client.query('COMMIT');
   return {data:{id,state:current.rows[0]?.state??'not_found',cancelled:changed.rowCount===1}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
 }
 async processExportJob(exportID:string,attempt:number){
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const result=await client.query<{id:string;organization_id:string;branch_id:string;requested_by:string;session_id:string;format:'csv'|'xlsx'|'pdf';processing_attempt:number;state:string;report_type:ReportType;permission_version:number}>(
    `SELECT j.id,j.organization_id,j.branch_id,j.requested_by,j.session_id,j.format,j.processing_attempt,j.state,
      r.report_type,s.permission_version FROM report_export_jobs j JOIN report_runs r ON r.id=j.report_run_id
      JOIN auth_sessions s ON s.id=j.session_id JOIN users u ON u.id=j.requested_by AND u.organization_id=j.organization_id
      WHERE j.id=$1 AND j.expires_at>clock_timestamp() AND s.revoked_at IS NULL AND s.expires_at>clock_timestamp()
        AND u.status='active' FOR UPDATE OF j`,[exportID]);
   const job=result.rows[0];
   if(!job){await client.query(`UPDATE report_export_jobs SET state='failed',error_message='Sesión vencida; vuelve a solicitar la exportación.',completed_at=clock_timestamp() WHERE id=$1 AND state IN('queued','running')`,[exportID]);await client.query('COMMIT');return;}
   if(job.processing_attempt>=attempt||!['queued','running'].includes(job.state)){await client.query('COMMIT');return;}
   const claimed=await client.query(`UPDATE report_export_jobs SET state='running',processing_attempt=$2,started_at=COALESCE(started_at,clock_timestamp()) WHERE id=$1 AND state IN('queued','running') AND processing_attempt<$2`,[exportID,attempt]);
   if(claimed.rowCount!==1){await client.query('COMMIT');return;}
   await client.query('COMMIT');
   const principal:AuthPrincipal={userId:job.requested_by,organizationId:job.organization_id,sessionId:job.session_id,permissionVersion:job.permission_version};
   await this.scope(principal,job.branch_id,job.report_type,true);
   const reportID=await this.reportRunID(exportID);
   const progress=async(completed:number,total:number)=>{
    const updated=await this.pool.query(`UPDATE report_export_jobs SET progress_rows=$3
     WHERE id=$1 AND processing_attempt=$2 AND state='running' AND progress_total=$4 AND $3<=$4`,
     [exportID,attempt,completed,total]);
    if(updated.rowCount!==1)throw new ExportCancelledError();
   };
   const output=job.format==='csv'?await this.csv(job.branch_id,reportID,principal,progress)
    :job.format==='xlsx'?await this.xlsx(job.branch_id,reportID,principal,progress)
    :await this.pdf(job.branch_id,reportID,principal,progress);
   const contentType=job.format==='csv'?'text/csv; charset=utf-8':job.format==='xlsx'
    ?'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'application/pdf';
   const bytes=Buffer.from(output.body);
   if(bytes.byteLength>32*1024*1024){await this.failExportJob(exportID,'El archivo supera el límite de 32 MiB. Reduce el periodo y vuelve a generarlo.');return;}
   await this.pool.query(`UPDATE report_export_jobs SET state='succeeded',filename=$3,content_type=$4,content=$5,
    completed_at=clock_timestamp(),error_message=NULL WHERE id=$1 AND processing_attempt=$2 AND state='running'`,
    [exportID,attempt,output.filename,contentType,bytes]);
  }catch(error){
   await client.query('ROLLBACK').catch(()=>undefined);
   if(error instanceof ExportCancelledError)return;
   if(error instanceof ForbiddenException||error instanceof NotFoundException){
    await this.failExportJob(exportID,'La sesión venció o ya no tienes permiso para exportar este reporte.');
    return;
   }
   throw error;
  }finally{client.release();}
 }
 async failExportJob(exportID:string,message:string){
  await this.pool.query(`UPDATE report_export_jobs SET state='failed',error_message=$2,completed_at=clock_timestamp()
   WHERE id=$1 AND state IN('queued','running')`,[exportID,message.slice(0,240)]);
 }
 async cleanupExpiredExports(){
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   await client.query(`DELETE FROM report_export_jobs WHERE expires_at<clock_timestamp() AND state IN('succeeded','failed','cancelled')`);
   await client.query(`DELETE FROM background_jobs WHERE job_type='report.export.generate' AND state IN('succeeded','dead')
    AND created_at<clock_timestamp()-interval '30 days'`);
   await client.query('COMMIT');
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
 }
 private async reportRunID(exportID:string):Promise<string>{
  const result=await this.pool.query<{report_run_id:string}>('SELECT report_run_id FROM report_export_jobs WHERE id=$1',[exportID]);
  if(!result.rows[0])throw new NotFoundException('Exportación no encontrada.');
  return result.rows[0].report_run_id;
 }
 private async query(c:PoolClient,p:AuthPrincipal,branch:string,timezone:string,f:ReportFilters,offset=0,batchSize=500):Promise<Array<Record<string,unknown>>>{
  const base=[p.organizationId,branch,f.from,f.to];
  let sql:string,args:unknown[];
  switch(f.type){
   case 'closed_cuts':sql=`SELECT c.operational_date::text AS "operationalDate",c.slot,c.status,
    cl.closed_at AS "closedAt",cl.closed_by AS "closedBy",prep.financial_summary->>'salesUsd' AS "salesUsd",
    prep.review_required AS "reviewRequired",prep.product_summary AS "productSummary",cl.closed_at AS "sourceAt"
    FROM operational_cuts c JOIN operational_cut_closures cl ON cl.cut_id=c.id
    JOIN operational_cut_preparations prep ON prep.id=cl.preparation_id
    WHERE c.organization_id=$1 AND c.branch_id=$2 AND c.operational_date BETWEEN $3::date AND $4::date
    ORDER BY c.operational_date,c.slot LIMIT 10001`;args=base;break;
   case 'fuel_sales':{
    if(f.groupBy){
     const dimensions:Record<ReportGroupBy,{key:string;value:string}>={
      day:{key:`(s.occurred_at AT TIME ZONE $7)::date`,value:`to_char((s.occurred_at AT TIME ZONE $7)::date,'YYYY-MM-DD')`},
      fuel:{key:'a.fuel_product_id',value:'f.display_name'},
      dispenser:{key:'d.id',value:'d.code'},
      service_mode:{key:'a.service_mode',value:"CASE a.service_mode WHEN 'full_service' THEN 'Servicio completo' ELSE 'Autoservicio' END"},
     };
     const dimension=dimensions[f.groupBy];
     sql=`SELECT $9::text AS "groupBy",${dimension.value} AS "groupValue",count(*)::integer AS "saleCount",
      sum(a.actual_l)::text AS liters,sum(s.total_usd)::text AS "totalUsd",max(s.occurred_at) AS "sourceAt"
      FROM sales s JOIN dispense_authorizations a ON a.id=s.authorization_id
      JOIN nozzles n ON n.id=a.nozzle_id JOIN dispensers d ON d.id=n.dispenser_id JOIN fuel_products f ON f.id=a.fuel_product_id
      WHERE s.organization_id=$1 AND s.branch_id=$2 AND s.occurred_at>=($3::date AT TIME ZONE $7)
       AND s.occurred_at<(($4::date+1) AT TIME ZONE $7) AND ($5::uuid IS NULL OR a.fuel_product_id=$5)
       AND ($6::uuid IS NULL OR d.id=$6) AND ($8::text IS NULL OR a.service_mode=$8)
      GROUP BY ${dimension.key},${dimension.value} ORDER BY "groupValue" LIMIT 10001`;
     args=[...base,f.productId,f.dispenserId,timezone,f.serviceMode,f.groupBy];
    }else{
     sql=`SELECT s.id,s.occurred_at AS "occurredAt",d.code AS "dispenserCode",
    f.display_name AS "fuelName",a.actual_l::text AS liters,s.total_usd::text AS "totalUsd",
    CASE WHEN EXISTS(SELECT 1 FROM payment_events e JOIN payment_attempts pa ON pa.id=e.attempt_id
     WHERE pa.sale_id=s.id AND e.outcome='confirmed') THEN 'confirmed_event' ELSE 'none_recorded' END AS "paymentStatus",
    s.occurred_at AS "sourceAt"
    FROM sales s JOIN dispense_authorizations a ON a.id=s.authorization_id
    JOIN nozzles n ON n.id=a.nozzle_id JOIN dispensers d ON d.id=n.dispenser_id
    JOIN fuel_products f ON f.id=a.fuel_product_id
    WHERE s.organization_id=$1 AND s.branch_id=$2 AND s.occurred_at>=($3::date AT TIME ZONE $7)
     AND s.occurred_at<(($4::date+1) AT TIME ZONE $7)
     AND ($5::uuid IS NULL OR a.fuel_product_id=$5) AND ($6::uuid IS NULL OR d.id=$6)
     AND ($8::text IS NULL OR a.service_mode=$8)
    ORDER BY s.occurred_at,s.id LIMIT 10001`;args=[...base,f.productId,f.dispenserId,timezone,f.serviceMode];
    }
    break;
   }
   case 'tank_movements':sql=`SELECT m.id,m.occurred_at AS "occurredAt",t.code AS "tankCode",f.display_name AS "fuelName",
    m.movement_type AS "movementType",m.delta_l::text AS "deltaLiters",m.after_quantity_l::text AS "balanceLiters",
    m.valuation_quality AS "costQuality",m.occurred_at AS "sourceAt"
    FROM inventory_movements m JOIN tanks t ON t.id=m.tank_id JOIN fuel_products f ON f.id=m.fuel_product_id
    WHERE m.organization_id=$1 AND m.branch_id=$2 AND m.occurred_at>=($3::date AT TIME ZONE $6)
     AND m.occurred_at<(($4::date+1) AT TIME ZONE $6) AND ($5::uuid IS NULL OR m.fuel_product_id=$5)
    ORDER BY m.occurred_at,m.id LIMIT 10001`;args=[...base,f.productId,timezone];break;
   case 'incidents':sql=`SELECT i.id,i.code,i.occurred_at AS "occurredAt",i.category,i.severity,i.status,i.description,
    i.reported_at AS "sourceAt" FROM incidents i WHERE i.organization_id=$1 AND i.branch_id=$2
    AND i.occurred_at>=($3::date AT TIME ZONE $6) AND i.occurred_at<(($4::date+1) AT TIME ZONE $6)
    AND ($5::text IS NULL OR i.status=$5) ORDER BY i.occurred_at,i.id LIMIT 10001`;args=[...base,f.status,timezone];break;
   case 'purchase_orders':sql=`SELECT o.id,o.order_number AS "orderNumber",o.created_at AS "createdAt",
    s.legal_name AS "supplierName",o.status,count(l.id)::integer AS "lineCount",o.updated_at AS "sourceAt"
    FROM purchase_orders o JOIN suppliers s ON s.id=o.supplier_id LEFT JOIN purchase_order_lines l ON l.purchase_order_id=o.id
    WHERE o.organization_id=$1 AND o.branch_id=$2 AND o.created_at>=($3::date AT TIME ZONE $6)
    AND o.created_at<(($4::date+1) AT TIME ZONE $6) AND ($5::text IS NULL OR o.status=$5)
    GROUP BY o.id,s.legal_name ORDER BY o.created_at,o.id LIMIT 10001`;args=[...base,f.status,timezone];break;
   case 'fuel_prices':sql=`SELECT v.effective_at AS "effectiveAt",f.display_name AS "fuelName",v.service_mode AS "serviceMode",
    v.price_usd_per_unit::text AS price,v.unit,v.version,p.status,v.effective_at AS "sourceAt"
    FROM fuel_price_versions v JOIN fuel_products f ON f.id=v.fuel_product_id
    JOIN fuel_price_proposals p ON p.id=v.proposal_id
    WHERE v.organization_id=$1 AND v.branch_id=$2 AND v.effective_at>=($3::date AT TIME ZONE $5)
     AND v.effective_at<(($4::date+1) AT TIME ZONE $5) AND ($6::uuid IS NULL OR v.fuel_product_id=$6)
    ORDER BY v.effective_at,v.fuel_product_id,v.service_mode LIMIT 10001`;args=[...base,timezone,f.productId];break;
   case 'expenses':sql=`SELECT e.id,e.incurred_on::text AS "incurredOn",c.name AS category,e.cost_center AS "costCenter",
    e.amount_usd::text AS "amountUsd",CASE WHEN d.outcome='rejected' THEN 'rejected'
     WHEN coalesce(paid.amount,0)>=e.amount_usd THEN 'paid' WHEN d.outcome='approved' AND coalesce(paid.amount,0)>0 THEN 'partially_paid'
     WHEN d.outcome='approved' THEN 'approved' ELSE 'pending' END AS status,e.source_kind AS "sourceKind",e.created_at AS "sourceAt"
    FROM expense_claims e JOIN expense_categories c ON c.id=e.category_id
    LEFT JOIN expense_decisions d ON d.expense_id=e.id
    LEFT JOIN LATERAL(SELECT sum(x.amount_usd) AS amount FROM expense_disbursements x WHERE x.expense_id=e.id) paid ON true
    WHERE e.organization_id=$1 AND e.branch_id=$2 AND e.incurred_on BETWEEN $3::date AND $4::date
     AND ($5::text IS NULL OR CASE WHEN d.outcome='rejected' THEN 'rejected'
      WHEN coalesce(paid.amount,0)>=e.amount_usd THEN 'paid' WHEN d.outcome='approved' AND coalesce(paid.amount,0)>0 THEN 'partially_paid'
      WHEN d.outcome='approved' THEN 'approved' ELSE 'pending' END=$5)
    ORDER BY e.incurred_on,e.id LIMIT 10001`;args=[...base,f.status];break;
   case 'cash_closures':sql=`SELECT c.id,c.created_at AS "createdAt",c.review_status AS "reviewStatus",
    c.expected_cash_usd::text AS "expectedCashUsd",c.counted_cash_usd::text AS "countedCashUsd",
    c.variance_cash_usd::text AS "varianceCashUsd",c.expected_card_usd::text AS "expectedCardUsd",
    c.settled_card_usd::text AS "settledCardUsd",c.variance_card_usd::text AS "varianceCardUsd",c.created_at AS "sourceAt"
    FROM cash_closures c WHERE c.organization_id=$1 AND c.branch_id=$2
     AND c.created_at>=($3::date AT TIME ZONE $5) AND c.created_at<(($4::date+1) AT TIME ZONE $5)
     AND ($6::text IS NULL OR c.review_status=$6) ORDER BY c.created_at,c.id LIMIT 10001`;args=[...base,timezone,f.status];break;
   case 'store_stock':sql=`SELECT p.sku AS "productName",p.kind,count(*)::integer AS "movementCount",
    coalesce(sum(m.delta_units) FILTER(WHERE m.kind='receipt'),0)::text AS "receivedUnits",
    coalesce(-sum(m.delta_units) FILTER(WHERE m.kind='sale'),0)::text AS "soldUnits",
    coalesce(sum(m.delta_units),0)::text AS "netUnits",max(m.created_at) AS "latestMovementAt",max(m.created_at) AS "sourceAt"
    FROM pos_stock_movements m JOIN pos_stock_lots l ON l.id=m.lot_id JOIN pos_products p ON p.id=l.product_id
    WHERE m.organization_id=$1 AND m.branch_id=$2 AND m.created_at>=($3::date AT TIME ZONE $5)
     AND m.created_at<(($4::date+1) AT TIME ZONE $5)
    GROUP BY p.sku,p.kind ORDER BY p.sku LIMIT 10001`;args=[...base,timezone];break;
   case 'maintenance_orders':sql=`SELECT w.id,w.kind,w.status,a.asset_type AS "assetType",
    coalesce(a.location_label,a.serial_number,a.asset_id::text) AS "assetLabel",w.due_at AS "dueAt",
    w.estimate_usd::text AS "estimateUsd",w.created_at AS "createdAt",w.created_at AS "sourceAt"
    FROM maintenance_work_orders w JOIN maintenance_asset_profiles a ON a.id=w.asset_profile_id
    WHERE w.organization_id=$1 AND w.branch_id=$2 AND w.created_at>=($3::date AT TIME ZONE $5)
     AND w.created_at<(($4::date+1) AT TIME ZONE $5) AND ($6::text IS NULL OR w.status=$6)
    ORDER BY w.created_at,w.id LIMIT 10001`;args=[...base,timezone,f.status];break;
   case 'staff_shifts':sql=`SELECT (s.starts_at AT TIME ZONE $5)::date::text AS date,s.position,s.status,
    count(*)::integer AS "shiftCount",round(sum(extract(epoch FROM(s.ends_at-s.starts_at))/3600)::numeric,2)::text AS "plannedHours",
    max(s.scheduled_at) AS "sourceAt"
    FROM employee_work_shifts s WHERE s.organization_id=$1 AND s.branch_id=$2
     AND s.starts_at>=($3::date AT TIME ZONE $5) AND s.starts_at<(($4::date+1) AT TIME ZONE $5)
     AND ($6::text IS NULL OR s.status=$6)
    GROUP BY (s.starts_at AT TIME ZONE $5)::date,s.position,s.status
    ORDER BY date,s.position LIMIT 10001`;args=[...base,timezone,f.status];break;
   case 'operational_assets':sql=`SELECT e.occurred_at AS "occurredAt",a.code,a.asset_type AS "assetType",a.name AS "assetName",e.event_type AS "eventType",
    e.from_status AS "fromStatus",e.to_status AS "toStatus",fb.name AS "fromBranch",tb.name AS "toBranch",
    coalesce(te.legal_name,fe.legal_name,'Sin asignar') AS custodian,i.code AS "incidentCode",e.note,e.occurred_at AS "sourceAt"
    FROM operational_asset_events e JOIN operational_assets a ON a.id=e.asset_id AND a.organization_id=e.organization_id
    LEFT JOIN branches fb ON fb.id=e.from_branch_id AND fb.organization_id=e.organization_id
    JOIN branches tb ON tb.id=e.to_branch_id AND tb.organization_id=e.organization_id
    LEFT JOIN employees fe ON fe.id=e.from_custodian_employee_id AND fe.organization_id=e.organization_id
    LEFT JOIN employees te ON te.id=e.to_custodian_employee_id AND te.organization_id=e.organization_id
    LEFT JOIN incidents i ON i.id=e.related_incident_id AND i.organization_id=e.organization_id
    WHERE e.organization_id=$1 AND (e.from_branch_id=$2 OR e.to_branch_id=$2)
     AND e.occurred_at>=($3::date AT TIME ZONE $5) AND e.occurred_at<(($4::date+1) AT TIME ZONE $5)
     AND ($6::text IS NULL OR e.to_status=$6) ORDER BY e.occurred_at,e.id LIMIT 10001`;args=[...base,timezone,f.status];break;
   default:throw new BadRequestException('Plantilla de reporte inválida.');
  }
  sql=sql.replace(/LIMIT 10001\s*$/i,`LIMIT $${args.length+1} OFFSET $${args.length+2}`);
  args=[...args,batchSize,offset];
  const r=await c.query(sql,args);return r.rows;
 }
}
function uuid(v:unknown):v is string{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);}
function date(v:unknown):v is string{return typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&!Number.isNaN(Date.parse(v))&&new Date(v).toISOString().slice(0,10)===v;}
