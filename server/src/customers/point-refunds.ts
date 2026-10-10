import { Body, ConflictException, Controller, ForbiddenException, Get, Inject, Injectable, NotFoundException, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import { IsIn, IsInt, IsString, IsUUID, Length, Max, Min } from 'class-validator';
import type { Request } from 'express';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import { RequirePermission } from '../authorization/permission.decorator.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
export class PointRefundRequestDto {
 @IsUUID() commandId!:string; @IsUUID() paymentId!:string;
 @IsInt() @Min(1) @Max(2000000000) points!:number;
 @IsString() @Length(8,500) reason!:string;
}
export class PointRefundDecisionDto {
 @IsUUID() commandId!:string; @IsUUID() requestId!:string;
 @IsIn(['approved','rejected']) decision!:'approved'|'rejected';
 @IsString() @Length(8,500) reason!:string;
}
@Injectable()
export class PointRefundsService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}
 private async scope(b:string,p:AuthPrincipal,permission:string){if(!(await this.auth.capabilities(p,b)).includes(permission))throw new ForbiddenException('Sin permiso para devolver puntos en esta sucursal.');}
 async list(b:string,sale:string,p:AuthPrincipal){
  await this.scope(b,p,'payment.read');
  const payments=await this.pool.query(`SELECT p.id,p.points,p.amount_usd AS "amountUsd",p.customer_id AS "customerId",
   COALESCE((SELECT sum(r.points) FROM customer_point_refund_requests r JOIN customer_point_refund_decisions d ON d.request_id=r.id WHERE r.payment_id=p.id AND d.decision='approved'),0) AS "returnedPoints"
   FROM customer_point_payments p WHERE p.sale_id=$1 AND p.branch_id=$2 AND p.organization_id=$3 ORDER BY p.created_at`,[sale,b,p.organizationId]);
  const requests=await this.pool.query(`SELECT r.id,r.payment_id AS "paymentId",r.points,r.reason,r.requested_by AS "requestedBy",d.decision,d.amount_usd AS "amountUsd"
   FROM customer_point_refund_requests r JOIN customer_point_payments p ON p.id=r.payment_id LEFT JOIN customer_point_refund_decisions d ON d.request_id=r.id
   WHERE p.sale_id=$1 AND p.branch_id=$2 AND p.organization_id=$3 ORDER BY r.created_at`,[sale,b,p.organizationId]);
  return {data:{payments:payments.rows,requests:requests.rows}};
 }
 async write(b:string,sale:string,p:AuthPrincipal,input:PointRefundRequestDto|PointRefundDecisionDto,correlation:string,decide:boolean){
  await this.scope(b,p,decide?'payment.refund':'sale.refund.request');
  const c=await this.pool.connect();
  try{
   await c.query('BEGIN');
   await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`point-refund-command:${p.organizationId}:${input.commandId}`]);
   const table=decide?'customer_point_refund_decisions':'customer_point_refund_requests';
   const old=await c.query(`SELECT * FROM ${table} WHERE organization_id=$1 AND command_id=$2`,[p.organizationId,input.commandId]);
   if(old.rows[0]){
    const row=old.rows[0],data=input as PointRefundDecisionDto;
    const same=decide?row.request_id===data.requestId&&row.decision===data.decision&&row.decided_by===p.userId
     :row.payment_id===(input as PointRefundRequestDto).paymentId&&BigInt(row.points)===BigInt((input as PointRefundRequestDto).points)&&row.requested_by===p.userId;
    if(!same||row.branch_id!==b||row.reason!==input.reason.trim())throw new ConflictException('Comando de devolución usado con otros datos.');
    // Scope the referenced sale even on replay.
    const scope=await c.query(decide?`SELECT 1 FROM customer_point_refund_requests r JOIN customer_point_payments p ON p.id=r.payment_id WHERE r.id=$1 AND p.sale_id=$2`:`SELECT 1 FROM customer_point_payments WHERE id=$1 AND sale_id=$2`,[decide?row.request_id:row.payment_id,sale]);
    if(!scope.rowCount)throw new NotFoundException('Devolución fuera de venta.');
    await c.query('COMMIT');return {data:row,idempotentReplay:true};
   }
   const reference=decide?(input as PointRefundDecisionDto).requestId:(input as PointRefundRequestDto).paymentId;
   const scope=await c.query(decide?`SELECT 1 FROM customer_point_refund_requests r JOIN customer_point_payments p ON p.id=r.payment_id WHERE r.id=$1 AND p.sale_id=$2 AND p.branch_id=$3 AND p.organization_id=$4`:`SELECT 1 FROM customer_point_payments WHERE id=$1 AND sale_id=$2 AND branch_id=$3 AND organization_id=$4`,[reference,sale,b,p.organizationId]);
   if(!scope.rowCount)throw new NotFoundException('Pago o solicitud fuera de venta.');
   const result=decide?await c.query(`INSERT INTO customer_point_refund_decisions(organization_id,branch_id,request_id,decision,decided_by,command_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *`,[p.organizationId,b,reference,(input as PointRefundDecisionDto).decision,p.userId,input.commandId,input.reason.trim()])
    :await c.query(`INSERT INTO customer_point_refund_requests(organization_id,branch_id,payment_id,points,requested_by,command_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *`,[p.organizationId,b,reference,(input as PointRefundRequestDto).points,p.userId,input.commandId,input.reason.trim()]);
   await this.audit.appendTransaction(c,{principal:p,branchId:b,correlationId:correlation,action:decide?'customer.points.refund.decided':'customer.points.refund.requested',entityType:table,entityId:result.rows[0].id,after:result.rows[0]});
   await c.query('COMMIT');return {data:result.rows[0],idempotentReplay:false};
  }catch(e){await c.query('ROLLBACK').catch(()=>undefined);if(['23514','23505'].includes((e as {code?:string}).code??''))throw new ConflictException('Devolución excedida, ya decidida o sin aprobación independiente.');throw e;}finally{c.release();}
 }
}
@Controller('branches/:branchId/sales/:saleId/point-refunds')
export class PointRefundsController {
 constructor(private readonly refunds:PointRefundsService){}
 @RequirePermission('payment.read') @Get()
 list(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('saleId',new ParseUUIDPipe()) sale:string,@Req() r:Request){return this.refunds.list(b,sale,r.principal!);}
 @RequirePermission('sale.refund.request') @Post('requests')
 request(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('saleId',new ParseUUIDPipe()) sale:string,@Body() body:PointRefundRequestDto,@Req() r:Request){return this.refunds.write(b,sale,r.principal!,body,r.header('x-request-id')!,false);}
 @RequirePermission('payment.refund') @Post('decisions')
 decide(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('saleId',new ParseUUIDPipe()) sale:string,@Body() body:PointRefundDecisionDto,@Req() r:Request){return this.refunds.write(b,sale,r.principal!,body,r.header('x-request-id')!,true);}
}
