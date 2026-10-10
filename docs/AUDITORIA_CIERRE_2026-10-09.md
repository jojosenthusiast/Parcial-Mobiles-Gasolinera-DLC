# Auditoría de cierre — 9 de octubre de 2026

## Estado vigente de esta actualización documental

**Fecha de evidencia:** 9 de octubre de 2026. Esta sección prevalece sobre recuentos y resultados posteriores conservados como historial. La evidencia es **local** y no acredita aceptación, despliegue, producción ni E2E de negocio.

- Actualización de entrega verificada el 9 de octubre de 2026: checkout dedicado autorizado en `main`; los commits de trabajo `55d1e99` (harness unitario tolerante a CRLF) y `a413d21` (limpieza de logging de sesión Flutter), junto con el commit documental `e80ebbf59d77c90f9f6642d9ebc558e33b2afd03`, se enviaron correctamente a `origin/main`. La rama local `main` está sincronizada con `origin/main`. No hubo despliegue.
- Entorno: Windows 10 x64; Node `v24.19.0`, pnpm `11.25.0`, Flutter `3.47.5` stable y Dart `3.13.4`; no hay dispositivos ADB conectados.
- `pnpm run test:unit`: salida 0, **222 pass, 0 fail, 0 skipped**. `test:integration` tiene 3 pruebas **SKIP** porque `DLC_API_BASE_URL` no está definido; no contactó endpoint alguno.
- Como comprobaciones locales previas en Node 24: build, typecheck, lint; contratos 93/93, web 15/15, contrato Flutter 1/1 y verificadores estructurales de reporte/aceptación/release. No son recorridos E2E de negocio ni walkthrough de navegador.
- Flutter actual: `flutter analyze --no-pub` pasa en `dlc_api`, `dlc_customers` y `dlc_operations`; pruebas Dart actuales: Clientes 1/1 y Operaciones 4/4. `dlc_api` no tiene directorio `test/`. La limpieza eliminó una comparación nula inalcanzable en `employee_session.dart:2241`; no cambió comportamiento fuente.
- APK de Operaciones reconstruido con `flutter build apk --debug --dart-define=DLC_API_BASE_URL=http://10.0.2.2:4000/api/v1`: salida 0, 179,113,952 bytes, SHA-256 `123C1F5D0F018866107EA359B094CDA5148ED8968E4A197B1DD93B6A00D49BD0`; canónico y alias son idénticos. No se instaló. El APK de Clientes no se reconstruyó: falta URL y publishable key de Supabase QA; el archivo existente permanece sin cambios, SHA-256 `bfe141f3190b7caeafbc68d8030cdd30f4695ec582f6d1f1cf84374362049e64`.
- Paquete fuente QA regenerado y verificado: 692 entradas, 108 migraciones locales hasta 0108 y SHA-256 02c5a2d1ec61a7c6f4ee9cf622de221ee95804d234695330ca0255f6587eb3f4. El dato describe el paquete local; no acredita migraciones remotas de Supabase.
- El catálogo fuente local tiene 108 migraciones hasta 0108. Esta sesión no abrió conexión a Supabase, no ejecutó SQL, seeds, API, concurrencia, autenticación/persistencia de sesión ni flujos remotos. Tampoco hubo navegador autenticado.
- RDD está activo por defecto, pero no hay revisión ni recibo/PASS: la evaluación del rango comprometido es de riesgo alto y STATUS solicita `external.select_intended_untracked` para cuatro caches/locks Flutter sin seguimiento; esa captura no está disponible en este runtime. Las seis modificaciones Windows de plugin (solo final de línea) y esos cuatro archivos sin seguimiento no se deben stagear/restaurar.
- Bloqueadores: destino QA aislado identificado con `DLC_API_BASE_URL`, login/tenant de prueba, URL y publishable key de Supabase QA, navegador autenticado y dispositivo Android. Mailjet, sandbox de tarjeta, DTE, push y Mac/iOS/Keychain siguen sin evidencia, credenciales ni aprobación aplicable; la contraseña antigua expuesta de Mailjet no debe reutilizarse.

