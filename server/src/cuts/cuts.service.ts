import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { CaptureCutMeterDto, CreateCutProfileDto, CutReconciliationPolicyDto, GenerateCutsDto, MeasureCutTankDto, OpenCutDto, PrepareCutDto, ReviewCutDto } from './cuts.dto.js';

@Injectable()
export class CutsService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService) {}
 private date(value:string){
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||Number.isNaN(Date.parse(value+'T00:00:00Z'))||
     new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value)throw new BadRequestException('Fecha operativa no válida.');
  return value;
 }
 private async access(branch:string,p:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(p,branch)).includes(permission))throw new ForbiddenException('Permiso insuficiente para los cortes.');
  const r=await this.pool.query<{timezone:string}>(`SELECT timezone FROM branches WHERE id=$1 AND organization_id=$2 AND status='active'`,[branch,p.organizationId]);
  if(!r.rows[0])throw new NotFoundException('La sucursal activa no existe en tu ámbito.');return r.rows[0].timezone;
 }
 async createProfile(branch:string,p:AuthPrincipal,input:CreateCutProfileDto,correlation:string){
  const timezone=await this.access(branch,p,'branch.manage');this.date(input.effectiveDate);
  if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(input.dayStart)||!/^([01]\d|2[0-3]):[0-5]\d$/.test(input.splitAt)||input.dayStart===input.splitAt)
   throw new BadRequestException('Elige dos horarios distintos de inicio y división.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query<{id:string}>(`INSERT INTO operational_cut_profiles(organization_id,branch_id,effective_date,day_start,split_at,timezone,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`,[p.organizationId,branch,input.effectiveDate,input.dayStart,input.splitAt,timezone,p.userId]);
   const id=r.rows[0]!.id;
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'cut.profile.created',entityType:'operational_cut_profile',entityId:id,after:{effectiveDate:input.effectiveDate,dayStart:input.dayStart,splitAt:input.splitAt,timezone}});
   await client.query('COMMIT');return {data:{id,effectiveDate:input.effectiveDate,dayStart:input.dayStart,splitAt:input.splitAt,timezone}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(['23514','23505'].includes((error as {code?:string}).code??''))throw new ConflictException('El perfil ya existe o afectaría cortes generados.');throw error;}finally{client.release();}
 }
 async generate(branch:string,p:AuthPrincipal,input:GenerateCutsDto){
  await this.access(branch,p,'cut.capture');this.date(input.operationalDate);
  try{
   const r=await this.pool.query<{cut_id:string;slot:number;starts_at:Date;ends_at:Date}>(
    'SELECT cut_id,slot,starts_at,ends_at FROM generate_operational_cuts($1,$2,$3)',[p.organizationId,branch,input.operationalDate]);
   return {data:r.rows.map(x=>({id:x.cut_id,slot:x.slot,startsAt:x.starts_at,endsAt:x.ends_at}))};
  }catch(error){if((error as {code?:string}).code==='23514')throw new ConflictException('Configura dos ventanas contiguas; no debe haber huecos ni cortes con otra configuración.');throw error;}
 }
 async list(branch:string,p:AuthPrincipal,date:string){
  await this.access(branch,p,'cut.read');this.date(date);
  const r=await this.pool.query(`SELECT c.id,c.slot,c.operational_date AS "operationalDate",c.starts_at AS "startsAt",c.ends_at AS "endsAt",c.status,c.version,
    closure.closed_at AS "closedAt",closer.display_name AS "closedByName"
   FROM operational_cuts c
   LEFT JOIN operational_cut_closures closure ON closure.cut_id=c.id AND closure.organization_id=c.organization_id AND closure.branch_id=c.branch_id
   LEFT JOIN users closer ON closer.id=closure.closed_by AND closer.organization_id=c.organization_id
   WHERE c.organization_id=$1 AND c.branch_id=$2 AND c.operational_date=$3 ORDER BY c.slot`,[p.organizationId,branch,date]);
  return {data:r.rows};
 }
 async open(branch:string,id:string,p:AuthPrincipal,input:OpenCutDto,correlation:string){
  await this.access(branch,p,'cut.capture');
  if(!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1)throw new BadRequestException('Versión de corte inválida.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const result=await client.query<{cut_id:string;version:number;expected_dispenser_count:number;expected_nozzle_count:number;excused_nozzle_count:number}>(
    'SELECT * FROM open_operational_cut($1,$2,$3,$4,$5)',[p.organizationId,branch,id,p.userId,input.expectedVersion]);
   const row=result.rows[0];if(!row)throw new ConflictException('No se pudo abrir el corte.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'cut.opened',entityType:'operational_cut',entityId:id,after:row});
   await client.query('COMMIT');
   return {data:{id:row.cut_id,version:row.version,expectedDispensers:row.expected_dispenser_count,expectedNozzles:row.expected_nozzle_count,excusedNozzles:row.excused_nozzle_count}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','40001','23505'].includes((error as {code?:string}).code??''))throw new ConflictException('La configuración, el estado o la versión del corte cambió; actualiza y revisa sus equipos.');throw error;
  }finally{client.release();}
 }
 async assets(branch:string,id:string,p:AuthPrincipal){
  await this.access(branch,p,'cut.read');
  const cut=await this.pool.query(`SELECT id,status,version,starts_at AS "startsAt",ends_at AS "endsAt" FROM operational_cuts WHERE id=$1 AND branch_id=$2 AND organization_id=$3`,[id,branch,p.organizationId]);
  if(!cut.rows[0])throw new NotFoundException('Corte fuera de tu sucursal.');
  const [dispensers,nozzles,tanks]=await Promise.all([
   this.pool.query(`SELECT dispenser_id AS id,code,physical_status AS "physicalStatus",configuration_version AS "configurationVersion" FROM operational_cut_dispensers WHERE cut_id=$1 ORDER BY code`,[id]),
   this.pool.query(`SELECT n.nozzle_id AS id,n.dispenser_id AS "dispenserId",n.code,n.fuel_product_id AS "fuelProductId",fp.display_name AS "fuelName",
      n.meter_unit AS "meterUnit",n.participation,n.exclusion_reason AS "exclusionReason",n.configuration_version AS "configurationVersion",
      ms.last_value AS "lastMeterValue",ms.version AS "meterVersion",ms.meter_serial AS "meterSerial",ms.last_reading_id AS "lastReadingId",
      last_reading.captured_at AS "lastReadingAt",last_reading.reading_type AS "lastReadingType",
      capture.reading_id AS "cutReadingId",capture.measured_l AS "measuredLiters"
     FROM operational_cut_nozzles n
     LEFT JOIN fuel_products fp ON fp.id=n.fuel_product_id AND fp.organization_id=n.organization_id
     LEFT JOIN nozzle_meter_states ms ON ms.nozzle_id=n.nozzle_id AND ms.organization_id=n.organization_id
     LEFT JOIN nozzle_meter_readings last_reading ON last_reading.id=ms.last_reading_id AND last_reading.nozzle_id=n.nozzle_id
     LEFT JOIN operational_cut_meter_captures capture ON capture.cut_id=n.cut_id AND capture.nozzle_id=n.nozzle_id
     WHERE n.cut_id=$1 ORDER BY n.dispenser_id,n.code`,[id]),
   this.pool.query(`SELECT t.id,t.code,t.name,t.fuel_product_id AS "fuelProductId",fp.display_name AS "fuelName",t.nominal_capacity_l AS "capacityLiters",
      measurement.measured_l AS "measuredLiters",measurement.water_l AS "waterLiters",measurement.temperature_c AS "temperatureC",
      measurement.observed_at AS "observedAt",measurement.source,measurement.evidence_reference AS "evidenceReference"
     FROM tanks t
     JOIN fuel_products fp ON fp.id=t.fuel_product_id AND fp.organization_id=t.organization_id
     LEFT JOIN operational_cut_tank_measurements measurement ON measurement.cut_id=$3 AND measurement.tank_id=t.id
     WHERE t.organization_id=$1 AND t.branch_id=$2 AND t.status='active' ORDER BY t.code`,[p.organizationId,branch,id])
  ]);
  return {data:{cut:cut.rows[0],dispensers:dispensers.rows,nozzles:nozzles.rows,tanks:tanks.rows}};
 }
 async capture(branch:string,id:string,p:AuthPrincipal,input:CaptureCutMeterDto,correlation:string){
  await this.access(branch,p,'cut.capture');
  if(!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1)throw new BadRequestException('Versión inválida.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const result=await client.query(`SELECT * FROM capture_cut_meter($1,$2,$3,$4,$5,$6,$7)`,
    [p.organizationId,branch,id,input.nozzleId,input.readingId,p.userId,input.expectedVersion]);
   const row=result.rows[0];if(!row)throw new ConflictException('La lectura no se registró.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'cut.meter.captured',entityType:'operational_cut',entityId:id,after:{nozzleId:input.nozzleId,readingId:input.readingId,version:row.version,measuredL:row.measured_l}});
   await client.query('COMMIT');return {data:{cutId:id,nozzleId:input.nozzleId,version:row.version,openingValue:row.opening_value,closingValue:row.closing_value,measuredL:row.measured_l}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505','40001'].includes((error as {code?:string}).code??''))throw new ConflictException('Lectura duplicada, fuera del turno o sin continuidad; actualiza el corte y revisa el medidor.');throw error;
  }finally{client.release();}
 }
 async progress(branch:string,id:string,p:AuthPrincipal){
  await this.access(branch,p,'cut.read');
  const c=await this.pool.query<{id:string;status:string;version:number;startsAt:Date;endsAt:Date}>(`SELECT id,status,version,starts_at AS "startsAt",ends_at AS "endsAt" FROM operational_cuts WHERE id=$1 AND branch_id=$2 AND organization_id=$3`,[id,branch,p.organizationId]);
  const cut=c.rows[0];if(!cut)throw new NotFoundException('Corte fuera de tu sucursal.');
  const [readings,dispenses,movements]=await Promise.all([
   this.pool.query(`SELECT n.fuel_product_id AS "fuelProductId",fp.display_name AS "productName",count(*) FILTER(WHERE n.participation='expected')::integer AS expected,
    count(m.reading_id)::integer AS captured,COALESCE(sum(m.measured_l),0)::text AS "meterLiters"
    FROM operational_cut_nozzles n JOIN fuel_products fp ON fp.id=n.fuel_product_id AND fp.organization_id=n.organization_id
    LEFT JOIN operational_cut_meter_captures m ON m.cut_id=n.cut_id AND m.nozzle_id=n.nozzle_id
    WHERE n.cut_id=$1 GROUP BY n.fuel_product_id,fp.display_name ORDER BY n.fuel_product_id`,[id]),
   this.pool.query(`SELECT a.fuel_product_id AS "fuelProductId",fp.display_name AS "productName",count(*)::integer AS dispatches,COALESCE(sum(a.actual_l),0)::text AS "soldLiters",
    COALESCE(sum(a.sale_amount_usd),0)::text AS "salesUsd" FROM dispense_authorizations a
    JOIN fuel_products fp ON fp.id=a.fuel_product_id AND fp.organization_id=a.organization_id
    WHERE a.organization_id=$1 AND a.branch_id=$2 AND a.status='completed' AND a.completed_at >=$3 AND a.completed_at<$4
    GROUP BY a.fuel_product_id,fp.display_name`,[p.organizationId,branch,cut.startsAt,cut.endsAt]),
   this.pool.query(`SELECT im.fuel_product_id AS "fuelProductId",fp.display_name AS "productName",im.movement_type AS type,COALESCE(sum(abs(im.delta_l)),0)::text AS liters
    FROM inventory_movements im JOIN fuel_products fp ON fp.id=im.fuel_product_id AND fp.organization_id=im.organization_id
    WHERE im.organization_id=$1 AND im.branch_id=$2 AND im.occurred_at >=$3 AND im.occurred_at<$4
      AND im.movement_type IN('receipt','loss') GROUP BY im.fuel_product_id,fp.display_name,im.movement_type`,[p.organizationId,branch,cut.startsAt,cut.endsAt])
  ]);
  return {data:{cut,products:readings.rows,postedDispenses:dispenses.rows,stockMovements:movements.rows,
   basis:'operational_window',provisional:cut.status!=='closed'}};
 }
 async measureTank(branch:string,id:string,p:AuthPrincipal,input:MeasureCutTankDto,correlation:string){
  await this.access(branch,p,'cut.capture');
  if(!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1||Number.isNaN(Date.parse(input.observedAt)))throw new BadRequestException('Versión o fecha inválida.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const result=await client.query('SELECT * FROM record_cut_tank_measurement($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',
    [p.organizationId,branch,id,input.tankId,p.userId,input.expectedVersion,input.measuredL,input.waterL??null,input.temperatureC??null,input.observedAt,input.source,input.evidenceReference??null]);
   const row=result.rows[0];if(!row)throw new ConflictException('No se registró el tanque.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'cut.tank.measured',entityType:'operational_cut',entityId:id,after:{tankId:input.tankId,version:row.version,measuredL:row.measured_l}});
   await client.query('COMMIT');return {data:{cutId:id,tankId:input.tankId,version:row.version,measuredL:row.measured_l}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505','40001','23503'].includes((error as {code?:string}).code??''))throw new ConflictException('Nivel fuera de capacidad, lectura duplicada o corte desactualizado.');throw error;
  }finally{client.release();}
 }
 async createPolicy(branch:string,p:AuthPrincipal,input:CutReconciliationPolicyDto,correlation:string){
  await this.access(branch,p,'branch.manage');this.date(input.effectiveDate);
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query<{id:string}>(`INSERT INTO operational_cut_reconciliation_policies
    (organization_id,branch_id,effective_date,meter_tolerance_l,tank_tolerance_l,collection_tolerance_usd,auto_close_enabled,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
    [p.organizationId,branch,input.effectiveDate,input.meterToleranceL,input.tankToleranceL,input.collectionToleranceUsd,input.autoCloseEnabled,p.userId]);
   const id=r.rows[0]!.id;
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'cut.policy.created',entityType:'operational_cut_reconciliation_policy',entityId:id,after:input});
   await client.query('COMMIT');return {data:{id,...input}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if((error as {code?:string}).code==='23505')throw new ConflictException('Ya existe una política en esa fecha.');throw error;}finally{client.release();}
 }
 async prepare(branch:string,id:string,p:AuthPrincipal,input:PrepareCutDto,correlation:string){
  await this.access(branch,p,'cut.submit');
  if(!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1)throw new BadRequestException('Versión inválida.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=await client.query<{preparation_id:string;version:number;review_required:boolean}>(
    'SELECT * FROM prepare_operational_cut($1,$2,$3,$4,$5)',[p.organizationId,branch,id,p.userId,input.expectedVersion]);
   const row=r.rows[0];if(!row)throw new ConflictException('No se preparó el corte.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'cut.prepared',entityType:'operational_cut',entityId:id,after:row});
   let automaticClosure:null|{id:string;version:number}=null;
   if(!row.review_required && (await this.auth.capabilities(p,branch)).includes('cut.close')){
    const policy=await client.query<{auto_close_enabled:boolean;ends_at:Date}>(`SELECT p.auto_close_enabled,c.ends_at FROM operational_cut_preparations prep
      JOIN operational_cut_reconciliation_policies p ON p.id=prep.policy_id
      JOIN operational_cuts c ON c.id=prep.cut_id WHERE prep.id=$1`,[row.preparation_id]);
    if(policy.rows[0]?.auto_close_enabled && new Date(policy.rows[0].ends_at).getTime()<=Date.now()){
     const closed=await client.query<{closure_id:string;version:number}>(
      'SELECT * FROM close_operational_cut($1,$2,$3,$4,$5)',[p.organizationId,branch,id,p.userId,row.version]);
     automaticClosure={id:closed.rows[0]!.closure_id,version:closed.rows[0]!.version};
     await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:'cut.closed.automatic',entityType:'operational_cut',entityId:id,after:automaticClosure});
    }
   }
   await client.query('COMMIT');return {data:{cutId:id,preparationId:row.preparation_id,
    version:automaticClosure?.version??row.version,reviewRequired:row.review_required,
    automaticClosureId:automaticClosure?.id??null}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505','40001'].includes((error as {code?:string}).code??''))throw new ConflictException('Faltan lecturas, ventas, línea base o política; hay despachos pendientes o cambió el corte.');throw error;
  }finally{client.release();}
 }
 async reconciliation(branch:string,id:string,p:AuthPrincipal){
  await this.access(branch,p,'cut.read');
  const result=await this.pool.query(`SELECT p.id,p.cut_id AS "cutId",p.input_version AS "inputVersion",p.output_version AS version,
   COALESCE((SELECT jsonb_agg(item.value||jsonb_build_object('productName',COALESCE(fp.display_name,'Combustible'),
     'meterLiters',item.value->>'meterLiters','soldLiters',item.value->>'soldLiters','salesUsd',item.value->>'salesUsd',
     'receiptsLiters',item.value->>'receiptsLiters','lossLiters',item.value->>'lossLiters','varianceLiters',item.value->>'varianceLiters',
     'priceVersions',COALESCE((SELECT jsonb_agg(price.value||jsonb_build_object('unitPriceUsd',price.value->>'unitPriceUsd',
       'liters',price.value->>'liters','salesUsd',price.value->>'salesUsd'))
       FROM jsonb_array_elements(COALESCE(item.value->'priceVersions','[]'::jsonb)) price(value)),'[]'::jsonb)))
     FROM jsonb_array_elements(p.product_summary) item(value)
     LEFT JOIN fuel_products fp ON fp.id=(item.value->>'fuelProductId')::uuid AND fp.organization_id=p.organization_id),'[]'::jsonb) AS products,
   COALESCE((SELECT jsonb_agg(item.value||jsonb_build_object('tankCode',t.code,'tankName',t.name,'fuelName',fp.display_name,
     'measuredLiters',item.value->>'measuredLiters','ledgerLiters',item.value->>'ledgerLiters','varianceLiters',item.value->>'varianceLiters')) FROM jsonb_array_elements(p.tank_summary) item(value)
     LEFT JOIN tanks t ON t.id=(item.value->>'tankId')::uuid AND t.branch_id=p.branch_id AND t.organization_id=p.organization_id
     LEFT JOIN fuel_products fp ON fp.id=t.fuel_product_id AND fp.organization_id=t.organization_id),'[]'::jsonb) AS tanks,
   jsonb_build_object('salesUsd',p.financial_summary->>'salesUsd','confirmedCollectionUsd',p.financial_summary->>'confirmedCollectionUsd',
     'cashConfirmedUsd',p.financial_summary->>'cashConfirmedUsd','cardConfirmedUsd',p.financial_summary->>'cardConfirmedUsd',
     'refundedUsd',p.financial_summary->>'refundedUsd') AS finance,
   p.review_required AS "reviewRequired",p.blocking_issues AS "blockingIssues",p.warnings,
   p.prepared_by AS "preparedBy",preparer.display_name AS "preparedByName",p.prepared_at AS "preparedAt",c.status,
   (SELECT jsonb_build_object('id',review.id,'reviewedBy',review.reviewed_by,
     'reviewedByName',reviewer.display_name,'reviewedAt',review.reviewed_at,'reason',review.reason)
    FROM operational_cut_reviews review
    LEFT JOIN users reviewer ON reviewer.id=review.reviewed_by AND reviewer.organization_id=review.organization_id
    WHERE review.cut_id=p.cut_id AND review.preparation_id=p.id) AS "review"
   FROM operational_cut_preparations p
   JOIN operational_cuts c ON c.id=p.cut_id
   LEFT JOIN users preparer ON preparer.id=p.prepared_by AND preparer.organization_id=p.organization_id
   WHERE p.cut_id=$1 AND p.branch_id=$2 AND p.organization_id=$3`,[id,branch,p.organizationId]);
  if(!result.rows[0])throw new NotFoundException('El corte no tiene preparación en tu sucursal.');return {data:result.rows[0]};
 }
 private async transition(branch:string,id:string,p:AuthPrincipal,version:number,correlation:string,kind:'review'|'close',reason?:string){
  await this.access(branch,p,'cut.close');
  if(!Number.isSafeInteger(version)||version<1)throw new BadRequestException('Versión inválida.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const r=kind==='review'
    ? await client.query('SELECT * FROM review_operational_cut($1,$2,$3,$4,$5,$6)',[p.organizationId,branch,id,p.userId,version,reason])
    : await client.query('SELECT * FROM close_operational_cut($1,$2,$3,$4,$5)',[p.organizationId,branch,id,p.userId,version]);
   const row=r.rows[0];if(!row)throw new ConflictException('La transición del corte no se completó.');
   await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action:kind==='review'?'cut.review.approved':'cut.closed',entityType:'operational_cut',entityId:id,after:row});
   await client.query('COMMIT');return {data:{cutId:id,...row}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505','40001'].includes((error as {code?:string}).code??''))throw new ConflictException('Revisión independiente, corte previo cerrado y versión vigente requeridos.');throw error;
  }finally{client.release();}
 }
 async review(branch:string,id:string,p:AuthPrincipal,input:ReviewCutDto,correlation:string){
  if(!input.reason||input.reason.trim().length<8||input.reason.length>500)throw new BadRequestException('Explica la discrepancia revisada.');
  return this.transition(branch,id,p,input.expectedVersion,correlation,'review',input.reason.trim());
 }
 async close(branch:string,id:string,p:AuthPrincipal,input:PrepareCutDto,correlation:string){
  return this.transition(branch,id,p,input.expectedVersion,correlation,'close');
 }
 async closure(branch:string,id:string,p:AuthPrincipal){
  await this.access(branch,p,'cut.read');
  const r=await this.pool.query(`SELECT closure.id,closure.cut_id AS "cutId",closure.preparation_id AS "preparationId",closure.review_id AS "reviewId",
   closure.input_version AS "inputVersion",closure.output_version AS version,closure.snapshot,closure.closed_by AS "closedBy",closer.display_name AS "closedByName",closure.closed_at AS "closedAt"
   FROM operational_cut_closures closure LEFT JOIN users closer ON closer.id=closure.closed_by AND closer.organization_id=closure.organization_id
   WHERE closure.cut_id=$1 AND closure.branch_id=$2 AND closure.organization_id=$3`,[id,branch,p.organizationId]);
  if(!r.rows[0])throw new NotFoundException('El corte no está cerrado en tu sucursal.');return {data:r.rows[0]};
 }
}
