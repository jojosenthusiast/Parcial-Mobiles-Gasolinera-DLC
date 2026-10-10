import { Global, Inject, Injectable, Module, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';
import { assertRestrictedDatabaseRole, databaseConnectionOptions } from '../../scripts/database-connection.mjs';

export const PG_POOL = Symbol('PG_POOL');

@Injectable()
class PgShutdown implements OnModuleDestroy, OnModuleInit {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly config: ConfigService) {}

  async onModuleInit(): Promise<void> {
    if (this.config.get<string>('NODE_ENV') !== 'production') return;
    const result = await this.pool.query<{
      isSuperuser: boolean; bypassesRls: boolean; createsRoles: boolean;
      createsDatabases: boolean; createsSchemaObjects: boolean;
      canEditAudit: boolean; canEditMigrations: boolean;
    }>(`SELECT rolsuper AS "isSuperuser", rolbypassrls AS "bypassesRls",
        rolcreaterole AS "createsRoles", rolcreatedb AS "createsDatabases",
        has_schema_privilege(current_user,'public','CREATE') AS "createsSchemaObjects",
        has_table_privilege(current_user,'public.audit_events','UPDATE,DELETE,TRUNCATE') AS "canEditAudit",
        has_table_privilege(current_user,'public.schema_migrations','INSERT,UPDATE,DELETE,TRUNCATE') AS "canEditMigrations"
        FROM pg_roles WHERE rolname=current_user`);
    assertRestrictedDatabaseRole(result.rows[0]);
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}

@Global()
@Module({
  providers: [{
    provide: PG_POOL,
    inject: [ConfigService],
    useFactory: (config: ConfigService) => new Pool({
      ...databaseConnectionOptions({
        DATABASE_URL: config.getOrThrow<string>('DATABASE_URL'),
        DATABASE_SSL_MODE: config.get<string>('DATABASE_SSL_MODE'),
        DATABASE_SSL_CA_FILE: config.get<string>('DATABASE_SSL_CA_FILE'),
        NODE_ENV: config.get<string>('NODE_ENV'),
      }),
      max: Number(config.get<string>('DATABASE_POOL_MAX') ?? 10),
      connectionTimeoutMillis: 5_000,
      keepAlive: true,
      application_name: 'dlc-gasolineras-api',
      statement_timeout: 10_000,
      idle_in_transaction_session_timeout: 10_000,
    }),
  }, PgShutdown],
  exports: [PG_POOL],
})
export class DatabaseModule {}
