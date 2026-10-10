# Decisión de inventarios y estado Mailjet

Fecha: 2026-10-09
Alcance: DLC Gasolineras, tres dominios de inventario y preparación de cuentas.

## Decisión recomendada

El sistema necesita tres dominios operativos, pero no tres copias del mismo almacén. Cada uno representa hechos diferentes y debe conservar su propio ledger y permisos:

| Dominio | Qué representa | Estado actual | Decisión |
|---|---|---|---|
| Inventario de combustible | Litros físicamente estimados en cada tanque y movimientos de recepción/venta/ajuste/contaminación | Implementado por tanques, movimientos, recepciones y ventas de combustible | Mantener el subledger por tanque. No vender combustible enlatado como producto POS genérico; una venta de combustible debe tener su medición, precio, trazabilidad y flujo de despacho. |
| Inventario de tienda | Artículos que se venden en caja, con lotes, vencimientos, proveedor y FEFO | Implementado: catálogo POS, lotes, movimientos, recepción, ventas, transferencias, conteos, cuarentena y mermas | Incluir aquí aceites, anticongelante, líquido de frenos, limpiaparabrisas, envases vacíos y accesorios vendidos por unidad. Clasificarlos en categorías de catálogo como Lubricantes y fluidos, Accesorios automotrices o Surtido rápido; no crear otro stock para el mismo artículo. |
| Activos operativos | Equipos reutilizables identificables y asignados a una sucursal: terminal POS, medidor de presión, manguera/equipo de aire, herramientas y otros | Falta un registro genérico. Mantenimiento perfila únicamente tanques, dispensadores y boquillas; equipment_damage existe, pero incidencias solo aceptan branch/dispenser/nozzle/tank/sale/other. | Crear Activos operativos como registro patrimonial con historial de movimientos, no como mercadería vendible ni como saldo de lotes. |

Combustible que se entregue a un recipiente debe continuar pasando por un flujo de combustible con cantidad/precio y controles operativos explícitos. No se debe registrar como una botella en inventario de tienda ni generar una salida ficticia del tanque. Antes de admitir esa modalidad hay que validar metrología, impuestos, seguridad y evidencia de despacho con las reglas aplicables.

## Requisitos de Activos operativos

Cada activo debería tener organización/sucursal, código interno, tipo/categoría, descripción, marca/modelo, serie opcional, proveedor y documento de adquisición, fecha/costo opcionales, garantía, ubicación, responsable/custodio y estado (disponible, asignado, en reparación, extraviado, retirado). No se deben almacenar PAN, PIN, credenciales bancarias, llaves de terminal ni secretos de adquirentes; para un POS basta el banco/adquirente y un identificador operativo no secreto.

Los cambios de sucursal, asignación, condición, baja o pérdida necesitan eventos inmutables con actor, hora, motivo y versión optimista. Una incidencia de daño/extravío debe enlazar el activo y su evento; informar el incidente no debe borrar ni dar de baja automáticamente el activo. Un perfil de sucursal puede reportar y consultar sus equipos; una acción de baja o ajuste financiero requiere permiso separado y aprobación independiente según política. Mantenimiento debe poder enlazar órdenes correctivas e inspecciones al mismo activo.

No duplicar proveedores: compras de equipo pueden usar el mismo maestro de proveedores y distinguir tipo comercial. La recepción de equipo crea o actualiza el activo mediante un flujo auditado, sin crear un lote vendible. Para consumibles de operación que no sean activos (rollos, repuestos, guantes), usar lotes de tienda con categoría interna y evitar incluirlos en el surtido de venta si no se venden; si después se requieren existencias internas separadas, diseñar un ledger de suministros antes de habilitar una cuarta lógica de stock.

### Gates mínimos antes de QA

1. Migración con claves foráneas de organización/sucursal, eventos inmutables, comandos idempotentes, control de versión y RLS solo para rol API.
2. API con permisos separados: leer/reportar, registrar/recibir, asignar/transferir, aprobar ajuste/baja; validar scope de sucursal en servicio y DB.
3. Web y Flutter con maestro-detalle, filtros por código/tipo/estado/sucursal, recepción, asignación, transferencia, reporte de daño/extravío y vínculo desde incidencias.
4. Pruebas de concurrencia sobre transferencia y cambio de condición, auditoría, dos actores, permisos cruzados, reintentos y relación incidencia-activo. No aceptar cambios de estado por edición directa ni conteo ficticio.
5. Reporte separado de stock de tienda y activos, con valor oculto salvo permiso de costo.

