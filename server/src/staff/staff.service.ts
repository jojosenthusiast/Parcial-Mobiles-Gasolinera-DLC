import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import type { AcknowledgeHandoverDto, AttendanceDto, CancelShiftDto, ChangeEmployeeDto, CreateEmployeeDto, HandoverDto, ScheduleShiftDto, StaffingBlockDto, UpdateEmployeeProfileDto } from './staff.dto.js';

@Injectable()
export class StaffService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}
 private async access(branch:string,p:AuthPrincipal,permission:string,allowSetup=false){
  const caps=await this.auth.capabilities(p,branch);
  if(!caps.includes(permission))throw new ForbiddenException('Permiso de personal insuficiente.');
  const b=await this.pool.query(`SELECT id FROM branches WHERE id=$1 AND organization_id=$2
    AND (status='active' OR ($3::boolean AND status IN ('draft','configured')))`
   ,[branch,p.organizationId,allowSetup]);
  if(!b.rows[0])throw new NotFoundException('Sucursal fuera de tu ámbito.');
  return caps;
 }
 private async write<T extends object>(branch:string,p:AuthPrincipal,correlation:string,action:string,type:string,
  fn:(client:PoolClient)=>Promise<{id:string;data:T;before?:unknown;replay?:boolean}>){
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');const value=await fn(client);
   if(!value.replay)await this.audit.appendTransaction(client,{principal:p,branchId:branch,correlationId:correlation,action,entityType:type,entityId:value.id,before:value.before,after:value.data});
   await client.query('COMMIT');return {data:{...value.data,idempotentReplay:!!value.replay}};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);
   if(['23514','23505','40001','55000'].includes((error as {code?:string}).code??''))throw new ConflictException('Estado, horario o responsable en conflicto.');
   if((error as {code?:string}).code==='23503')throw new NotFoundException('Referencia fuera de la sucursal.');
   throw error;
  }finally{client.release();}
 }
 async create(branch:string,p:AuthPrincipal,input:CreateEmployeeDto,correlation:string){
  await this.access(branch,p,'staff.manage',true);
  const code=short(input.employeeCode,40),name=short(input.legalName,160),position=short(input.positionTitle,100);
  if(!/^[A-Za-z0-9._-]{2,40}$/.test(code)||name.length<2||position.length<2
   ||input.contactEmail!==undefined&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.contactEmail))
   throw new BadRequestException('Ficha de empleado no válida.');
  return this.write(branch,p,correlation,'staff.employee.created','employee',async client=>{
   const r=await client.query<{id:string}>(`INSERT INTO employees(organization_id,branch_id,employee_code,legal_name,position_title,contact_email,contact_phone,hired_on)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
    [p.organizationId,branch,code,name,position,input.contactEmail?.trim().toLowerCase()??null,input.contactPhone??null,input.hiredOn??null]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,employeeCode:code,status:'active'}};
  });
 }
 async updateProfile(branch:string,id:string,p:AuthPrincipal,input:UpdateEmployeeProfileDto,correlation:string){
  const caps=await this.access(branch,p,'staff.manage',true);
  if(!uuid(id)||!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1)
   throw new BadRequestException('Ficha o versión del colaborador no válida.');
  const name=short(input.legalName,160),position=short(input.positionTitle,100);
  const email=input.contactEmail===undefined?undefined:input.contactEmail===null?null:input.contactEmail.trim().normalize('NFKC').toLowerCase();
  const phone=input.contactPhone===undefined?undefined:input.contactPhone===null?null:input.contactPhone.trim();
  const hiredOn=input.hiredOn===undefined?undefined:input.hiredOn;
  if(name.length<2||position.length<2||email!==undefined&&email!==null&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
   ||phone!==undefined&&phone!==null&&phone!==''&&!/^\+?[0-9 ()-]{7,24}$/.test(phone)
   ||hiredOn!==undefined&&hiredOn!==null&&!date(hiredOn))throw new BadRequestException('Los datos del colaborador no son válidos.');
  if((email!==undefined||phone!==undefined)&&!caps.includes('staff.private.read'))
   throw new ForbiddenException('Se requiere permiso staff.private.read para cambiar el contacto.');
  return this.write(branch,p,correlation,'staff.employee.profile_updated','employee',async client=>{
   const old=await client.query<{legalName:string;positionTitle:string;status:string;version:number}>(
    `SELECT legal_name AS "legalName",position_title AS "positionTitle",status,version FROM employees
      WHERE id=$1 AND organization_id=$2 AND branch_id=$3 FOR UPDATE`,[id,p.organizationId,branch]);
   const current=old.rows[0];if(!current)throw new NotFoundException('El colaborador no existe en esta sucursal.');
   if(current.version!==input.expectedVersion)throw new ConflictException('La ficha cambió; recarga el detalle antes de guardar.');
   if(current.status==='terminated')throw new ConflictException('No se puede editar la ficha de un colaborador terminado.');
   const result=await client.query<{version:number}>(`UPDATE employees SET legal_name=$4,position_title=$5,
     contact_email=CASE WHEN $6::boolean THEN $7 ELSE contact_email END,
     contact_phone=CASE WHEN $8::boolean THEN $9 ELSE contact_phone END,
     hired_on=CASE WHEN $10::boolean THEN $11::date ELSE hired_on END,
     version=version+1,updated_at=clock_timestamp()
     WHERE id=$1 AND organization_id=$2 AND branch_id=$3 AND version=$12 RETURNING version`,
    [id,p.organizationId,branch,name,position,email!==undefined,email??null,phone!==undefined,phone??null,hiredOn!==undefined,hiredOn??null,input.expectedVersion]);
   if(!result.rows[0])throw new ConflictException('La ficha cambió; recarga el detalle antes de guardar.');
   const fields=['legalName','positionTitle',...(email!==undefined?['contactEmail']:[]),...(phone!==undefined?['contactPhone']:[]),...(hiredOn!==undefined?['hiredOn']:[])];
   return {id,data:{id,version:result.rows[0]!.version,updatedFields:fields},before:{version:current.version,fields}};
  });
 }
 async employees(branch:string,p:AuthPrincipal,query:{q?:string;status?:string;cursor?:string;limit?:number}){
  const caps=await this.access(branch,p,'staff.read',true);const {limit,cursor}=page(query);
  const q=query.q?.trim()??'';if(q.length>100||query.status!==undefined&&!['active','leave','suspended','terminated'].includes(query.status))
   throw new BadRequestException('Filtro no válido.');
  const r=await this.pool.query<{id:string}>(`SELECT e.id,e.employee_code AS "employeeCode",e.legal_name AS "legalName",e.position_title AS "positionTitle",
   e.status,e.version,e.hired_on AS "hiredOn",e.ended_on AS "endedOn",
   CASE WHEN $7 THEN e.contact_email END AS "contactEmail",CASE WHEN $7 THEN e.contact_phone END AS "contactPhone",
   u.id AS "userId",u.status AS "userStatus" FROM employees e LEFT JOIN users u ON u.employee_id=e.id AND u.organization_id=e.organization_id
   WHERE e.organization_id=$1 AND e.branch_id=$2 AND ($3::text='' OR e.employee_code ILIKE '%'||$3||'%' OR e.legal_name ILIKE '%'||$3||'%')
    AND ($4::text IS NULL OR e.status=$4) AND ($5::uuid IS NULL OR e.id>$5)
   ORDER BY e.id LIMIT $6`,[p.organizationId,branch,q,query.status??null,cursor,limit+1,caps.includes('staff.private.read')]);
  const data=r.rows.slice(0,limit);return {data,meta:{limit,nextCursor:r.rows.length>limit?data.at(-1)!.id:null}};
 }
 async change(branch:string,id:string,p:AuthPrincipal,input:ChangeEmployeeDto,correlation:string){
  await this.access(branch,p,'staff.manage');if(!uuid(id)||!uuid(input.commandId)||!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1
   ||!['active','leave','suspended','terminated'].includes(input.status)||!date(input.effectiveOn))
   throw new BadRequestException('Transición de empleado no válida.');
  const reason=short(input.reason,500);if(reason.length<10)throw new BadRequestException('Explica el cambio.');
  const targetBranch=input.branchId===undefined?branch:input.branchId;
  if(targetBranch!==null&&!uuid(targetBranch))throw new BadRequestException('Sucursal destino no válida.');
  if(targetBranch!==null&&targetBranch!==branch)await this.access(targetBranch,p,'staff.manage');
  const hash=digest({v:1,id,version:input.expectedVersion,status:input.status,targetBranch,effectiveOn:input.effectiveOn,reason});
  const localToday=new Intl.DateTimeFormat('en-CA',{timeZone:'America/El_Salvador',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  if(input.effectiveOn>localToday)return this.write(branch,p,correlation,'staff.employee.change_scheduled','employee_planned_change',async client=>{
   const old=await client.query('SELECT id FROM employee_planned_changes WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT schedule_employee_change($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) AS id',
    [p.organizationId,p.userId,id,input.expectedVersion,input.status,targetBranch,input.effectiveOn,reason,input.commandId,hash,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,employeeId:id,status:'scheduled',effectiveOn:input.effectiveOn},replay:!!old.rows[0]};
  });
  return this.write(branch,p,correlation,'staff.employee.changed','employee',async client=>{
   const old=await client.query('SELECT id FROM employee_lifecycle_events WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT change_employee_lifecycle($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) AS id',
    [p.organizationId,p.userId,id,input.expectedVersion,input.status,targetBranch,input.effectiveOn,reason,input.commandId,hash,correlation]);
   return {id,data:{id,changeId:r.rows[0]!.id,status:input.status},replay:!!old.rows[0]};
  });
 }
 async applyPlan(branch:string,planId:string,p:AuthPrincipal,commandId:string,correlation:string){
  await this.access(branch,p,'staff.manage');
  if(!uuid(planId)||!uuid(commandId))throw new BadRequestException('Cambio programado no válido.');
  const plan=await this.pool.query<{employee_id:string;next_branch_id:string|null;branch_id:string;applied_event_id:string|null}>(`SELECT plan.employee_id,plan.next_branch_id,e.branch_id,plan.applied_event_id
    FROM employee_planned_changes plan JOIN employees e ON e.id=plan.employee_id
    WHERE plan.id=$1 AND plan.organization_id=$2 AND e.branch_id=$3`,[planId,p.organizationId,branch]);
  if(!plan.rows[0])throw new NotFoundException('Cambio programado fuera de sucursal.');
  if(plan.rows[0].next_branch_id&&plan.rows[0].next_branch_id!==branch)await this.access(plan.rows[0].next_branch_id,p,'staff.manage');
  const hash=digest({v:1,branch,planId});
  return this.write(branch,p,correlation,'staff.employee.change_applied','employee',async client=>{
   const old=plan.rows[0]!.applied_event_id;
   const r=await client.query<{id:string}>('SELECT apply_employee_change($1,$2,$3,$4,$5,$6) AS id',
    [p.organizationId,p.userId,planId,commandId,hash,correlation]);
   return {id:plan.rows[0]!.employee_id,data:{id:plan.rows[0]!.employee_id,eventId:r.rows[0]!.id,planId},replay:!!old};
  });
 }
 async plans(branch:string,p:AuthPrincipal){
  await this.access(branch,p,'staff.read');
  const r=await this.pool.query(`SELECT plan.id,plan.employee_id AS "employeeId",plan.expected_version AS "expectedVersion",
   plan.next_status AS "nextStatus",plan.next_branch_id AS "nextBranchId",plan.effective_on AS "effectiveOn",
   plan.reason,plan.scheduled_at AS "scheduledAt",plan.applied_at AS "appliedAt"
   FROM employee_planned_changes plan JOIN employees e ON e.id=plan.employee_id
   WHERE plan.organization_id=$1 AND e.branch_id=$2 ORDER BY plan.effective_on,plan.id LIMIT 200`,[p.organizationId,branch]);
  return {data:r.rows};
 }
 async schedule(branch:string,p:AuthPrincipal,input:ScheduleShiftDto,correlation:string){
  await this.access(branch,p,'staff.shifts.plan');
  if(!uuid(input.commandId)||!uuid(input.employeeId)||!dateTime(input.startsAt)||!dateTime(input.endsAt)
   ||Date.parse(input.endsAt)<=Date.parse(input.startsAt)||Date.parse(input.endsAt)-Date.parse(input.startsAt)>86400000)
   throw new BadRequestException('Horario no válido.');
  if(input.position==='cashier'?!uuid(input.cashRegisterId):input.position==='forecourt'?!uuid(input.dispenserId):
   input.cashRegisterId!==undefined||input.dispenserId!==undefined)throw new BadRequestException('Asigna el recurso correspondiente al puesto.');
  const hash=digest({v:1,branch,employeeId:input.employeeId,position:input.position,cashRegisterId:input.cashRegisterId??null,
   dispenserId:input.dispenserId??null,startsAt:input.startsAt,endsAt:input.endsAt});
  return this.write<{id:string;employeeId?:string;startsAt?:string;endsAt?:string}>(branch,p,correlation,'staff.shift.scheduled','employee_work_shift',async client=>{
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[ 'shift-command:'+p.organizationId+':'+input.commandId ]);
   const old=await client.query<{id:string;request_hash:string;scheduled_by:string}>('SELECT id,request_hash,scheduled_by FROM employee_work_shifts WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   if(old.rows[0]){
    if(old.rows[0].request_hash!==hash||old.rows[0].scheduled_by!==p.userId)throw new ConflictException('El comando ya tiene otro turno.');
    return {id:old.rows[0].id,data:{id:old.rows[0].id},replay:true};
   }
   const r=await client.query<{id:string}>(`INSERT INTO employee_work_shifts(organization_id,branch_id,employee_id,position,cash_register_id,dispenser_id,starts_at,ends_at,command_id,request_hash,scheduled_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,
    [p.organizationId,branch,input.employeeId,input.position,input.cashRegisterId??null,input.dispenserId??null,input.startsAt,input.endsAt,input.commandId,hash,p.userId,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,employeeId:input.employeeId,startsAt:input.startsAt,endsAt:input.endsAt}};
  });
 }
 async shifts(branch:string,p:AuthPrincipal,query:{from?:string;to?:string}){
  await this.access(branch,p,'staff.read',true);
  const from=query.from??new Date(Date.now()-86400000).toISOString(),to=query.to??new Date(Date.now()+7*86400000).toISOString();
  if(!dateTime(from)||!dateTime(to)||Date.parse(to)<=Date.parse(from)||Date.parse(to)-Date.parse(from)>31*86400000)
   throw new BadRequestException('Periodo no válido.');
  const r=await this.pool.query(`SELECT s.id,s.employee_id AS "employeeId",e.legal_name AS "employeeName",s.position,
   s.cash_register_id AS "cashRegisterId",s.dispenser_id AS "dispenserId",s.starts_at AS "startsAt",s.ends_at AS "endsAt",
   s.status,a.clocked_in_at AS "clockedInAt",a.clocked_out_at AS "clockedOutAt",a.attendance_state AS "attendanceState"
   FROM employee_work_shifts s JOIN employees e ON e.id=s.employee_id
   LEFT JOIN employee_shift_attendance a ON a.shift_id=s.id
   WHERE s.organization_id=$1 AND s.branch_id=$2 AND s.starts_at<$4 AND s.ends_at>$3 ORDER BY s.starts_at,s.id`,
   [p.organizationId,branch,from,to]);
  return {data:r.rows};
 }
 async cancel(branch:string,id:string,p:AuthPrincipal,input:CancelShiftDto,correlation:string){
  await this.access(branch,p,'staff.shifts.plan');if(!uuid(id)||!uuid(input.commandId))throw new BadRequestException('Turno no válido.');
  const reason=short(input.reason,500);if(reason.length<10)throw new BadRequestException('Explica la cancelación.');
  const hash=digest({v:1,branch,id,reason});
  return this.write(branch,p,correlation,'staff.shift.cancelled','employee_work_shift',async client=>{
   const old=await client.query('SELECT shift_id FROM employee_shift_cancellations WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT cancel_employee_shift($1,$2,$3,$4,$5,$6,$7,$8) AS id',
    [p.organizationId,branch,p.userId,id,reason,input.commandId,hash,correlation]);
   return {id,data:{id:r.rows[0]!.id,status:'cancelled'},replay:!!old.rows[0]};
  });
 }
 async attendance(branch:string,id:string,p:AuthPrincipal,input:AttendanceDto,correlation:string){
  const permission=input.kind==='correction'?'staff.attendance.correct':'staff.attendance.record';
  await this.access(branch,p,permission);
  if(!uuid(id)||!uuid(input.commandId)||!dateTime(input.occurredAt)||!['clock_in','clock_out','correction'].includes(input.kind)
   ||(input.kind==='correction')!==!!input.correctsEventId||input.kind==='correction'&&!input.reason)
   throw new BadRequestException('Marcación no válida.');
  const reason=input.reason===undefined?null:short(input.reason,500);
  const hash=digest({v:1,branch,id,kind:input.kind,occurredAt:input.occurredAt,correctsEventId:input.correctsEventId??null,reason});
  return this.write(branch,p,correlation,'staff.attendance.'+input.kind,'employee_attendance_event',async client=>{
   const old=await client.query('SELECT id FROM employee_attendance_events WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT record_employee_attendance($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) AS id',
    [p.organizationId,branch,p.userId,id,input.kind,input.occurredAt,input.correctsEventId??null,reason,input.commandId,hash,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,shiftId:id,kind:input.kind},replay:!!old.rows[0]};
  });
 }
 async handover(branch:string,id:string,p:AuthPrincipal,input:HandoverDto,correlation:string){
  await this.access(branch,p,'staff.handover');
  if(!uuid(id)||!uuid(input.commandId)||!uuid(input.incomingShiftId)||!Array.isArray(input.pendingItems)||input.pendingItems.length>30
   ||input.pendingItems.some(x=>typeof x!=='object'||x===null||typeof (x as {text?:unknown}).text!=='string'||((x as {text:string}).text.length)>500)
   ||(input.cashSessionId===undefined)!==(input.observedCashUsd===undefined))
   throw new BadRequestException('Relevo incompleto.');
  const note=short(input.equipmentNote,500);
  const hash=digest({v:1,branch,id,incomingShiftId:input.incomingShiftId,pendingItems:input.pendingItems,note,cashSessionId:input.cashSessionId??null,cash:input.observedCashUsd??null});
  return this.write<{id:string;outgoingShiftId?:string;incomingShiftId?:string}>(branch,p,correlation,'staff.handover.created','employee_shift_handover',async client=>{
   await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['handover:'+p.organizationId+':'+input.commandId]);
   const old=await client.query<{id:string;request_hash:string;handed_by:string}>('SELECT id,request_hash,handed_by FROM employee_shift_handovers WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   if(old.rows[0]){if(old.rows[0].request_hash!==hash||old.rows[0].handed_by!==p.userId)throw new ConflictException('Relevo duplicado distinto.');return {id:old.rows[0].id,data:{id:old.rows[0].id},replay:true};}
   const r=await client.query<{id:string}>(`INSERT INTO employee_shift_handovers(organization_id,branch_id,outgoing_shift_id,incoming_shift_id,pending_items,equipment_note,cash_session_id,observed_cash_usd,command_id,request_hash,handed_by,correlation_id)
    VALUES($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,
    [p.organizationId,branch,id,input.incomingShiftId,JSON.stringify(input.pendingItems),note,input.cashSessionId??null,input.observedCashUsd??null,input.commandId,hash,p.userId,correlation]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,outgoingShiftId:id,incomingShiftId:input.incomingShiftId}};
  });
 }
 async acknowledge(branch:string,id:string,p:AuthPrincipal,input:AcknowledgeHandoverDto,correlation:string){
  await this.access(branch,p,'staff.handover');if(!uuid(id)||!uuid(input.commandId))throw new BadRequestException('Relevo no válido.');
  const note=short(input.note,500),hash=digest({v:1,branch,id,note});
  return this.write(branch,p,correlation,'staff.handover.acknowledged','employee_shift_handover',async client=>{
   const old=await client.query<{handover_id:string;request_hash:string;received_by:string}>('SELECT handover_id,request_hash,received_by FROM employee_handover_acknowledgments WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   if(old.rows[0]){if(old.rows[0].request_hash!==hash||old.rows[0].received_by!==p.userId||old.rows[0].handover_id!==id)throw new ConflictException('Confirmación duplicada distinta.');return {id,data:{id,acknowledged:true},replay:true};}
   await client.query(`INSERT INTO employee_handover_acknowledgments(handover_id,organization_id,branch_id,note,command_id,request_hash,received_by,correlation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[id,p.organizationId,branch,note,input.commandId,hash,p.userId,correlation]);
   return {id,data:{id,acknowledged:true}};
  });
 }
 async block(branch:string,dispenser:string,p:AuthPrincipal,input:StaffingBlockDto,correlation:string){
  await this.access(branch,p,'staff.staffing.block');
  if(!uuid(dispenser)||!uuid(input.commandId)||typeof input.blocked!=='boolean')throw new BadRequestException('Estado de pista no válido.');
  const reason=short(input.reason,500);if(reason.length<10)throw new BadRequestException('Explica la disponibilidad.');
  const hash=digest({v:1,branch,dispenser,blocked:input.blocked,reason});
  return this.write(branch,p,correlation,input.blocked?'staff.pump_blocked':'staff.pump_reopened','asset_block',async client=>{
   const old=await client.query('SELECT block_id FROM staffing_asset_blocks WHERE organization_id=$1 AND command_id=$2 UNION ALL SELECT block_id FROM staffing_block_resolutions WHERE organization_id=$1 AND command_id=$2',[p.organizationId,input.commandId]);
   const r=await client.query<{id:string}>('SELECT set_staffing_block($1,$2,$3,$4,$5,$6,$7,$8) AS id',
    [p.organizationId,branch,p.userId,dispenser,input.blocked,reason,input.commandId,hash]);
   return {id:r.rows[0]!.id,data:{id:r.rows[0]!.id,blocked:input.blocked},replay:!!old.rows[0]};
  });
 }
}
function uuid(v:unknown):v is string{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);}
function date(v:unknown):v is string{return typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&!Number.isNaN(Date.parse(v))&&new Date(v).toISOString().slice(0,10)===v;}
function dateTime(v:unknown):v is string{return typeof v==='string'&&!Number.isNaN(Date.parse(v));}
function short(v:unknown,max:number){if(typeof v!=='string'||!v.trim()||v.trim().length>max)throw new BadRequestException('Texto no válido.');return v.trim();}
function digest(v:unknown){return createHash('sha256').update(JSON.stringify(v)).digest('hex');}
function page(q:{cursor?:string;limit?:number}){const limit=q.limit??25,cursor=q.cursor??null;if(!Number.isInteger(limit)||limit<1||limit>100||cursor!==null&&!uuid(cursor))throw new BadRequestException('Paginación inválida.');return {limit,cursor};}
