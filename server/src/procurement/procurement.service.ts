import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import { createHash, randomUUID } from 'node:crypto';
import { Decimal } from 'decimal.js';
import { PG_POOL } from '../database/database.module.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { PurchaseOrderCreateDto, PurchaseOrderDecisionDto, PurchaseReceiptDto, SupplierCreateDto, SupplierInvoiceCreateDto, SupplierPaymentDto } from './procurement.dto.js';
import { FuelInventoryService } from '../inventory/fuel-inventory.service.js';

@Injectable()
export class ProcurementService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly audit: AuditService, private readonly inventory: FuelInventoryService) {}

  async suppliers(principal: AuthPrincipal, query: string | undefined, limit: number) {
    const q = query?.trim();
    const result = await this.pool.query(
      `SELECT s.id,s.legal_name AS "legalName",s.display_name AS "displayName",s.tax_id_normalized AS "taxId",
              s.contact_name AS "contactName",s.contact_email AS "contactEmail",s.contact_phone AS "contactPhone",
              s.payment_terms_days AS "paymentTermsDays",s.status,s.created_at AS "createdAt",
              COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'fuelProductId',o.fuel_product_id,'supplierProductCode',o.supplier_product_code,
                'lastQuotedUnitPriceUsd',o.last_quoted_unit_price_usd,'lastQuotedUnit',o.last_quoted_unit,'quoteValidUntil',o.quote_valid_until)
                ORDER BY o.created_at) FILTER (WHERE o.id IS NOT NULL),'[]'::jsonb) AS offers
         FROM suppliers s LEFT JOIN supplier_fuel_offers o ON o.supplier_id=s.id AND o.is_active
        WHERE s.organization_id=$1 AND ($2::text IS NULL OR s.legal_name ILIKE '%'||$2||'%' OR s.display_name ILIKE '%'||$2||'%' OR s.tax_id_normalized ILIKE '%'||$2||'%')
        GROUP BY s.id ORDER BY lower(s.legal_name),s.id LIMIT $3`, [principal.organizationId,q ?? null,Math.max(1,Math.min(limit,100))],
    );
    return { data: result.rows };
  }

  async createSupplier(principal: AuthPrincipal, input: SupplierCreateDto, correlationId: string) {
    const legalName = input.legalName.trim();
    if (!legalName) throw new BadRequestException('El nombre legal es obligatorio.');
    const taxId = normalizeTaxId(input.taxId);
    const offers = input.offers ?? [];
    if (new Set(offers.map((offer) => offer.fuelProductId)).size !== offers.length) throw new BadRequestException('No repitas productos en las ofertas del proveedor.');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      for (const offer of offers) await this.assertActiveProduct(client, principal.organizationId, offer.fuelProductId);
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO suppliers(organization_id,legal_name,display_name,tax_id_normalized,contact_name,contact_email,contact_phone,payment_terms_days,notes,created_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
        [principal.organizationId,legalName,clean(input.displayName),taxId,clean(input.contactName),clean(input.contactEmail)?.toLowerCase(),clean(input.contactPhone),input.paymentTermsDays ?? 0,clean(input.notes),principal.userId],
      );
      const supplierId = inserted.rows[0]!.id;
      for (const offer of offers) await client.query(
        `INSERT INTO supplier_fuel_offers(organization_id,supplier_id,fuel_product_id,supplier_product_code,last_quoted_unit_price_usd,last_quoted_unit,quote_valid_until)
         VALUES($1,$2,$3,$4,$5,$6,$7)`,
        [principal.organizationId,supplierId,offer.fuelProductId,clean(offer.supplierProductCode),offer.lastQuotedUnitPriceUsd ?? null,offer.lastQuotedUnit ?? null,offer.quoteValidUntil ?? null],
      );
      await this.audit.appendTransaction(client,{principal,correlationId,action:'supplier.create',entityType:'supplier',entityId:supplierId,after:{legalName,taxId,offers:offers.length}});
      await client.query('COMMIT');
      return { id:supplierId,legalName,status:'active',offers:offers.length };
    } catch (error) {
      await client.query('ROLLBACK').catch(()=>undefined);
      if (isUnique(error)) throw new ConflictException('Ya existe un proveedor con ese identificador fiscal.');
      throw error;
    } finally { client.release(); }
  }

  async createPurchaseOrder(branchId: string, principal: AuthPrincipal, input: PurchaseOrderCreateDto, correlationId: string) {
    const lines = input.lines;
    if (!input.orderNumber.trim()) throw new BadRequestException('El número de orden es obligatorio.');
    if (new Set(lines.map((line)=>line.fuelProductId)).size !== lines.length) throw new BadRequestException('Consolida cada producto en una sola línea por orden.');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const supplier = await client.query('SELECT id FROM suppliers WHERE id=$1 AND organization_id=$2 AND status=$3 FOR SHARE',[input.supplierId,principal.organizationId,'active']);
      if (!supplier.rowCount) throw new ConflictException('El proveedor no existe o está bloqueado/inactivo.');
      const branch = await client.query('SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status=$3 FOR SHARE',[branchId,principal.organizationId,'active']);
      if (!branch.rowCount) throw new NotFoundException('La sucursal activa no existe.');
      for (const line of lines) {
        const offer = await client.query('SELECT 1 FROM supplier_fuel_offers WHERE supplier_id=$1 AND fuel_product_id=$2 AND organization_id=$3 AND is_active',[input.supplierId,line.fuelProductId,principal.organizationId]);
        if (!offer.rowCount) throw new ConflictException('El proveedor no tiene una oferta activa para uno de los productos.');
        const product = await client.query('SELECT 1 FROM branch_fuel_offers WHERE branch_id=$1 AND fuel_product_id=$2 AND organization_id=$3 AND status=$4 AND valid_from<=now() AND (valid_until IS NULL OR valid_until>now())',[branchId,line.fuelProductId,principal.organizationId,'active']);
        if (!product.rowCount) throw new ConflictException('El producto no está habilitado en esta sucursal.');
        if (line.tankId) {
          const tank = await client.query('SELECT 1 FROM tanks WHERE id=$1 AND branch_id=$2 AND fuel_product_id=$3 AND organization_id=$4 AND status=$5',[line.tankId,branchId,line.fuelProductId,principal.organizationId,'active']);
          if (!tank.rowCount) throw new ConflictException('El tanque destino no está activo o no admite el producto de la línea.');
        }
      }
      const orderResult = await client.query<{id:string}>(
        `INSERT INTO purchase_orders(organization_id,branch_id,supplier_id,order_number,status,requested_delivery_at,notes,created_by)
         VALUES($1,$2,$3,$4,'draft',$5,$6,$7) RETURNING id`,
        [principal.organizationId,branchId,input.supplierId,input.orderNumber.trim(),input.requestedDeliveryAt ?? null,clean(input.notes),principal.userId],
      );
      const orderId=orderResult.rows[0]!.id;
      for (const line of lines) await client.query(
        `INSERT INTO purchase_order_lines(organization_id,purchase_order_id,branch_id,fuel_product_id,quantity_ordered,unit,agreed_unit_price_usd,tank_id)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[principal.organizationId,orderId,branchId,line.fuelProductId,line.quantity,line.unit,line.agreedUnitPriceUsd,line.tankId ?? null],
      );
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'purchase_order.create',entityType:'purchase_order',entityId:orderId,after:{supplierId:input.supplierId,orderNumber:input.orderNumber.trim(),lines:lines.length}});
      await client.query('COMMIT');
      return this.purchaseOrder(orderId,branchId,principal);
    } catch(error) {
      await client.query('ROLLBACK').catch(()=>undefined);
      if(isUnique(error)) throw new ConflictException('El número de orden ya existe en la organización.');
      throw error;
    } finally { client.release(); }
  }

  async listPurchaseOrders(branchId: string, principal: AuthPrincipal, status?: string, cursor?: string, limit = 50, query?: string) {
    const q = query?.trim();
    if (q && q.length > 100) throw new BadRequestException('La búsqueda no puede superar 100 caracteres.');
    let cursorAt:Date|null=null;
    if(cursor){
      const anchor=await this.pool.query<{created_at:Date}>('SELECT created_at FROM purchase_orders WHERE id=$1 AND organization_id=$2 AND branch_id=$3',[cursor,principal.organizationId,branchId]);
      if(!anchor.rows[0])throw new BadRequestException('Cursor de orden inválido.');
      cursorAt=anchor.rows[0].created_at;
    }
    const result=await this.pool.query(
      `SELECT po.id,po.order_number AS "orderNumber",po.status,po.version,po.requested_delivery_at AS "requestedDeliveryAt",
              po.created_at AS "createdAt",s.legal_name AS "supplierName",
              COALESCE(jsonb_agg(jsonb_build_object('id',l.id,'fuelProductId',l.fuel_product_id,'quantityOrdered',l.quantity_ordered,
                'quantityReceived',l.received_quantity,'unit',l.unit,'agreedUnitPriceUsd',l.agreed_unit_price_usd,'tankId',l.tank_id)
                ORDER BY l.created_at) FILTER (WHERE l.id IS NOT NULL),'[]'::jsonb) AS lines
         FROM purchase_orders po JOIN suppliers s ON s.id=po.supplier_id LEFT JOIN purchase_order_lines l ON l.purchase_order_id=po.id
        WHERE po.organization_id=$1 AND po.branch_id=$2 AND ($3::text IS NULL OR po.status=$3)
          AND ($4::timestamptz IS NULL OR (po.created_at,po.id)<($4::timestamptz,$5::uuid))
          AND ($6::text IS NULL OR po.order_number ILIKE '%'||$6||'%' ESCAPE '\\'
            OR s.legal_name ILIKE '%'||$6||'%' ESCAPE '\\' OR COALESCE(s.display_name,'') ILIKE '%'||$6||'%' ESCAPE '\\'
            OR EXISTS (SELECT 1 FROM purchase_order_lines ql JOIN fuel_products fp ON fp.id=ql.fuel_product_id AND fp.organization_id=ql.organization_id
                WHERE ql.purchase_order_id=po.id AND ql.organization_id=po.organization_id
                  AND (fp.display_name ILIKE '%'||$6||'%' ESCAPE '\\' OR fp.sku ILIKE '%'||$6||'%' ESCAPE '\\'))
          )
        GROUP BY po.id,s.legal_name ORDER BY po.created_at DESC,po.id DESC LIMIT $7`,[principal.organizationId,branchId,status ?? null,cursorAt,cursor??null,q?escapeLike(q):null,limit+1]);
    const data=result.rows.slice(0,limit);return {data,meta:{limit,nextCursor:result.rows.length>limit?data.at(-1)!.id:null}};
  }

  async submit(branchId:string,orderId:string,principal:AuthPrincipal,input:PurchaseOrderDecisionDto,correlationId:string) {
    return this.transition(branchId,orderId,principal,input,correlationId,'draft','pending_approval','purchase_order.submit');
  }

  async decide(branchId:string,orderId:string,principal:AuthPrincipal,input:PurchaseOrderDecisionDto,correlationId:string,decision:'approve'|'reject') {
    const client=await this.pool.connect();
    try {
      await client.query('BEGIN');
      const found=await client.query<{status:string;version:number;created_by:string}>(
        'SELECT status,version,created_by FROM purchase_orders WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE',[orderId,branchId,principal.organizationId]);
      const order=found.rows[0];
      if(!order) throw new NotFoundException('La orden no existe en esta sucursal.');
      if(order.status!=='pending_approval'||order.version!==input.expectedVersion) throw new ConflictException('La orden cambió o ya no espera aprobación. Actualiza la vista.');
      if(order.created_by===principal.userId) throw new ConflictException('Quien creó la orden no puede aprobarla ni rechazarla.');
      const next=decision==='approve'?'approved':'rejected';
      await client.query('UPDATE purchase_orders SET status=$2,approved_by=$3,approved_at=CASE WHEN $2=$4 THEN now() ELSE NULL END,version=version+1,updated_at=now() WHERE id=$1',[orderId,next,decision==='approve'?principal.userId:null,'approved']);
      await client.query('INSERT INTO purchase_approvals(organization_id,purchase_order_id,decision,reason,decided_by) VALUES($1,$2,$3,$4,$5)',[principal.organizationId,orderId,next,clean(input.reason),principal.userId]);
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:`purchase_order.${next}`,entityType:'purchase_order',entityId:orderId,before:{status:order.status,version:order.version},after:{status:next,reason:clean(input.reason)}});
      await client.query('COMMIT');
      return this.purchaseOrder(orderId,branchId,principal);
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
  }

  async markOrdered(branchId:string,orderId:string,principal:AuthPrincipal,input:PurchaseOrderDecisionDto,correlationId:string){
    return this.transition(branchId,orderId,principal,input,correlationId,'approved','ordered','purchase_order.ordered');
  }

  async receive(branchId:string,orderId:string,principal:AuthPrincipal,input:PurchaseReceiptDto,correlationId:string){
    const request={branchId,orderId,purchaseOrderLineId:input.purchaseOrderLineId,tankId:input.tankId,
      supplierDeliveryReference:input.supplierDeliveryReference.trim(),compartmentReference:clean(input.compartmentReference),
      documentReference:input.documentReference.trim(),billedQuantity:input.billedQuantity ?? null,inventory:input.inventory};
    const requestHash=createHash('sha256').update(JSON.stringify(request)).digest('hex');
    const client=await this.pool.connect();
    let deliveryId:string;
    let replay=false;
    try{
      await client.query('BEGIN');
      const prior=await client.query<{id:string;request_hash:string;status:string}>(
        'SELECT id,request_hash,status FROM purchase_deliveries WHERE organization_id=$1 AND command_id=$2 FOR UPDATE',[principal.organizationId,input.inventory.commandId]);
      if(prior.rows[0]){
        if(prior.rows[0].request_hash!==requestHash) throw new ConflictException('commandId ya fue utilizado con otra recepción.');
        if(prior.rows[0].status==='received'){
          await client.query('COMMIT');
          return {id:prior.rows[0].id,status:'received',idempotentReplay:true};
        }
        deliveryId=prior.rows[0].id; replay=true;
      }else{
        const po=await client.query<{status:string}>(`SELECT status FROM purchase_orders WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`,[orderId,branchId,principal.organizationId]);
        if(!po.rows[0]) throw new NotFoundException('La orden no existe en esta sucursal.');
        if(!['ordered','partially_received'].includes(po.rows[0].status)) throw new ConflictException('La orden debe estar enviada y no cerrada para recibir entregas.');
        const lineResult=await client.query<{id:string;fuel_product_id:string;branch_id:string;unit:string;quantity_ordered:string;received_quantity:string;tank_id:string|null}>(
          `SELECT id,fuel_product_id,branch_id,unit,quantity_ordered,received_quantity,tank_id FROM purchase_order_lines
            WHERE id=$1 AND purchase_order_id=$2 AND organization_id=$3 FOR UPDATE`,[input.purchaseOrderLineId,orderId,principal.organizationId]);
        const line=lineResult.rows[0];
        if(!line) throw new NotFoundException('La línea no pertenece a la orden.');
        if(line.unit!==input.inventory.unit) throw new BadRequestException('La recepción debe usar la unidad acordada en la línea de compra.');
        if(line.tank_id && line.tank_id!==input.tankId) throw new ConflictException('El tanque de destino no coincide con el acordado en la orden.');
        const tank=await client.query('SELECT 1 FROM tanks WHERE id=$1 AND branch_id=$2 AND fuel_product_id=$3 AND organization_id=$4 AND status=$5',[input.tankId,branchId,line.fuel_product_id,principal.organizationId,'active']);
        if(!tank.rowCount) throw new ConflictException('El tanque de recepción debe estar activo y admitir el combustible de la línea.');
        const reservations=await client.query<{reserved:string}>(`SELECT COALESCE(sum(accepted_quantity),0)::text AS reserved FROM purchase_deliveries WHERE purchase_order_line_id=$1 AND status='processing'`,[line.id]);
        const contaminated=await client.query<{lost:string}>('SELECT COALESCE(sum(actual_quantity),0)::text AS lost FROM contaminated_deliveries WHERE purchase_order_line_id=$1',[line.id]);
        const remaining=new Decimal(line.quantity_ordered).minus(line.received_quantity).minus(contaminated.rows[0]?.lost ?? '0').minus(reservations.rows[0]?.reserved ?? '0');
        if(new Decimal(input.inventory.quantity).lte(0)||new Decimal(input.inventory.quantity).gt(remaining)) throw new ConflictException('La cantidad excede el saldo de la orden disponible para recepción.');
        deliveryId=randomUUID();
        await client.query(
          `INSERT INTO purchase_deliveries(id,organization_id,branch_id,purchase_order_id,purchase_order_line_id,fuel_product_id,tank_id,command_id,request_hash,
            accepted_quantity,unit,billed_quantity,supplier_delivery_reference,compartment_reference,document_reference,actor_user_id)
           VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`,
          [deliveryId,principal.organizationId,branchId,orderId,line.id,line.fuel_product_id,input.tankId,input.inventory.commandId,requestHash,
            input.inventory.quantity,input.inventory.unit,input.billedQuantity ?? null,request.supplierDeliveryReference,request.compartmentReference ?? null,request.documentReference,principal.userId],
        );
      }
      await client.query('COMMIT');
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUnique(error)) throw new ConflictException('La recepción ya fue registrada; reintenta con su mismo commandId.');throw error;}finally{client.release();}

    const inventoryInput={...input.inventory,sourceId:deliveryId!,sourceLine:input.purchaseOrderLineId,documentReference:request.documentReference};
    const applied=await this.inventory.receive(branchId,input.tankId,principal,inventoryInput,correlationId);
    const finalize=await this.pool.connect();
    try{
      await finalize.query('BEGIN');
      const delivery=await finalize.query<{status:string;purchase_order_line_id:string;accepted_quantity:string;purchase_order_id:string}>(
        `SELECT status,purchase_order_line_id,accepted_quantity,purchase_order_id FROM purchase_deliveries WHERE id=$1 AND organization_id=$2 FOR UPDATE`,[deliveryId!,principal.organizationId]);
      const receipt=delivery.rows[0];
      if(!receipt) throw new NotFoundException('No se encontró el registro de recepción pendiente.');
      if(receipt.status==='received'){await finalize.query('COMMIT');return {id:deliveryId!,status:'received',idempotentReplay:true};}
      await finalize.query('SELECT id FROM purchase_orders WHERE id=$1 FOR UPDATE',[receipt.purchase_order_id]);
      const line=await finalize.query<{received_quantity:string;quantity_ordered:string}>(
        'SELECT received_quantity,quantity_ordered FROM purchase_order_lines WHERE id=$1 FOR UPDATE',[receipt.purchase_order_line_id]);
      const current=line.rows[0];
      if(!current||new Decimal(current.received_quantity).plus(receipt.accepted_quantity).gt(current.quantity_ordered)) throw new ConflictException('La orden alcanzó su cantidad pedida mientras se confirmaba esta recepción.');
      await finalize.query('UPDATE purchase_order_lines SET received_quantity=received_quantity+$2 WHERE id=$1',[receipt.purchase_order_line_id,receipt.accepted_quantity]);
      await finalize.query(`UPDATE purchase_deliveries SET status='received',inventory_movement_id=$2,received_at=now() WHERE id=$1`,[deliveryId!,applied.movement.id]);
      const all=await finalize.query<{complete:boolean}>(`SELECT bool_and(received_quantity>=quantity_ordered) AS complete FROM purchase_order_lines WHERE purchase_order_id=$1`,[receipt.purchase_order_id]);
      const next=all.rows[0]?.complete?'received':'partially_received';
      const orderUpdate=await finalize.query('UPDATE purchase_orders SET status=$2,version=version+1,updated_at=now() WHERE id=$1 AND status IN ($3,$4)',[receipt.purchase_order_id,next,'ordered','partially_received']);
      if(orderUpdate.rowCount!==1) throw new ConflictException('La orden cambió de estado antes de confirmar la recepción.');
      await this.audit.appendTransaction(finalize,{principal,branchId,correlationId,action:'purchase_order.delivery_received',entityType:'purchase_delivery',entityId:deliveryId!,after:{purchaseOrderId:receipt.purchase_order_id,lineId:receipt.purchase_order_line_id,acceptedQuantity:receipt.accepted_quantity,unit:input.inventory.unit,inventoryMovementId:applied.movement.id}});
      await finalize.query('COMMIT');
      return {id:deliveryId!,status:'received',idempotentReplay:replay,inventoryMovement:applied.movement,balance:applied.balance};
    }catch(error){await finalize.query('ROLLBACK').catch(()=>undefined);throw error;}finally{finalize.release();}
  }

  async cancel(branchId:string,orderId:string,principal:AuthPrincipal,input:PurchaseOrderDecisionDto,correlationId:string){
    const client=await this.pool.connect();
    try{
      await client.query('BEGIN');
      const found=await client.query<{status:string;version:number}>(`SELECT po.status,po.version FROM purchase_orders po WHERE po.id=$1 AND po.branch_id=$2 AND po.organization_id=$3 FOR UPDATE`,[orderId,branchId,principal.organizationId]);
      const order=found.rows[0];
      if(!order) throw new NotFoundException('La orden no existe en esta sucursal.');
      if(order.version!==input.expectedVersion||!['draft','pending_approval','approved','ordered','rejected'].includes(order.status)) throw new ConflictException('La orden cambió o no puede cancelarse en su estado actual.');
      const receipts=await client.query(`SELECT 1 FROM purchase_order_lines WHERE purchase_order_id=$1 AND received_quantity>0
        UNION ALL SELECT 1 FROM purchase_deliveries WHERE purchase_order_id=$1 LIMIT 1`,[orderId]);
      if(receipts.rowCount) throw new ConflictException('Una orden con recepción iniciada o registrada no puede cancelarse; reclama o cierra el saldo pendiente.');
      await client.query('UPDATE purchase_orders SET status=$2,version=version+1,updated_at=now() WHERE id=$1',[orderId,'cancelled']);
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'purchase_order.cancelled',entityType:'purchase_order',entityId:orderId,before:{status:order.status,version:order.version},after:{status:'cancelled',reason:clean(input.reason)}});
      await client.query('COMMIT'); return {id:orderId,status:'cancelled',version:order.version+1};
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
  }

  async purchaseOrder(orderId:string,branchId:string,principal:AuthPrincipal){
    const result=await this.pool.query(
      `SELECT po.id,po.order_number AS "orderNumber",po.status,po.version,po.requested_delivery_at AS "requestedDeliveryAt",
              po.notes,po.created_by AS "createdBy",po.approved_by AS "approvedBy",po.approved_at AS "approvedAt",po.created_at AS "createdAt",
              s.id AS "supplierId",s.legal_name AS "supplierName",
              COALESCE(jsonb_agg(jsonb_build_object('id',l.id,'fuelProductId',l.fuel_product_id,'quantityOrdered',l.quantity_ordered,
               'quantityReceived',l.received_quantity,'unit',l.unit,'agreedUnitPriceUsd',l.agreed_unit_price_usd,'tankId',l.tank_id)
               ORDER BY l.created_at) FILTER (WHERE l.id IS NOT NULL),'[]'::jsonb) AS lines,
              (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'purchaseOrderLineId',d.purchase_order_line_id,'tankId',d.tank_id,
                'acceptedQuantity',d.accepted_quantity,'billedQuantity',d.billed_quantity,'unit',d.unit,'status',d.status,
                'supplierDeliveryReference',d.supplier_delivery_reference,'compartmentReference',d.compartment_reference,
                'documentReference',d.document_reference,'inventoryMovementId',d.inventory_movement_id,'receivedAt',d.received_at)
                ORDER BY d.created_at DESC),'[]'::jsonb) FROM purchase_deliveries d WHERE d.purchase_order_id=po.id) AS deliveries
         FROM purchase_orders po JOIN suppliers s ON s.id=po.supplier_id LEFT JOIN purchase_order_lines l ON l.purchase_order_id=po.id
        WHERE po.id=$1 AND po.branch_id=$2 AND po.organization_id=$3 GROUP BY po.id,s.id`,[orderId,branchId,principal.organizationId]);
    if(!result.rowCount) throw new NotFoundException('La orden no existe en esta sucursal.');
    return result.rows[0];
  }

  async createInvoice(branchId:string,orderId:string,principal:AuthPrincipal,input:SupplierInvoiceCreateDto,correlationId:string){
    const subtotal=new Decimal(input.subtotalUsd);
    const tax=new Decimal(input.taxUsd ?? '0');
    const total=new Decimal(input.totalUsd);
    if(subtotal.plus(tax).toDecimalPlaces(2).eq(total)===false||!total.gt(0)) throw new BadRequestException('El total debe ser igual a subtotal más impuestos y ser mayor que cero.');
    const client=await this.pool.connect();
    try{
      await client.query('BEGIN');
      const order=await client.query<{supplier_id:string;status:string}>(`SELECT supplier_id,status FROM purchase_orders WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR SHARE`,[orderId,branchId,principal.organizationId]);
      if(!order.rows[0]) throw new NotFoundException('La orden no existe en esta sucursal.');
      if(!['partially_received','received'].includes(order.rows[0].status)) throw new ConflictException('Solo se factura una orden que ya tenga recepción física.');
      const receipt=await client.query('SELECT 1 FROM purchase_deliveries WHERE purchase_order_id=$1 AND status=$2 LIMIT 1',[orderId,'received']);
      if(!receipt.rowCount) throw new ConflictException('La orden aún no tiene entregas confirmadas.');
      const inserted=await client.query<{id:string}>(
        `INSERT INTO supplier_invoices(organization_id,purchase_order_id,supplier_id,invoice_number,subtotal_usd,tax_usd,total_usd,due_at,created_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
        [principal.organizationId,orderId,order.rows[0].supplier_id,input.invoiceNumber.trim(),subtotal.toFixed(2),tax.toFixed(2),total.toFixed(2),input.dueAt ?? null,principal.userId],
      );
      const invoiceId=inserted.rows[0]!.id;
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'supplier_invoice.create',entityType:'supplier_invoice',entityId:invoiceId,after:{purchaseOrderId:orderId,invoiceNumber:input.invoiceNumber.trim(),subtotalUsd:subtotal.toFixed(2),taxUsd:tax.toFixed(2),totalUsd:total.toFixed(2)}});
      await client.query('COMMIT');
      return {id:invoiceId,invoiceNumber:input.invoiceNumber.trim(),subtotalUsd:subtotal.toFixed(2),taxUsd:tax.toFixed(2),totalUsd:total.toFixed(2),paidUsd:'0.00',balanceUsd:total.toFixed(2),status:'open'};
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUnique(error)) throw new ConflictException('El número de factura ya está registrado para este proveedor.');throw error;}finally{client.release();}
  }

  async invoices(branchId:string,orderId:string,principal:AuthPrincipal){
    await this.purchaseOrder(orderId,branchId,principal);
    const result=await this.pool.query(
      `SELECT i.id,i.invoice_number AS "invoiceNumber",i.subtotal_usd AS "subtotalUsd",i.tax_usd AS "taxUsd",i.total_usd AS "totalUsd",
              i.due_at AS "dueAt",i.status,i.created_at AS "createdAt",
              COALESCE((SELECT sum(p.amount_usd) FROM supplier_invoice_payments p WHERE p.invoice_id=i.id),0)::text AS "paidUsd",
              COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'amountUsd',p.amount_usd,'paidAt',p.paid_at,'paymentMethod',p.payment_method,
                'externalReference',p.external_reference) ORDER BY p.paid_at DESC) FROM supplier_invoice_payments p WHERE p.invoice_id=i.id),'[]'::jsonb) AS payments
         FROM supplier_invoices i JOIN purchase_orders po ON po.id=i.purchase_order_id
        WHERE i.organization_id=$1 AND po.branch_id=$2 AND i.purchase_order_id=$3 ORDER BY i.created_at DESC`,[principal.organizationId,branchId,orderId]);
    return {data:result.rows};
  }

  async payInvoice(branchId:string,invoiceId:string,principal:AuthPrincipal,input:SupplierPaymentDto,correlationId:string){
    const normalized={amountUsd:new Decimal(input.amountUsd).toFixed(2),paidAt:input.paidAt,paymentMethod:input.paymentMethod,externalReference:clean(input.externalReference)};
    const requestHash=createHash('sha256').update(JSON.stringify(normalized)).digest('hex');
    const client=await this.pool.connect();
    try{
      await client.query('BEGIN');
      const prior=await client.query<{id:string;request_hash:string}>(`SELECT id,request_hash FROM supplier_invoice_payments WHERE organization_id=$1 AND command_id=$2`,[principal.organizationId,input.commandId]);
      if(prior.rows[0]){
        if(prior.rows[0].request_hash!==requestHash) throw new ConflictException('commandId ya fue usado para otro pago.');
        await client.query('COMMIT');
        return {id:prior.rows[0].id,idempotentReplay:true};
      }
      const found=await client.query<{total_usd:string;status:string;purchase_order_id:string;branch_id:string}>(
        `SELECT i.total_usd,i.status,i.purchase_order_id,o.branch_id FROM supplier_invoices i JOIN purchase_orders o ON o.id=i.purchase_order_id
          WHERE i.id=$1 AND i.organization_id=$2 AND o.branch_id=$3 FOR UPDATE OF i`,[invoiceId,principal.organizationId,branchId]);
      const invoice=found.rows[0];
      if(!invoice) throw new NotFoundException('La factura no existe.');
      if(!['open','partially_paid'].includes(invoice.status)) throw new ConflictException('La factura no admite pagos en su estado actual.');
      const paid=await client.query<{paid:string}>(`SELECT COALESCE(sum(amount_usd),0)::text AS paid FROM supplier_invoice_payments WHERE invoice_id=$1`,[invoiceId]);
      const balance=new Decimal(invoice.total_usd).minus(paid.rows[0]?.paid ?? '0');
      if(new Decimal(normalized.amountUsd).gt(balance)) throw new ConflictException('El pago supera el saldo pendiente de la factura.');
      const payment=await client.query<{id:string}>(
        `INSERT INTO supplier_invoice_payments(organization_id,invoice_id,amount_usd,paid_at,payment_method,external_reference,command_id,request_hash,recorded_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
        [principal.organizationId,invoiceId,normalized.amountUsd,normalized.paidAt,normalized.paymentMethod,normalized.externalReference ?? null,input.commandId,requestHash,principal.userId],
      );
      const remaining=balance.minus(normalized.amountUsd);
      const status=remaining.isZero()?'paid':'partially_paid';
      await client.query('UPDATE supplier_invoices SET status=$2 WHERE id=$1',[invoiceId,status]);
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action:'supplier_invoice.payment_recorded',entityType:'supplier_invoice_payment',entityId:payment.rows[0]!.id,after:{invoiceId,amountUsd:normalized.amountUsd,balanceAfterUsd:remaining.toFixed(2),paymentMethod:input.paymentMethod,externalReference:normalized.externalReference}});
      await client.query('COMMIT');
      return {id:payment.rows[0]!.id,invoiceId,amountUsd:normalized.amountUsd,paidUsd:new Decimal(paid.rows[0]?.paid ?? '0').plus(normalized.amountUsd).toFixed(2),balanceUsd:remaining.toFixed(2),status,idempotentReplay:false};
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);if(isUnique(error)) throw new ConflictException('La referencia externa o el commandId ya están registrados.');throw error;}finally{client.release();}
  }

  private async transition(branchId:string,orderId:string,principal:AuthPrincipal,input:PurchaseOrderDecisionDto,correlationId:string,from:string,to:string,action:string){
    const client=await this.pool.connect();
    try{
      await client.query('BEGIN');
      const found=await client.query<{status:string;version:number}>(`SELECT status,version FROM purchase_orders WHERE id=$1 AND branch_id=$2 AND organization_id=$3 FOR UPDATE`,[orderId,branchId,principal.organizationId]);
      const order=found.rows[0];
      if(!order) throw new NotFoundException('La orden no existe en esta sucursal.');
      if(order.status!==from||order.version!==input.expectedVersion) throw new ConflictException('La orden cambió o no admite esta transición.');
      const changed=await client.query('UPDATE purchase_orders SET status=$2,version=version+1,updated_at=now() WHERE id=$1 AND version=$3',[orderId,to,input.expectedVersion]);
      if(changed.rowCount!==1) throw new ConflictException('La orden cambió; vuelve a cargarla.');
      await this.audit.appendTransaction(client,{principal,branchId,correlationId,action,entityType:'purchase_order',entityId:orderId,before:{status:from,version:order.version},after:{status:to,version:order.version+1}});
      await client.query('COMMIT'); return this.purchaseOrder(orderId,branchId,principal);
    }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
  }

  private async assertActiveProduct(client: import('pg').PoolClient,organizationId:string,productId:string){
    const result=await client.query('SELECT 1 FROM fuel_products WHERE id=$1 AND organization_id=$2 AND status=$3',[productId,organizationId,'active']);
    if(!result.rowCount) throw new BadRequestException('Una oferta referencia un combustible inexistente o inactivo.');
  }
}

function clean(value:string|undefined):string|undefined { const result=value?.trim(); return result||undefined; }
function escapeLike(value:string):string { return value.replace(/[\\%_]/g,'\\$&'); }
function normalizeTaxId(value:string|undefined):string|null { const normalized=value?.normalize('NFKC').toUpperCase().replace(/[\s-]/g,''); return normalized||null; }
function isUnique(error:unknown):boolean { return !!error&&typeof error==='object'&&'code' in error&&(error as {code?:string}).code==='23505'; }
