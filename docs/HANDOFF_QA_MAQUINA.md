> Continuación vigente: consulta HANDOFF_TRABAJO_PENDIENTE_WORK.md en la raíz del proyecto. Reejecuta las suites y registra evidencia actual; existen notas históricas contradictorias sobre Flutter.

# Handoff de QA en la máquina local

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

Este handoff prepara la verificación con Flutter, Android y PostgreSQL/Supabase que no existen en el entorno de edición. El código es candidato de QA, no una versión certificada para producción. Mantén el canje monetario de puntos desactivado (`redemptionUsdPerPoint = 0`) hasta cerrar las pruebas y el reverso de los puntos usados como tender en devoluciones.

## Cambios incluidos aquí

- Política central de puntos con creación, maker-checker y conversión USD por punto (`0089`, `0091`), y puntos ganados por porción elegible de venta efectivamente pagada.
- Pago con puntos por cotización con vencimiento de 120 segundos, consentimiento explícito del Cliente, débito/tender atómico, idempotencia, locks y límite de saldo de venta (`0092`). Caja envía la solicitud; Clientes muestra sucursal, puntos e importe y requiere confirmación. El QR es identidad, no autorización de pago.
- Cobros mixtos: el pago en puntos se refleja en saldo cobrado y la porción en puntos no genera puntos nuevos. El efectivo esperado no incluye puntos.
- Logs globales de Flutter para errores no capturados y logs de API con correlación. La caja vuelve a consultar el saldo después de la confirmación para cobrar el remanente.
- OpenAPI actualizado; pruebas de contrato para las rutas y un test unitario de idempotencia en rechazo.
- Reverso proporcional de puntos ganados ante reembolsos monetarios aprobados (`0093`).
- Revisión documentada de límites: reverso de puntos usados como tender, premios físicos, vencimientos, push real, campañas financieras transaccionales, fiscalidad y conexiones de terminal siguen requiriendo trabajo o evidencia.

## 1. Preparar un entorno QA aislado

