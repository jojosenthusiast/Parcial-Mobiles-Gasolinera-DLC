# DLC Gasolineras — entrega para QA humano

## Estado vigente de esta actualización documental

**Fecha de evidencia:** 9 de octubre de 2026. Esta sección prevalece sobre recuentos y resultados posteriores conservados como historial. La evidencia es **local** y no acredita aceptación, despliegue, producción ni E2E de negocio.

- Checkout dedicado autorizado en `main`; commits locales `55d1e99` (harness unitario tolerante a CRLF) y `a413d21` (limpieza de logging de sesión Flutter). No hubo push ni despliegue.
- Entorno: Windows 10 x64; Node `v24.19.0`, pnpm `11.25.0`, Flutter `3.47.5` stable y Dart `3.13.4`; no hay dispositivos ADB conectados.
- `pnpm run test:unit`: salida 0, **222 pass, 0 fail, 0 skipped**. `test:integration` tiene 3 pruebas **SKIP** porque `DLC_API_BASE_URL` no está definido; no contactó endpoint alguno.
- Como comprobaciones locales previas en Node 24: build, typecheck, lint; contratos 93/93, web 15/15, contrato Flutter 1/1 y verificadores estructurales de reporte/aceptación/release. No son recorridos E2E de negocio ni walkthrough de navegador.
- Flutter actual: `flutter analyze --no-pub` pasa en `dlc_api`, `dlc_customers` y `dlc_operations`; pruebas Dart actuales: Clientes 1/1 y Operaciones 4/4. `dlc_api` no tiene directorio `test/`. La limpieza eliminó una comparación nula inalcanzable en `employee_session.dart:2241`; no cambió comportamiento fuente.
- APK de Operaciones reconstruido con `flutter build apk --debug --dart-define=DLC_API_BASE_URL=http://10.0.2.2:4000/api/v1`: salida 0, 179,113,952 bytes, SHA-256 `123C1F5D0F018866107EA359B094CDA5148ED8968E4A197B1DD93B6A00D49BD0`; canónico y alias son idénticos. No se instaló. El APK de Clientes no se reconstruyó: falta URL y publishable key de Supabase QA; el archivo existente permanece sin cambios, SHA-256 `bfe141f3190b7caeafbc68d8030cdd30f4695ec582f6d1f1cf84374362049e64`.
- Paquete fuente QA regenerado y verificado: 692 entradas, 108 migraciones locales hasta 0108 y SHA-256 02c5a2d1ec61a7c6f4ee9cf622de221ee95804d234695330ca0255f6587eb3f4. El dato describe el paquete local; no acredita migraciones remotas de Supabase.
- El catálogo fuente local tiene 108 migraciones hasta 0108. Esta sesión no abrió conexión a Supabase, no ejecutó SQL, seeds, API, concurrencia, autenticación/persistencia de sesión ni flujos remotos. Tampoco hubo navegador autenticado.
- RDD está activo por defecto, pero no hay revisión ni recibo/PASS: la evaluación del rango comprometido es de riesgo alto y STATUS solicita `external.select_intended_untracked` para cuatro caches/locks Flutter sin seguimiento; esa captura no está disponible en este runtime. Las seis modificaciones Windows de plugin (solo final de línea) y esos cuatro archivos sin seguimiento no se deben stagear/restaurar.
- Bloqueadores: destino QA aislado identificado con `DLC_API_BASE_URL`, login/tenant de prueba, URL y publishable key de Supabase QA, navegador autenticado y dispositivo Android. Mailjet, sandbox de tarjeta, DTE, push y Mac/iOS/Keychain siguen sin evidencia, credenciales ni aprobación aplicable; la contraseña antigua expuesta de Mailjet no debe reutilizarse.

## Continuación de trabajo en Work (prioridad)

Sigue HANDOFF_TRABAJO_PENDIENTE_WORK.md para el backlog completo, criterios de aceptación y entregables. Las notas históricas de pruebas Flutter son contradictorias: reejecuta y registra la evidencia actual.

## Estado anterior verificado (histórico; sustituido por la evidencia vigente)

Este bloque reemplaza los estados antiguos de Supabase y los recuentos previos que permanecen abajo como historial.

Este bloque reemplaza estados antiguos de Supabase y recuentos previos que permanecen abajo como historial. La copia de trabajo incorpora ambas versiones originales y los cambios descritos aquí. El proyecto Supabase DLC (PostgreSQL 17.11) recibió las migraciones 0086–0108; el ledger de la API contiene 108 versiones; las 23 migraciones nuevas aparecen también en el historial de Supabase y sus SHA-256 coinciden. La base sigue vacía de organizaciones/sucursales. El smoke SQL remoto pasó con rollback y sin datos persistentes. Esta entrega está preparada para QA humano; **no está certificada para producción ni significa que todos los recorridos estén aceptados**.

