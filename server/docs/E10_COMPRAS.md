# E10 — Proveedores y órdenes de compra

## Implementado

- Ficha de proveedor con identificador fiscal normalizado, contacto, días de crédito, estado y ofertas de productos.
- Búsqueda de proveedores y consulta de sus cotizaciones activas.
- Orden por sucursal, proveedor y productos de combustible, con cantidad y precio acordado en litros o galones estadounidenses.
- Validación de proveedor activo, producto ofrecido, producto habilitado en la sucursal y compatibilidad del tanque destino.
- Transiciones controladas `draft → pending_approval → approved → ordered`, además de rechazo y cancelación anterior a una recepción.
- Recepción parcial por línea con referencia documental/de entrega, compartimento, tanque, cantidad física aceptada y cantidad facturada opcional.
- Cada recepción crea una reserva idempotente, registra el movimiento de inventario con el costo recibido y luego consolida cantidades y estado de la orden. Reintentar el mismo comando recupera una recepción pendiente sin duplicar el movimiento.
- El maestro detalle de la orden lista sus líneas y entregas asociadas.
- Registro de factura posterior a una entrega confirmada, validación `subtotal + impuesto = total` y número único por proveedor.
- Pagos parciales idempotentes con referencia externa, método, fecha, saldo y bloqueo de sobrepago.
- Separación de funciones: el usuario que crea una orden no puede aprobarla ni rechazarla.
- Versión optimista, registros de auditoría en la misma transacción y control de duplicidad de número de orden.
- Esquema inicial para entregas, facturas y pagos parciales, con restricciones de integridad para monto, moneda y saldo recibido.

## Pendiente dentro de E10

Todavía no se han modelado el manifiesto completo del camión, varios compartimentos en una sola descarga, mediciones de nivel antes/después, sellos y tolerancias de diferencia, conciliación de las líneas facturadas contra cada entrega, reclamos y costos adicionales de flete. Los importes fiscales se capturan como aparecen en la factura; aún falta una política fiscal validada. Los pagos se registran con referencia externa: no se debitan de caja mientras E12/E18 no implementen esa operación. Las pantallas web/iOS para cotizar, ordenar y recibir no están construidas. La migración aún no se ha aplicado: falta PostgreSQL.

La cantidad de la orden es una obligación comercial estimada. La recepción física debe registrar por separado cantidad medida/facturada, compartimentos, tanque, temperatura, agua, guía y diferencias. Una recepción parcial nunca debe aumentar stock al aprobar una orden; solo una recepción validada puede crear el movimiento de inventario.

## Rutas

- `GET/POST /suppliers`
- `GET/POST /branches/{branchId}/purchase-orders`
- `GET /branches/{branchId}/purchase-orders/{orderId}`
- `POST /branches/{branchId}/purchase-orders/{orderId}/submit`
- `POST /branches/{branchId}/purchase-orders/{orderId}/approve`
- `POST /branches/{branchId}/purchase-orders/{orderId}/reject`
- `POST /branches/{branchId}/purchase-orders/{orderId}/mark-ordered`
- `POST /branches/{branchId}/purchase-orders/{orderId}/receipts`
- `GET/POST /branches/{branchId}/purchase-orders/{orderId}/invoices`
- `POST /branches/{branchId}/supplier-invoices/{invoiceId}/payments`
- `POST /branches/{branchId}/purchase-orders/{orderId}/cancel`

## Verificación

OpenAPI y pruebas de contrato se validan en el entorno disponible. No se ha ejecutado `tsc`, ni la migración SQL contra PostgreSQL, ni pruebas transaccionales/concurrentes; por ello este módulo queda implementado pendiente de validación de ejecución.