## Clasificación rápida de productos

La tienda ya permite store_catalog_products.category y los lotes/cobros resuelven pos_stock_lots y sale_lines. Los fluidos y productos automotrices empacados deben vivir en el mismo POS de tienda y aprovechar FEFO, proveedor, recepción, conteo, cuarentena y merma. Se añadió alta con categoría configurable y filtro por categoría en API/OpenAPI, Web y cesta POS móvil; el listado de categorías se obtiene con scope de sucursal. La migración de datos no es necesaria. En productos ya existentes, la categoría continúa siendo dato del catálogo global y no se cambia silenciosamente desde la publicación por sucursal.

## Mailjet: estado real verificado

Mailjet no está configurado ni integrado en la copia: no hay cliente/API de envío ni variables MAILJET_* en los archivos de entorno de ejemplo. La invitación existente crea usuario y token de activación pero, en producción, responde La entrega segura de invitaciones no está configurada. El token se devuelve en la respuesta de desarrollo. El flujo no está listo para probar el alta por correo en producción.

La dirección/correo y la contraseña de inicio de sesión de Mailjet no son la API Key y Secret Key que necesita la API. No se usaron ni se copiaron credenciales. Para cerrar la integración hacen falta API Key/Secret configurados solo en el gestor de secretos del servidor QA, un remitente autorizado y URL pública/deep link de activación. En producción el endpoint debe enviar el token por correo, conservar solo su hash en DB y nunca devolverlo al gerente/API. Debe agregar expiración, límite/rate limit, reenvío idempotente, auditoría sin token y test de entrega en sandbox.

La confirmación de email de Clientes la gestiona Supabase Auth; conectar Mailjet requiere configurar su SMTP en el proyecto Supabase QA, aparte del envío de invitaciones del servidor. Para sender de un dominio propio, verificar remitente/dominio y DKIM/SPF; una dirección de buzón temporal no sustituye esa autorización. No se debe enviar correo real usando credenciales compartidas en conversación.

### Comprobación al 2026-10-09

- Código fuente: búsqueda no encontró integración Mailjet, SMTP, Nodemailer, SendGrid ni Resend; las menciones solo aparecen en handoffs de pendiente.
- Configuración: .env.example, server/.env.example y flutter/.env.example no documentan variables Mailjet.
- Backend: server/src/auth/user-admin.service.ts bloquea invitaciones y restablecimientos en NODE_ENV=production hasta configurar una entrega segura; en desarrollo genera tokens.
- Cliente: el alta depende de Supabase Auth y su correo de verificación; falta SMTP QA de Mailjet y prueba de deep links.
- Resultado: el intento de abrir el navegador de trabajo falló antes de mostrar la sesión por un error de permisos del sandbox (`helper_sandbox_lock_failed`). No se inició sesión ni se modificó la cuenta Mailjet ni se envió correo. Los APK pueden probar login con una cuenta ya configurada, pero no el flujo integral de activación por correo.

## Política y presentación de puntos en compras

- En ventas normales de combustible y artículos POS de tienda, una venta solo gana puntos cuando queda completamente pagada y vinculada a una cuenta Cliente. El SQL calcula la base de puntos con cobros confirmados en efectivo/tarjeta y anticipos capturados; los puntos usados se excluyen. Por ello una compra mixta gana sobre el dinero real pagado, sin contar dos veces la parte canjeada.
- La política de canje vigente controla el valor USD por punto. El API de `/customer/me/loyalty` ahora devuelve esa tasa, si el canje está habilitado y el equivalente disponible en USD, redondeado hacia abajo a centavos por el servidor. La app de Clientes muestra saldo, valor y tasa, y aclara cuando no existe canje activo.
- Evidencia: el smoke SQL de pagos mixtos sobre venta POS ya verifica que usar 500 puntos ($5) y pagar los $5 restantes en efectivo genera únicamente los 5 puntos correspondientes al pago monetario. Se añadieron pruebas unitarias del saldo del cliente y del caso sin tasa de canje.
