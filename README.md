# DLC Gasolineras

Sistema de gestión de franquicia de gasolineras. Dos perfiles (Gerente General y Gerente de Sucursal), 6 bombas por sucursal, 3 combustibles (Súper, Regular, Diésel), dos cortes diarios, tanques con estado óptimo/medio/crítico y consolidado filtrable por sucursal o país.

## Estructura

| Carpeta | Contenido |
|---|---|
| `DLCGasolineras/`, `DLCGasolineras.xcodeproj` | App iOS en SwiftUI (MVVM). Incluye modo **Demo local** sin servidor |
| `flutter/apps/dlc_operations` | App de Operaciones (gerentes y personal), Android |
| `flutter/apps/dlc_customers` | App de Clientes (puntos, QR), Android |
| `flutter/packages/dlc_api` | Cliente HTTP compartido por las apps Flutter |
| `server/` | API NestJS + migraciones PostgreSQL (`server/migrations`) |
| `web/` | Panel web (gerencia) |
| `contracts/` | Contrato OpenAPI |
| `infra/` | Docker Compose local |

Las apps y el panel **no hablan con la base directamente**: todo pasa por la API (`/api/v1`), que usa PostgreSQL en Supabase.

## Ejecutar en local

Requiere Node 24 y pnpm 11.

```powershell
pnpm install
copy server\.env.example server\.env   # completa DATABASE_URL, SUPABASE_*, AUTH_RATE_LIMIT_KEY
pnpm build
node --env-file=server/.env server/dist/main.js          # API en :4000
$env:WEB_API_BASE_URL="http://127.0.0.1:4000/api/v1"; $env:WEB_SESSION_KEY="<32+ bytes aleatorios>"
node web/server.mjs                                      # panel en :4173
```

## Pruebas

```powershell
pnpm typecheck; pnpm lint; pnpm test:unit; pnpm test:contract; pnpm test:web
cd flutter/apps/dlc_operations; flutter analyze; flutter test
cd flutter/apps/dlc_customers;  flutter analyze; flutter test
```

## Apps Flutter

```powershell
cd flutter/apps/dlc_operations
flutter build apk --debug --dart-define=DLC_API_BASE_URL=https://<tu-api>/api/v1
cd ../dlc_customers
flutter build apk --debug --dart-define=DLC_API_BASE_URL=https://<tu-api>/api/v1 `
  --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_PUBLISHABLE_KEY=<clave-publica> `
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=sv.com.dlc.dlc_customers://login-callback/ `
  --dart-define=CUSTOMER_TERMS_VERSION=demo-v1
```

## Despliegue de la API

`server/Dockerfile` (contexto: raíz del repositorio). En Render: servicio Docker, `Dockerfile Path = server/Dockerfile`, `Root Directory` vacío, health check `/api/v1/health/live`. Variables mínimas: `NODE_ENV`, `DATABASE_URL`, `DATABASE_SSL_MODE=verify-full`, `DATABASE_SSL_CA_FILE=/app/server/certs/supabase-prod-ca-2021.crt`, `AUTH_RATE_LIMIT_KEY`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `CUSTOMER_ORGANIZATION_ID`, `CUSTOMER_TERMS_VERSION`, `TRUST_PROXY_HOPS=1`.

## Datos de QA

`server/scripts/sql/README-qa-setup.md` y `README-qa-seed.md` describen el SQL de arranque (organización, usuarios, sucursales) y el script que activa las sucursales por API.

## Compilar la app iOS sin Mac

El flujo `iOS build` de GitHub Actions (`.github/workflows/ios-build.yml`, manual) compila el proyecto Xcode en un runner macOS.
