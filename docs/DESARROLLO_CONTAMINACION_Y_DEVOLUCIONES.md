# Descargas contaminantes y devolución de puntos

## Flujo de descarga
Compras → detalle de orden → Descarga con incidencia. Seleccionar línea y tanque real, revisar saldo/costo congelado y capturar cantidad REAL descargada en unidad de compra. Registrar documento y explicación. El servidor toma locks, valida saldo/pedido y guarda incidente, bloqueo y snapshots en una transacción. Si saldo previo es positivo crea evaluación de pérdida. Cantidad entrante se resta del saldo disponible para recibir de la orden.

Incidencias → asignar/evaluar y avanzar a assessed/in_progress → aprobación independiente de pérdida previa → movimiento de inventario a cero una vez resueltas autorizaciones de despacho pendientes. Compras → aprobar pérdida entrante por otra persona. Compras → verificar retiro medido con documento y nota. Mantenimiento → limpieza, inspección independiente y liberación del bloqueo. Registrar pérdidas no certifica retiro; verificar retiro no sustituye mantenimiento.

Volumen disponible para venta cero durante bloqueo. `quarantinedPhysicalEstimateL` conserva mezcla estimada hasta disposición; es una estimación, no una lectura metrológica. Accidentes que exceden capacidad pueden registrarse porque ocurrieron físicamente; la recepción normal conserva límites de capacidad. Costo previo desconocido aparece como desconocido, no cero. Pérdida entrante usa cantidad real por precio contractual. Saldos de pedido, valores históricos y unidades se mantienen como decimales.

Límite: los costos aprobados del producto entrante están en un ledger específico, no constituyen asiento en un sistema contable externo ni resolución contractual automática del proveedor. Para discrepancias o remanente devuelto, conservar documentos y conciliar factura. Nuevas descargas en el mismo tanque en cuarentena se rechazan para impedir doble valoración del contenido previo; ampliaciones de un accidente requieren flujo explícito futuro.

## Devolución de puntos
Cajas → Devoluciones de puntos → buscar venta → solicitar cantidad de puntos → otra persona aprueba/rechaza. Restitución a la cuenta original; no devuelve efectivo ni genera movimientos de caja. Las solicitudes pendientes reservan capacidad de devolución y las rechazadas la liberan. El valor monetario de cada parcialidad se determina por redondeo acumulado de la cantidad original; la devolución final completa devuelve todos los centavos originales.

Un pago con dinero devuelto reversa puntos ganados mediante 0093. Un pago con puntos devuelto restituye puntos gastados mediante 0098. Son conceptos separados. Los registros son inmutables; la aprobación y el ledger se insertan en la misma transacción. Repetir comando con datos cambiados falla. No se reabre la venta para volver a cobrar por haber devuelto puntos.

## Estado de verificación
TypeScript compila, ESLint pasa en módulos modificados, pruebas de servicios pasan para snapshots, remanentes, permisos, scope e idempotencia. Migraciones y smoke SQL preparados sin ejecución. Flutter y QA visual aún sin ejecución. Mantener canje en cero fuera de QA hasta ejecutar las pruebas financieras y resolver expiración/restauración y saldo negativo.