## Revalidación posterior contra Supabase (histórico; no revalidado en la evidencia vigente)

Este relato se conserva como antecedente documental. La evidencia vigente de arriba no conecta a Supabase ni permite afirmar que una migración esté aplicada o que el smoke remoto haya ocurrido en la sesión actual.

- Se identificó el proyecto Supabase DLC (PostgreSQL 17.11, activo). No se usó Docker ni PostgreSQL local para validar la base remota.
- Aplicadas localmente pendientes 0086–0108: 23 migraciones. Las 23 migraciones nuevas aparecen en el historial Supabase y public.schema_migrations; los SHA-256 locales/remotos coinciden 23/23. La línea base interna de Supabase está consolidada y tiene una cantidad total distinta.
- El smoke transaccional remoto pasó: creó datos ficticios, registró equipo asignado, reportó daño, confirmó estado under_repair, versión incrementada e historial append-only; rechazó un evento inválido. ROLLBACK dejó 0 organizaciones, sucursales, activos e incidencias de prueba.
- RLS activo en ambas tablas de activos. No hay SELECT para anon, authenticated ni service_role; el runtime puede leer/insertar y no actualizar/eliminar eventos.
- Advisors después de corregir: seguridad 0 hallazgos; rendimiento 331 avisos INFO de FK sin índice (mismo número que antes de la cadena) y 120 índices no usados en una base sin carga.
- Se añadieron 0106 (search_path fijo), 0107 (67 índices para 68 FK nuevas) y 0108 (privilegios append-only mínimos).
- Limitaciones abiertas: no hay organizaciones/sucursales ni cuenta de API runtime configurada para ejecutar rutas autenticadas contra esta base; no hay prueba de concurrencia con dos sesiones reales, recorrido visual web autenticado ni validación en teléfonos. Los defaults de funciones de supabase_admin requieren un administrador del proyecto. Ver docs/SUPABASE_DLC.md.

La ausencia de PostgreSQL local/Docker no bloqueaba el test de Supabase; la migración y el smoke ya quedaron verificados mediante el conector.

## Dictamen

**No está terminado ni autorizado para producción.** Hay dos proyectos Flutter separados, backend NestJS/PostgreSQL y web operativa. También existe una aplicación SwiftUI de laboratorio con repositorio local; sus funciones no acreditan paridad con el backend ni con Flutter. La auditoría histórica `AUDITORIA-LAB22.md` describe ese prototipo y debe leerse exclusivamente en ese contexto.

Esta revisión es de código, contratos, estructura y pruebas disponibles. No equivale a recorrer todas las pantallas en dispositivos ni ejecutar cada regla SQL. No hay Flutter/Dart/PostgreSQL CLI disponibles en este entorno. No se ha certificado APK, migración real, concurrencia integrada ni operación real. No se consultaron servicios externos ni se usaron credenciales de producción.

## Hallazgos y correcciones concretas

| Prioridad | Hallazgo | Acción / estado |
|---|---|---|
| Crítica | `0092` exige que quien decide el pago con puntos sea DISTINTO al cliente de la cotización: rechaza al cliente correcto | Nueva `0094` cambia a IS NOT DISTINCT FROM y protege identidad, creación y cambios de decisión sin transición |
| Alta | Disparador compartido accede a NEW.outcome de una tabla que no tiene ese campo | `0094` accede al campo únicamente dentro de la rama payment_events |
| Alta | Venta directa de inventario solo verifica estado del tanque, no bloqueo de activo | `fuel-inventory.service.ts` consulta bloqueos de tanque bajo el bloqueo FOR UPDATE antes de venta |
| Alta | No existe categoría específica de descarga contaminante | API, web y `0095` incorporan wrong_tank_delivery; exige tanque y gravedad alta/crítica; crea bloqueo de seguridad en transacción |
| Implementado parcialmente, pendiente QA | 0096/0097 añaden cantidades reales, remanente, evaluación previa, aprobación entrante y disposición física | Pendiente contabilización/exportación completa, remanente contractual y ejecución integrada |
| Implementado, pendiente QA | Devoluciones del pago con puntos añadidas mediante 0098, API, Flutter y web | Mantener conversión en cero fuera de QA hasta probar SQL y conciliación mixta |
| Alta pendiente | Campañas financieras no se aplican integralmente a cobro/acumulación | Hay definición, validación y aprobación; no certificar descuentos/cashback/multiplicadores operativos |
| Alta pendiente | Paridad incompleta entre prototipo Swift y Flutter/backend | Tienda y otros módulos locales requieren implementación integrada, no basta portar pantalla |
| Alta pendiente | SQL completo y apps no ejecutados | Ejecutar migraciones y recorridos integrados en máquina local |

