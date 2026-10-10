import { Module } from '@nestjs/common';
import { JobsStore } from './jobs.store.js';
import { OutboxStore } from './outbox.store.js';

@Module({ providers: [JobsStore, OutboxStore], exports: [JobsStore, OutboxStore] })
export class JobsModule {}
