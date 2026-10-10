import { Inject, Injectable } from '@nestjs/common';
import type { Pool, PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';

@Injectable()
export class OutboxStore {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async append(client: PoolClient, event: {
    eventType: string;
    aggregateType: string;
    aggregateID: string;
    payload: unknown;
  }): Promise<void> {
    await client.query(
      `INSERT INTO outbox_events(event_type,aggregate_type,aggregate_id,payload)
       VALUES ($1,$2,$3,$4::jsonb)`,
      [event.eventType, event.aggregateType, event.aggregateID, JSON.stringify(event.payload)],
    );
  }

  async claimBatch(limit: number, leaseSeconds = 60) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `UPDATE outbox_events SET dead_lettered_at=now(),locked_until=NULL,
           last_error=COALESCE(last_error,'Se agotaron los reintentos.')
          WHERE published_at IS NULL AND dead_lettered_at IS NULL AND attempts >= max_attempts
            AND (locked_until IS NULL OR locked_until < now())`,
      );
      const events = await client.query(
        `WITH ready AS (
           SELECT id FROM outbox_events
            WHERE published_at IS NULL AND dead_lettered_at IS NULL AND attempts < max_attempts AND available_at <= now()
              AND (locked_until IS NULL OR locked_until < now())
            ORDER BY occurred_at
            FOR UPDATE SKIP LOCKED
            LIMIT $1
         )
         UPDATE outbox_events event
            SET locked_until=now()+($2::text || ' seconds')::interval,
                attempts=event.attempts+1
           FROM ready WHERE event.id=ready.id
         RETURNING event.id,event.event_type,event.aggregate_type,event.aggregate_id,event.payload,event.attempts`,
        [Math.max(1, Math.min(100, Math.trunc(limit))), Math.max(5, Math.min(3600, Math.trunc(leaseSeconds)))],
      );
      await client.query('COMMIT');
      return events.rows;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async markPublished(eventID: string, claimedAttempt: number): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE outbox_events SET published_at=now(),locked_until=NULL
        WHERE id=$1 AND published_at IS NULL AND dead_lettered_at IS NULL AND attempts=$2`, [eventID, claimedAttempt],
    );
    return result.rowCount === 1;
  }

  async retry(eventID: string, claimedAttempt: number, errorMessage: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE outbox_events
          SET available_at=now() + make_interval(secs => LEAST(3600, power(2, LEAST(attempts,10))::integer)),
              locked_until=NULL,last_error=$2,
              dead_lettered_at=CASE WHEN attempts >= max_attempts THEN now() ELSE NULL END
        WHERE id=$1 AND published_at IS NULL AND attempts=$3`,
      [eventID, sanitizeError(errorMessage), claimedAttempt],
    );
    return result.rowCount === 1;
  }
}

function sanitizeError(value: string): string {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/-]+=*/gi, 'Bearer [REDACTED]')
    .replace(/(password|token|secret|authorization)=([^\s&]+)/gi, '$1=[REDACTED]')
    .slice(0, 1000);
}
