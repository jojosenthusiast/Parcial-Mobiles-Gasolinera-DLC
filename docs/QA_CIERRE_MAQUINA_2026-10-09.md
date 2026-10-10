# Cierre de QA local — 9 de octubre de 2026

## Alcance y resultado

Esta es la evidencia más reciente de la copia aislada `work/DLCGasolineras_Laboratorio22`. No se modificaron las dos carpetas originales del Escritorio ni se usaron datos, cuentas o servicios de producción. La carpeta de trabajo no es un checkout Git; no ejecutar `git add` desde ella.

La verificación detectó y corrigió fallos reales en triggers de puntos bajo `dlc_api_runtime`, además de endurecer el flujo de descarga contaminante y corregir detalles del paquete QA. La fuente pasa las suites locales disponibles. Esto **no** representa aceptación funcional completa ni preparación para producción: faltan recorridos autenticados conectados, revisión visual real y decisiones/reglas externas.

## Verificaciones ejecutadas

| Capa | Resultado observado |
|---|---|
| Node | 24.19.0, coincide con `.node-version` y el rango declarado del proyecto |
| TypeScript | `tsc --noEmit -p tsconfig.json`: PASS; `tsc -p tsconfig.build.json`: PASS |
| ESLint | `eslint src test scripts`: PASS |
| Backend | 208 pruebas unitarias PASS + 89 contratos PASS; 3/3 pruebas HTTP de integración PASS contra API local y PostgreSQL usando un login miembro del rol runtime restringido |
| Web | Sintaxis `node --check web/public/app.js`: PASS; 14/14 pruebas PASS |
| Contratos Flutter ejecutados con Node | 5/5 PASS; estos contratos no sustituyen pruebas Dart |
| Flutter/Dart | Flutter 3.47.5/Dart 3.13.4: análisis limpio en ambas apps; Operaciones 4/4 y Clientes 1/1 pruebas Dart PASS |
| Android | APK debug de ambas apps compilados. No instalados ni probados en dispositivo/emulador; QR físico no verificado |
| PostgreSQL | Cluster 18.6 efímero: 104/104 migraciones, 0001–0104, aplicadas en orden; 42/42 scripts SQL smoke PASS. El cluster fue desechable; no se conectó a QA externo |
| QA gates | `verify-plan`, `verify-acceptance-matrix` y `verify-release`: PASS |
| Integración HTTP | Health/live, readiness de PostgreSQL y 401 con request ID/correlation: 3/3 PASS. No se ejecutaron recorridos autenticados de negocio por falta de cuentas QA |
| Navegador | No se hizo recorrido visual autenticado ni evaluación de lector de pantalla/responsive |

Las pruebas SQL incluyen cash, ventas, inventario, compras, turnos, incidencias, mantenimiento, reportes, Supabase/RLS, puntos/refunds y la nueva regresión `contamination-fuel-mismatch-smoke.sql`. Los fixtures de esa regresión se revierten.

## Correcciones de esta continuación

1. El smoke de pago con puntos descubrió que `validate_customer_point_payment()` leía `sales` como rol runtime y fallaba por permisos. Los triggers de aprobación/devolución de puntos también hacían lecturas fuera de los grants del runtime. Se corrigieron con funciones de trigger `SECURITY DEFINER`, `search_path` fijo y `EXECUTE` revocado a roles cliente/API.
2. El mismo smoke descubrió campos omitidos y referencias de registro inválidas en el trigger que otorga puntos al pagar. Se corrigieron los snapshots de sucursal y el acceso condicional a `NEW.outcome`. `customer-points-payment-smoke.sql` pasa completo con mezcla efectivo/puntos, reembolso monetario parcial y devolución aprobada de puntos.
3. El flujo especializado de contaminación ahora rechaza producto entrante igual al combustible del tanque en API y PostgreSQL. La recepción del mismo combustible conserva el flujo normal de recepción. La regresión SQL confirma rechazo de misma gasolina y aceptación de diésel en tanque de gasolina.
4. La lista de contaminación expone tanque, combustibles, reportante, aprobaciones, responsables, importe, motivo, fecha, disposición y referencia/evidencia. La web desactiva el retiro antes de aprobar las pérdidas necesarias y explica la dependencia.
5. El empaquetador excluye el directorio de caché de Windows que apareció dentro de Flutter al ejecutar pruebas en esta máquina. El ZIP se inspecciona de nuevo para confirmar que no incluya `%SystemDrive%` ni archivos `.db` de caché.