1. Crear una base PostgreSQL/Supabase de QA vacía o restaurable y un proyecto Supabase de QA separado. No apuntar a producción.
2. Configurar API y migrador con secretos solo en el `.env` local no versionado. Para Clientes: `CUSTOMER_ORGANIZATION_ID`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` y `CUSTOMER_TERMS_VERSION` deben corresponder al mismo tenant/proyecto.
3. Antes de migrar, guardar backup y consultar `schema_migrations`. Desde `server/`, ejecutar `node --env-file-if-exists=.env scripts/migrate.mjs`; el runner aplica todas las migraciones pendientes en orden. Confirmar que llega hasta `0098_point_payment_refunds.sql` y guardar la salida completa.
4. Verificar rol `dlc_api_runtime`, RLS/grants, integridad de FK e índices tras migrar. No ejecutar el SQL con el cliente conectado como superuser para las pruebas de autorización runtime.
5. Crear organización, sucursal, usuarios/capacidades, caja, cliente confirmado por correo y política central activa de QA. Para probar canje, configurar conversión solo en esta base desechable.

## 2. Checks automatizados

Desde la raíz del repo:

```bash
cd server
node_modules/.bin/tsc --noEmit -p tsconfig.json
node_modules/.bin/eslint src test
node --test test/*.test.mjs test/contracts/*.test.mjs
cd ../flutter
node --test test/*.test.mjs
```

Con Flutter instalado, en `flutter/`:

```bash
cd apps/dlc_operations
flutter pub get
flutter analyze
flutter test
cd ../dlc_customers
flutter pub get
flutter analyze
flutter test
```

Después compilar ambas por separado con los comandos de `flutter/README.md`. Probar al menos un Android emulator y un dispositivo físico con HTTPS. Guardar APKs de QA fuera del repositorio y anotar commit, versión, Android/API level y hashes.

## 3. Pruebas obligatorias del flujo de puntos

| Caso | Acción | Resultado esperado |
|---|---|---|
| Política desactivada | conversión = 0; intentar solicitud | Caja/servidor rechazan; no quote, pago ni asiento de ledger. |
| Sin Cliente vinculado | caja intenta solicitar puntos | Rechazo sin revelar datos de otra cuenta. |
| Cotización válida | enlazar Cliente, solicitar parte de saldo | Cliente ve sucursal, puntos, importe exacto y expiración; no se descuentan puntos todavía. |
| Aprobación | Cliente confirma antes de 120 s | Un solo tender y un débito; recibo/saldo de venta actualizados. |
| Rechazo | Cliente rechaza | No cambia venta ni saldo de puntos; reenvío del mismo command es idempotente. |
| Expiración | esperar 120 s y confirmar | No se cobra; UI muestra vencida y requiere cotización nueva. |
| Balance insuficiente | gastar puntos por otro flujo después de cotizar | Confirmación falla sin tender ni débito parcial. |
| Importe excesivo | solicitar puntos cuyo USD exceda saldo pendiente | Rechazo; sin cobrar de más. |
| Pago mixto | usar puntos y después cobrar remanente en efectivo/tarjeta QA | Total cobrado no supera venta; caja solo aumenta efectivo por el tender cash; solo tender elegible gana puntos. |
| Sobrepago concurrente | dos cajas/requests intentan pagar saldo restante | La serialización de venta permite como máximo el total; la segunda recibe conflicto. |
| Doble tap/reintento/red caída | repetir solicitud, confirmación y respuesta con misma clave | Un asiento; reintentos recuperan resultado; no duplicar saldo ni tender. |
| Cierre de caja concurrente | cerrar sesión mientras hay aprobación | El cierre o tender se serializan; nunca confirmar un tender contra una sesión ya cerrada. |
| Crédito comercial | intentar puntos en venta a crédito | Rechazo explícito y no se altera deuda ni ledger. |
| Tenant isolation | autenticar otro Cliente/organización y consultar/confirmar quote ajena | 404/403 sin filtrar sucursal, importe o puntos. |
| Borrado/desactivación | bloquear cuenta o retirar política durante la espera | Confirmación falla de forma segura; no consume puntos. |

**Bloqueador de aceptación financiera:** probar devolución total/parcial de venta con tenders mixtos y reembolso. La migración 0093 revierte proporcionalmente puntos ganados cuando se reembolsa dinero; 0098 añade devolución de los puntos usados como tender; falta ejecutarla en QA, definir saldo negativo/recuperación y enlazar con reglas de devolución parcial mixta. No aprobar ni habilitar canje real hasta implementar esa regla, añadir pruebas SQL/concurrencia y verificar el reporte conciliado. Mantener `redemptionUsdPerPoint=0` en cualquier entorno no desechable.

## 4. Pruebas de ambas apps y flujos colindantes

- Empleado: login/refresh/logout, permisos por sucursal, sesión caducada, pérdida de red y logs/correlation IDs en `flutter logs` y `adb logcat`.
- Caja/POS: vincular QR/código correcto, código inválido, venta sin Cliente, venta duplicada, pago cash/card manual, tarjeta `unknown`, conciliación, click doble, reanudación tras matar la app y cuadre del cierre.
- Cliente: registro, correo no confirmado, confirmación, login, reset, deep links, expiración/logout, aislamiento de cuenta; QR nunca autoriza tender.
- Campañas: aprobación de gerente vs administrador, fechas, recurrencia, zonas/sucursales/audiencias congeladas, imágenes dañadas, detalles/condiciones. Confirmar en POS que descuentos, cashback y multiplicadores siguen bloqueados si el motor transaccional correspondiente no está habilitado.
- Inventario/compra/retorno: recepciones duplicadas, lotes/expiry, devolución física de POS, reembolso separado y conciliación. Documentar diferencias entre mercancía, dinero y puntos.
- Reportes y caja: venta/tender mixto aparece una vez en reportes; puntos no inflan efectivo/tarjeta; exportes, auditoría y cierres cuadran con el ledger.

## 5. Observabilidad y paquete de evidencia

Reproducir al menos un 4xx esperado, un error de red y un crash controlado en QA. Recoger hora UTC, app/build/device, pantalla/flujo, pasos, `X-Request-ID`/correlation ID, logs filtrados por `dlc.customer.crash`, `dlc.operations.crash`, `dlc.customer` y `dlc.api`, más request/response saneados. Quitar tokens, claves, correo/teléfono, QR y datos personales antes de compartir. Confirmar que logs no incluyan contraseña, JWT, secreto, contenido sensible del QR o datos financieros innecesarios.

Registrar matriz ejecutada con PASS/FAIL/BLOCKED, evidencia y defectos. No cambiar `human_result` a aceptado por compilar solamente. En la revalidación local del 9 de octubre se ejecutaron todos los smokes SQL contra PostgreSQL 18.6 efímero; ver `QA_CIERRE_MAQUINA_2026-10-09.md` para los comandos y límites.

## Lo que no se certifica con este paquete

La revalidación local sí incluye PostgreSQL efímero, `flutter analyze`, pruebas Dart y build de ambos APK; no hubo Supabase real, integración HTTP autenticada, instalación Android, push remoto, terminal ni fiscalidad. La migración 0098 implementa solicitudes/decisiones de devolución del tender con puntos, pero la política de vencimiento, saldo negativo y recuperación sigue sin definición ni aceptación integrada. Las promociones cashback/descuento no se cargan a cobros reales. Términos y privacidad de Clientes siguen siendo texto de QA hasta aprobación legal.


## Auditoría adicional 2026-10-09
Leer AUDITORIA_CIERRE_2026-10-09.md. Aplicar hasta migración 0095. 0094 corrige autorización SQL de cotización de puntos y acceso a NEW.outcome. 0095 añade descarga en tanque equivocado. El reporte/bloqueo están añadidos; 0096/0097 añaden snapshots, aprobación de pérdidas y disposición física; su ejecución integrada sigue pendiente. No confundir este pendiente de desarrollo con QA. Probar cliente correcto/incorrecto y metadatos de decisión inmutables en PostgreSQL antes de habilitar canje.


## Desarrollo adicional: migraciones 0096–0098

- 0096/0097: registro de descarga contaminante, foto lógica del saldo previo, cantidad real entrante, costos separados, remanente de compra, evaluación de pérdida previa, aprobación independiente de pérdida entrante y retiro verificado. Hay pantallas Flutter y web. Incidencias conserva el flujo de aprobar la pérdida previa; mantenimiento conserva inspección/liberación.
- 0098: devolución parcial/total del pago con puntos. Solicitud y decisión independientes, límites que incluyen solicitudes pendientes y aprobadas, restitución por ledger y equivalente monetario acumulado. Acceso Flutter: Cajas → icono Devoluciones de puntos. Web: detalle de pagos de venta.
- Inventario: disponible para vender cero en tanque bloqueado, saldo físico estimado de mezcla separado, ajustes manuales prohibidos durante contaminación, pérdidas aprobadas pueden retirar reserva inutilizable; despachos pendientes deben resolverse antes de retirar inventario.

### Recorridos que Work debe ejecutar y depurar
1. Aplicar migraciones en base descartable en orden hasta 0098; correr customer-points-payment-smoke.sql con ON_ERROR_STOP y revisar rollback. El smoke aún no se ejecutó aquí.
2. Flutter pub get, dart format, flutter analyze, pruebas de widgets y compilación de ambas APK; no tratar los contratos Node como pruebas de Flutter.
3. Contaminación 4.000 L + 250 L de un pedido de 3.000 L: saldo comercial disponible cero, costos separados, remanente 2.750 L; otro usuario aprueba pérdidas; retiro con documento; mantenimiento verifica y libera.
4. Verificar tanque vacío (no genera evaluación de pérdida previa), costo desconocido, sobrellenado real documentable, versión desactualizada, pedido excedido, comando repetido, segundo reporte del mismo tanque bloqueado y permisos cruzados.
5. Probar que recepción normal descuenta cantidad contaminada del pedido y que ningún ajuste manual evita el bloqueo.
6. Devoluciones de puntos: parcial y final, solicitante no puede decidir su solicitud; rechazo libera puntos reservados para devolución; solicitud excedida no crea asiento; reinicio/red perdida no duplica. Sin salida de dinero del cajón.
7. Probar resta de puntos ganados por devolución monetaria por separado; programa retirado/cambiado no altera conversión del pago histórico. Restitución de puntos expirados y tratamiento de saldo negativo todavía requieren decisión comercial y validación integrada.
8. Revisar exportación financiera de pérdidas entrantes y devoluciones de puntos: existen registros propios, pero no se acredita paridad de todos los reportes ni contabilización externa.

### Pendientes funcionales que NO son meramente QA
Campañas financieras transaccionales, proveedor push, prueba de cámara del lector QR en dispositivo real, ciclo completo de premios, cobertura Flutter de tienda/crédito/servicios/gastos y retorno SwiftUI. Integraciones reales de terminales y fiscalidad requieren proveedor y credenciales. No habilitar comercialmente beneficios hasta completar estos flujos y la validación financiera.


## Estado histórico de una ejecución anterior — 9 octubre 2026

La evidencia vigente está consolidada en `QA_CIERRE_MAQUINA_2026-10-09.md`: 208 unitarias, 89 contratos de servidor, 14 web, 5 contratos Flutter en Node, 4 pruebas Dart en Operaciones y 1 en Clientes; TypeScript, build, ESLint, análisis Flutter y `node --check` pasan. Las migraciones 0001–0104 y 41 scripts SQL smoke pasan en PostgreSQL 18.6 efímero y limpio. Se compilaron ambos APK debug para el API de emulador local. No se hizo inspección visual de navegador ni instalación en dispositivo.

Los APK están en `../artifacts/qa-2026-10-09/` y apuntan al backend de emulador `http://10.0.2.2:4000/api/v1`. Para ejecutar un recorrido funcional, inicia una API QA con PostgreSQL migrado y configura Supabase de QA en Clientes. No uses datos de producción.

**Pendiente para aceptación:** configurar API/DB QA con usuarios de prueba y recorrer por rol compra/descarga contaminante/resolución, devoluciones mixtas y concurrencia; probar QR/cámara y ambas APK en emulador/dispositivo; habilitar cobros/integraciones solo con sandbox. Las pruebas HTTP locales 3/3 sí pasaron contra una API conectada a PostgreSQL temporal con login runtime restringido; no cubren flujos autenticados de negocio ni Supabase. Consulta `QA_CIERRE_MAQUINA_2026-10-09.md` para evidencia completa.

### Correcciones posteriores y autoridad de estado

La auditoría más reciente es `QA_CIERRE_MAQUINA_2026-10-09.md`; reemplaza las afirmaciones antiguas de esta página sobre pruebas Flutter/PostgreSQL no ejecutadas y migración final 0098. Incluye los arreglos SQL de 0099–0104, la regresión para distinguir combustible incompatible del mismo combustible, la tabla web con responsables/evidencias y la lista de trabajos que siguen bloqueados por entorno, proveedor o decisiones comerciales. El ZIP excluye ahora el caché local `%SystemDrive%` generado por Windows.


### Nota de cámara para iOS

Operaciones usa mobile_scanner 7.4.2 para QR en Android y conserva entrada manual si no hay cámara o se niega el permiso. Esta copia no trae scaffold iOS; antes de generar o compilar iOS hay que añadir NSCameraUsageDescription a ios/Runner/Info.plist y probar el permiso/cámara en dispositivo Apple. No se afirma soporte iOS validado.


## Estado funcional añadido el 2026-10-09

- PDF tipo ticket de venta interno/no fiscal (`receipt.pdf`) disponible desde Flutter y Web; saldo pendiente visible en caja Web; cobro web evita dobles envíos concurrentes usando un commandId estable para el mismo contenido.
- Flutter despacho permite monto USD o volumen en litros/galones US, y habilita el siguiente despacho luego de completar el anterior.
- Evidencia actualizada: 212 unit tests servidor, 89 contratos API, 14 web; build y lint servidor, sintaxis JS y análisis Flutter Operaciones pasan; APK Operaciones recompilado. `flutter test` no inició porque el SDK cae en `test_core._globalConfigPath` (Null check).
- Quedan fuera de este paquete: documento fiscal/DTE, POS real, vuelto/cambio, push/Mailjet, perfil Cliente con DOB, términos aprobados, telemetría física de nivel tanque, QA Supabase autenticado y prueba en teléfono. El ticket indica explícitamente “NO FISCAL”.

## Actualización 2026-10-09: QR, canje y consentimiento

El perfil Cliente recibe su UUID público al ser creado después de verificación de correo; la app muestra QR y código. Operaciones despacho permite escanearlo o escribirlo. El QR solo vincula identidad. Caja puede solicitar tender de puntos parcial o suficiente para cubrir todo el saldo; el Cliente revisa monto/puntos y confirma desde su sesión, luego caja cobra el remanente. La API limita valor al saldo, la tasa vigente y balance disponible.

La creación de perfil requiere termsAccepted=true y la versión vigente del servidor. El checkbox obligatorio de condiciones no se usa como permiso promocional; comunicaciones de marketing tienen checkbox separado y opcional.

No hay vínculo de campañas a ventas: descuentos/cashback/multiplicadores financieros no se publican ni cambian el ticket, así que no existe venta de campaña que pueda pagar puntos actualmente. En futuras campañas transaccionales la regla predeterminada será no combinable; solo una política with_points aprobada, guardada en el snapshot de venta y validada en servidor/DB podrá permitirlo.

Verificación 2026-10-09: TypeScript build y ESLint PASS; 302/302 unitarias + contratos PASS; flutter analyze PASS para ambas apps; APK debug Operaciones y Clientes recompilados. flutter test no llega a ejecutar los casos por crash previo del SDK Flutter 3.47.5/test_core (_globalConfigPath). Sin instalación física, E2E conectado ni aceptación humana; mantener redención monetaria desactivada fuera de QA desechable.


## Decisión de inventarios y preparación de Mailjet

La clasificación recomendada y el estado real de Mailjet están en docs/DECISION_INVENTARIOS_OPERATIVOS_Y_MAILJET.md. Los artículos automotrices empacados pertenecen al inventario POS existente por lote/categoría; Activos operativos debe ser un registro nuevo con historia de asignación/daño/baja, conectado a incidencias/mantenimiento. Mailjet no está configurado: sin API Key/Secret, sender autorizado y URL de activación, las invitaciones de empleados se bloquean en producción; el correo/contraseña de inicio de cuenta no es la API key. La confirmación de Cliente depende además del SMTP del proyecto Supabase QA.


## Continuación: categorías de venta rápida

Los productos automotrices empacados usan inventario POS de tienda existente; ahora alta admite categoría y API/OpenAPI, Web y POS móvil muestran el filtro. Se mantienen lotes/FEFO/proveedores y trazabilidad de venta; no se crea un tercer stock de mercadería ni se modifica el global catalog existente de forma silenciosa. Combustible servido en recipientes continúa sujeto a flujo/controles de combustible, no es un SKU genérico. El módulo independiente que falta es Activos operativos, según docs/DECISION_INVENTARIOS_OPERATIVOS_Y_MAILJET.md.


## Actualización 2026-10-09 — puntos de tienda y valor visible

- El endpoint de lealtad devuelve `pointsBalance`, `redemptionUsdPerPoint`, `canRedeem` y `availableValueUsd`; el cálculo usa tasa activa del servidor y redondeo descendente a centavos. La app de Clientes presenta saldo y equivalente monetario o informa cuando el canje no está habilitado.
- La regla de puntos para ventas mixtas se conserva: solo la porción confirmada en dinero real genera puntos. La venta POS mixta se cubre en el smoke SQL existente (500 puntos aplicados a una venta de USD 10 y USD 5 cobrados en efectivo; solo esos USD 5 entran al cálculo de puntos).
- La prueba de cliente cubre una tasa activa (125 puntos = USD 1.25) y tasa ausente/cero.
- Mailjet sigue sin quedar configurado. Intenté abrir el navegador autorizado, pero el motor se detuvo antes de mostrarlo por `helper_sandbox_lock_failed`; no hubo login ni cambios de cuenta. Hace falta iniciar sesión en Mailjet desde un navegador funcional y guardar API Key/Secret como secretos del servidor QA y SMTP del Supabase QA.
- Verificación de esta actualización: build TypeScript y 217 pruebas unitarias PASS; 91 contratos PASS; ESLint PASS; `flutter analyze` de Clientes PASS. PostgreSQL no se ejecutó en esta pasada.
