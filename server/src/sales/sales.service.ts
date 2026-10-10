import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import { createHash } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { CreateCombinedReceiptDto, CreateFuelSaleDto } from './sales.dto.js';
import { serializeReceiptPdf } from '../reports/export-documents.js';

@Injectable()
export class SalesService {
 constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly auth: AuthService, private readonly audit: AuditService) {}

 private async access(principal: AuthPrincipal, branchId: string, permission: string) {
  const capabilities=await this.auth.capabilities(principal,branchId);
  if(!capabilities.includes(permission)) throw new ForbiddenException('No tienes permiso para ventas en esta sucursal.');
  const branch=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2',[branchId,principal.organizationId]);
  if(!branch.rowCount) throw new NotFoundException('La sucursal no existe.');
  return capabilities;
 }

 async createFuelSale(branchId: string, principal: AuthPrincipal, input: CreateFuelSaleDto, correlationId: string) {
  const capabilities=await this.access(principal,branchId,'sale.create');
  if(!isUuid(input.commandId)||!isUuid(input.authorizationId)) throw new BadRequestException('commandId y authorizationId deben ser UUID.');
  const requestHash=createHash('sha256').update(JSON.stringify({v:1,branchId:branchId.toLowerCase(),authorizationId:input.authorizationId.toLowerCase()})).digest('hex');
  const client=await this.pool.connect();
  let saleId: string;
  let replay=false;
  try {
   await client.query('BEGIN');
   // Serialize identical commands, including a command reused across different dispatches.
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`sale:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const existing=await client.query<{id:string;request_hash:string;created_by:string}>('SELECT id,request_hash,created_by FROM sales WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(existing.rows[0]) {
    if(existing.rows[0].created_by!==principal.userId&&!capabilities.includes('sale.read')) throw new ForbiddenException('No puedes consultar la venta de otro usuario.');
    if(existing.rows[0].request_hash!==requestHash) throw new ConflictException('commandId ya se usó para otra venta.');
    saleId=existing.rows[0].id; replay=true;
   } else {
    const dispatch=await client.query<{id:string;status:string}>(
     'SELECT id,status FROM dispense_authorizations WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE',
     [input.authorizationId,principal.organizationId,branchId]);
    if(!dispatch.rows[0]) throw new NotFoundException('El despacho no existe en esta sucursal.');
    if(dispatch.rows[0].status!=='completed') throw new ConflictException('Completa y confirma el despacho antes de registrar la venta.');
    const linked=await client.query('SELECT id FROM sales WHERE authorization_id=$1',[input.authorizationId]);
    if(linked.rowCount) throw new ConflictException('Este despacho ya tiene una venta; consulta el comprobante existente.');
    const inserted=await client.query<{id:string}>(
     `INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
      SELECT organization_id,branch_id,id,$4,$5,sale_amount_usd,$6,completed_at,$7 FROM dispense_authorizations
      WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND status='completed' RETURNING id`,
     [input.authorizationId,principal.organizationId,branchId,input.commandId,requestHash,principal.userId,correlationId]);
    saleId=inserted.rows[0]!.id;
    const line=await client.query(
     `INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,
        price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality)
      SELECT a.organization_id,a.branch_id,$4,1,a.fuel_product_id,p.display_name,a.actual_l,a.price_usd_per_unit,a.price_unit,
        a.price_version_id,a.sale_amount_usd,a.inventory_movement_id,m.cost_recognized_usd,m.unit_cost_usd_per_l,m.valuation_quality
      FROM dispense_authorizations a JOIN fuel_products p ON p.id=a.fuel_product_id
      JOIN inventory_movements m ON m.id=a.inventory_movement_id AND m.organization_id=a.organization_id AND m.branch_id=a.branch_id
      WHERE a.id=$1 AND a.organization_id=$2 AND a.branch_id=$3 AND a.status='completed'`,
     [input.authorizationId,principal.organizationId,branchId,saleId]);
    if(line.rowCount!==1) throw new ConflictException('Falta el movimiento confirmado de inventario.');
    const fiscal=await client.query('SELECT policy_version_id,result FROM sale_tax_snapshots WHERE sale_id=$1',[saleId]);
    await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'sale.created',entityType:'sale',entityId:saleId,
     after:{authorizationId:input.authorizationId,status:'pending_collection',receiptType:'internal',taxSnapshot:fiscal.rows[0]??null}});
   }
   await client.query('COMMIT');
  } catch(error) {
   await client.query('ROLLBACK').catch(()=>undefined);
   if((error as {code?:string}).code==='23514') throw new ConflictException('Revisa el desglose fiscal o la conciliación del despacho.');
   if((error as {code?:string}).code==='23505') throw new ConflictException('El despacho o comando ya tiene una venta.');
   throw error;
  } finally {client.release();}
  // A create-only user can receive their own result without granting unrestricted sale reads.
  return this.detail(branchId,saleId,principal,'sale.create',replay);
 }

 async createCombinedReceipt(branchId:string,principal:AuthPrincipal,input:CreateCombinedReceiptDto,correlationId:string) {
  const capabilities=await this.access(principal,branchId,'sale.create');
  if(!isUuid(input.commandId)||!isUuid(input.fuelSaleId)||!isUuid(input.posSaleId)||input.fuelSaleId.toLowerCase()===input.posSaleId.toLowerCase())
   throw new BadRequestException('El comando y las dos ventas deben ser UUID distintos.');
  const fuelSaleId=input.fuelSaleId.toLowerCase(),posSaleId=input.posSaleId.toLowerCase();
  const requestHash=createHash('sha256').update(JSON.stringify({v:1,branchId:branchId.toLowerCase(),fuelSaleId,posSaleId})).digest('hex');
  const client=await this.pool.connect();let receiptId:string;let replay=false;
  try {
   await client.query('BEGIN');
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`combined-receipt:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const prior=await client.query<{id:string;request_hash:string;created_by:string}>(
    'SELECT id,request_hash,created_by FROM combined_internal_receipts WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(prior.rows[0]) {
    if(prior.rows[0].created_by!==principal.userId&&!capabilities.includes('sale.read'))throw new ForbiddenException('No puedes consultar un comprobante de otra persona.');
    if(prior.rows[0].request_hash!==requestHash)throw new ConflictException('El comando ya se utilizó con otras ventas.');
    receiptId=prior.rows[0].id;replay=true;
   } else {
    for(const saleId of [fuelSaleId,posSaleId].sort())
     await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`sale-collection:${saleId}`]);
    const source=await client.query<{id:string;authorization_id:string|null}>(
     `SELECT id,authorization_id FROM sales WHERE organization_id=$1 AND branch_id=$2 AND id=ANY($3::uuid[]) ORDER BY id FOR UPDATE`,
     [principal.organizationId,branchId,[fuelSaleId,posSaleId]]);
    if(source.rows.length!==2)throw new NotFoundException('Una de las ventas no existe en esta sucursal.');
    const fuel=source.rows.find(row=>row.id===fuelSaleId),pos=source.rows.find(row=>row.id===posSaleId);
    if(!fuel?.authorization_id||pos?.authorization_id)throw new ConflictException('El comprobante combinado requiere una venta de combustible y una venta POS.');
    const inserted=await client.query<{id:string}>(
     `INSERT INTO combined_internal_receipts(organization_id,branch_id,fuel_sale_id,pos_sale_id,command_id,request_hash,created_by,correlation_id)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
     [principal.organizationId,branchId,fuelSaleId,posSaleId,input.commandId,requestHash,principal.userId,correlationId]);
    receiptId=inserted.rows[0]!.id;
    await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'sale.combined_receipt_created',entityType:'combined_internal_receipt',entityId:receiptId,
     after:{fuelSaleId,posSaleId,receiptType:'internal_combined',fiscalStatus:'not_fiscal'}});
   }
   await client.query('COMMIT');
  } catch(error) {
   await client.query('ROLLBACK').catch(()=>undefined);
   if((error as {code?:string}).code==='23505')throw new ConflictException('Una de estas ventas ya forma parte de otro comprobante combinado.');
   if((error as {code?:string}).code==='23514')throw new ConflictException('No se puede combinar una venta con cobros o anticipos previos.');
   throw error;
  } finally {client.release();}
  return this.combinedReceiptDetail(branchId,receiptId,principal,'sale.create',replay);
 }

 async combinedReceipt(branchId:string,receiptId:string,principal:AuthPrincipal) {
  if(!isUuid(receiptId))throw new BadRequestException('El comprobante no es válido.');
  return this.combinedReceiptDetail(branchId,receiptId,principal,'sale.read',false);
 }

 async combinedReceiptForSale(branchId:string,saleId:string,principal:AuthPrincipal) {
  await this.access(principal,branchId,'sale.read');
  if(!isUuid(saleId))throw new BadRequestException('La venta no es válida.');
  const linked=await this.pool.query<{id:string}>(
   'SELECT id FROM combined_internal_receipts WHERE organization_id=$1 AND branch_id=$2 AND (fuel_sale_id=$3 OR pos_sale_id=$3)',
   [principal.organizationId,branchId,saleId]);
  return linked.rows[0]?this.combinedReceiptDetail(branchId,linked.rows[0].id,principal,'sale.read',false):{data:null};
 }

 private async combinedReceiptDetail(branchId:string,receiptId:string,principal:AuthPrincipal,permission:string,replay:boolean) {
  await this.access(principal,branchId,permission);
  const result=await this.pool.query<{id:string;fuelSaleId:string;posSaleId:string;createdAt:Date;createdBy:string;correlationId:string;
   totalUsd:string;fuelStatus:string;posStatus:string;fuelCollectedUsd:string;posCollectedUsd:string;fuelReservedUsd:string;posReservedUsd:string;collectionStatus:string}>(
   `SELECT c.id,c.fuel_sale_id AS "fuelSaleId",c.pos_sale_id AS "posSaleId",c.created_at AS "createdAt",c.created_by AS "createdBy",c.correlation_id AS "correlationId",
     (f.total_usd+p.total_usd)::text AS "totalUsd",fb.collection_status AS "fuelStatus",pb.collection_status AS "posStatus",
     fb.collected_usd::text AS "fuelCollectedUsd",pb.collected_usd::text AS "posCollectedUsd",fb.reserved_usd::text AS "fuelReservedUsd",pb.reserved_usd::text AS "posReservedUsd",
     CASE WHEN fb.collection_status='paid' AND pb.collection_status='paid' THEN 'paid'
       WHEN fb.collected_usd+pb.collected_usd>0 THEN 'partially_collected'
       WHEN fb.reserved_usd+pb.reserved_usd>0 THEN 'awaiting_confirmation' ELSE 'pending_collection' END AS "collectionStatus"
    FROM combined_internal_receipts c JOIN sales f ON f.id=c.fuel_sale_id JOIN sales p ON p.id=c.pos_sale_id
    JOIN sale_collection_balances fb ON fb.id=f.id JOIN sale_collection_balances pb ON pb.id=p.id
    WHERE c.id=$1 AND c.organization_id=$2 AND c.branch_id=$3`,[receiptId,principal.organizationId,branchId]);
  const row=result.rows[0];if(!row)throw new NotFoundException('El comprobante combinado no existe en esta sucursal.');
  const [fuel,pos]=await Promise.all([
   this.detail(branchId,row.fuelSaleId,principal,permission,false),
   this.detail(branchId,row.posSaleId,principal,permission,false)
  ]);
  return {data:{id:row.id,receiptType:'internal_combined',fiscalStatus:'not_fiscal',taxStatus:'not_consolidated',totalUsd:row.totalUsd,
   collectionStatus:row.collectionStatus,createdAt:row.createdAt,createdBy:row.createdBy,correlationId:row.correlationId,idempotentReplay:replay,
   components:{fuel:fuel.data,pos:pos.data}}};
 }

 async detail(branchId:string,saleId:string,principal:AuthPrincipal,permission='sale.read',replay=false) {
  const capabilities=await this.access(principal,branchId,permission);
  const header=await this.pool.query(
   `SELECT s.id,s.branch_id AS "branchId",s.authorization_id AS "authorizationId",cb.collection_status AS status,s.currency,s.total_usd::text AS "totalUsd",
      cb.collected_usd::text AS "collectedUsd",cb.outstanding_usd::text AS "outstandingUsd",cb.reserved_usd::text AS "reservedUsd",
      COALESCE(t.result->>'status',s.tax_status) AS "taxStatus",t.result->>'netUsd' AS "netUsd",t.result->>'taxUsd' AS "taxUsd",
      t.policy_version_id AS "taxPolicyVersionId",COALESCE(t.result->'components','[]'::jsonb) AS "taxComponents",
      cb.refunded_usd::text AS "refundedUsd",cb.refund_status AS "refundStatus",
      s.receipt_type AS "receiptType",s.version,s.occurred_at AS "occurredAt",s.created_at AS "createdAt",s.created_by AS "createdBy",s.correlation_id AS "correlationId"
    FROM sales s LEFT JOIN sale_tax_snapshots t ON t.sale_id=s.id JOIN sale_collection_balances cb ON cb.id=s.id
    WHERE s.id=$1 AND s.organization_id=$2 AND s.branch_id=$3`,[saleId,principal.organizationId,branchId]);
  if(!header.rows[0]) throw new NotFoundException('La venta no existe en esta sucursal.');
  const visibleCost=capabilities.includes('finance.cost.read');
  const lines=await this.pool.query(
   `SELECT id,kind,description,pos_product_id AS "posProductId",offer_version_id AS "offerVersionId",quantity_units::text AS "quantityUnits",fuel_product_id AS "fuelProductId",quantity_l::text AS "quantityL",price_usd_per_unit::text AS "priceUsdPerUnit",
      price_unit AS "priceUnit",price_version_id AS "priceVersionId",total_usd::text AS "totalUsd",inventory_movement_id AS "inventoryMovementId",
      CASE WHEN $4 THEN unit_cost_usd::text END AS "unitCostUsd",CASE WHEN $4 THEN cost_usd::text END AS "costUsd",CASE WHEN $4 THEN unit_cost_usd_per_l::text END AS "unitCostUsdPerL",
      CASE WHEN $4 THEN cost_quality ELSE 'restricted' END AS "costQuality"
    FROM sale_lines WHERE sale_id=$1 AND organization_id=$2 AND branch_id=$3 ORDER BY line_number`,
   [saleId,principal.organizationId,branchId,visibleCost]);
  return {data:{...header.rows[0],lines:lines.rows,idempotentReplay:replay}};
 }

 async receiptPdf(branchId:string,saleId:string,principal:AuthPrincipal) {
  await this.access(principal,branchId,'sale.read');
  const result=await this.detail(branchId,saleId,principal);
  const sale=result.data;
  const localDate=new Date(sale.occurredAt).toLocaleString('es-SV',{timeZone:'America/El_Salvador'});
  const lines=[
   'DLC GASOLINERAS',
   'COMPROBANTE INTERNO - NO FISCAL',
   'No sustituye factura, credito fiscal ni DTE.',
   '',
   'Venta: '+sale.id,
   'Fecha: '+localDate+' (America/El_Salvador)',
   'Estado: '+sale.status,
   'Sucursal: '+sale.branchId,
   '------------------------------------------',
   ...sale.lines.flatMap((line: {description:string;kind:string;priceUnit:string;quantityL:string;quantityUnits:string;priceUsdPerUnit:string;totalUsd:string})=>{
    const quantity=line.kind==='fuel' ? (line.priceUnit==='us_gallon' ? (Number(line.quantityL)/3.785411784).toFixed(3)+' gal' : Number(line.quantityL).toFixed(3)+' L') : line.quantityUnits+' unidades';
    const unit=line.kind==='fuel'?(line.priceUnit==='us_gallon'?'gal':'L'):'unidad';
    return [line.description,quantity+' x USD '+line.priceUsdPerUnit+'/'+unit+' = USD '+line.totalUsd];
   }),
   '------------------------------------------',
   'Total: USD '+sale.totalUsd,
   'Pagado: USD '+sale.collectedUsd,
   'Saldo: USD '+sale.outstandingUsd,
   'Estado fiscal: '+sale.taxStatus,
   'Documento interno para referencia operativa.',
  ];
  return serializeReceiptPdf(lines);
 }

 async forDispatch(branchId:string,authorizationId:string,principal:AuthPrincipal) {
  await this.access(principal,branchId,'sale.read');
  const found=await this.pool.query<{id:string}>('SELECT id FROM sales WHERE authorization_id=$1 AND organization_id=$2 AND branch_id=$3',[authorizationId,principal.organizationId,branchId]);
  return found.rows[0] ? this.detail(branchId,found.rows[0].id,principal) : {data:null};
 }

 async list(branchId:string,principal:AuthPrincipal,query:{q?:string;cursor?:string;limit?:number}) {
  await this.access(principal,branchId,'sale.read');
  const limit=query.limit??25;const q=query.q?.trim()??null;
  if(!Number.isInteger(limit)||limit<1||limit>100||(q?.length??0)>120) throw new BadRequestException('Filtros no válidos.');
  let cursorDate:string|null=null,cursorId:string|null=null;
  if(query.cursor) {
   if(query.cursor.length>2048) throw new BadRequestException('cursor no es válido.');
   try {const decoded=JSON.parse(Buffer.from(query.cursor,'base64url').toString()) as {at:unknown;id:unknown};
    if(typeof decoded.at!=='string'||!/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}(?::?\d{2})?)$/.test(decoded.at)||!Number.isFinite(Date.parse(decoded.at))||!isUuid(decoded.id)) throw new Error();
    cursorDate=decoded.at;cursorId=decoded.id as string;
   } catch {throw new BadRequestException('cursor no es válido.');}
  }
  const result=await this.pool.query<{id:string;occurredAt:Date;cursorAt:string}>(
   `SELECT s.id,s.authorization_id AS "authorizationId",cb.collection_status AS status,s.total_usd::text AS "totalUsd",cb.collected_usd::text AS "collectedUsd",cb.outstanding_usd::text AS "outstandingUsd",cb.reserved_usd::text AS "reservedUsd",s.currency,s.receipt_type AS "receiptType",
      COALESCE(t.result->>'status',s.tax_status) AS "taxStatus",s.occurred_at AS "occurredAt",s.occurred_at::text AS "cursorAt",l.description,l.quantity_l::text AS "quantityL",l.line_count AS "lineCount"
    FROM sales s JOIN LATERAL(SELECT string_agg(description,' · ' ORDER BY line_number) AS description,
      CASE WHEN count(*)=1 AND min(kind)='fuel' THEN sum(quantity_l) END AS quantity_l,count(*)::int AS line_count FROM sale_lines WHERE sale_id=s.id) l ON true
    LEFT JOIN sale_tax_snapshots t ON t.sale_id=s.id JOIN sale_collection_balances cb ON cb.id=s.id
    WHERE s.organization_id=$1 AND s.branch_id=$2 AND ($3::text IS NULL OR l.description ILIKE '%'||$3||'%' OR s.id::text=$3)
      AND ($4::timestamptz IS NULL OR (s.occurred_at,s.id)<($4::timestamptz,$5::uuid))
    ORDER BY s.occurred_at DESC,s.id DESC LIMIT $6`,[principal.organizationId,branchId,q,cursorDate,cursorId,limit+1]);
  const data=result.rows.slice(0,limit);const last=data.at(-1);
  const publicRows=data.map(row=>{const publicRow={...row};Reflect.deleteProperty(publicRow,'cursorAt');return publicRow;});
  return {data:publicRows,meta:{limit,nextCursor:result.rows.length>limit&&last?Buffer.from(JSON.stringify({at:last.cursorAt,id:last.id})).toString('base64url'):null}};
 }
}
function isUuid(value:unknown):value is string {return typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);}
