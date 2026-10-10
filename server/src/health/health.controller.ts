import { Controller, Get, Inject, ServiceUnavailableException } from '@nestjs/common';
import { Public } from '../auth/public.decorator.js';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  @Get('live')
  @Public()
  @ApiOperation({ summary: 'Proceso de API activo; no implica que la base esté lista.' })
  live() {
    return { status: 'ok', service: 'dlc-api', timestamp: new Date().toISOString() };
  }

  @Get('ready')
  @Public()
  @ApiOperation({ summary: 'API lista cuando responde PostgreSQL.' })
  async ready() {
    try {
      await this.pool.query('SELECT 1');
      return { status: 'ready', database: 'reachable', timestamp: new Date().toISOString() };
    } catch {
      throw new ServiceUnavailableException({
        status: 'not_ready',
        code: 'DATABASE_UNAVAILABLE',
        message: 'La base de datos no está disponible.',
      });
    }
  }
}