Las correcciones SQL son migraciones adicionales: **no editar una migración ya aplicada ni borrar su checksum**. Aplicar 0094 y 0095 después de 0093. La comprobación de igualdad corregida todavía debe probarse en PostgreSQL con cliente correcto e incorrecto.

## Matriz de módulos y flujos

“Código presente” significa implementación identificada, no aceptación de producción.

| Área | Evidencia principal | Estado y límite |
|---|---|---|
| Organización, sucursales y parque | server/src/branches, infrastructure; Flutter branch_onboarding/infrastructure_setup | Código presente; probar creación, cambios de capacidad, conexiones de boquillas y acceso entre sucursales |
| Identidad de empleados y permisos | auth, authorization, staff; dlc_api/employee_session | Servidor y almacenamiento seguro presentes; probar revocación, expiración, cambio de roles y aislamiento |
| Identidad de clientes | customers/customer-auth.guard, supabase_flutter | Integración Auth presente; necesita proyecto configurado y prueba de identidad real |
| Personal y turnos | staff; staff_shifts_screen | Código presente; validar solapamientos, ausencias, relevos y atribuciones por sucursal |
| Precios | pricing; branch_prices_screen | Versionado/aprobación presentes; verificar fecha efectiva, unidad y modalidad de servicio |
| Compras y proveedores combustible | procurement; procurement_screen | Orden, aprobación, recepción parcial, factura y pagos presentes; recepción usa varias transacciones recuperables, verificar reintentos y registros processing atascados |
| Inventario combustible | inventory; movimientos y valoración SQL | Comandos idempotentes y bloqueo de tanque presentes; probar precisión, capacidad, reserva inutilizable y carreras con despacho |
| Despacho y ventas | sales; dispense_screen | Código presente; adaptador manual/simulado, no certificación de equipo real |
| Caja y cortes | finance, cuts; cash_screen | Cobros y saldos presentes; comprobar parcialidades, recuperación tras pérdida de red, arqueo, relevos y conciliación |
| Anticipos, crédito y gastos | finance/prepayments, credit, expenses | Backend presente; comprobar cobertura de interfaz y flujo completo; no certificar módulo por existencia de endpoint |
| Servicios | finance/services | Backend presente; pendiente recorrido de venta/cobro/anulación y paridad en apps |
| Incidencias | incidents; Flutter lista/detalle; formulario web | Reporte, evaluación, pérdida aprobada y recuperación presentes; contaminación integral ausente |
| Mantenimiento | maintenance; maintenance_screen | Bloqueo, ejecución y liberación presentes; probar inspección independiente y prohibición de liberar por atajo |
| Tienda y lotes | server/src/sales/pos.service.ts, pos.controller.ts; web/public/app.js | Corrección de esta revisión: el backend sí implementa catálogo, surtido y lotes bajo POS, aunque no exista carpeta store. Pendiente paridad Flutter y recorridos integrados; no confundir estructura de directorios con ausencia de funcionalidad |
| Lealtad | customers/loyalty-program; loyalty_programs_screen | Política central y aprobación presentes; canje aún incompleto por devoluciones; vencimiento operativo pendiente |
| QR | qr_flutter y código de cliente | QR visual/identidad presente; scanner de empleados no integrado en dependencias Flutter |
| Premios | GET customers/rewards | Catálogo no acredita reserva, entrega, devolución ni administración completa |
| Promociones | promotions; promotions_screen | Definición, términos, alcance, imagen y aprobación presentes; efecto financiero no terminado |
| Notificaciones | customers/me/notifications | Bandeja presente; sin proveedor push FCM/APNs integrado |
| Web e informes | web/public/app.js; reports/export-documents | Gráficos con valores y exportaciones CSV/XLSX/PDF presentes; pendiente prueba visual, worker, archivos y permisos reales |
| Logs y trazabilidad | audit, observability; main.dart y dlc_api | Bases de logs/correlación presentes; pendiente retención, exportación de diagnósticos y comprobación de redacción de datos sensibles |
| Persistencia y concurrencia | migrations, pg, idempotency, jobs | Diseño presente; RLS del runtime usa políticas permisivas y confía en alcance del backend: no es aislamiento automático por usuario |
| SwiftUI | DLCGasolineras/Services/MockRepository.swift | Prototipo local; regreso a Swift de las dos apps y QA Mac pendientes |
| Pagos y fiscalidad reales | core/env y plan | Integraciones externas diferidas; no sustituirlas con éxito manual/simulado |
| Despliegue y recuperación | infra, scripts | Preparación no acredita backup restaurable, monitoreo, capacidad ni rollback de despliegue |

