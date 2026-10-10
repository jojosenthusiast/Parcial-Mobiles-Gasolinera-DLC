# E12.01 — Catálogo y ventas de tienda y servicios

## Operaciones

El catálogo es por sucursal. Cada producto tiene código normalizado, tipo tienda/servicio y control de vencimiento. Nombre, precio y estado se publican como versiones nuevas; una edición exige la versión que se consultó. Código, tipo y control de vencimiento conservan la identidad del producto.

Las recepciones de tienda registran documento, lote, unidades completas, vencimiento cuando corresponda y costo de adquisición si se conoce. Cada recepción produce un movimiento único. El inventario disponible excluye lotes vencidos y conserva su cantidad por separado. La recepción manual es una entrada física documentada; no contabiliza por sí misma una factura, una deuda ni un pago a proveedor.

Una venta POS admite entre una y cincuenta líneas distintas de tienda y servicios. Guarda cantidades, descripción y precio de la versión aceptada. Los productos de tienda se asignan primero a los lotes que vencen antes; entre lotes equivalentes se usa fecha de recepción e ID. Las unidades sin vencimiento se asignan después. Los servicios no descuentan tanques ni inventario de tienda.

El costo de tienda proviene de las asignaciones de lotes. Si cualquiera de los lotes usados tiene costo desconocido, la línea conserva costo desconocido. El costo de servicio es el importe directo por unidad declarado en su versión; no representa todavía distribución de materiales, salarios ni gastos generales. Omitir el costo al editar un servicio conserva el anterior; enviar `null` lo deja desconocido.

La venta y todas sus asignaciones se confirman en una transacción. Una falta de existencias o una versión de precio desactualizada revierte la operación. Los bloqueos por producto siguen un orden estable y se comparten con publicación y recepción. No requieren permiso UPDATE sobre hechos históricos.

## API

| Método | Ruta bajo `/api/v1/branches/{branchId}` | Permiso |
| --- | --- | --- |
| GET | `/pos/catalog` | `pos.catalog.read` |
| GET | `/pos/catalog/{productId}` | `pos.catalog.read` |
| POST | `/pos/catalog/offers` | `pos.catalog.manage` |
| GET | `/pos/catalog/{productId}/lots` | `pos.catalog.read` |
| POST | `/pos/stock/receipts` | `pos.stock.receive` |
| POST | `/sales/pos` | `sale.create` |
| GET | `/sales`, `/sales/{saleId}` | `sale.read` |

El catálogo admite búsqueda por nombre/código, tipo, inclusión de inactivos y cursor. Los lotes también tienen cursor. La ficha consulta el ID exacto y permite leer productos inactivos. Los costos solo se devuelven con `finance.cost.read`. Los nuevos permisos se registran sin asignarlos automáticamente a roles existentes.

El historial devuelve una fila por comprobante. El detalle conserva sus líneas y distingue litros de unidades. Los comprobantes son internos y quedan pendientes de cobro. La venta de combustible existente sigue usando el movimiento del despacho, sin otra salida del tanque.

## iOS

El gerente de sucursal accede al catálogo desde el inicio remoto. El gerente general accede desde la ficha de la sucursal. La navegación muestra acciones según permisos y mantiene las validaciones del servidor.

El flujo incluye búsqueda/filtros, ficha del producto, lotes, recepción, publicación del catálogo y cesta editable. El subtotal mostrado usa Decimal y redondeo por línea; el importe confirmado procede del servidor. Los ViewModels gestionan consultas, cantidades, comandos y resultados.

Antes de enviar una operación, la app guarda su cuerpo y UUID en un archivo protegido y limitado a organización, usuario y sucursal. Ante una respuesta incierta, bloquea nuevas operaciones POS y permite reintentar explícitamente el mismo comando. No sincroniza escrituras automáticamente. Las operaciones guardadas se recuperan al abrir el catálogo; un archivo ilegible bloquea nuevas escrituras y conserva el original. Si la operación se confirma pero no se puede borrar el registro local, el mismo comando sigue siendo seguro para consultar su resultado.

## Datos y verificación

La migración `0020_pos_catalog_and_sales.sql` agrega cuatro tablas y amplía líneas/comprobantes. Mantiene RLS, acceso exclusivo del backend, triggers de inmutabilidad y validaciones de cantidades, costos, totales y asignaciones. Las líneas no pueden añadirse en una transacción posterior al comprobante.

Se ejecutaron 87 pruebas locales de servicios, configuración, adaptadores, aritmética y contratos. Las clases de servicio se ejecutan con sustitutos de infraestructura; no equivalen a levantar Nest. El parseo de diez archivos TypeScript del módulo pasó sin resolver tipos/importaciones ni ejecutar decoradores.

En Supabase pasaron 29 comprobaciones POS, 25 regresiones de venta de combustible y 20 fiscales. Incluyen recepción, venta mixta tienda/servicios, FEFO, costos conocidos/desconocidos, reintentos, comprobante interno combinado, duplicados, vencimiento, ámbito, versión de precio, inmutabilidad y consultas reales. Las filas de prueba se revirtieron. Las migraciones 0084/0085 quedaron aplicadas en DLC con sus checksums en `evidence/E12_combined_receipt_verification.json`; el comprobante combinado quedó habilitado con RLS y lectura/escritura solo para `dlc_api_runtime`.

## Pendientes de E12

- La migración `0084_combined_internal_receipts.sql` y su corrección `0085_combined_receipt_validation_lock.sql` están aplicadas en Supabase y pasaron 25 comprobaciones SQL con fixtures revertidas. La app permite agrupar una venta de combustible y una POS ya registradas en un comprobante interno. Cobros, devoluciones e impuestos permanecen en sus ventas fuente; no constituye una factura fiscal ni una sola operación de pago. Falta compilar y recorrer la interfaz iOS con Xcode.
- Política y desglose fiscal de tienda/servicios; siguen sin configurar hasta contar con tasas y fuente aprobadas.
- HTTP autenticado y concurrencia real de servicios contra PostgreSQL.
- Compilación Xcode, simulador y recuperación móvil después de cerrar/reabrir la app.

Traslados, conteos, devoluciones físicas, pérdidas de tienda y procesos completos de compras/lotes pertenecen a E16. El catálogo, los lotes y las asignaciones de esta entrega son su base; no completan esa etapa.
