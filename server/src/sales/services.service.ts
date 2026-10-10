import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { AddServiceMaterialDto, ConfigureServiceDto, FulfillServiceDto } from './services.dto.js';
@Injectable()
export class ServicesService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}
 private async access(branch:string,p:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(p,branch)).includes(permission))throw new ForbiddenException('Permiso de servicios insuficiente.');
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
  }catch(error){await c.query('ROLLBACK').catch(()=>undefined);
   if(['23505','23514','40001','55000'].includes((error as {code?:string}).code??''))throw new ConflictException('Servicio, receta o existencias en conflicto.');
   if((error as {code?:string}).code==='23503')throw new NotFoundException('Referencia fuera de sucursal.');
   throw error;
  }finally{c.release();}
 }
 async configure(branch:string,id:string,p:AuthPrincipal,input:ConfigureServiceDto,correlation:string){
  await this.access(branch,p,'pos.service.catalog.manage');
  if(!uuid(id)||!text(input.workDescription,5,300)||input.taxCode!==undefined&&!text(input.taxCode,2,40))
   throw new BadRequestException('Detalle de servicio inválido.');
  return this.write(branch,p,correlation,'pos.service.configured','service_catalog',async c=>{
   const old=await c.query<{work_description:string;tax_code:string|null}>(`SELECT work_description,tax_code FROM service_catalog_details
    WHERE product_id=$1 AND organization_id=$2 AND branch_id=$3`,[id,p.organizationId,branch]);
   if(old.rows[0]){
    if(old.rows[0].work_description!==input.workDescription.trim()||old.rows[0].tax_code!==(input.taxCode?.trim()??null))
     throw new ConflictException('El servicio ya tiene otros detalles. Publica un nuevo producto para cambiar su identidad.');
    return {id,data:{id},replay:true};
   }
   await c.query(`INSERT INTO service_catalog_details(product_id,organization_id,branch_id,tax_code,work_description,created_by)
    VALUES($1,$2,$3,$4,$5,$6)`,[id,p.organizationId,branch,input.taxCode?.trim()??null,input.workDescription.trim(),p.userId]);
   return {id,data:{id,workDescription:input.workDescription.trim(),taxCode:input.taxCode?.trim()??null}};
  });
 }
 async material(branch:string,offer:string,p:AuthPrincipal,input:AddServiceMaterialDto,correlation:string){
  await this.access(branch,p,'pos.service.catalog.manage');
  if(!uuid(offer)||!uuid(input.catalogProductId)||!positiveInteger(input.unitsPerService))
   throw new BadRequestException('Recurso inválido.');
  return this.write(branch,p,correlation,'pos.service.material_added','service_material_requirement',async c=>{
   const old=await c.query<{id:string;units_per_service:string}>(`SELECT id,units_per_service::text FROM service_material_requirements
    WHERE offer_version_id=$1 AND catalog_product_id=$2 AND organization_id=$3 AND branch_id=$4`,[offer,input.catalogProductId,p.organizationId,branch]);
   if(old.rows[0]){
    if(old.rows[0].units_per_service!==String(Number(input.unitsPerService)))throw new ConflictException('Ya existe otro requerimiento.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id},replay:true};
   }
   const r=await c.query<{id:string}>(`INSERT INTO service_material_requirements(organization_id,branch_id,offer_version_id,catalog_product_id,units_per_service,created_by)
    VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,[p.organizationId,branch,offer,input.catalogProductId,input.unitsPerService,p.userId]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,offerVersionId:offer,catalogProductId:input.catalogProductId,unitsPerService:input.unitsPerService}};
  });
 }
 async recipe(branch:string,offer:string,p:AuthPrincipal){
  await this.access(branch,p,'pos.catalog.read');
  if(!uuid(offer))throw new BadRequestException('Oferta inválida.');
  const target=await this.pool.query(`SELECT v.id,d.work_description AS "workDescription",d.tax_code AS "taxCode",v.price_usd AS "priceUsd",
   v.service_unit_cost_usd AS "serviceUnitCostUsd" FROM pos_offer_versions v
   JOIN service_catalog_details d ON d.product_id=v.product_id WHERE v.id=$1 AND v.organization_id=$2 AND v.branch_id=$3`,
   [offer,p.organizationId,branch]);
  if(!target.rows[0])throw new NotFoundException('Servicio fuera de sucursal.');
  const materials=await this.pool.query(`SELECT r.id,c.sku,c.presentation,r.units_per_service AS "unitsPerService"
   FROM service_material_requirements r JOIN store_catalog_products c ON c.id=r.catalog_product_id
   WHERE r.offer_version_id=$1 AND r.branch_id=$2 ORDER BY c.sku`,[offer,branch]);
  return {data:{...target.rows[0],materials:materials.rows,taxStatus:'unconfigured'}};
 }
 async fulfill(branch:string,line:string,p:AuthPrincipal,input:FulfillServiceDto,correlation:string){
  await this.access(branch,p,'pos.service.fulfill');
  if(!uuid(line)||!uuid(input.commandId)||!text(input.workReference,5,200))throw new BadRequestException('Ejecución inválida.');
  const hash=createHash('sha256').update(JSON.stringify({branch,line,reference:input.workReference.trim()})).digest('hex');
  return this.write(branch,p,correlation,'pos.service.fulfilled','service_fulfillment',async c=>{
   const old=await c.query<{id:string}>('SELECT id FROM service_fulfillments WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   const r=await c.query<{id:string}>('SELECT fulfill_pos_service($1,$2,$3,$4,$5,$6,$7,$8) AS id',
    [p.organizationId,branch,p.userId,line,input.workReference.trim(),input.commandId,hash,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,saleLineId:line},replay:!!old.rows[0]};
  });
 }
 async detail(branch:string,line:string,p:AuthPrincipal){
  await this.access(branch,p,'pos.catalog.read');
  if(!uuid(line))throw new BadRequestException('Línea inválida.');
  const sale=await this.pool.query('SELECT id FROM sale_lines WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND kind=$4',
   [line,p.organizationId,branch,'service']);
  if(!sale.rows[0])throw new NotFoundException('Servicio fuera de sucursal.');
  const f=await this.pool.query(`SELECT f.id,f.work_reference AS "workReference",f.fulfilled_at AS "fulfilledAt",f.fulfilled_by AS "fulfilledBy",
   coalesce(sum(-m.delta_units*l.unit_cost_usd) FILTER(WHERE l.unit_cost_usd IS NOT NULL),0) AS "knownMaterialCostUsd",
   count(m.id) FILTER(WHERE l.unit_cost_usd IS NULL)::integer AS "unknownCostAllocations"
   FROM service_fulfillments f LEFT JOIN pos_stock_movements m ON m.service_fulfillment_id=f.id
   LEFT JOIN pos_stock_lots l ON l.id=m.lot_id WHERE f.sale_line_id=$1 GROUP BY f.id`,[line]);
  return {data:{saleLineId:line,status:f.rows[0]?'fulfilled':'pending',fulfillment:f.rows[0]??null}};
 }
}
function uuid(v:unknown):v is string{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);}
function text(v:unknown,min:number,max:number){return typeof v==='string'&&v.trim().length>=min&&v.trim().length<=max;}
function positiveInteger(v:unknown){return typeof v==='string'&&/^[1-9][0-9]{0,8}$/.test(v);}
