# HANDOFF (2026-10-10)

## Hecho y verificado
- API en Render: https://dlc-gasolineras-api-qa.onrender.com (Supabase, migraciones hasta 0110). Panel: https://dlc-gasolineras-web-qa.onrender.com
- Filtro por país, modo oscuro, corte vespertino 14–22, login corregido, QA con 2 sucursales activas (QA-SV-01, QA-GT-01).
- Rediseño fase 1 (logo, iconos sin emojis, ScopeBar, configuración, drawers, asistente de sucursal por pasos) en web y Flutter Operaciones; Clientes completo.
- Pruebas: server 237 unit / 100 contract; web 62; Flutter ops 158, clientes 38, dlc_api 8.
- Skills de diseño instaladas en `.claude/skills/` (ignoradas por git). Guía: `PRODUCT.md`, `DESIGN.md`.
- Último commit subido: a46c4db. TODO lo posterior está SIN commit (web fase 1, Flutter ops/clientes, `GET /roles`, flag de entrega manual, worker inline de reportes, tests).

## En curso (agentes, al cierre de esta sesión)
- Web fase 2 (Reportes→Analítica, Cortes guiados, Incidencias, Compras, Cuentas/activación).
- Operaciones fase 2 (corte con recepciones y pérdidas, navegación por rol, despacho, alertas, usuarios).
- Cuentas de trabajadores (despachador, cajero, tienda, cliente) y auditoría real: scripts en `server/scripts/` y `AUDIT_RUNTIME.md` en el scratchpad. Si no terminaron, revisar `git status`.

## Auditoría real (AUDIT_RUNTIME.md en el scratchpad de Claude; P0 aún abiertos)
- Arreglados al cierre (sin commit): `POST /branches` 500 (parámetros sin tipo, branches.service.ts:35) y `dispense-authorizations/:id/complete` 500 (microsegundos de completed_at, infrastructure.service.ts:601).
- Abiertos: reembolso 500 con rol de mínimo privilegio (payments.service.ts:110 FOR UPDATE); reportes 500 con rol runtime (reports.service.ts:122 falta GRANT UPDATE en report_runs; puede ser latente si Render usa rol con privilegios); reporte operational_assets viola un CHECK de report_type (migración nueva 0111); semilla crea el corte de la mañana inutilizable si corre después de las 06:00; PDF pierde tildes/ñ, XLSX guarda números como texto.
- Test de contrato `operational asset inventory stays connected...` falla (busca `operational_assets` en web/public/app.js, que se está reescribiendo): ajustar el test a los módulos nuevos del panel.
- Cuentas de trabajadores: `cd server; node scripts/generate-qa-workers.mjs`; pegar `scripts/sql/qa-workers.generated.sql` en Supabase; `node scripts/create-qa-customer.mjs`.

## Pendiente
1. Cuando los agentes terminen: correr todas las pruebas, commit y push a `main` (Render redepliega solo).
2. Render API: variables `ALLOW_MANUAL_ACCOUNT_DELIVERY=true` y `REPORTS_WORKER_INLINE=true`.
3. Pegar en Supabase el SQL de cuentas de trabajadores y correr `server/scripts/create-qa-customer.mjs`; credenciales en archivos `server/.qa-*-credentials.local.txt` (no se suben).
4. Recompilar APK: `flutter build apk --debug --dart-define=DLC_API_BASE_URL=https://dlc-gasolineras-api-qa.onrender.com/api/v1` (Clientes además `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_AUTH_REDIRECT_URL=sv.com.dlc.dlc_customers://login-callback/`, `CUSTOMER_TERMS_VERSION=demo-v1`).
5. Backlog de la auditoría (`AUDIT_COVERAGE.md`): cobro de combustible en la app, bandeja de aprobaciones, premios/canje del cliente, selectores por nombre en Incidencias, diálogos restantes.
6. Traducir a SwiftUI usando como base lo que compila en `C:\Users\frenzied\Downloads\proyectosquecorrenenmac`; DLCGasolineras/ tiene fixes de modo oscuro sin compilar. Probar compilación con el flujo manual `iOS build` de GitHub Actions.