## Descarga en tanque equivocado: lo que existe y lo que falta

**Ahora existe maestro/detalle de descarga contaminante en web y Flutter, snapshots y pérdidas separadas, aprobaciones y disposición. La ejecución en PostgreSQL/Flutter y la conciliación contable/contractual completa siguen pendientes.** La recepción normal rechaza producto incompatible y tanque diferente al acordado; esa validación evita registrar una recepción incorrecta como si fuera correcta, pero no documenta el accidente que ocurrió físicamente.

### Flujo requerido para terminarlo

1. Preparar entrega vinculada a orden/línea/proveedor/documento; seleccionar tanque previsto y combustible. Mostrar producto, capacidad libre, saldo y unidad configurada. Confirmación previa independiente del tanque físico.
2. Registrar resultado: correcto, entrega parcial, rechazada o descarga en tanque equivocado. En contaminación seleccionar tanque real, cantidad **efectivamente descargada**, cantidad comprada/planificada y remanente. No usar el máximo comprado como pérdida automática.
3. Bajo transacción y bloqueo de orden/línea/tanques/balances, congelar saldo previo, producto previo, producto entrante, unidad, costo histórico y costo contractual. Revalidar sucursal, permisos, capacidad y saldo de orden; comandos idempotentes con hash de todos los datos.
4. Poner **disponible para vender = 0** y mantener volumen físico contaminado en cuarentena. No afirmar “tanque vacío” hasta confirmar retiro medido. Suspender autorizaciones pendientes y evitar cobro/despacho nuevo del tanque bloqueado.
5. Crear dos conceptos separados: pérdida de contenido anterior a costo histórico; pérdida del producto entrante realmente descargado a costo de compra. No sumar pérdida al precio comercial como si fuera costo. Si costo histórico es desconocido, mostrar desconocido y solicitar conciliación, nunca cero inventado.
6. Registrar diferencia contractual: combustible que sigue en camión, devuelto, pendiente por entregar, facturado, no facturado y reclamado. Evitar cargar el mismo combustible a inventario normal y a pérdida a la vez.
7. Aprobación independiente de pérdidas; evidencia, responsables, horarios, cantidades y versión. Bloqueo inmediato no depende de esperar aprobación financiera.
8. Retiro/limpieza/inspección, costos asociados y verificación independiente antes de liberar tanque/boquillas. Recuperaciones de seguro/proveedor se registran aparte del valor bruto de pérdida.
9. Detalle final en web y Flutter: orden, entrega, tanque previsto/real, litros y galones, costos separados, incidente, aprobación, disposición y saldo pendiente. Solo “todo salió bien” para recepción correcta confirmada.

