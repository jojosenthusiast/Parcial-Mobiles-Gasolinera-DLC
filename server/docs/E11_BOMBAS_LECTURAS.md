# E11 — Bombas y lecturas acumuladas

## Lecturas implementadas

- Cada manguera tiene un totalizador y una unidad definida por la configuración (`gallon_us` o `liter`).
- La primera captura es una línea base con `expectedVersion: 0`.
- Las siguientes capturas requieren la versión actual y no pueden disminuir respecto a la lectura anterior.
- Un reemplazo/reset usa un endpoint y permiso diferentes, exige motivo y número de serie nuevo y conserva lectura/serie anterior.
- Cada evento incluye autor, hora, solicitud correlacionada y clave idempotente; las lecturas son append-only.
- El detalle del dispensador muestra la última lectura, serie, versión y hora de captura. El historial de manguera lista las lecturas recientes.
- Autorización por importe USD o volumen, con precio versionado del producto/modalidad, vencimiento y reserva en litros.
- Solo se permite un despacho activo por manguera; las reservas de todas las mangueras se descuentan del inventario disponible.
- Estados `authorized → dispensing → posting → completed`, con cancelación antes del inicio. Un resultado incierto conserva la reserva hasta conciliación.
- El cierre registra importe con el precio congelado y publica un movimiento de inventario de venta usando la misma clave idempotente. Reintentar un cierre incompleto recupera el movimiento sin duplicarlo.

## Rutas

- `GET /branches/{branchId}/nozzles/{nozzleId}/meter-readings`
- `POST /branches/{branchId}/nozzles/{nozzleId}/meter-readings/baseline`
- `POST /branches/{branchId}/nozzles/{nozzleId}/meter-readings`
- `POST /branches/{branchId}/nozzles/{nozzleId}/meter-changes`
- `POST /branches/{branchId}/nozzles/{nozzleId}/dispense-authorizations`
- `GET /branches/{branchId}/dispense-authorizations`
- `GET /branches/{branchId}/dispense-authorizations/{authorizationId}`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/start`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/progress`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/complete`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/cancel`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/unknown`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/reconcile-no-flow`

Un despacho desconocido conserva inventario reservado. Si la verificación confirma que sí hubo flujo, `/complete` requiere volumen medido y referencia de evidencia antes de publicar la venta. Si confirma que no hubo flujo, `/reconcile-no-flow` requiere referencia, motivo, versión y `commandId`; el estado pasa a cancelado y libera la reserva. Repetir el mismo comando devuelve el detalle sin duplicar el evento. Este flujo manual documenta una decisión del operador y no consulta ni controla una bomba física.

La lista `GET /branches/{branchId}/dispense-authorizations` requiere `dispense.read`, limita la consulta al tenant y sucursal autorizados, y admite filtros `active`, `authorized`, `dispensing`, `unknown`, `posting`, `completed`, `cancelled` y `expired`. `active` incluye autorizaciones `authorized` solo mientras no venzan, además de operaciones `dispensing`, `unknown` y `posting`; el filtro `expired` también muestra autorizaciones cuya fecha venció aunque su estado persistido aún sea `authorized`. Acepta cursor UUID y `limit` de 1–100. La respuesta contiene la ficha necesaria para recuperar la autorización y sus eventos. Antes de actuar desde una copia cacheada, la app debe volver a leer el detalle actual.

## Pendiente

Las lecturas acumuladas aún no se usan para calcular el volumen completado ni consolidar cortes; el cierre requiere cantidad medida explícita. Los adaptadores manual/simulado, timeout desconocido y consulta/conciliación están implementados; ver E11_ADAPTADORES.md. El contrato físico está definido, pero falta un proveedor real. No hay conciliación de línea, POS ni caja. El maestro detalle todavía no muestra cortes, incidentes y mantenimiento reunidos. Las migraciones 0010, 0011 y 0016 están aplicadas en Supabase DLC.

## Verificación

Las pruebas de adaptadores/coordinación y los constraints SQL remotos pasan. Faltan transacciones/concurrencia de los servicios reales, descenso de medidor, reemplazo/continuidad, TypeScript estricto y build Nest/Xcode. La evidencia distingue pruebas unitarias con stub de pruebas SQL sobre la base real.