Las migraciones 0099–0104 son correctivas y deben aplicarse en secuencia en cualquier QA futuro. No editar checksums de migraciones ya aplicadas en bases persistentes; este handoff solo verificó un esquema nuevo y desechable.

## APK canónicos

Los nombres con guion bajo son los builds QA que se documentan y deben instalarse:

| App | Archivo | SHA-256 |
|---|---|---|
| Operaciones | `artifacts/qa-2026-10-09/dlc_operations-qa-debug.apk` | `7556b6dfcfad0de7049e98cebc20b266acca60e4e9d4cf7e43b027b0df9f3943` |
| Clientes | `artifacts/qa-2026-10-09/dlc_customers-qa-debug.apk` | `5509aeb354569766df4557db0d3288839b284212ab939678c83739421c00728d` |

Hay copias antiguas con nombres `dlc-operations-debug-qa.apk` y `dlc-customers-debug-qa.apk`. La de Operaciones **no** es el build QR documentado; ambas copias con guion son versiones sustituidas. Se conservan para no borrar archivos del usuario, pero no deben instalarse. Ver `artifacts/qa-2026-10-09/ARTIFACTS.md` y `SHA256SUMS.txt`.

El paquete fuente QA contiene 711 archivos, CRC íntegro, las 104 migraciones y el scanner QR; el ZIP no contiene APK, `.db` de caché ni `%SystemDrive%`. Su SHA-256 se registra en `artifacts/qa-2026-10-09/SHA256SUMS.txt`.

## Pendientes de aceptación y desarrollo

| Pendiente | Qué impide cerrarlo aquí |
|---|---|
| Recorridos de API/DB por rol, dos usuarios, red incierta y concurrencia | Falta una API con PostgreSQL QA y cuentas/roles de prueba aislados; no existe `DLC_API_BASE_URL` |
| Login y flujos reales de Clientes | Requiere proyecto Supabase de QA, publishable key, correo/deep links configurados y usuarios de prueba |
| Prueba visual de web y lector de pantalla | Falta navegador/entorno autenticado accesible en esta corrida |
| Instalación, QR/cámara y UX en móvil | No hay dispositivo ni emulador conectado; el build solo valida compilación |
| Flutter Operaciones | Continúan tickets de paridad para tienda, crédito, servicios/gastos, algunas operaciones/inventario y reportes según `ESTADO_FLUTTER.json` |
| Premios y campañas financieras | La administración/fulfillment de premios y el efecto transaccional real de descuentos, cashback y multiplicadores no están cerrados |
| Reglas comerciales de puntos | Falta decidir expiración/restitución de puntos vencidos, saldo negativo y recuperación; no se inventaron reglas |
| Disposición y conciliación física | Falta validar el volumen medido contra evidencias y definir tolerancias; no se debe inferir cuánto producto puede recuperarse |
| Pagos, fiscalidad e instalaciones físicas | Requieren proveedor, reglas validadas, credenciales/sandbox y equipo real (terminal, surtidor, sensores); siguen fuera de la conexión local |
| Términos y privacidad | El texto necesita aprobación legal y versión de producción |
| Regreso a SwiftUI y QA iOS | Requiere Mac/Xcode, targets/scaffolds iOS completos, XCTest y recorridos en simulador/dispositivo |

Mantener `redemptionUsdPerPoint=0` fuera de una base desechable hasta que la política de devoluciones mixtas, puntos vencidos/saldo negativo, conciliación y QA conectado tengan aceptación formal. No declarar que el sistema está terminado, aprobado por usuarios o listo para producción por pasar compilación y pruebas locales.



