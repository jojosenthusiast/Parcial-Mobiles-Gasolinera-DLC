# Versiones y compatibilidad E02

Fijadas el 4 de octubre de 2026; no usar `latest`. Runtime medido: Node 24.19.0 y pnpm 11.25.0. NestJS 12 requiere el piso de Node 20.19/22.12 según sus notas oficiales, y su línea v12 publica paquetes ESM; por eso el backend declara ESM y usa `NodeNext` con sufijo `.js` en imports locales. Node 24.19 satisface ese piso. PostgreSQL 18.6 es el parche publicado por el proyecto PostgreSQL el 13 de agosto de 2026. La imagen oficial 18 usa `/var/lib/postgresql` como punto de montaje persistente, cambio que ya refleja Compose.

La persistencia central usa PostgreSQL tanto en desarrollo como en despliegue; iOS/web solo hablan con la API. En producción, `DATABASE_SSL_MODE=verify-full` fuerza TLS con validación de certificado y `DATABASE_URL` se guarda como secreto del servidor. La URL no acepta parámetros TLS, para evitar que contradigan la política explícita. El 5 de octubre de 2026 se eligió Supabase por instrucción del usuario y se provisionó el esquema en el proyecto DLC (sole), PostgreSQL 17.11. Compose conserva PostgreSQL 18 para desarrollo local. La base remota está validada por SQL; el despliegue de la API, TLS del proceso y la restauración siguen pendientes. Ver docs/SUPABASE_DLC.md para la configuración y evidencia.

Dependencias fijadas exactamente en `server/package.json`: Nest common/core/platform-express 12.1.2, config 12.0.1, Swagger 12.0.2, TypeScript 6.0.3, pg 8.23.1, decimal.js 10.6.0, class-validator 0.14.3, class-transformer 0.5.1, rxjs 7.8.2 y reflect-metadata 0.2.2. Tipos: `@types/node` 24.12.2, `@types/pg` 8.23.1, `@types/express` 5.0.6. Lint: ESLint 9.39.4 y typescript-eslint 8.70.0. Estas versiones se deben resolver y validar mediante `pnpm-lock.yaml` antes de considerarlas reproducibles.

No se generó `pnpm-lock.yaml`: el acceso desde este entorno a `registry.npmjs.org` falló con `EPERM`. Tampoco se pudo verificar la resolución de peer dependencies. No se incluyeron hashes de tarballs que no se descargaron. Ejecutar `pnpm install --frozen-lockfile` no será posible hasta generar el lockfile en una máquina con acceso al registro; crear un lockfile manual sería fingir una resolución que no ocurrió.

Fuentes oficiales consultadas:

- Node.js releases: https://nodejs.org/en/about/previous-releases
- Node.js 24: https://nodejs.org/en/blog/migrations/v22-to-v24
- NestJS 12 ESM/Node compatibility: https://docs.nestjs.com/migration-guide
- NestJS 12 first steps: https://docs.nestjs.com/first-steps
- NestJS v12.1.2 releases: https://github.com/nestjs/nest/releases
- PostgreSQL 18.6 release notes: https://www.postgresql.org/docs/release/18.6/
- Imagen oficial PostgreSQL en Docker: https://hub.docker.com/_/postgres
- npm metadata for pinned versions: https://www.npmjs.com/package/%40nestjs/core ; https://www.npmjs.com/package/pg ; https://www.npmjs.com/package/decimal.js