### Ejemplo y casos de aceptación

Tanque con 4.000 L de gasolina; pedido de 3.000 L de diésel; solo 250 L descargados antes de detectarlo. Inventario comercial afectado: 4.000 L anteriores; producto entrante perdido: 250 L; mezcla física: 4.250 L en cuarentena; **2.750 L no se pierden automáticamente**. Su destino se concilia con proveedor. Valorar 4.000 L a costo histórico y 250 L a costo contractual. Mostrar galones usando 1 US gal = 3,785411784 L y reglas de redondeo de presentación.

Probar también tanque inicialmente vacío, producto correcto en tanque incorrecto, descarga total, lectura discrepante, capacidad excedida, dos operadores concurrentes, venta autorizada antes del bloqueo, reintento después de timeout, falta de costo, evidencia ausente, usuario de otra sucursal y autoaprobación. La mezcla no debe convertirse en gasolina/diésel comercial automáticamente.

## Validaciones transversales que deben aceptarse en ejecución

UUID y alcance organización/sucursal; capacidades por acción; cuenta activa; maker/checker; montos decimales exactos; litros/galones; base observada/compensada; fechas y zona horaria; versiones optimistas; claves idempotentes y payload distinto; saldos reservados; límites de pedido y tanque; inmutabilidad de historia; reintentos; cierres y reversos; privacidad de logs y archivos; permisos de exportación; consentimiento y términos comerciales.

Una prueba de texto no acredita estas reglas. Las pruebas de servicios con mocks verifican ramas específicas, no triggers, RLS, carreras ni integridad entre procesos.

## Verificación de esta revisión

- Compilación TypeScript de servidor: pasa.
- ESLint en incidencias e inventario modificados: pasa.
- Pruebas de servicio de incidencias (incluye nueva categoría/bloqueo/reintento), pago de puntos y contrato de puntos: pasan como archivos del harness.
- Sintaxis JavaScript web: pasa.
- SQL 0094/0095: pendiente ejecución en base QA.
- Flutter analyze/build, APK, dispositivos y recorridos web autenticados: pendientes.

## Inventario de controladores

Conteo mecánico de decoradores HTTP, incluido para localizar módulos. No es cobertura de pruebas ni cuenta de flujos aceptados.

| Archivo | Decoradores HTTP |
|---|---:|
| `server/src/auth/auth.controller.ts` | 5 |
| `server/src/auth/users.controller.ts` | 7 |
| `server/src/authorization/approval.controller.ts` | 1 |
| `server/src/branches/branches.controller.ts` | 6 |
| `server/src/customers/customers.controller.ts` | 21 |
| `server/src/cuts/cuts.controller.ts` | 14 |
| `server/src/finance/credit.controller.ts` | 9 |
| `server/src/finance/expenses.controller.ts` | 8 |
| `server/src/health/health.controller.ts` | 2 |
| `server/src/imports/imports.controller.ts` | 2 |
| `server/src/incidents/incidents.controller.ts` | 10 |
| `server/src/infrastructure/infrastructure.controller.ts` | 39 |
| `server/src/inventory/fuel-inventory.controller.ts` | 7 |
| `server/src/maintenance/maintenance.controller.ts` | 14 |
| `server/src/metrics/metrics.controller.ts` | 4 |
| `server/src/pricing/pricing.controller.ts` | 9 |
| `server/src/procurement/planning.controller.ts` | 9 |
| `server/src/procurement/procurement.controller.ts` | 14 |
| `server/src/promotions/promotions.controller.ts` | 13 |
| `server/src/reports/reports.controller.ts` | 13 |
| `server/src/sales/payments.controller.ts` | 15 |
| `server/src/sales/pos.controller.ts` | 21 |
| `server/src/sales/prepayments.controller.ts` | 8 |
| `server/src/sales/sales.controller.ts` | 7 |
| `server/src/sales/services.controller.ts` | 5 |
| `server/src/sales/tax-policy.controller.ts` | 4 |
| `server/src/staff/staff.controller.ts` | 13 |

