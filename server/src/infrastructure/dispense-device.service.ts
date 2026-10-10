import { BadRequestException, ConflictException, Inject, Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'node:crypto';
import type { Pool } from 'pg';
import { selectDispenseAdapter } from '../../scripts/dispense-device-adapters.mjs';
import type { DeviceMode, DeviceObservation, DeviceSnapshot } from '../../scripts/dispense-device-adapters.mjs';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { PG_POOL } from '../database/database.module.js';
import { InfrastructureService } from './infrastructure.service.js';
import type { DeviceOperationDto } from './device-operation.dto.js';

interface Snapshot extends DeviceSnapshot {
  expectedVersion: number; startEventId: string; unknownEventId: string; finishEventId: string;
}
interface OperationRow {
  command_id: string; request_hash: string; adapter_mode: DeviceMode;
  scenario: Snapshot['scenario']; snapshot: Snapshot; outcome: DeviceObservation | null;
  state: 'prepared'|'observed'|'applied';
}

export const DEVICE_PG_POOL = Symbol('DEVICE_PG_POOL');

@Injectable()
export class DispenseDeviceService implements OnModuleDestroy {
  constructor(@Inject(PG_POOL) private readonly pool: Pool,
    @Inject(DEVICE_PG_POOL) private readonly lockPool: Pool,
    private readonly infrastructure: InfrastructureService, private readonly config: ConfigService) {}

  async onModuleDestroy(): Promise<void> { await this.lockPool.end(); }

  capabilities() {
    const adapter = this.adapter(this.config.get<string>('DISPENSE_ADAPTER_MODE') ?? 'manual');
    return { data: { mode: adapter.mode, physicalHardwareConnected: false,
      scenarios: adapter.mode === 'simulated' ? ['normal','timeout_after_completion','timeout_before_start'] : [],
      automaticReconciliation: adapter.mode === 'simulated' } };
  }

  private adapter(mode: string) {
    return selectDispenseAdapter(mode, this.config.get<string>('NODE_ENV') ?? 'development');
  }

  async history(branchId:string,authorizationId:string,principal:AuthPrincipal) {
    await this.infrastructure.dispenseDetail(authorizationId,branchId,principal);
    const rows=await this.pool.query(`SELECT command_id AS "commandId",operation,adapter_mode AS mode,scenario,state,outcome,
      requested_by AS "requestedBy",correlation_id AS "correlationId",created_at AS "createdAt",observed_at AS "observedAt",applied_at AS "appliedAt"
      FROM dispense_device_operations WHERE organization_id=$1 AND branch_id=$2 AND authorization_id=$3
      ORDER BY created_at DESC,id DESC LIMIT 20`,[principal.organizationId,branchId,authorizationId]);
    return {data:rows.rows};
  }

  async execute(operation: 'start'|'query', branchId: string, authorizationId: string,
    principal: AuthPrincipal, input: DeviceOperationDto, correlationId: string) {
    // Checks tenant and branch scope even on replay and on device status queries.
    await this.infrastructure.dispenseDetail(authorizationId,branchId,principal);
    if (operation === 'query' && input.scenario !== undefined) throw new BadRequestException('El escenario se fija al iniciar, no al consultar.');
    const requestHash = createHash('sha256').update(JSON.stringify({operation,branchId,authorizationId,
      expectedVersion:input.expectedVersion,scenario:input.scenario??null})).digest('hex');
    // Dedicated pool avoids starving the business pool while holding a session
    // lock. Concurrent device operations cannot occupy every business connection.
    const client = await this.lockPool.connect();
    let locked = false;
    try {
      // Session lock survives each committed intent/observation; no DB transaction
      // is left open while other business services post their own transactions.
      const lock = await client.query<{locked:boolean}>(
        'SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS locked', [`dlc-device:${authorizationId}`]);
      locked = lock.rows[0]?.locked ?? false;
      if (!locked) throw new ConflictException('Hay una consulta de equipo en curso. Reintenta con el mismo commandId.');
      const prior = await client.query<OperationRow>(
        'SELECT * FROM dispense_device_operations WHERE organization_id=$1 AND command_id=$2', [principal.organizationId,input.commandId]);
      let row = prior.rows[0];
      if (row && row.request_hash !== requestHash) throw new ConflictException('commandId ya fue utilizado para otra operación de equipo.');
      if (!row) {
        const current = (await this.infrastructure.dispenseDetail(authorizationId,branchId,principal)).data;
        if (current.version !== input.expectedVersion) throw new ConflictException('La autorización cambió; actualiza el detalle antes de consultar.');
        const started = await client.query<OperationRow>(
          "SELECT * FROM dispense_device_operations WHERE authorization_id=$1 AND organization_id=$2 AND branch_id=$3 AND operation='start'",
          [authorizationId,principal.organizationId,branchId]);
        if (operation === 'start' && started.rowCount) throw new ConflictException('El inicio ya fue registrado. Consulta el resultado; no generes otra autorización.');
        if (operation === 'query' && !started.rows[0]) throw new ConflictException('No hay un inicio de adaptador registrado para consultar.');
        if (operation === 'start' && current.status !== 'authorized') throw new ConflictException('Solo puede iniciarse una autorización vigente sin despacho.');
        if (operation === 'query' && ['completed','cancelled','expired'].includes(current.status)) throw new ConflictException('El despacho ya terminó. Consulta su detalle e historial.');
        const mode = started.rows[0]?.adapter_mode ?? (this.config.get<string>('DISPENSE_ADAPTER_MODE') ?? 'manual');
        const adapter = this.adapter(mode);
        const scenario = started.rows[0]?.scenario ?? input.scenario ?? 'normal';
        if (mode === 'manual' && scenario !== 'normal') throw new BadRequestException('Los escenarios de prueba solo se admiten en el simulador.');
        const snapshot: Snapshot = {
          authorizationId,nozzleId:current.nozzleId,reservedL:current.reservedL,scenario,
          startCommandId:started.rows[0]?.command_id ?? input.commandId,expectedVersion:input.expectedVersion,
          startEventId:derivedId(input.commandId,'start'),unknownEventId:derivedId(input.commandId,'unknown'),finishEventId:derivedId(input.commandId,'finish'),
        };
        const inserted = await client.query<OperationRow>(
          `INSERT INTO dispense_device_operations(organization_id,branch_id,authorization_id,command_id,request_hash,operation,adapter_mode,scenario,snapshot,requested_by,correlation_id)
           VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING *`,
          [principal.organizationId,branchId,authorizationId,input.commandId,requestHash,operation,adapter.mode,scenario,snapshot,principal.userId,correlationId]);
        row = inserted.rows[0]!;
      }
      if (row.state === 'applied') return this.response(branchId,authorizationId,principal,row,true);
      this.adapter(row.adapter_mode); // Also blocks pending simulated recovery in production.
      if (!row.outcome) {
        const adapter = this.adapter(row.adapter_mode);
        // Only manual/simulated adapters exist. Physical commands must use a
        // durable provider outbox plus query-by-original-ID, never this replay.
        const outcome = operation === 'start' ? await adapter.start(row.snapshot) : await adapter.query(row.snapshot);
        const observed = await client.query<OperationRow>(
          "UPDATE dispense_device_operations SET outcome=$3,state='observed',observed_at=now() WHERE organization_id=$1 AND command_id=$2 AND state='prepared' RETURNING *",
          [principal.organizationId,input.commandId,outcome]);
        row = observed.rows[0]!;
      }
      const snapshot = row.snapshot;
      const outcome = row.outcome!;
      if (operation === 'start' && ['started','timeout'].includes(outcome.status)) {
        await this.infrastructure.startDispense(branchId,authorizationId,principal,
          {commandId:snapshot.startEventId,expectedVersion:snapshot.expectedVersion},correlationId);
        if (outcome.status === 'timeout') {
          await this.infrastructure.markDispenseUnknown(branchId,authorizationId,principal,
            {commandId:snapshot.unknownEventId,expectedVersion:snapshot.expectedVersion+1,reason:'Timeout del simulador; consultar el resultado original antes de repetir.'},correlationId);
        }
      } else if (operation === 'query') {
        const current = (await this.infrastructure.dispenseDetail(authorizationId,branchId,principal)).data;
        if (!['completed','cancelled','expired'].includes(current.status)) {
          if (outcome.status === 'completed') {
            await this.infrastructure.completeDispense(branchId,authorizationId,principal,
              {commandId:snapshot.finishEventId,expectedVersion:snapshot.expectedVersion,quantity:outcome.measuredL!,unit:'liter',documentReference:outcome.evidenceReference!},correlationId);
          } else if (outcome.status === 'no_flow') {
            await this.infrastructure.reconcileDispenseNoFlow(branchId,authorizationId,principal,
              {commandId:snapshot.finishEventId,expectedVersion:snapshot.expectedVersion,evidenceReference:outcome.evidenceReference!,reason:'Simulador: consulta confirma que no hubo flujo.'},correlationId);
          }
        }
      }
      // If posting crashes, the observed outcome and stable event IDs survive;
      // retry resumes the same business command and cannot create a second sale.
      await client.query("UPDATE dispense_device_operations SET state='applied',applied_at=now() WHERE organization_id=$1 AND command_id=$2",[principal.organizationId,input.commandId]);
      row.state = 'applied';
      return this.response(branchId,authorizationId,principal,row,false);
    } finally {
      let discard = false;
      if (locked) {
        try { await client.query('SELECT pg_advisory_unlock(hashtextextended($1,0))',[`dlc-device:${authorizationId}`]); }
        catch { discard = true; }
      }
      client.release(discard);
    }
  }

  private async response(branchId:string,authorizationId:string,principal:AuthPrincipal,row:OperationRow,replay:boolean) {
    return { ...(await this.infrastructure.dispenseDetail(authorizationId,branchId,principal)),
      device: { mode:row.adapter_mode, scenario:row.scenario, outcome:row.outcome, state:row.state,
        commandId:row.command_id,idempotentReplay:replay,physicalHardwareConnected:false } };
  }
}

function derivedId(commandId:string,step:string):string {
  const hex=createHash('sha256').update(`${commandId}:${step}`).digest('hex');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-5${hex.slice(13,16)}-a${hex.slice(17,20)}-${hex.slice(20,32)}`;
}
