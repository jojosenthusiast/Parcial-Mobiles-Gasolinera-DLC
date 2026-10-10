# Inventario de combustible

La migración `0007_fuel_inventory_ledger.sql` agrega un saldo materializado por tanque y un ledger append-only. Una fila ausente de saldo significa **sin saldo inicial confirmado**; no se interpreta como tanque vacío.

## Operaciones

- Apertura de saldo: una vez por tanque, incluso si empieza en cero. El costo puede quedar como `unknown` o `provisional`; “known” exige costo documentado.
- Recepción: aumenta existencia y acepta referencia documental. El costo total puede quedar desconocido; si se conoce se incorpora al promedio ponderado móvil.
- Venta: descuenta al costo promedio vigente. No acepta costo ingresado manualmente y no puede consumir la reserva no utilizable.
- Pérdida y ajuste: requieren motivo; las salidas usan el costo promedio para reconocer el costo de pérdida. Ajustes de entrada solo recuperan costo conocido si el saldo previo es conocido o está vacío.
- Cada comando tiene UUID idempotente. El mismo UUID y mismo contenido devuelve el movimiento existente; reutilizarlo con otro contenido devuelve conflicto.
- La operación bloquea el tanque, valida que el saldo resultante no sea negativo ni exceda el límite seguro y actualiza saldo, ledger y auditoría en una misma transacción.

## Cantidad y valuación

Se guarda la cantidad original, unidad de entrada y factor exacto de conversión. El galón utilizado es galón estadounidense (`3.785411784 L`). Para volumen compensado se registran aparte volumen observado y compensado, más temperatura medida y de referencia; esta API no calcula por sí misma una corrección ASTM. Las mediciones de agua no se suman al volumen de combustible.

El costo minorista no se usa como costo de inventario. Si el costo de adquisición es desconocido o se mezcló existencia sin costo conocido, la valuación total queda desconocida; no se inventa un promedio a partir del precio de venta.

## Rutas

`GET .../inventory` entrega ficha de saldo y calidad; `GET .../inventory/movements` entrega historial cursor-paginado. Las mutaciones quedan separadas en `opening`, `receipts`, `sales`, `losses` y `adjustments` con permisos distintos.

La migración está escrita, no aplicada. Aún falta PostgreSQL/Nest para probar transacciones, carrera de comandos, capacidad, costo promedio, replay idempotente y triggers. Las ventas todavía no están conectadas al corte de bombas; hasta esa integración, estos endpoints no reciben descuentos automáticamente desde la pantalla local.
