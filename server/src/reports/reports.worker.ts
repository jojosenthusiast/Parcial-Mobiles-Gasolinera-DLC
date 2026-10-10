import { Injectable, Logger } from '@nestjs/common';
import { JobsStore } from '../jobs/jobs.store.js';
import { ReportsService } from './reports.service.js';

@Injectable()
export class ReportsWorker {
  private readonly logger = new Logger(ReportsWorker.name);
  private lastCleanup = 0;
  constructor(private readonly jobs: JobsStore, private readonly reports: ReportsService) {}

  async runOnce(): Promise<number> {
    if (Date.now() - this.lastCleanup > 15 * 60 * 1000) {
      await this.reports.cleanupExpiredExports();
      this.lastCleanup = Date.now();
    }
    const batch = await this.jobs.claimBatch(5, 300);
    for (const job of batch) {
      try {
        if (job.job_type !== 'report.export.generate' || typeof job.payload?.exportId !== 'string') {
          const updated = await this.jobs.fail(job.id, job.attempts, 'Tipo o carga de trabajo no reconocidos.');
          if (!updated) this.logger.warn(`Se venció el lease del trabajo: ${job.id}`);
          continue;
        }
        await this.reports.processExportJob(job.payload.exportId, job.attempts);
        await this.jobs.complete(job.id, job.attempts);
      } catch {
        if (job.attempts >= job.max_attempts && typeof job.payload?.exportId === 'string') {
          await this.reports.failExportJob(job.payload.exportId, 'No se pudo generar el archivo. Comprueba tus permisos e inténtalo de nuevo.');
        }
        await this.jobs.fail(job.id, job.attempts, 'No se pudo procesar la exportación del reporte.');
        this.logger.warn(`Falló un trabajo de exportación ${job.id} en intento ${job.attempts}.`);
      }
    }
    return batch.length;
  }
}
