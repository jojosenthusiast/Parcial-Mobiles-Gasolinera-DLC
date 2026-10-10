# API y worker

NestJS 12 + TypeScript ESM; PostgreSQL 18.6 local / Supabase 17.11; consultas parametrizadas con `pg`. Requiere Node 24.15 o posterior dentro de la línea 24. Para Windows, el procedimiento recomendado es el stack Docker Compose documentado en [infra](../infra/README.md), que crea y usa una cuenta PostgreSQL local limitada. No apuntes a datos reales desde `seed:demo`.

La imagen Compose solo publica PostgreSQL en loopback. Ejecutar `docker compose -f infra/compose.yaml up -d` desde la raíz del proyecto después de crear `.env`; luego `pnpm install`, `pnpm db:migrate`, `pnpm db:seed:demo`, `pnpm --filter @dlc/server start:dev`. API base `http://localhost:4000/api/v1`; OpenAPI local en `/api/docs`.

## Trabajos de exportación

Las exportaciones CSV, XLSX y PDF se encolan en `background_jobs`. Ejecuta el consumidor como un proceso separado junto a la API: `pnpm --filter @dlc/server build` y luego `pnpm --filter @dlc/server start:worker`. El worker consume los trabajos en cola, aplica reintentos con espera creciente y genera cada archivo desde la instantánea inmutable del reporte. La API informa filas procesadas, total y porcentaje, y permite cancelar una exportación propia mientras siga en cola o en proceso; el worker actualiza el avance cada 250 filas y descarta resultados si el trabajo fue cancelado. La API vuelve a validar los permisos al solicitar, consultar y descargar; el trabajador también verifica sesión vigente y permiso antes de generar. Los archivos quedan privados en PostgreSQL y expiran a los siete días. Mantén al menos un consumidor activo en despliegue y supervisa su reinicio y logs. La creación de la instantánea limita cada reporte a 10 000 filas para acotar memoria y tamaño del archivo. La exportación asíncrona evita bloquear la interfaz mientras serializa CSV, XLSX o PDF, pero no elimina ese límite de consulta; reduce periodo o filtros si el reporte lo supera.

## Panel web

Inicia la API en el puerto 4000 y el cliente web con `WEB_API_BASE_URL=http://localhost:4000/api/v1`, una `WEB_SESSION_KEY` aleatoria (32 bytes o más) y `npm --prefix web start`. El panel escucha en el puerto 4173. En producción debe publicarse detrás de HTTPS y su proxy debe usar la misma URL de origen; no expongas el API de administración a Internet sin una puerta de enlace y controles de red.

## Límites HTTP y proxy

Las solicitudes JSON tienen un máximo de 2 MiB; la importación de legado permite hasta 36 MiB (texto de 32 MiB más sobre JSON). En producción limita también conexiones concurrentes, tasa por IP y tiempo de lectura en el proxy de borde. Configura `TRUST_PROXY_HOPS` solo con la cantidad exacta de proxies controlados delante del API (0–5); no confíes en encabezados `X-Forwarded-*` enviados directamente por clientes.

## PostgreSQL administrado en la nube

La app móvil y el panel web se conectan únicamente a la API HTTPS. La API abre la conexión PostgreSQL desde el servidor mediante `DATABASE_URL`; nunca se incluye esa URL, usuario o contraseña en la app móvil. En producción configura `DATABASE_URL` como secreto del servicio API y `DATABASE_SSL_MODE=verify-full`. El servidor valida el certificado TLS y rechaza el arranque si producción intenta desactivar esa verificación. Para desarrollo local, `server/.env.example` usa `DATABASE_SSL_MODE=disable` porque Compose publica PostgreSQL solo en loopback.

Antes de apuntar a datos de operación, crea una instancia separada de staging, aplica las migraciones desde cero, valida backups/restauración, red privada o allowlist, rotación del secreto y límites de conexiones. Supabase sole/DLC ya tiene el esquema de desarrollo aplicado y probado por SQL; no se deben correr `seed:demo` ni pruebas destructivas contra una base real.

La conexión TLS de los servicios y la compilación limpia requieren ejecución en un host con acceso al registro npm y PostgreSQL. Ver [configuración y evidencia de Supabase](../docs/SUPABASE_DLC.md) y [procedimiento de backup/restauración](../scripts/README.md).
