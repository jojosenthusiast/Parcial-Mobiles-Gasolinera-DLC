# Preparación del tenant QA (DLC)

Crea la organización QA, dos usuarios y dos sucursales borrador en la base remota (Supabase). La API no puede hacerlo: su rol de ejecución no tiene DDL ni inserta organizaciones.

## Quién y en qué orden
1. Quien tenga el repositorio: `cd server && node scripts/generate-qa-bootstrap.mjs` (usa el `argon2` de `server/node_modules`). Genera:
   - `server/scripts/sql/qa-setup.generated.sql` (contiene hashes; ignorado por git, no lo compartas por chat).
   - `server/.qa-credentials.local.txt` (contraseñas en texto plano; ignorado por git).
2. Un administrador abre el SQL editor de Supabase como `postgres`, pega el contenido completo de `qa-setup.generated.sql` y lo ejecuta una sola vez. Es una transacción única: aplica la migración 0109, registra su checksum en `schema_migrations` y crea el tenant. Es idempotente (se puede repetir; nunca cambia la contraseña de un usuario existente).
3. La última consulta devuelve el resumen esperado: 1 organización, 2 roles, 211 filas de permisos, 2 usuarios, 2 asignaciones, 2 sucursales, ledger_0109 = 1.
4. Después `node scripts/migrate.mjs` ya no tiene nada pendiente (el checksum coincide). No cambies los saltos de línea de `0109_branch_country.sql` (CRLF) o el checksum dejará de coincidir.

## Credenciales
Abre `server/.qa-credentials.local.txt`. Contiene el correo y la contraseña de:
- Gerente general (`qa.gerente.general@dlc-qa.example`): alcance de red, los 112 permisos.
- Gerente de sucursal (`qa.gerente.sucursal@dlc-qa.example`): solo `QA-SV-01`, 99 permisos (sin administración de red, usuarios, activación ni impuestos).
Sucursales: `QA-SV-01` (SV, occidental) y `QA-GT-01` (GT, otra zona, America/Guatemala), ambas en `draft`; el asistente de alta completa tanques y bombas. El panel de red (`/metrics/network/dashboard`) solo cuenta sucursales `active`, así que `countries` aparece vacío hasta activar al menos una de cada país.

## Clientes
En `server/.env` configura `CUSTOMER_ORGANIZATION_ID=00000000-0000-4000-8000-0000000000a1` y reinicia la API.

## Rotar contraseñas
`node scripts/generate-qa-bootstrap.mjs --rotate` crea nuevas contraseñas, actualiza el archivo de credenciales (deja `.bak` con las anteriores; bórralo) y genera `qa-rotate-passwords.generated.sql`; el administrador lo ejecuta. Revoca las sesiones activas.

## Eliminar el tenant QA
- Suave (conserva historial): suspender usuarios y archivar sucursales (comandos en la cabecera de `qa-remove.sql`).
- Total e irreversible: el administrador ejecuta `server/scripts/sql/qa-remove.sql`. Borra la organización, sus filas y su auditoría. Falla con la lista de tablas pendientes si ya hay datos operativos; en ese caso usa la ruta suave. No revierte la migración 0109.