Estados del plan (incluye niveles agrupadores y tareas; no contar como funcionalidades): {'pending': 39, 'implemented': 3, 'in_progress': 17, 'deferred': 3}.


## Actualización de implementación posterior a esta auditoría
Se añadieron 0096–0098, servicio de contaminación y devoluciones de puntos y pantallas Flutter/web. La sección de hallazgos anterior describe el estado al comienzo de la auditoría: ahora existe registro integral de descarga, costos separados, saldo pendiente, cuarentena, pérdida previa evaluada y pérdida entrante aprobable, disposición y bloqueo de liberación. También existe devolución del tender en puntos con aprobación independiente. Esto NO acredita ejecución de PostgreSQL ni compilación Flutter, ni integra por sí solo todos los reportes contables. Véase HANDOFF_QA_MAQUINA.md para alcance actualizado y pendientes todavía de desarrollo.


## Revalidación de máquina — 9 de octubre de 2026

La copia de trabajo se probó con dependencias locales y sin credenciales externas. Las carpetas originales en Desktop se conservaron intactas.

### Evidencia ejecutada

- TypeScript: `tsc --noEmit` y build: correctos. ESLint: correcto.
- Servidor: 207/207 pruebas unitarias; 89/89 contratos. Pruebas de integración: 3 omitidas automáticamente porque no se configuró `DLC_API_BASE_URL`; no cuentan como recorridos API integrados.
- Web: 12/12 pruebas (contratos y runtime HTTP simulado); `node --check web/public/app.js` pasa.
- Contratos Flutter: 5/5 pruebas Node; pruebas widget Dart: 4 pruebas Dart en Operaciones (1 widget + 3 de QR) y 1 widget en Clientes; `flutter analyze` sin incidencias en ambas apps.
- Android: ambos APK debug compilaron correctamente con Flutter 3.47.5/Dart 3.13.4 y Java 17. No se instaló ni probó en dispositivo físico o emulador. Los APK usan el endpoint de emulador local `10.0.2.2:4000`; Clientes requiere configurar Supabase QA.
- PostgreSQL 18 efímero y descartable: el runner aplicó en limpio las 98 migraciones, de 0001 a 0098. El clúster se detuvo y eliminó. Esto no ejecuta escenarios SQL de negocio ni concurrencia con datos semilla.
- `verify-plan.mjs`, `verify-acceptance-matrix.mjs` y `verify-release.mjs` completan correctamente después de retirar el clúster temporal. La matriz es estructural; no simula cada caso de aceptación.

### Hueco corregido durante esta revalidación

La API de incidencias genéricas ahora rechaza `wrong_tank_delivery` y guía a Compras → Descarga contaminante; las pruebas cubren que no escriba incidentes ni bloqueos. La descarga web obliga a elegir combustible y tanque expresamente (antes podía usar el primero), muestra el nombre del combustible y litros + galones US. Flutter también muestra el nombre y ambas unidades; litros sigue siendo la unidad canónica.

### Límites para QA de aceptación

No se dispone de API QA conectada, usuario de prueba, proveedor Supabase ni dispositivo/emulador conectado; por eso no se probaron login real, viajes API + SQL, concurrencia entre usuarios, push y cobros ni fidelidad visual en pantallas reales. Política comercial de caducidad de puntos devueltos y regla de conciliación volumétrica siguen sin definirse; no se inventaron. La compilación no certifica producción.

Los APK debug y las instrucciones de instalación están en `artifacts/qa-2026-10-09/`.


### Continuación de implementación: escaneo QR en Operaciones

