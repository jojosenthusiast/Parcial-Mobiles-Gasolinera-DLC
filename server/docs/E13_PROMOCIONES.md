# Promociones de Clientes

La migración `0088_customer_promotions.sql` agrega borradores versionados, revisión por otra persona, alcances de sucursal/red, fechas y recurrencias, condiciones, socios bancarios, registro de imágenes y bandeja de avisos dentro de la app. Operaciones permite preparar, previsualizar, enviar a revisión, aprobar/rechazar y suspender anuncios. Clientes ve el maestro-detalle de los anuncios publicados y sus avisos internos.

## Estado de publicación

Los anuncios informativos son el único tipo que se puede aprobar y publicar. Los descuentos, cashback y multiplicadores pueden prepararse como borradores, pero la API bloquea su aprobación y la app de Clientes no los anuncia. El POS no recalcula el importe de una venta con reglas de promoción; el trigger de puntos tampoco aplica multiplicadores. Cashback no está conectado a un adquirente/banco para validar elegibilidad, liquidar el beneficio o conciliar topes y presupuesto. Mostrar esos beneficios como activos antes de cerrar esas integraciones expondría a la organización a cobrar importes incorrectos o prometer beneficios no liquidados.

La revisión y aprobación de promociones ahora exige el permiso global `promotion.network.approve`, incluso para borradores de sucursal. Así se permite que un gerente proponga y documente una oferta local, pero la activación queda con Administración General. La pantalla debe mostrar este permiso global para habilitar las acciones de revisión.

Administración General puede acotar una campaña de red por sucursales seleccionadas, por zonas o por ambas (unión), y puede aplicar un umbral de ventas pagadas o litros de combustible de los últimos 30 días. La vista previa consulta las sucursales y las mediciones; la definición guarda el corte temporal y las sucursales que cumplieron, así que la audiencia queda congelada y visible para revisión. Las campañas recurrentes solo se aceptan si las sucursales elegidas comparten la zona horaria configurada.

El umbral usa ventas actualmente pagadas y volumen de líneas de combustible pagadas; no representa el margen ni la venta neta después de devoluciones. Clientes puede filtrar el feed por sucursal, aunque la preferencia no se guarda en su cuenta. Avisos internos se envían a toda la red solo cuando la audiencia contiene todas las sucursales activas. Para avisos de una selección parcial se necesita una sucursal favorita persistida en la cuenta Cliente. Push FCM/APNs sigue pendiente.

La bandeja de notificaciones es interna a la app. No hay integración de notificaciones push (FCM/APNs), registros de tokens de dispositivo ni entrega/reintento con un proveedor móvil.

## Imágenes

En producción configura `SUPABASE_URL`, `SUPABASE_SECRET_KEY` y `PROMOTION_IMAGE_BUCKET` únicamente en el servidor. Crea el bucket indicado como público desde Supabase Storage antes de habilitar esta función; no se crea automáticamente mediante SQL. El servidor valida formato/firma, resolución máxima de 4096×4096 y 8 megapíxeles, tamaño binario de 1 MiB, alcance y pertenencia de la imagen a la organización; usa ruta determinista, registro idempotente y auditoría para que un reintento no produzca archivos repetidos. La llave secreta no debe entrar en Flutter ni en el navegador.

## Validaciones y despliegue

- Fechas de calendario se resuelven en la zona IANA seleccionada; los fines de vigencia incluyen el día completo. Se rechazan intervalos invertidos, fechas inexistentes, zonas inválidas y vigencias mayores a cinco años.
- Recurrencias semanal/mensual se evalúan con la zona de la sucursal; el día mensual que no existe se omite. La vista previa está acotada.
- Tipos de beneficio exigen sus valores, unidades, banco/cap, topes, límites, condiciones y texto alternativo aplicables. La app exige revisar las condiciones antes de guardar y previsualizar antes de crear el borrador.
- Una aprobación requiere otro usuario distinto de quien creó/envió la versión. Las definiciones y los eventos son inmutables/auditados.
- Aplicar `0088_customer_promotions.sql`, `0089_loyalty_program_approval.sql` y `0090_backfill_completed_fuel_sales.sql`; probar RLS, permisos, secuencias concurrentes, bucket, audiencias, publicación y avisos en PostgreSQL/Supabase QA antes del despliegue. Las migraciones no se ejecutaron desde este entorno.
- Flutter/Dart no están instalados en este entorno; la pantalla debe pasar `flutter analyze`, compilación Android y pruebas de dispositivo en la máquina de validación.


## Elegibilidad para pagar con puntos

A 2026-10-10, la API bloquea publicar beneficios financieros y no existe relación de campaña/versión con una venta ni motor que cambie el total del ticket. Por eso el pago con puntos solo opera sobre ventas normales que ya existen; ninguna promoción puede aplicarse al mismo ticket hoy. La política comercial prevista es excluir promociones por defecto. Si se conecta una campaña a ventas, deberá persistir en el ticket la promoción y versión aprobadas y su regla explícita de acumulación (none o with_points); el servidor y los triggers de cotización/confirmación deberán rechazar none o campaña sin snapshot. No confiar solo en esconder el botón en la app.
