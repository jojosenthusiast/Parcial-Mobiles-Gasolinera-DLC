import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import { createHash } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { calculateFuelTax,validateFuelTaxPolicy } from '../../scripts/fuel-tax.mjs';
import type { ProposeFuelTaxDto,ApproveFuelTaxDto,PreviewFuelTaxDto } from './tax-policy.dto.js';

@Injectable()
export class TaxPolicyService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService) {}
 private async access(branchId:string,principal:AuthPrincipal,permission:string){
  if(!(await this.auth.capabilities(principal,branchId)).includes(permission))throw new ForbiddenException('No tienes permiso para políticas fiscales en esta sucursal.');
  if(!(await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2',[branchId,principal.organizationId])).rowCount)throw new NotFoundException('La sucursal no existe.');
 }
 async list(branchId:string,principal:AuthPrincipal,productId?:string){
  await this.access(branchId,principal,'sale.read');
  if(productId&&!uuid(productId))throw new BadRequestException('fuelProductId no es válido.');
  const rows=await this.pool.query(
   `SELECT p.id,p.fuel_product_id AS "fuelProductId",f.display_name AS "fuelName",p.mode,p.rules,p.source_reference AS "sourceReference",
     p.reason,p.effective_at AS "effectiveAt",p.proposed_at AS "proposedAt",p.proposed_by AS "proposedBy",
     v.id AS "policyVersionId",v.version,v.approved_by AS "approvedBy",v.approved_at AS "approvedAt",
     CASE WHEN v.id IS NULL THEN 'awaiting_approval' WHEN v.effective_at>now() THEN 'scheduled' WHEN EXISTS(SELECT 1 FROM fuel_tax_versions newer WHERE newer.organization_id=v.organization_id AND newer.branch_id=v.branch_id AND newer.fuel_product_id=v.fuel_product_id AND newer.effective_at>v.effective_at AND newer.effective_at<=now()) THEN 'superseded' ELSE 'effective' END AS status
    FROM fuel_tax_proposals p JOIN fuel_products f ON f.id=p.fuel_product_id
    LEFT JOIN fuel_tax_versions v ON v.proposal_id=p.id
    WHERE p.organization_id=$1 AND p.branch_id=$2 AND ($3::uuid IS NULL OR p.fuel_product_id=$3)
    ORDER BY p.proposed_at DESC,p.id DESC LIMIT 100`,[principal.organizationId,branchId,productId??null]);
  // A past version may be superseded; its snapshot remains a valid historical source.
  const products=await this.pool.query(`SELECT f.id,f.display_name AS name FROM branch_fuel_offers o JOIN fuel_products f ON f.id=o.fuel_product_id
   WHERE o.organization_id=$1 AND o.branch_id=$2 AND o.status='active' AND f.status='active' ORDER BY f.display_name,f.id LIMIT 100`,[principal.organizationId,branchId]);
  return {data:rows.rows,products:products.rows,meta:{limit:100}};
 }
 async propose(branchId:string,principal:AuthPrincipal,input:ProposeFuelTaxDto,correlationId:string){
  await this.access(branchId,principal,'tax.policy.propose');
  if(!uuid(input.commandId)||!uuid(input.fuelProductId))throw new BadRequestException('commandId y fuelProductId deben ser UUID.');
  try{validateFuelTaxPolicy(input.mode,input.rules);}catch(error){throw new BadRequestException((error as Error).message);}
  const source=typeof input.sourceReference==='string'?input.sourceReference.trim():'',reason=typeof input.reason==='string'?input.reason.trim():'';
  if(!source||source.length>500||!reason||reason.length>500)throw new BadRequestException('Indica fuente documental y motivo, hasta 500 caracteres.');
  if(!validDateTime(input.effectiveAt))throw new BadRequestException('Fecha de vigencia no válida.');
  const effective=new Date(input.effectiveAt).toISOString();
  const hash=createHash('sha256').update(JSON.stringify({v:1,branchId:branchId.toLowerCase(),productId:input.fuelProductId.toLowerCase(),mode:input.mode,rules:input.rules,source,reason,effective})).digest('hex');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`tax-proposal:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const old=await client.query<{id:string;request_hash:string;proposed_by:string}>('SELECT id,request_hash,proposed_by FROM fuel_tax_proposals WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].proposed_by!==principal.userId)throw new ConflictException('El comando corresponde a otra propuesta o persona.');
    await client.query('COMMIT');return {data:{id:old.rows[0].id,idempotentReplay:true}};
   }
   if(Date.parse(effective)<=Date.now())throw new ConflictException('La vigencia debe ser futura; no se modifican impuestos de ventas anteriores.');
   const product=await client.query(`SELECT f.id FROM fuel_products f JOIN branch_fuel_offers o ON o.fuel_product_id=f.id AND o.branch_id=$4 AND o.organization_id=f.organization_id WHERE f.id=$1 AND f.organization_id=$2 AND f.status=$3 AND o.status='active'`,[input.fuelProductId,principal.organizationId,'active',branchId]);
   if(!product.rowCount)throw new NotFoundException('El combustible no existe o está inactivo.');
   const result=await client.query<{id:string}>(`INSERT INTO fuel_tax_proposals(organization_id,branch_id,fuel_product_id,command_id,request_hash,mode,rules,source_reference,reason,effective_at,proposed_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,[principal.organizationId,branchId,input.fuelProductId,input.commandId,hash,input.mode,JSON.stringify(input.rules),source,reason,effective,principal.userId,correlationId]);
   const id=result.rows[0]!.id;await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'tax_policy.proposed',entityType:'fuel_tax_proposal',entityId:id,after:{mode:input.mode,effectiveAt:effective,sourceReference:source}});
   await client.query('COMMIT');return {data:{id,idempotentReplay:false}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
 }
 async approve(branchId:string,proposalId:string,principal:AuthPrincipal,input:ApproveFuelTaxDto,correlationId:string){
  await this.access(branchId,principal,'tax.policy.approve');
  if(!uuid(proposalId)||!uuid(input.commandId))throw new BadRequestException('Identificadores de aprobación no válidos.');
  const hash=createHash('sha256').update(JSON.stringify({v:1,branchId:branchId.toLowerCase(),proposalId:proposalId.toLowerCase()})).digest('hex');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`tax-approval:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const old=await client.query<{id:string;request_hash:string;approved_by:string}>('SELECT id,request_hash,approved_by FROM fuel_tax_versions WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].approved_by!==principal.userId)throw new ConflictException('El comando corresponde a otra aprobación o persona.');
    await client.query('COMMIT');return {data:{id:old.rows[0].id,idempotentReplay:true}};
   }
   const p=await client.query<{id:string;fuel_product_id:string;proposed_by:string;effective_at:Date}>('SELECT id,fuel_product_id,proposed_by,effective_at FROM fuel_tax_proposals WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[proposalId,principal.organizationId,branchId]);
   const proposal=p.rows[0];if(!proposal)throw new NotFoundException('La propuesta no existe en esta sucursal.');
   if(proposal.proposed_by===principal.userId)throw new ForbiddenException('Otra persona debe aprobar la política fiscal.');
   if(new Date(proposal.effective_at).getTime()<=Date.now())throw new ConflictException('La propuesta venció; crea una con vigencia futura.');
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`tax-scope:${principal.organizationId}:${branchId.toLowerCase()}:${proposal.fuel_product_id}`]);
   if(new Date(proposal.effective_at).getTime()<=Date.now())throw new ConflictException('La propuesta venció mientras esperaba la aprobación.');
   const duplicate=await client.query('SELECT id FROM fuel_tax_versions WHERE proposal_id=$1',[proposalId]);
   if(duplicate.rowCount)throw new ConflictException('La propuesta ya fue aprobada.');
   const result=await client.query<{id:string}>(`INSERT INTO fuel_tax_versions(organization_id,branch_id,fuel_product_id,proposal_id,version,command_id,request_hash,mode,rules,source_reference,effective_at,approved_by,correlation_id)
    SELECT p.organization_id,p.branch_id,p.fuel_product_id,p.id,COALESCE((SELECT max(v.version) FROM fuel_tax_versions v WHERE v.organization_id=p.organization_id AND v.branch_id=p.branch_id AND v.fuel_product_id=p.fuel_product_id),0)+1,
     $4,$5,p.mode,p.rules,p.source_reference,p.effective_at,$6,$7 FROM fuel_tax_proposals p WHERE p.id=$1 AND p.organization_id=$2 AND p.branch_id=$3 RETURNING id`,
    [proposalId,principal.organizationId,branchId,input.commandId,hash,principal.userId,correlationId]);
   const id=result.rows[0]!.id;await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'tax_policy.approved',entityType:'fuel_tax_version',entityId:id,after:{proposalId}});
   await client.query('COMMIT');return {data:{id,idempotentReplay:false}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if((error as {code?:string}).code==='23505')throw new ConflictException('Ya existe una aprobación o vigencia para este combustible.');if((error as {code?:string}).code==='23514')throw new ConflictException('La propuesta venció o no coincide con la aprobación.');throw error;}finally{client.release();}
 }
 async preview(branchId:string,principal:AuthPrincipal,input:PreviewFuelTaxDto){
  await this.access(branchId,principal,'sale.read');
  if(!uuid(input.policyVersionId))throw new BadRequestException('policyVersionId no es válido.');
  const row=await this.pool.query<{mode:'included'|'exempt'|'unconfigured';rules:ProposeFuelTaxDto['rules']}>('SELECT mode,rules FROM fuel_tax_versions WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[input.policyVersionId,principal.organizationId,branchId]);
  if(!row.rows[0])throw new NotFoundException('La versión fiscal no existe.');
  try{return {data:{...calculateFuelTax({grossUsd:input.grossUsd,quantityL:input.quantityL,...row.rows[0]}),preview:true}};}
  catch(error){throw new BadRequestException((error as Error).message);}
 }
}
function uuid(value:unknown):value is string{return typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);}

function validDateTime(value:unknown):value is string {
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)||!Number.isFinite(Date.parse(value)))return false;
 const [year,month,day]=value.slice(0,10).split('-').map(Number);const check=new Date(Date.UTC(year!,month!-1,day!));
 return check.getUTCFullYear()===year&&check.getUTCMonth()+1===month&&check.getUTCDate()===day;
}