Operaciones ahora escanea el QR de identidad del Cliente con la cámara usando mobile_scanner 7.4.2; el campo manual queda disponible como respaldo. La detección filtra únicamente formato QR, rechaza vacío o más de 200 caracteres y solo rellena el código; el operador aún debe vincularlo antes del cobro y el Cliente autoriza por separado los pagos con puntos. El manifiesto Android final incluye CAMERA. Añadí tres pruebas unitarias de parsing y un contrato Node. Flutter analiza limpio, las cuatro pruebas Dart de Operaciones pasan y el APK se recompiló. No había dispositivo conectado para validar la cámara física. En iOS se debe añadir NSCameraUsageDescription cuando exista el scaffold correspondiente.

## Cierre de revisión de máquina — 9 de octubre de 2026

El estado vigente y la matriz de pendientes están en [`QA_CIERRE_MAQUINA_2026-10-09.md`](QA_CIERRE_MAQUINA_2026-10-09.md). Esta revalidación posterior corrige los recuentos y el último estado aquí arriba: **208 unitarias + 89 contratos de servidor, 13 web, 5 contratos Flutter en Node, 5 pruebas Dart, 42 smokes SQL y 104 migraciones** pasan localmente. Node 24.19.0, TypeScript, build, ESLint, Flutter 3.47.5/Dart 3.13.4, PostgreSQL 18.6 efímero y los tres verificadores del proyecto fueron comprobados.

### Hallazgos corregidos al ejecutar PostgreSQL real

- `validate_customer_point_payment()` fallaba al leer `sales` como `dlc_api_runtime`; el trigger de puntos también tenía un snapshot de venta incompleto y dereferenciaba `NEW.outcome` cuando corría para `customer_point_payments`.
- Los validadores de solicitudes/decisiones de devolución de puntos leían tablas sin grants para el rol runtime.
- Se añadieron migraciones correctivas 0099–0104 con `search_path` fijo, privilegios mínimos, snapshot de sucursal y transición condicional por tabla. El smoke de puntos ahora pasa pago mixto, reembolso monetario parcial y devolución independiente de puntos.
- El flujo de contaminación permitía que el combustible de entrada coincidiera con el combustible existente y trataba el evento como mezcla/pérdida. Ahora API y trigger SQL rechazan esa clasificación; la recepción ordinaria queda separada. Un smoke SQL confirma rechazo mismo-producto y aceptación de combustible incompatible.
- La lista de descargas exponía demasiado pocos datos para auditar quién autorizó las pérdidas y la evidencia de retiro. API/web ahora muestran tanque y combustibles, responsables, montos, motivos, fechas y referencia/notas de disposición. El botón de retiro respeta las aprobaciones previas.
- El ZIP podía incluir archivos `.db` de un caché Windows creado por Flutter. El empaquetador excluye ese árbol y la verificación posterior del ZIP confirmará su ausencia.

### Límites vigentes

El API local respondió salud/readiness y control 401 con correlación: 3/3 pruebas HTTP PASS mediante login de prueba miembro del rol runtime restringido. Esto no valida login real, rutas financieras autenticadas, RLS en Supabase ni concurrencia entre sesiones. No hay proyecto/cuentas Supabase QA ni secrets sandbox. Tampoco hubo navegador visual autenticado, emulador/dispositivo ni lectura QR física. Siguen pendientes los tickets de paridad Flutter F03–F11, premios/campañas transaccionales, política de puntos vencidos/saldo negativo, push/proveedores, fiscalidad y hardware, términos con visto bueno legal y los tres gates SwiftUI/Mac. Esto no está listo para producción.


# Revisión UI/UX y activos operativos — 2026-10-10

## Resultado

Se completó la primera versión funcional de Activos operativos para registrar y controlar terminales POS, medidores, mangueras, herramientas y equipo de seguridad. El inventario queda separado del combustible por tanque y de la mercadería POS por lote. Aceites, refrigerantes y otros productos de venta rápida siguen en Inventario/Tienda.

