import { ConflictException, Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';

export type IdempotencyDecision =
  | { kind: 'execute' }
  | { kind: 'replay'; status: number; body: unknown };

@Injectable()
export class IdempotencyStore {
  async reserve(client: PoolClient, scope: string, key: string, requestHash: string): Promise<IdempotencyDecision> {
    if (!/^[A-Za-z0-9._:-]{8,120}$/.test(key)) {
      throw new ConflictException({ code: 'IDEMPOTENCY_KEY_INVALID', message: 'La clave de operación no es válida.' });
    }
    await client.query(
      `DELETE FROM idempotency_records
        WHERE scope=$1 AND idempotency_key=$2 AND expires_at <= now()`, [scope, key],
    );
    const inserted = await client.query(
      `INSERT INTO idempotency_records(scope,idempotency_key,request_hash,expires_at)
       VALUES ($1,$2,$3,now() + interval '48 hours')
       ON CONFLICT (scope,idempotency_key) DO NOTHING RETURNING id`,
      [scope, key, requestHash],
    );
    if (inserted.rowCount === 1) return { kind: 'execute' };

    const existing = await client.query(
      `SELECT request_hash,state,response_status,response_body
         FROM idempotency_records
        WHERE scope=$1 AND idempotency_key=$2
        FOR UPDATE`, [scope, key],
    );
    const row = existing.rows[0];
    if (!row) throw new ConflictException({ code: 'IDEMPOTENCY_RETRY', message: 'Reintenta la operación con la misma clave.' });
    if (row.request_hash !== requestHash) {
      throw new ConflictException({ code: 'IDEMPOTENCY_KEY_REUSED', message: 'La clave ya se usó para otra operación.' });
    }
    if (row.state !== 'completed') {
      throw new ConflictException({ code: 'OPERATION_IN_PROGRESS', message: 'La operación todavía está en proceso.' });
    }
    return { kind: 'replay', status: row.response_status, body: row.response_body };
  }

  async complete(client: PoolClient, scope: string, key: string, status: number, body: unknown): Promise<void> {
    const result = await client.query(
      `UPDATE idempotency_records
          SET state='completed',response_status=$3,response_body=$4::jsonb
        WHERE scope=$1 AND idempotency_key=$2 AND state='processing'`,
      [scope, key, status, JSON.stringify(body)],
    );
    if (result.rowCount !== 1) throw new Error('No se pudo completar la clave de idempotencia.');
  }
}
