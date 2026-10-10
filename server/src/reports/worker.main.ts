import { NestFactory } from '@nestjs/core';
import { AppModule } from '../app.module.js';
import { ReportsWorker } from './reports.worker.js';

const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn', 'log'] });
const worker = app.get(ReportsWorker);
let stopping = false;
process.once('SIGINT', () => { stopping = true; });
process.once('SIGTERM', () => { stopping = true; });
try {
  while (!stopping) {
    try {
      const count = await worker.runOnce();
      if (count === 0) await new Promise((resolve) => setTimeout(resolve, 1000));
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 3000));
    }
  }
} finally {
  await app.close();
}