## Evidencia anterior de verificación (histórica; no usar como estado actual)

- Servidor: build TypeScript y ESLint PASS; 222 pruebas unitarias y 93 contratos PASS.
- Web: 15/15 pruebas PASS. Contrato Flutter/API en Node: 1/1 PASS.
- Flutter: analyze en Operaciones y Clientes sin issues; ambos APK debug compilan. flutter test no llegó a iniciar en este entorno por error del lanzador Flutter al resolver PROGRAMFILES(X86); no se presenta como suite aprobada.
- Supabase real: PostgreSQL 17.11; 0086–0108 aplicadas y 23/23 checksums remotos/locales coinciden. SQL smoke de activos PASS con ROLLBACK; no quedaron filas de prueba.
- Supabase advisors: seguridad 0 hallazgos; rendimiento conserva 331 avisos INFO históricos de FK sin índice, sin aumento por estas migraciones. Se observaron 120 índices no usados en la base vacía; no se eliminan sin carga representativa.
- release:verify PASS con Node 24.19.0; OpenAPI 3.1 y 108 migraciones. ZIP fuente QA actualizado y SHA-256 recalculado.
- No se completó login/ruta autenticada con la API local contra Supabase: falta el login servidor de dlc_api_runtime y no hay organizaciones/sucursales de QA. No se hizo recorrido visual autenticado en navegador ni se instalaron los APK en teléfonos.

## Correcciones de esta pasada

- La API genérica rechaza la categoría `wrong_tank_delivery` y dirige a Compras → Descarga contaminante, evitando saltarse cantidades, costos y conciliación.
- El formulario web de descarga exige escoger expresamente producto y tanque; muestra el nombre del combustible y litros + galones US. Flutter muestra la misma información. La unidad canónica de almacenamiento/API sigue siendo litro.
- Operaciones incorpora cámara QR para vincular la identidad del Cliente antes del cobro; conserva la captura manual como respaldo. La lectura solo identifica la cuenta y el Cliente autoriza pagos con puntos desde su app.
- Los smokes PostgreSQL revelaron y corrigieron permisos y errores de registro en los triggers de pago/otorgamiento/devolución de puntos; las migraciones correctivas 0099–0103 pasan bajo un login de runtime restringido.
- Descargas con el mismo combustible del tanque ya no se registran como contaminación. La vista de descargas muestra aprobadores y evidencia y no permite verificar el retiro antes de aprobar las pérdidas.
- El ZIP fuente excluye la caché Windows generada dentro del árbol Flutter; `SHA256SUMS.txt` identifica el paquete y los APK canónicos.

## Evidencia local histórica (sustituida cuando contradiga la evidencia vigente)

- Servidor: TypeScript, build y ESLint pasan; 212 unitarias + 89 contratos PASS. 3/3 pruebas HTTP básicas (health/readiness/401) pasan contra API local y PostgreSQL temporal con login runtime restringido; no prueban flujos de negocio autenticados.
- Web: 14/14 pruebas y chequeo de sintaxis pasan. No hubo recorrido visual autenticado en navegador.
- Flutter: análisis de Operaciones pasa y el APK debug se recompiló; el runner `flutter test` no inició por un crash del SDK en `test_core` (`_globalConfigPath`, Null check). Los 4 tests previos de Operaciones y 1 de Clientes anteceden a los cambios de este handoff.
- Android: ambos APK debug compilan; el APK de Operaciones incluye el permiso de cámara. PostgreSQL 18.6 temporal aplicó 104 migraciones y pasó 42/42 smokes SQL en base vacía.
- No se instalaron APK ni se probaron en dispositivo/emulador; no se pudo validar lectura QR física. No se probaron rutas de negocio autenticadas con datos QA.

## APK debug histórico (la evidencia vigente de arriba tiene precedencia)

Ambos APK apuntan a `http://10.0.2.2:4000/api/v1` para emulador Android. Clientes necesita recompilarse con un proyecto Supabase de QA y su publishable key; no se incluyeron credenciales.

- Operaciones SHA-256 histórico de un build anterior: 9d1e06622d026f262bf6f73d2736b6ba9d43deab1fc38e7866458039f592aec0; el hash actual verificado es 123c1f5d0f018866107ea359b094cda5148ed8968e4a197b1dd93b6a00d49bd0.
- Clientes SHA-256: bfe141f3190b7caeafbc68d8030cdd30f4695ec582f6d1f1cf84374362049e64

## Aún pendiente