## Verificación adicional posterior al cierre

Se endureció la autenticación de cuentas asociadas a empleados: login, refresh y token de acceso requieren un turno programado vigente, empleado activo y sucursal coincidente. Se compilaron los cambios, ESLint pasó en los archivos tocados y las pruebas unitarias del servidor pasaron 210/210; el total incluye 2 pruebas nuevas para el bloqueo fuera de turno. Esto es una prueba de servicio con dobles, no concurrencia ni autenticación integrada contra PostgreSQL. La sesión móvil se confirma por almacenamiento seguro en código; no se probó en teléfono.

Mailjet permanece pendiente: el navegador local no inició por un bloqueo del sandbox. No se configuró API key/secret, remitente o DNS, no se envió correo y aún hace falta la pantalla de activación. El detalle de credenciales requeridas y privacidad está en `docs/SEGURIDAD_SESIONES_CONCURRENCIA.md`.

Paquete fuente actualizado tras los cambios: `artifacts/DLCGasolineras_Laboratorio22_source.zip`; el checksum SHA-256 se entrega en el archivo `.sha256` junto al ZIP.


## Seguimiento: ticket interno, despacho y caja web

La revisión posterior agregó `GET /branches/{branchId}/sales/{saleId}/receipt.pdf` con PDF de recibo interno rotulado como no fiscal, conectado a Flutter y Web. La lista de ventas expone saldo recogido/reservado/pendiente; Web prellena el saldo pendiente y usa un `commandId` estable durante reintentos de cobro mientras el formulario no cambia. Flutter deja compartir el ticket al completar la venta y el despacho acepta monto o volumen en litros/galones US; el API calcula el volumen usando el precio vigente y permite la siguiente autorización después de completar una anterior.

Verificación de esta actualización: TypeScript build, ESLint, 212 unitarias, 89 contratos de servidor, Web 14/14, `node --check`, Flutter analyze Operaciones y APK debug Operaciones pasan. `flutter test` se detiene dentro de Flutter 3.47.5/test_core antes de ejecutar los casos (`_globalConfigPath`, null check); por eso los tests Dart previos no se presentan como verificación de estos cambios. No se ejecutó una DB QA nueva, una prueba Supabase real ni instalación en teléfono. El PDF no es DTE ni factura fiscal; tarjeta/POS, cambio, Mailjet, fecha de nacimiento de Cliente, flujo legal de consentimiento, Keychain SwiftUI, porcentaje de tanque con telemetría y recorridos integrados siguen pendientes.

## Seguimiento al 10 de octubre de 2026

Se añadió QR/código al vínculo opcional de Cliente durante despacho, manteniendo escritura manual. La cuenta crea el UUID al completar perfil tras verificar correo; no se añadió un segundo identificador ni se convirtió el QR en credencial de pago. Se separó aceptación obligatoria de condiciones del consentimiento promocional opcional y la API exige la aceptación explícita.

La solicitud de puntos sigue ligada a una venta y debe ser confirmada por el Cliente; se admite parcial o cubrir el saldo, con cálculo USD del servidor y cobro posterior del remanente. Promociones financieras aún no pueden publicarse ni asociarse a ventas; por ello no hay venta de campaña elegible hoy. La futura integración queda especificada como no acumulable por defecto y with_points solo con snapshot versionado y validación backend/DB.

Verificación observada: build TypeScript PASS, ESLint server PASS, tests server (unit + contrato) 302/302 PASS, flutter analyze en las dos apps PASS y ambos APK debug reconstruidos. Prueba Dart scanner intentada pero runner Flutter 3.47.5 crashea antes de cargar casos en test_core._globalConfigPath. No hubo cámara física, instalación, sesión Supabase conectada ni E2E con dos teléfonos. Se debe instalar desde los APK con hashes vigentes en artifacts/qa-2026-10-09/SHA256SUMS.txt.
