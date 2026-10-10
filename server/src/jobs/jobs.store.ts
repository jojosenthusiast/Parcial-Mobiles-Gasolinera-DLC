import { Injectable } from '@nestjs/common';
import type { Pool, PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { Inject } from '@nestjs/common';

@Injectable()
export class JobsStore {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async enqueue(client: PoolClient, jobType: string, dedupeKey: string, payload: unknown): Promise<void> {
    await client.query(
      `INSERT INTO background_jobs(job_type,dedupe_key,payload)
       VALUES ($1,$2,$3::jsonb)
       ON CONFLICT (job_type,dedupe_key) DO NOTHING`,
      [jobType, dedupeKey, JSON.stringify(payload)],
    );
  }

  async claimBatch(limit: number, leaseSeconds = 60) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `UPDATE background_jobs
            SET state='dead',locked_until=NULL,last_error=COALESCE(last_error,'Se agotaron los reintentos.')
          WHERE state='running' AND locked_until < now() AND attempts >= max_attempts`,
      );
      const claimed = await client.query(
        `WITH ready AS (
           SELECT id FROM background_jobs
            WHERE ((state='queued' AND available_at <= now())
                OR (state='running' AND locked_until < now()))
              AND attempts < max_attempts
            ORDER BY available_at,created_at
            FOR UPDATE SKIP LOCKED
            LIMIT $1
         )
         UPDATE background_jobs job
            SET state='running',attempts=job.attempts+1,
                locked_until=now()+($2::text || ' seconds')::interval
           FROM ready WHERE job.id=ready.id
         RETURNING job.id,job.job_type,job.dedupe_key,job.payload,job.attempts,job.max_attempts`,
        [Math.max(1, Math.min(100, Math.trunc(limit))), Math.max(5, Math.min(3600, Math.trunc(leaseSeconds)))],
      );
      await client.query('COMMIT');
      return claimed.rows;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async complete(jobID: string, claimedAttempt: number): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE background_jobs SET state='succeeded',completed_at=now(),locked_until=NULL
        WHERE id=$1 AND state='running' AND attempts=$2`, [jobID, claimedAttempt],
    );
    return result.rowCount === 1;
  }

  async fail(jobID: string, claimedAttempt: number, errorMessage: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE background_jobs
          SET state=CASE WHEN attempts < max_attempts THEN 'queued' ELSE 'dead' END,
              available_at=now() + make_interval(secs => LEAST(3600, power(2, LEAST(attempts,10))::integer)),
              locked_until=NULL,last_error=$2
        WHERE id=$1 AND state='running' AND attempts=$3`,
      [jobID, sanitizeError(errorMessage), claimedAttempt],
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