Recorridos E2E autenticados de API contra Supabase, pruebas reales en navegador y dispositivos, push, campañas financieras transaccionales, premios, reglas comerciales de vencimiento/restitución de puntos, cobertura Flutter faltante y conexiones reales de tarjeta/fiscalidad. Ver `docs/AUDITORIA_CIERRE_2026-10-09.md` y `docs/HANDOFF_QA_MAQUINA.md` para detalles y casos.

## Archivos

- Paquete fuente QA: artifacts/qa-2026-10-09/DLCGasolineras_Laboratorio22_QA_source.zip
- Hashes de paquete y APKs: artifacts/qa-2026-10-09/SHA256SUMS.txt
- APK de Operaciones: `artifacts/qa-2026-10-09/dlc_operations-qa-debug.apk`
- APK de Clientes: `artifacts/qa-2026-10-09/dlc_customers-qa-debug.apk`
- Reporte y handoff: `docs/AUDITORIA_CIERRE_2026-10-09.md`, `docs/HANDOFF_QA_MAQUINA.md`


## Auditoría adicional de sesiones y concurrencia

Consulta docs/SEGURIDAD_SESIONES_CONCURRENCIA.md. El acceso de usuarios vinculados a empleados ahora requiere un turno programado activo en login, renovación y cada petición autenticada. Build TypeScript, ESLint focalizado y 210 pruebas unitarias del servidor pasan. Mailjet aún no está conectado: faltan API key/secret, remitente verificado, DNS de autenticación y pantalla de activación; no se hizo envío real.


## Actualización funcional: caja, ticket y despacho (2026-10-09)

- API: `GET /branches/{branchId}/sales/{saleId}/receipt.pdf` genera un PDF tipo ticket de 80 mm con venta, fecha local de El Salvador, combustible/producto, cantidad, precio, total, pagado, saldo y estado fiscal informativo. Lleva la leyenda **COMPROBANTE INTERNO - NO FISCAL**. La ruta requiere `sale.read` y responde `private, no-store`. OpenAPI actualizado.
- Flutter Operaciones permite compartir el PDF al completar cobro; Web permite descargarlo desde el detalle de pagos. La lista de ventas ahora devuelve cobrado, reservado y saldo pendiente para precargar el importe correcto después de pagos parciales; el formulario web evita doble envío y conserva commandId al reintentar un payload sin cambios.
- Despacho Flutter permite fijar el objetivo por volumen (litros/galones US) o monto USD; el servidor convierte monto con el precio vigente. Las autorizaciones terminadas ya no bloquean autorizar un siguiente despacho, y las que requieren conciliación siguen bloqueando.
- Validación de este cambio: build TypeScript y ESLint pasan; 212/212 unitarias; 89/89 contratos API; web 14/14 y `node --check`; `flutter analyze` Operaciones sin issues; APK debug Operaciones compilado. `flutter test` se intentó pero Flutter 3.47.5 se cae antes de ejecutar tests con `Null check operator used on a null value` en `test_core._globalConfigPath`.

### Límites para aceptación humana

- El PDF es un comprobante operativo interno; no es factura, crédito fiscal ni DTE. La fiscalidad y emisión electrónica quedan pendientes de requisitos y proveedor aprobados para El Salvador.
- La tarjeta sigue siendo registro manual/simulado, no POS; no se agregó vuelto/cambio de efectivo ni comprobación bancaria.
- No se muestra porcentaje de llenado por bomba: no hay telemetría calibrada que lo respalde. El saldo de inventario del tanque es dato de libro, no una lectura física del surtidor.
- No se agregó DOB a perfiles de Cliente ni se conectó Mailjet; alta/confirmación por correo usa el flujo Supabase ya existente. Los términos legales y el consentimiento final requieren texto aprobado. El port SwiftUI/Keychain y perfiles múltiples siguen siendo trabajo futuro; el almacenamiento seguro Flutter actual no demuestra Keychain/iOS.
- No se ejecutó un recorrido autenticado real con PostgreSQL/Supabase ni se probó el APK en un teléfono/emulador en esta actualización. Esta entrega es para QA humano, no para producción.


Los hashes vigentes de APK y ZIP están en `artifacts/qa-2026-10-09/SHA256SUMS.txt`.

## Continuación: QR de despacho, consentimiento y puntos (2026-10-09)