La pantalla resume unidades por estado e incidencias abiertas y grafica cambios mensuales de los últimos seis meses. Las barras incluyen valores y detalle textual para que el dato no dependa solo del color. Web y la app de Operaciones usan el mismo dominio y permisos; Clientes no recibe controles administrativos que no corresponden a su función.

## Flujos incluidos

- Registrar equipo con código único, tipo, nombre, ubicación y metadatos; el costo se solicita y se devuelve solo a perfiles con permiso explícito.
- Buscar y filtrar por tipo/estado; abrir ficha e historial inmutable.
- Editar ficha con versión esperada para detectar actualizaciones simultáneas.
- Asignar o devolver custodia; cambiar condición, retirar o verificar recuperación; trasladar entre sucursales con autorización en origen y destino.
- Crear incidencias de daño o pérdida enlazadas al activo. Un trigger transaccional pone el equipo dañado en reparación o perdido en estado missing, registra el evento y limpia la custodia cuando corresponde.
- Generar el reporte operational_assets con filtros de fechas y las exportaciones disponibles en el módulo.

## Revisión visual y de interacción

- Se reutilizaron colores, tarjetas, etiquetas y controles existentes para mantener continuidad con las pantallas actuales.
- La actividad se presenta como una serie temporal compacta, con conteos y alternativa textual; no se usa un gráfico circular sin detalle.
- Las acciones aparecen según permisos y estado, y las operaciones sensibles piden nota de auditoría. Los cambios vencidos devuelven conflicto de versión para volver a cargar la ficha.
- Las animaciones son pequeñas y respetan la preferencia del sistema para reducir movimiento; la web también aplica prefers-reduced-motion.
- Filtros y detalles son responsivos; los controles mantienen etiquetas, foco visible y estados legibles sin depender del color.

## Hallazgos corregidos

1. Costo oculto que podía borrarse en una edición. La API podía sustituir por NULL el costo que el usuario no tenía permiso de leer. Ahora no permite enviar ese campo sin permiso y conserva el valor existente cuando se omite. Prueba de regresión añadida.
2. Falta de perfil editable en las vistas nuevas. Web y Operaciones ya permiten editar metadatos con control optimista de versión.
3. Falta de vínculo práctico a incidencias. La ficha ahora ofrece registrar daño o pérdida; la pérdida cambia el estado a missing en la misma transacción de la incidencia.
4. Representación estadística incompleta. Se agregó resumen por estado, incidencia pendiente y actividad por mes tanto al tablero web como a Operaciones; Activos quedó disponible como reporte también en móvil.

## Evidencia de esta revisión

- Servidor: build TypeScript, ESLint, 222 pruebas unitarias y 93 pruebas de contrato.
- Web: sintaxis JavaScript y 15 pruebas web.
- Flutter: flutter analyze sin issues en Operaciones y Clientes; APK debug de Operaciones compilado.
- Contrato Flutter y verificación de paquete fuente: PASS.

## Límites comprobados

- PostgreSQL no responde en localhost:5432 (pg_isready); Docker no está instalado. Por eso la migración 0105_operational_assets.sql y sus triggers aún no se han aplicado ni probado contra un servidor PostgreSQL real. La verificación de release reconoce 105 migraciones y conserva secuencia.
- flutter test no llegó a iniciar: el lanzador Flutter de esta sesión informa que falta PROGRAMFILES(X86). El APK sí compila y el análisis estático pasa. No instalé ni probé en teléfonos/emuladores.
- No hubo recorrido web autenticado en navegador en esta sesión. El módulo se verificó por pruebas, contratos y análisis estático.
- La app de Clientes se revisó a nivel de alcance: el inventario operativo pertenece a empleados/gerencia y no debe aparecer en la experiencia de lealtad del cliente.
- El catálogo de roles debe otorgar estos permisos deliberadamente. operational_asset.cost.read controla la exposición de costos; operational_asset.verify, transfer y retire separan acciones sensibles.
