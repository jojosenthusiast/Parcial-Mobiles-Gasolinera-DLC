import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { createHash } from 'node:crypto';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import { SalesService } from './sales.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { AcceptStoreReturnDto, ApproveStoreCountDto, CaptureStoreCountDto, ChangeLotConditionDto, ClassifyStoreLossDto, CloseStoreTransferDto, CreatePosSaleDto, DispatchStoreTransferDto, PublishPosOfferDto, ReceivePosLotDto, ReceiveStoreTransferDto, UpdateAssortmentDto, UpdateGlobalCatalogDto } from './pos.dto.js';

@Injectable()
export class PosService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService,private readonly sales:SalesService) {}
 private async access(branchId:string,principal:AuthPrincipal,permission:string) {
  const capabilities=await this.auth.capabilities(principal,branchId);
  if(!capabilities.includes(permission))throw new ForbiddenException('No tienes permiso para esta operación de tienda o servicios.');
  const branch=await this.pool.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2',[branchId,principal.organizationId]);
  if(!branch.rowCount)throw new NotFoundException('La sucursal no existe.');
  return capabilities;
 }
 private async transaction<T>(work:(client:PoolClient)=>Promise<T>):Promise<T> {
  const client=await this.pool.connect();
  try {await client.query('BEGIN');const value=await work(client);await client.query('COMMIT');return value;}
  catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if((error as {code?:string}).code==='22003')throw new BadRequestException('Las cantidades o importes exceden el máximo permitido.');
   if((error as {code?:string}).code==='23514')throw new ConflictException('Revisa disponibilidad, versión del precio, cantidades, vencimiento y costo.');
   if((error as {code?:string}).code==='23503')throw new NotFoundException('El producto no existe en esta sucursal.');
   if((error as {code?:string}).code==='23505')throw new ConflictException('El código, documento, lote o comando ya está registrado.');
   throw error;
  }finally{client.release();}
 }
 async publish(branchId:string,principal:AuthPrincipal,input:PublishPosOfferDto,correlationId:string) {
  await this.access(branchId,principal,'pos.catalog.manage');
  if(!uuid(input.commandId)||!['store','service'].includes(input.kind)||typeof input.active!=='boolean'||typeof input.expiryRequired!=='boolean')throw new BadRequestException('Datos de catálogo no válidos.');
  const sku=bounded(input.sku,40,'Código').toUpperCase(),description=bounded(input.description,120,'Nombre');
  const category=input.kind==='store'?bounded(input.category??'Surtido general',80,'Categoría'):'Surtido general';
  if(input.kind==='store'&&category.length<2||input.kind==='service'&&input.category!==undefined)throw new BadRequestException('Categoría no válida para el tipo publicado.');
  if(!/^[A-Z0-9][A-Z0-9._-]{0,39}$/.test(sku)||!decimal(input.priceUsd,4)||!positive(input.priceUsd))throw new BadRequestException('Código o precio no válido.');
  const serviceCost=input.serviceUnitCostUsd??null;
  if(serviceCost!==null&&!decimal(serviceCost,8))throw new BadRequestException('Costo no válido.');
  if(input.kind==='store'&&serviceCost!==null||input.kind==='service'&&input.expiryRequired)throw new BadRequestException('El costo fijo es de servicios; los lotes corresponden a tienda.');
  if((input.productId===undefined)!==(input.expectedOfferVersionId===undefined)||input.productId!==undefined&&(!uuid(input.productId)||!uuid(input.expectedOfferVersionId)))throw new BadRequestException('Editar requiere producto y versión esperada.');
  const normalized={v:1,branchId:branchId.toLowerCase(),category:input.kind==='store'?category:null,productId:input.productId?.toLowerCase()??null,expectedOfferVersionId:input.expectedOfferVersionId?.toLowerCase()??null,sku,kind:input.kind,expiryRequired:input.expiryRequired,description,active:input.active,priceUsd:canonical(input.priceUsd),serviceCost:input.kind==='service'&&input.productId!==undefined&&input.serviceUnitCostUsd===undefined?'preserve':serviceCost===null?null:canonical(serviceCost)};
  const hash=digest(normalized);
  return this.transaction(async client=>{
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`pos-offer:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const replay=await client.query<{id:string;product_id:string;request_hash:string;created_by:string}>('SELECT id,product_id,request_hash,created_by FROM pos_offer_versions WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(replay.rows[0]){sameCommand(replay.rows[0],hash,principal.userId);return {data:{id:replay.rows[0].id,productId:replay.rows[0].product_id,idempotentReplay:true}};}
   let productId=input.productId;let costToPublish=serviceCost;
   if(productId){
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`pos-product:${productId.toLowerCase()}`]);
    const product=await client.query<{id:string;sku:string;kind:string;expiry_required:boolean}>('SELECT id,sku,kind,expiry_required FROM pos_products WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[productId,principal.organizationId,branchId]);
    const p=product.rows[0];if(!p)throw new NotFoundException('El producto no existe en esta sucursal.');
    if(p.sku!==sku||p.kind!==input.kind||p.expiry_required!==input.expiryRequired)throw new ConflictException('Código, tipo y control de vencimiento identifican el producto y se conservan.');
    const current=await client.query<{id:string;service_unit_cost_usd:string|null}>('SELECT id,service_unit_cost_usd::text FROM pos_offer_versions WHERE product_id=$1 ORDER BY version DESC LIMIT 1',[productId]);
    if(current.rows[0]?.id!==input.expectedOfferVersionId?.toLowerCase())throw new ConflictException('El catálogo cambió; actualiza antes de editar.');
    if(input.kind==='service'&&input.serviceUnitCostUsd===undefined)costToPublish=current.rows[0]!.service_unit_cost_usd;
   }else{
    const product=await client.query<{id:string}>('INSERT INTO pos_products(organization_id,branch_id,sku,kind,expiry_required,created_by) VALUES($1,$2,$3,$4,$5,$6) RETURNING id',[principal.organizationId,branchId,sku,input.kind,input.expiryRequired,principal.userId]);
    productId=product.rows[0]!.id;
   }
   if(input.kind==='store'){
    const catalog=await client.query<{id:string}>(`INSERT INTO store_catalog_products(organization_id,sku,kind,category,presentation,unit,created_by)
      VALUES($1,$2,'store',$3,$4,'unit',$5)
      ON CONFLICT(organization_id,sku) DO UPDATE SET sku=EXCLUDED.sku RETURNING id`,
      [principal.organizationId,sku,category,description,principal.userId]);
    await client.query(`INSERT INTO branch_assortments(organization_id,branch_id,catalog_product_id,pos_product_id,created_by)
      VALUES($1,$2,$3,$4,$5) ON CONFLICT(branch_id,catalog_product_id) DO NOTHING`,
      [principal.organizationId,branchId,catalog.rows[0]!.id,productId,principal.userId]);
   }
   const result=await client.query<{id:string}>(`INSERT INTO pos_offer_versions(organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id)
    SELECT $1,$2,$3,coalesce(max(version),0)+1,$4,$5,$6,$7,$8,$9,$10,$11 FROM pos_offer_versions WHERE product_id=$3 RETURNING id`,
    [principal.organizationId,branchId,productId,description,input.active,input.priceUsd,costToPublish,input.commandId,hash,principal.userId,correlationId]);
   const id=result.rows[0]!.id;await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.offer_published',entityType:'pos_product',entityId:productId,after:{offerVersionId:id,active:input.active,priceUsd:input.priceUsd}});
   return {data:{id,productId,idempotentReplay:false}};
  });
 }
 async receive(branchId:string,principal:AuthPrincipal,input:ReceivePosLotDto,correlationId:string) {
  await this.access(branchId,principal,'pos.stock.receive');
  if(!uuid(input.commandId)||!uuid(input.productId)||typeof input.quantity!=='string'||!/^[1-9][0-9]{0,8}$/.test(input.quantity))throw new BadRequestException('Producto, comando o cantidad no válido.');
  const lotCode=bounded(input.lotCode,80,'Lote'),source=bounded(input.sourceReference,300,'Documento');
  const expiry=input.expiresOn??null,cost=input.unitCostUsd??null;
  if(cost!==null&&!decimal(cost,8))throw new BadRequestException('Costo no válido.');
  if(expiry!==null&&(!/^\d{4}-\d{2}-\d{2}$/.test(expiry)||!Number.isFinite(Date.parse(expiry))||new Date(expiry).toISOString().slice(0,10)!==expiry))throw new BadRequestException('Fecha de vencimiento no válida.');
  const hash=digest({v:1,branchId:branchId.toLowerCase(),productId:input.productId.toLowerCase(),lotCode,source,expiry,quantity:input.quantity,cost:cost===null?null:canonical(cost)});
  return this.transaction(async client=>{
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`pos-lot:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const replay=await client.query<{id:string;request_hash:string;created_by:string}>('SELECT id,request_hash,received_by AS created_by FROM pos_stock_lots WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(replay.rows[0]){sameCommand(replay.rows[0],hash,principal.userId);return {data:{id:replay.rows[0].id,idempotentReplay:true}};}
   const result=await client.query<{id:string}>(`INSERT INTO pos_stock_lots(organization_id,branch_id,product_id,lot_code,expires_on,quantity_received,unit_cost_usd,source_reference,command_id,request_hash,received_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,[principal.organizationId,branchId,input.productId,lotCode,expiry,input.quantity,cost,source,input.commandId,hash,principal.userId,correlationId]);
   const id=result.rows[0]!.id;await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.stock_received',entityType:'pos_stock_lot',entityId:id,after:{productId:input.productId,quantity:input.quantity,sourceReference:source}});
   return {data:{id,idempotentReplay:false}};
  });
 }
 async createSale(branchId:string,principal:AuthPrincipal,input:CreatePosSaleDto,correlationId:string) {
  const capabilities=await this.access(branchId,principal,'sale.create');
  if(!uuid(input.commandId)||!Array.isArray(input.items)||input.items.length<1||input.items.length>50)throw new BadRequestException('La venta requiere entre 1 y 50 productos.');
  const items=input.items.map(item=>{
   if(!uuid(item?.productId)||!uuid(item?.offerVersionId)||!decimal(item?.quantity,3)||!positive(item.quantity))throw new BadRequestException('Producto, versión o cantidad no válido.');
   return {productId:item.productId.toLowerCase(),offerVersionId:item.offerVersionId.toLowerCase(),quantity:canonical(item.quantity)};
  });
  if(new Set(items.map(i=>i.productId)).size!==items.length)throw new BadRequestException('Agrupa las cantidades de cada producto en una sola línea.');
  const hash=digest({v:1,branchId:branchId.toLowerCase(),items});
  const result=await this.transaction(async client=>{
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`sale:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const old=await client.query<{id:string;created_by:string;request_hash:string}>('SELECT id,created_by,request_hash FROM sales WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(old.rows[0]){
    if(old.rows[0].created_by!==principal.userId&&!capabilities.includes('sale.read'))throw new ForbiddenException('No puedes consultar una venta de otra persona.');
    if(old.rows[0].request_hash!==hash)throw new ConflictException('El comando corresponde a otra venta.');
    return {id:old.rows[0].id,replay:true};
   }
   const posted=await client.query<{id:string}>('SELECT post_pos_sale($1,$2,$3,$4,$5,$6::jsonb,$7) AS id',[principal.organizationId,branchId,principal.userId,input.commandId,hash,JSON.stringify(items),correlationId]);
   const id=posted.rows[0]!.id;await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'sale.created',entityType:'sale',entityId:id,after:{lineCount:items.length,status:'pending_collection',receiptType:'internal'}});
   return {id,replay:false};
  });
  return this.sales.detail(branchId,result.id,principal,'sale.create',result.replay);
 }
 async catalog(branchId:string,principal:AuthPrincipal,query:{q?:string;kind?:string;category?:string;cursor?:string;limit?:number;includeInactive?:string},productId?:string) {
  const capabilities=await this.access(branchId,principal,'pos.catalog.read');
  const {limit,q,cursor}=page(query);
  if(query.kind!==undefined&&!['store','service'].includes(query.kind)||query.category!==undefined&&(query.category.trim().length<2||query.category.length>80)||query.includeInactive!==undefined&&!['true','false'].includes(query.includeInactive))throw new BadRequestException('Filtro no válido.');
  if(query.includeInactive==='true'&&!capabilities.some(permission=>['pos.catalog.manage','pos.catalog.global.manage'].includes(permission)))throw new ForbiddenException('No tienes permiso para consultar productos inactivos.');
  const result=await this.pool.query<{id:string}>(`SELECT p.id,p.sku,p.kind,p.expiry_required AS "expiryRequired",o.id AS "offerVersionId",o.version,o.description,o.active,o.price_usd::text AS "priceUsd",
   CASE WHEN $8 THEN o.service_unit_cost_usd::text END AS "serviceUnitCostUsd",o.created_at AS "updatedAt",
   a.active AS "inAssortment",a.min_stock_units AS "minStockUnits",c.id AS "catalogProductId",
   c.barcode,c.category,c.presentation,c.unit,c.tax_code AS "taxCode",c.active AS "catalogActive",
   coalesce(stock.available,0)::text AS "availableUnits",coalesce(stock.expired,0)::text AS "expiredUnits"
   FROM pos_products p JOIN LATERAL(SELECT * FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1)o ON true
   LEFT JOIN branch_assortments a ON a.pos_product_id=p.id
   LEFT JOIN store_catalog_products c ON c.id=a.catalog_product_id
   LEFT JOIN LATERAL(SELECT sum(b.balance) FILTER(WHERE b.condition='sellable' AND (b.expires_on IS NULL OR b.expires_on>=(clock_timestamp() AT TIME ZONE br.timezone)::date)) AS available,
    sum(b.balance) FILTER(WHERE b.expires_on<(clock_timestamp() AT TIME ZONE br.timezone)::date) AS expired
    FROM (SELECT l.expires_on,l.condition,coalesce(sum(m.delta_units),0) AS balance FROM pos_stock_lots l LEFT JOIN pos_stock_movements m ON m.lot_id=l.id WHERE l.product_id=p.id GROUP BY l.id) b
    JOIN branches br ON br.id=p.branch_id) stock ON true
   WHERE p.organization_id=$1 AND p.branch_id=$2 AND ($3::text IS NULL OR p.sku ILIKE '%'||$3||'%' OR o.description ILIKE '%'||$3||'%')
   AND ($4::text IS NULL OR p.kind=$4) AND ($5::uuid IS NULL OR p.id>$5) AND ($6 OR o.active) AND ($9::uuid IS NULL OR p.id=$9)
   AND ($10::text IS NULL OR lower(c.category)=lower($10)) ORDER BY p.id LIMIT $7`,
   [principal.organizationId,branchId,q,query.kind??null,cursor,query.includeInactive==='true',limit+1,capabilities.includes('finance.cost.read'),productId??null,query.category?.trim()??null]);
  const data=result.rows.slice(0,limit);return {data,meta:{limit,nextCursor:result.rows.length>limit?data.at(-1)!.id:null}};
 }
 async categories(branchId:string,principal:AuthPrincipal) {
  await this.access(branchId,principal,'pos.catalog.read');
  const result=await this.pool.query<{category:string}>(`SELECT DISTINCT c.category FROM branch_assortments a
   JOIN store_catalog_products c ON c.id=a.catalog_product_id AND c.organization_id=a.organization_id
   JOIN pos_products p ON p.id=a.pos_product_id AND p.organization_id=a.organization_id AND p.branch_id=a.branch_id
   JOIN LATERAL(SELECT active FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1)o ON true
   WHERE a.organization_id=$1 AND a.branch_id=$2 AND a.active AND c.active AND o.active ORDER BY c.category`,[principal.organizationId,branchId]);
  return {data:result.rows.map(row=>row.category)};
 }
 async product(branchId:string,productId:string,principal:AuthPrincipal) {
  if(!uuid(productId))throw new BadRequestException('Producto no válido.');
  const result=await this.catalog(branchId,principal,{limit:1,includeInactive:'true'},productId);
  if(!result.data[0])throw new NotFoundException('El producto no existe en esta sucursal.');
  return {data:result.data[0]};
 }
 async lots(branchId:string,productId:string,principal:AuthPrincipal,query:{cursor?:string;limit?:number}) {
  const capabilities=await this.access(branchId,principal,'pos.catalog.read');const {limit,cursor}=page(query);
  if(!uuid(productId))throw new BadRequestException('Producto no válido.');
  const result=await this.pool.query<{id:string}>(`SELECT l.id,l.lot_code AS "lotCode",l.expires_on::text AS "expiresOn",l.quantity_received::text AS "receivedUnits",
   l.source_reference AS "sourceReference",l.received_at AS "receivedAt",CASE WHEN $6 THEN l.unit_cost_usd::text END AS "unitCostUsd",
   l.condition,(SELECT sum(delta_units)::text FROM pos_stock_movements WHERE lot_id=l.id) AS "remainingUnits"
   FROM pos_stock_lots l WHERE l.organization_id=$1 AND l.branch_id=$2 AND l.product_id=$3 AND ($4::uuid IS NULL OR l.id>$4) ORDER BY l.id LIMIT $5`,
   [principal.organizationId,branchId,productId,cursor,limit+1,capabilities.includes('finance.cost.read')]);
  const data=result.rows.slice(0,limit);return {data,meta:{limit,nextCursor:result.rows.length>limit?data.at(-1)!.id:null}};
 }
 async condition(branchId:string,lotId:string,principal:AuthPrincipal,input:ChangeLotConditionDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.quarantine');
  if(!uuid(lotId)||!uuid(input.commandId)||!['sellable','quarantine'].includes(input.condition))throw new BadRequestException('Lote o condición no válida.');
  const reason=bounded(input.reason,500,'Motivo');if(reason.length<10)throw new BadRequestException('Explica el motivo en al menos diez caracteres.');
  const hash=digest({v:1,branchId:branchId.toLowerCase(),lotId:lotId.toLowerCase(),condition:input.condition,reason});
  return this.transaction(async client=>{
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`pos-condition:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
   const replay=await client.query<{id:string;request_hash:string;actor_id:string;lot_id:string}>('SELECT id,request_hash,actor_id,lot_id FROM pos_lot_condition_events WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   if(replay.rows[0]){
    if(replay.rows[0].request_hash!==hash||replay.rows[0].actor_id!==principal.userId||replay.rows[0].lot_id!==lotId)throw new ConflictException('El comando ya se utilizó para otra transición.');
    return {data:{id:replay.rows[0].id,lotId,condition:input.condition,idempotentReplay:true}};
   }
   const event=await client.query<{id:string}>('SELECT set_pos_lot_condition($1,$2,$3,$4,$5,$6,$7,$8,$9) AS id',
    [principal.organizationId,branchId,principal.userId,lotId,input.condition,reason,input.commandId,hash,correlationId]);
   const id=event.rows[0]!.id;
   await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.lot_condition_changed',entityType:'pos_stock_lot',entityId:lotId,after:{eventId:id,condition:input.condition,reason}});
   return {data:{id,lotId,condition:input.condition}};
  });
 }
 async dispatch(branchId:string,principal:AuthPrincipal,input:DispatchStoreTransferDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.transfer.send');
  if(!uuid(input.commandId)||!uuid(input.destinationBranchId)||!uuid(input.sourceLotId)||!uuid(input.destinationProductId)||!/^[1-9][0-9]{0,8}$/.test(input.quantity))throw new BadRequestException('Traslado no válido.');
  const document=bounded(input.document,160,'Documento');if(document.length<3)throw new BadRequestException('Documento no válido.');
  const hash=digest({v:1,branchId,destinationBranchId:input.destinationBranchId,sourceLotId:input.sourceLotId,destinationProductId:input.destinationProductId,quantity:input.quantity,document});
  return this.transaction(async client=>{
   const old=await client.query<{id:string;request_hash:string;created_by:string}>('SELECT id,request_hash,created_by FROM store_transfers WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT dispatch_store_transfer($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) AS id',
    [principal.organizationId,branchId,input.destinationBranchId,principal.userId,input.sourceLotId,input.destinationProductId,Number(input.quantity),document,input.commandId,hash,correlationId]);
   const id=r.rows[0]!.id;
   if(!old.rows[0])await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.transfer_dispatched',entityType:'store_transfer',entityId:id,after:{sourceLotId:input.sourceLotId,destinationBranchId:input.destinationBranchId,quantity:input.quantity}});
   return {data:{id,idempotentReplay:!!old.rows[0]}};
  });
 }
 async transferReceipt(branchId:string,transferId:string,principal:AuthPrincipal,input:ReceiveStoreTransferDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.transfer.receive');
  if(!uuid(transferId)||!uuid(input.commandId)||!/^[1-9][0-9]{0,8}$/.test(input.quantity))throw new BadRequestException('Recepción no válida.');
  const document=bounded(input.document,160,'Documento');if(document.length<3)throw new BadRequestException('Documento no válido.');
  const hash=digest({v:1,branchId,transferId,quantity:input.quantity,document});
  return this.transaction(async client=>{
   const old=await client.query<{id:string}>('SELECT id FROM store_transfer_receipts WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT receive_store_transfer($1,$2,$3,$4,$5,$6,$7,$8,$9) AS id',
    [principal.organizationId,branchId,principal.userId,transferId,Number(input.quantity),document,input.commandId,hash,correlationId]);
   const id=r.rows[0]!.id;
   if(!old.rows[0])await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.transfer_received',entityType:'store_transfer',entityId:transferId,after:{receiptId:id,quantity:input.quantity}});
   return {data:{id,transferId,idempotentReplay:!!old.rows[0]}};
  });
 }
 async transferClose(branchId:string,transferId:string,principal:AuthPrincipal,input:CloseStoreTransferDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.transfer.close');
  if(!uuid(transferId)||!uuid(input.commandId))throw new BadRequestException('Cierre no válido.');
  const reason=bounded(input.reason,500,'Motivo');if(reason.length<10)throw new BadRequestException('Describe la diferencia o conformidad.');
  const hash=digest({v:1,branchId,transferId,reason});
  return this.transaction(async client=>{
   const old=await client.query<{transfer_id:string}>('SELECT transfer_id FROM store_transfer_closures WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT close_store_transfer($1,$2,$3,$4,$5,$6,$7,$8) AS id',
    [principal.organizationId,branchId,principal.userId,transferId,reason,input.commandId,hash,correlationId]);
   if(!old.rows[0])await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.transfer_closed',entityType:'store_transfer',entityId:r.rows[0]!.id,after:{reason}});
   return {data:{id:r.rows[0]!.id,idempotentReplay:!!old.rows[0]}};
  });
 }
 async transfers(branchId:string,principal:AuthPrincipal,query:{cursor?:string;limit?:number}){
  await this.access(branchId,principal,'pos.catalog.read');const {cursor,limit}=page(query);
  const r=await this.pool.query<{id:string}>(`SELECT t.id,t.source_branch_id AS "sourceBranchId",t.destination_branch_id AS "destinationBranchId",
   t.quantity_sent AS "quantitySent",t.quantity_received AS "quantityReceived",t.quantity_in_transit AS "quantityInTransit",
   t.quantity_missing AS "quantityMissing",t.status,t.created_at AS "createdAt",t.closed_at AS "closedAt"
   FROM store_transfer_status t WHERE t.organization_id=$1 AND (t.source_branch_id=$2 OR t.destination_branch_id=$2)
   AND ($3::uuid IS NULL OR t.id>$3) ORDER BY t.id LIMIT $4`,[principal.organizationId,branchId,cursor,limit+1]);
  const data=r.rows.slice(0,limit);return {data,meta:{limit,nextCursor:r.rows.length>limit?data.at(-1)!.id:null}};
 }
 async transfer(branchId:string,transferId:string,principal:AuthPrincipal){
  await this.access(branchId,principal,'pos.catalog.read');if(!uuid(transferId))throw new BadRequestException('Traslado no válido.');
  const t=await this.pool.query(`SELECT * FROM store_transfer_status WHERE id=$1 AND organization_id=$2 AND (source_branch_id=$3 OR destination_branch_id=$3)`,[transferId,principal.organizationId,branchId]);
  if(!t.rows[0])throw new NotFoundException('Traslado no encontrado.');
  const r=await this.pool.query(`SELECT id,quantity_received AS "quantityReceived",document,received_at AS "receivedAt",destination_lot_id AS "lotId" FROM store_transfer_receipts WHERE transfer_id=$1 ORDER BY received_at,id`,[transferId]);
  return {data:{...t.rows[0],receipts:r.rows}};
 }
 async count(branchId:string,principal:AuthPrincipal,input:CaptureStoreCountDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.count');
  if(!uuid(input.commandId)||!uuid(input.lotId)||!/^(0|[1-9][0-9]{0,8})$/.test(input.observedUnits))throw new BadRequestException('Conteo no válido.');
  const reason=bounded(input.reason,500,'Motivo');if(reason.length<10)throw new BadRequestException('Explica el conteo.');
  const hash=digest({v:1,branchId,lotId:input.lotId,observedUnits:input.observedUnits,reason});
  return this.transaction(async client=>{
   const old=await client.query('SELECT id FROM store_stock_counts WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT capture_store_count($1,$2,$3,$4,$5,$6,$7,$8,$9) AS id',
    [principal.organizationId,branchId,principal.userId,input.lotId,Number(input.observedUnits),reason,input.commandId,hash,correlationId]);
   const id=r.rows[0]!.id;
   if(!old.rows[0])await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.stock_count_captured',entityType:'store_stock_count',entityId:id,after:{lotId:input.lotId,observedUnits:input.observedUnits,reason}});
   return {data:{id,idempotentReplay:!!old.rows[0]}};
  });
 }
 async approveCount(branchId:string,countId:string,principal:AuthPrincipal,input:ApproveStoreCountDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.adjust.approve');
  if(!uuid(countId)||!uuid(input.commandId))throw new BadRequestException('Conteo o comando no válido.');
  const hash=digest({v:1,branchId,countId});
  return this.transaction(async client=>{
   const old=await client.query('SELECT count_id FROM store_count_approvals WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT approve_store_count($1,$2,$3,$4,$5,$6,$7) AS id',
    [principal.organizationId,branchId,principal.userId,countId,input.commandId,hash,correlationId]);
   if(!old.rows[0])await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.stock_count_approved',entityType:'store_stock_count',entityId:countId,after:{approved:true}});
   return {data:{id:r.rows[0]!.id,idempotentReplay:!!old.rows[0]}};
  });
 }
 async counts(branchId:string,principal:AuthPrincipal,query:{cursor?:string;limit?:number}){
  const caps=await this.access(branchId,principal,'pos.catalog.read');const {cursor,limit}=page(query);
  const r=await this.pool.query<{id:string}>(`SELECT c.id,c.lot_id AS "lotId",c.expected_units AS "expectedUnits",c.observed_units AS "observedUnits",
   c.reason,c.counted_by AS "countedBy",c.counted_at AS "countedAt",a.approved_by AS "approvedBy",
   a.approved_at AS "approvedAt",a.delta_units AS "adjustmentUnits",loss.cause AS "lossCause",
   CASE WHEN $5 THEN loss.cost_usd::text END AS "lossCostUsd",loss.cost_quality AS "lossCostQuality"
   FROM store_stock_counts c LEFT JOIN store_count_approvals a ON a.count_id=c.id
   LEFT JOIN store_stock_loss_classifications loss ON loss.count_id=c.id
   WHERE c.organization_id=$1 AND c.branch_id=$2 AND ($3::uuid IS NULL OR c.id>$3) ORDER BY c.id LIMIT $4`,
   [principal.organizationId,branchId,cursor,limit+1,caps.includes('finance.cost.read')]);
  const data=r.rows.slice(0,limit);return {data,meta:{limit,nextCursor:r.rows.length>limit?data.at(-1)!.id:null}};
 }
 async classifyLoss(branchId:string,countId:string,principal:AuthPrincipal,input:ClassifyStoreLossDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.loss.classify');
  if(!uuid(countId)||!uuid(input.commandId)||!['damage','expired','suspected_theft','unexplained'].includes(input.cause))
   throw new BadRequestException('Clasificación no válida.');
  const reason=bounded(input.reason,500,'Motivo');if(reason.length<10)throw new BadRequestException('Explica la causa de la merma.');
  const hash=digest({v:1,branchId,countId,cause:input.cause,reason});
  return this.transaction(async client=>{
   const old=await client.query('SELECT count_id FROM store_stock_loss_classifications WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT classify_store_stock_loss($1,$2,$3,$4,$5,$6,$7,$8,$9) AS id',
    [principal.organizationId,branchId,principal.userId,countId,input.cause,reason,input.commandId,hash,correlationId]);
   if(!old.rows[0])await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.stock_loss_classified',entityType:'store_stock_count',entityId:countId,after:{cause:input.cause,reason}});
   return {data:{id:r.rows[0]!.id,idempotentReplay:!!old.rows[0]}};
  });
 }
 async acceptReturn(branchId:string,principal:AuthPrincipal,input:AcceptStoreReturnDto,correlationId:string){
  await this.access(branchId,principal,'pos.stock.return');
  if(!uuid(input.commandId)||!uuid(input.saleLineId)||!uuid(input.sourceLotId)||!/^[1-9][0-9]{0,8}$/.test(input.quantity)
   ||!['sellable','quarantine'].includes(input.disposition))throw new BadRequestException('Devolución no válida.');
  const reason=bounded(input.reason,500,'Motivo');if(reason.length<10)throw new BadRequestException('Explica la devolución.');
  const hash=digest({v:1,branchId,saleLineId:input.saleLineId,sourceLotId:input.sourceLotId,quantity:input.quantity,disposition:input.disposition,reason});
  return this.transaction(async client=>{
   const old=await client.query('SELECT id FROM store_returns WHERE organization_id=$1 AND command_id=$2',[principal.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT accept_store_return($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) AS id',
    [principal.organizationId,branchId,principal.userId,input.saleLineId,input.sourceLotId,Number(input.quantity),input.disposition,reason,input.commandId,hash,correlationId]);
   const id=r.rows[0]!.id;
   if(!old.rows[0])await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.store_return_accepted',entityType:'store_return',entityId:id,after:{saleLineId:input.saleLineId,quantity:input.quantity,disposition:input.disposition}});
   return {data:{id,idempotentReplay:!!old.rows[0]}};
  });
 }
 async returns(branchId:string,principal:AuthPrincipal,query:{cursor?:string;limit?:number}){
  await this.access(branchId,principal,'pos.catalog.read');const {cursor,limit}=page(query);
  const r=await this.pool.query<{id:string}>(`SELECT r.id,r.sale_line_id AS "saleLineId",r.source_lot_id AS "sourceLotId",r.return_lot_id AS "returnLotId",
   r.quantity_units AS "quantityUnits",r.disposition,r.amount_eligible_usd::text AS "eligibleRefundUsd",
   coalesce((SELECT sum(amount_usd) FROM payment_refunds WHERE store_return_id=r.id),0)::text AS "refundedUsd",
   r.reason,r.accepted_at AS "acceptedAt" FROM store_returns r
   WHERE r.organization_id=$1 AND r.branch_id=$2 AND ($3::uuid IS NULL OR r.id>$3) ORDER BY r.id LIMIT $4`,
   [principal.organizationId,branchId,cursor,limit+1]);
  const data=r.rows.slice(0,limit);return {data,meta:{limit,nextCursor:r.rows.length>limit?data.at(-1)!.id:null}};
 }
 async updateGlobalCatalog(branchId:string,catalogId:string,principal:AuthPrincipal,input:UpdateGlobalCatalogDto,correlationId:string){
  await this.access(branchId,principal,'pos.catalog.global.manage');
  if(!uuid(catalogId)||!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1
   ||!['store','lubricant','part'].includes(input.kind)||!['unit','bottle','liter','case','pack','kg'].includes(input.unit)
   ||typeof input.active!=='boolean')throw new BadRequestException('Datos maestros no válidos.');
  const category=bounded(input.category,80,'Categoría'),presentation=bounded(input.presentation,120,'Presentación');
  if(category.length<2||presentation.length<2||input.barcode!=null&&!/^[0-9]{8,14}$/.test(input.barcode)
   ||input.defaultSupplierId!=null&&!uuid(input.defaultSupplierId))throw new BadRequestException('Presentación, código o proveedor no válido.');
  const taxCode=input.taxCode==null?null:bounded(input.taxCode,40,'Código tributario');
  return this.transaction(async client=>{
   const r=await client.query<{id:string;version:number}>(`UPDATE store_catalog_products SET barcode=$4,kind=$5,category=$6,presentation=$7,unit=$8,
    tax_code=$9,default_supplier_id=$10,active=$11,version=version+1
    WHERE id=$1 AND organization_id=$2 AND version=$3 RETURNING id,version`,
    [catalogId,principal.organizationId,input.expectedVersion,input.barcode??null,input.kind,category,presentation,input.unit,taxCode,input.defaultSupplierId??null,input.active]);
   if(!r.rows[0])throw new ConflictException('El producto maestro cambió o no pertenece a la organización.');
   await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.global_catalog_updated',entityType:'store_catalog_product',entityId:catalogId,after:{version:r.rows[0].version,category,presentation,unit:input.unit,active:input.active}});
   return {data:r.rows[0]};
  });
 }
 async updateAssortment(branchId:string,productId:string,principal:AuthPrincipal,input:UpdateAssortmentDto,correlationId:string){
  await this.access(branchId,principal,'pos.catalog.manage');
  if(!uuid(productId)||typeof input.active!=='boolean'||!Number.isSafeInteger(input.minStockUnits)||input.minStockUnits<0||input.minStockUnits>999999999)
   throw new BadRequestException('Surtido o mínimo no válido.');
  return this.transaction(async client=>{
   const r=await client.query<{catalog_product_id:string}>(`UPDATE branch_assortments SET active=$4,min_stock_units=$5
     WHERE pos_product_id=$1 AND branch_id=$2 AND organization_id=$3 RETURNING catalog_product_id`,
    [productId,branchId,principal.organizationId,input.active,input.minStockUnits]);
   if(!r.rows[0])throw new NotFoundException('Este producto no forma parte del surtido de la sucursal.');
   await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'pos.branch_assortment_updated',entityType:'pos_product',entityId:productId,after:{active:input.active,minStockUnits:input.minStockUnits}});
   return {data:{productId,catalogProductId:r.rows[0].catalog_product_id,active:input.active,minStockUnits:input.minStockUnits}};
  });
 }
 async stockAlerts(branchId:string,principal:AuthPrincipal){
  await this.access(branchId,principal,'pos.catalog.read');
  const r=await this.pool.query(`SELECT a.pos_product_id AS "productId",c.sku,c.presentation,a.min_stock_units AS "minimumUnits",
   coalesce(sum(b.balance) FILTER(WHERE b.condition='sellable' AND (b.expires_on IS NULL OR b.expires_on>= (clock_timestamp() AT TIME ZONE br.timezone)::date)),0)::text AS "availableUnits",
   coalesce(sum(b.balance) FILTER(WHERE b.condition<>'sellable'),0)::text AS "heldUnits",
   coalesce(sum(b.balance) FILTER(WHERE b.expires_on<(clock_timestamp() AT TIME ZONE br.timezone)::date),0)::text AS "expiredUnits",
   min(b.expires_on) FILTER(WHERE b.balance>0 AND b.expires_on>=(clock_timestamp() AT TIME ZONE br.timezone)::date) AS "nextExpiry"
   FROM branch_assortments a JOIN store_catalog_products c ON c.id=a.catalog_product_id
   JOIN branches br ON br.id=a.branch_id
   LEFT JOIN LATERAL(SELECT l.condition,l.expires_on,coalesce(sum(m.delta_units),0) AS balance
     FROM pos_stock_lots l LEFT JOIN pos_stock_movements m ON m.lot_id=l.id
     WHERE l.product_id=a.pos_product_id GROUP BY l.id) b ON true
   WHERE a.branch_id=$1 AND a.organization_id=$2 AND a.active AND c.active
   GROUP BY a.pos_product_id,c.sku,c.presentation,a.min_stock_units,br.timezone
   HAVING coalesce(sum(b.balance) FILTER(WHERE b.condition='sellable' AND (b.expires_on IS NULL OR b.expires_on>=(clock_timestamp() AT TIME ZONE br.timezone)::date)),0)<a.min_stock_units
     OR coalesce(sum(b.balance) FILTER(WHERE b.condition<>'sellable' OR b.expires_on<(clock_timestamp() AT TIME ZONE br.timezone)::date),0)>0
   ORDER BY c.sku`,[branchId,principal.organizationId]);
  return {data:r.rows};
 }
}
function uuid(value:unknown):value is string{return typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);}
function decimal(value:unknown,precision:number):value is string{return typeof value==='string'&&new RegExp(`^(0|[1-9][0-9]{0,8})(\\.[0-9]{1,${precision}})?$`).test(value);}
function positive(value:string){return /[1-9]/.test(value);}
function canonical(value:string){return value.includes('.')?value.replace(/0+$/,'').replace(/\.$/,''):value;}
function bounded(value:unknown,max:number,label:string){if(typeof value!=='string'||!value.trim()||value.trim().length>max)throw new BadRequestException(`${label} no válido.`);return value.trim();}
function digest(value:unknown){return createHash('sha256').update(JSON.stringify(value)).digest('hex');}
function sameCommand(row:{request_hash:string;created_by:string},hash:string,actor:string){if(row.request_hash!==hash||row.created_by!==actor)throw new ConflictException('El comando corresponde a otros datos o persona.');}
function page(query:{q?:string;cursor?:string;limit?:number}){
 const limit=query.limit??25,q=query.q?.trim()||null,cursor=query.cursor??null;
 if(!Number.isInteger(limit)||limit<1||limit>100||(q?.length??0)>120||cursor!==null&&!uuid(cursor))throw new BadRequestException('Paginación o búsqueda no válida.');
 return {limit,q,cursor};
}