- El código QR de Cliente ya se genera al crear su perfil después de verificar correo; /customer/me/qr devuelve una identidad UUID que la app muestra como QR y código legible. El flujo de despacho ahora ofrece escáner QR y entrada manual para enlazar la cuenta a la venta. El QR no autoriza pago ni canje; el Cliente autenticado confirma por separado el pago con puntos.
- Se corrigió el perfil: el checkbox obligatorio acepta la versión de condiciones indicada al servidor (termsAccepted: true); el consentimiento de comunicaciones promocionales es opt-in separado y opcional. La API ahora rechaza crear/actualizar perfil si no llega la aceptación explícita.
- Puntos aceptan un tender parcial o pueden cubrir el saldo completo si los puntos disponibles alcanzan; la app caja solicita la cantidad, el servidor calcula su equivalente con tasa vigente, la limita al saldo abierto y el Cliente confirma en su app. Se paga después cualquier remanente por tender normal.
- Las promociones financieras continúan bloqueadas y sin vínculo transaccional con tickets; hoy no existe venta promocional a la que aplicar puntos. La regla acordada para futura integración es excluir campañas por defecto y permitir acumulación solo con política with_points explícita y snapshot versionado en la venta.
- Verificación de esta continuación: TypeScript build PASS; ESLint server PASS; 302/302 unitarias + contratos PASS; análisis Flutter limpio en Operaciones y Clientes; ambos APK debug recompilados. flutter test test/customer_qr_scanner_test.dart intentó ejecutarse pero Flutter 3.47.5 se cae antes de correr el runner (test_core._globalConfigPath, null check); no lo contamos como test Dart. No se instaló/probó la cámara en dispositivo.
- Sigue bloqueado el canje real fuera de QA: falta E2E del tender con devoluciones, política de puntos vencidos/saldo negativo, prueba de dos dispositivos conectados y activación en una base aislada; mantén la conversión de canje apagada fuera de una base desechable.


## Actualización 2026-10-09 — valor monetario del saldo de puntos

- El backend entrega saldo, tasa USD por punto, elegibilidad de canje y equivalente monetario redondeado hacia abajo a centavos; Flutter Clientes lo muestra junto al saldo. Si la tasa activa falta o es cero, muestra canje no habilitado.
- La compra POS de tienda soporta vinculación de Cliente y solicitud parcial de puntos. La regla de ledger existente premia solo importes externos confirmados; la fracción pagada con puntos queda excluida. El smoke SQL existente cubre una venta POS de USD 10 con USD 5 en puntos y USD 5 en efectivo, y comprueba la base de puntos.
- API de lealtad documentada en OpenAPI; pruebas nuevas para tasa activa/cero y respuesta móvil.
- Verificación: TypeScript build, 217 unitarias, 92 contratos, ESLint, análisis Flutter Clientes y compilación APK Clientes pasan. No se ejecutó PostgreSQL en esta pasada; el smoke de puntos está en el árbol para repetirlo con DB QA.
- El APK actualizado y ZIP fuente están en `artifacts/qa-2026-10-09/`; hashes en su `SHA256SUMS.txt`. No instalado en emulador/dispositivo.
- Mailjet no se configuró: el control de navegador falló al crear el sandbox (`helper_sandbox_lock_failed`), por lo que no hubo sesión, cambios en cuenta ni correo de prueba.


## Actualización 2026-10-10 — Activos operativos y repaso de interfaz

- Se implementó el inventario de activos durables de sucursal, separado del combustible y de la mercadería de tienda. Los productos rápidos de venta siguen en lotes POS existentes.
- Migración nueva 0105_operational_assets.sql: catálogo de equipo, custodios, estado, versión optimista, eventos append-only, enlace de incidencias y permisos de costo, verificación, traslado y retiro.
- Web y Operaciones móvil incluyen resumen estadístico, actividad de seis meses, filtros, ficha/historial, edición, asignaciones, reparación/verificación, pérdida/daño, retiro y traslado. Reportes incluye operational_assets y exporta según las capacidades existentes.
- Al reportar daño el activo entra en reparación; al reportar pérdida pasa a missing. El evento y la incidencia se persisten en la misma transacción. La recuperación requiere el permiso de verificación y una nota.
- Se corrigió un problema de permiso: una edición sin acceso a costos ya no borra el costo de adquisición. Costos tampoco se pueden escribir sin el permiso explícito.
- UI: se reutiliza el sistema visual existente, se muestran conteos y detalle textual junto al gráfico y las transiciones respetan la preferencia de reducir movimiento.
- Verificación: TypeScript build y ESLint PASS; 222/222 unitarias; 93/93 contratos; 15/15 Web; contrato Flutter 1/1; análisis Flutter de Operaciones y Clientes sin issues; verificador de release confirma OpenAPI 3.1 y 105 migraciones. APK debug de Operaciones compilado.
- Límites: PostgreSQL no responde en localhost:5432 y Docker no está instalado, por lo que la migración y triggers no se ejecutaron en DB real. flutter test no inició por PROGRAMFILES(X86) ausente en el entorno del lanzador. No se instalaron APK ni se recorrió web autenticada en navegador.
- Ver docs/UX_UI_AUDITORIA_ACTIVOS_2026-10-10.md para hallazgos y límites de revisión.
