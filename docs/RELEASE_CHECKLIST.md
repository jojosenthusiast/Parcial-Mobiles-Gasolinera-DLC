# Lista de validación y entrega

## Fuente incluida

El paquete contiene el proyecto SwiftUI/Xcode, panel web, API, contrato OpenAPI, 104 migraciones, configuración Compose, scripts de backup/restauración y ejemplos de entorno. El adaptador de despacho local opera en modo manual. La carga de datos sintéticos es explícita y solo debe ejecutarse en una base local desechable.

Generar un ZIP sin dependencias ni secretos:

```powershell
node scripts/verify-release.mjs
node scripts/verify-acceptance-matrix.mjs
node scripts/package-release.mjs --output .\artifacts\DLCGasolineras_Laboratorio22_source.zip
```

El primer comando falla si detecta archivos `.env` locales, claves privadas, respaldos, compilados o una estructura incompleta. El segundo incluye `.env.example`, excluye configuraciones personales y no afirma que el proyecto haya sido compilado.

## Verificación web y API en Windows

Con Node 24.15+ y pnpm 11.25:

```powershell
pnpm install --frozen-lockfile
node scripts/verify-plan.mjs
node scripts/verify-release.mjs
node --check web/server.mjs
node --check web/public/app.js
pnpm test:web
pnpm --filter @dlc/server test:contract
pnpm --filter @dlc/server test:unit
```

`test:unit` compila el servidor antes de cargar `server/dist`; ejecutar `node --test server/test/*.test.mjs` directamente sin `pnpm build` deja fuera ese prerrequisito. La instalación local requiere acceso al registry npm para dependencias que no vengan ya en caché.

Para ejecutar el stack en Docker Desktop, copia `.env.example` a `.env`, genera secretos diferentes para cada variable y sigue `infra/README.md`. Arranca con `docker compose -f infra/compose.yaml up --build`. La API se ejecuta después de migrar una base local nueva; no conectes el seed a Supabase ni a datos reales.

## Verificación de iOS

En una Mac con Xcode, abre `DLCGasolineras.xcodeproj`, ejecuta los tests disponibles, compila el scheme compartido para un simulador iOS instalado y recorre login, permisos, tablero, cortes, inventario, alta de sucursal y modo offline. Guarda capturas de esa misma compilación junto con la versión/commit y el dispositivo/simulador. No reutilices capturas de prototipos anteriores como evidencia del build final.

## Estado de evidencia conocido

| Área | Estado observado en este entorno | Evidencia faltante |
| --- | --- | --- |
| Web | Sintaxis y suite de contrato aprobadas; errores muestran código y referencia de correlación | Sesión autenticada, navegador real, responsive y lector de pantalla |
| API | Build, typecheck, lint, unitarias, contratos e integración HTTP 3/3 con PostgreSQL 16.15 y rol restringido aprobados | Recorridos autenticados con datos QA; crear login de servicio en Supabase y configurar el secreto de despliegue |
| Migraciones | OpenAPI y 83 archivos numerados; migraciones limpias y repetición verificadas en PostgreSQL 16.15; 0082/0083 aplicadas en Supabase | Repetir en la versión objetivo de Compose y con la cuenta de migración del entorno QA |
| Exportes | CSV/XLSX/PDF, snapshot por lotes y retención implementados | Datos operativos voluminosos, permisos revocados y exportes por HTTP |
| Backup/restore | Backup cifrado y restore aislado verificados con `pg_dump`/`pg_restore` 16.15 | Repetir contra servicio QA con adjuntos/datos y medir RPO/RTO |
| iOS | Código SwiftUI y contratos presentes; copia de fuente del proyecto dentro del ZIP validado | Build/test de Xcode y recorrido de simulador en Mac |
| Integraciones | Adaptadores manuales/simulados documentados | Surtidor, terminal, sensores y facturación con fabricante/credenciales |
| Alertas | Reglas iniciales versionadas en `infra/monitoring/dlc-alerts.yml` | `promtool`, scrape privado autenticado y receptor de alertas |
| Supabase | 83 migraciones, 135 tablas `public` con RLS, 0 funciones `public` ejecutables por roles cliente; asesor de seguridad sin hallazgos | Crear credencial login restringida para la API (hoy solo existe `dlc_api_runtime` NOLOGIN); una sesión con privilegios de `supabase_admin` debe quitar EXECUTE por defecto en `public`; asesor de rendimiento INFO lista 327 FK sin índice y 33 índices no usados sin carga representativa |

## Criterio de liberación

Este ZIP es una entrega de fuente para validación, no una declaración de release aprobado. La versión solo se presenta como aceptada después de completar los gates anteriores, registrar comandos/exit codes en `docs/evidence/E24.md` y comparar capturas, documentación, PDF académico y Figma con la misma versión del código.

## Revalidación de máquina 2026-10-09

El último resultado local está en `docs/QA_CIERRE_MAQUINA_2026-10-09.md`. Se aplicaron 104 migraciones y corrieron 42 SQL smokes con PostgreSQL 18.6 efímero; servidor 208 unit + 89 contracts, 3 HTTP básicos con API local/rol runtime, web 13/13, Flutter Node 5/5 y Dart 5/5; typecheck/build/lint/analyze pasan. El empaquetador excluye la caché `%SystemDrive%` creada por Windows. La carpeta de artefactos del workspace identifica los APK canónicos mediante su manifiesto y hashes; los APK no se incluyen dentro del ZIP fuente.

QA conectado/autenticado, Supabase, navegador visual, dispositivo/emulador, permisos de cámara física, Mac/Xcode, aceptación legal, proveedores/hardware y reglas comerciales siguen pendientes. Compilación y smokes locales no equivalen a producción aprobada.
