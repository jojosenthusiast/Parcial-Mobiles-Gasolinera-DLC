export function validateDatabaseEnvironment(values: Record<string, unknown>): { databaseUrl: string; sslMode: string; caFile: string };
export function databaseConnectionOptions(values: Record<string, unknown>): {
  connectionString: string;
  ssl: false | { rejectUnauthorized: true; ca?: string };
};
export function assertRestrictedDatabaseRole(role: {
  isSuperuser: boolean; bypassesRls: boolean; createsRoles: boolean;
  createsDatabases: boolean; createsSchemaObjects: boolean;
  canEditAudit: boolean; canEditMigrations: boolean;
} | undefined): void;
