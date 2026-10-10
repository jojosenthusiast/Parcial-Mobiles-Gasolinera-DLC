# E12.01 — Ventas de combustible

Cada despacho completado puede generar un comprobante interno pendiente de cobro. La operación copia el volumen real, el precio aplicado, su versión y el costo del movimiento original. No consulta el precio vigente ni publica otra salida de inventario.

`POST /branches/{branchId}/sales/from-dispatch` recibe `authorizationId` y `commandId`. Un reintento con la misma clave y contenido devuelve la venta existente. Cambiar el despacho conservando la clave produce conflicto. Otro comando tampoco puede crear un segundo comprobante del mismo despacho. El bloqueo de comando precede al bloqueo del despacho y ambos se liberan al terminar la transacción. Venta, línea y auditoría se guardan juntas.

`GET /branches/{branchId}/sales` permite búsqueda por combustible o ID exacto y paginación de hasta 100 resultados. El cursor conserva los microsegundos de PostgreSQL para no saltar filas cuando las fechas son próximas. Las rutas de detalle y consulta por despacho permiten recuperar el comprobante sin recrearlo; la segunda devuelve `data: null` cuando aún no existe.

La autorización se comprueba en el controlador y en el servicio, incluso al repetir un comando. Los datos se restringen por organización y sucursal. Registrar exige `sale.create`; consultar exige `sale.read`. El detalle oculta costos sin `finance.cost.read`.

## Comprobante interno combinado

`POST /branches/{branchId}/sales/combined-receipts` vincula una venta de combustible y una venta POS existentes mediante un comando idempotente. Solo admite ventas de la misma sucursal sin cobros, anticipos, devoluciones de artículos o crédito comercial previos. Los bloqueos por venta serializan el vínculo frente al inicio de un cobro; cada venta solo puede pertenecer a un comprobante combinado.

`GET /branches/{branchId}/sales/combined-receipts/{receiptId}` devuelve ambas ventas, el total agregado y los estados por separado. También se consulta desde `GET /branches/{branchId}/sales/{saleId}/combined-receipt`; responde `data: null` si aún no existe vínculo. Es un documento interno de dos ventas inmutables: no consolida cobros, impuestos, reembolsos ni cuentas por cobrar y no es una factura fiscal. Los cobros posteriores se registran en cada venta fuente.

## Datos y seguridad

La migración 0017 agrega `sales` y `sale_lines`, ambas con RLS y acceso exclusivo del servidor. Los precios, cantidades y costos quedan inmutables. Las claves foráneas vinculan organización, sucursal, actor, despacho y movimiento. Los triggers rechazan cantidades, precios, fechas o costos distintos de los originales. Una comprobación diferida exige exactamente una línea al confirmar la transacción; no se admite un encabezado huérfano.

El importe es el registrado por el despacho. `netUsd` y `taxUsd` son nulos y `taxStatus` es `unconfigured`: no hay una política fiscal validada. El comprobante se identifica como interno. Esta implementación no calcula ganancias netas ni emite factura fiscal.

Las salidas con costo conocido conservarán también el costo por litro previo a la salida. Los movimientos anteriores no se editan. Si uno de ellos contiene un costo total conocido y un costo unitario ausente, la venta mantiene esa información tal como fue registrada. Un costo desconocido no se reemplaza por cero.

## App

El acceso remoto de sucursal incluye una lista de ventas con búsqueda, carga adicional y maestro–detalle. Un despacho completado permite consultar su comprobante o registrar la venta según los permisos de la cuenta. El comando se conserva al reintentar y al actualizar el despacho. La interfaz mantiene los componentes y colores DLC y utiliza archivos Swift ya registrados en Xcode.

La consulta remota de ventas no usa la persistencia de la demostración local. Requiere una API desplegada y su sesión remota; la conexión directa del teléfono a PostgreSQL no está habilitada.

## Verificación

- 58 pruebas locales aprobadas de contratos, configuración, regresión y orquestación. Los tests de servicio ejecutan la clase real con repositorios stub; no sustituyen una prueba de Nest compilado.
- 25 comprobaciones SQL aprobadas en Supabase: creación con rol de ejecución, comprobante interno combinado, conservación de ventas fuente, duplicados, costos, fiscalidad pendiente, inmutabilidad, restricciones de clientes, línea obligatoria y reversión de fixtures. Las migraciones 0084 y 0085 quedaron aplicadas y sus SHA-256 están registrados en `evidence/E12_combined_receipt_verification.json`.
- Migración y SHA-256 coincidentes: 17 migraciones internas y 50 tablas; sin organizaciones ni ventas de prueba persistentes.
- Asesores de seguridad sin avisos. Rendimiento conserva avisos INFO; requiere revisión con carga y planes reales.

Pendiente: compilación y HTTP de Nest, concurrencia de servicios sobre PostgreSQL, cuenta LOGIN/TLS del servidor, compilación SwiftUI y simulador en Mac. La comprobación sintáctica de TypeScript con decoradores retirados no equivale a typecheck.

## Trabajo restante de E12

E12.01 sigue en progreso: el comprobante interno combinado está implementado en API y móvil, y las migraciones 0084/0085 y la prueba transaccional pasaron en Supabase PostgreSQL 17.11. El recorrido móvil requiere compilación y prueba con Xcode. La fiscalidad POS continúa pendiente; no se configuraron tasas ni se presenta el agregado como documento fiscal. Las líneas de tienda/servicio conservan costos y precios propios. Las devoluciones y anulaciones no devuelven combustible al tanque automáticamente.

E12.02 registra efectivo, tarjeta observada, estados desconocidos, saldos y devoluciones de pagos de venta. El cliente móvil incluye solicitud, revisión independiente y ejecución en caja; quedan pendientes la conexión a terminal físico y la validación HTTP autenticada recurrente. E12.03 incorpora apertura, movimientos, depósitos, arqueo y aprobación independiente de diferencias; conteo intermedio y relevo formal siguen pendientes. E12.04 incluye anticipos y devoluciones en servidor y móvil; su validación externa continúa pendiente. E12.05 contiene revisión de varianzas de caja; faltan permisos efectivos asignados a usuarios y validación autenticada/concurrente. E12 permanece en progreso; el recorrido despacho → venta → cobro → arqueo está conectado en partes y debe validarse integralmente.
