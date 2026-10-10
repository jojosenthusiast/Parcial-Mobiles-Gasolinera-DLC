# Operación y verificaciones

## Backup cifrado

Necesita `pg_dump` compatible con PostgreSQL 17/18 y Node 24.15 o posterior.

```powershell
$env:DATABASE_URL = "postgresql://usuario:contraseña@host:5432/base"
$env:DATABASE_SSL_MODE = "verify-full"
$env:BACKUP_ENCRYPTION_KEY = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
pnpm backup:encrypted
```

Guarda la clave fuera del equipo y del directorio de backups; sin ella no se puede recuperar el archivo. `pg_dump` transmite el formato custom directamente a AES-256-GCM; el archivo lleva versión, IV y tag de autenticación. La clave/URL no se imprimen. Por defecto los archivos van a `backups/`, permiso local restrictivo, y se borran los `.dump.enc` mayores a 30 días. Configura `BACKUP_DIRECTORY` y `BACKUP_RETENTION_DAYS` según el plan de recuperación. Copia los backups cifrados a almacenamiento independiente; una carpeta local no constituye un backup frente a pérdida del equipo.

## Restauración de verificación

Restaura siempre en una base vacía y aislada. El script compara el host y nombre de base de `DATABASE_URL` con el destino y bloquea si coinciden; no ejecuta `--clean` ni borra objetos existentes.

```powershell
$env:RESTORE_DATABASE_URL = "postgresql://usuario:contraseña@host-aislado:5432/dlc_restore"
pnpm restore:check .\backups\dlc-2026-10-08T12-00-00-000Z.dump.enc
```

La verificación descifra a un archivo temporal con acceso restringido, restaura dentro de una transacción y comprueba que saldos de combustible concuerden con el ledger, lotes de tienda no tengan stock negativo/superior a recibido, auditoría conserve referencias válidas y snapshots de reportes mantengan su cantidad de filas. El directorio temporal se elimina al salir. Se requiere `pg_restore` y `psql`; define `PG_RESTORE_BIN`/`PSQL_BIN` si no están en `PATH`.

Los objetivos RPO/RTO no se declaran hasta medir duración, tamaño y restauración con volúmenes realistas. La copia y restauración contra un servidor administrado de Supabase todavía requiere ejecución operativa en el entorno del proyecto.

## Verificación estática disponible

- `node scripts/verify-plan.mjs`: OpenAPI válido, migraciones numeradas y configuración ESM.
- `node scripts/check-typescript-syntax.mjs <archivos .ts>`: análisis de sintaxis con el soporte TypeScript de Node 24; no reemplaza `tsc`.
- `pnpm test:web`: contrato de cliente web.
- `pnpm --filter @dlc/server test:unit`: compila y ejecuta el conjunto del servidor cuando las dependencias están instaladas.
