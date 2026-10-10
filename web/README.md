# Panel web DLC

Cliente web liviano para el mismo API y la misma base Supabase que usa la app iOS. Requiere Node 24.15 o posterior; el panel no instala paquetes externos.

## Ejecución local

Ejecuta el API primero. Después inicia el panel desde esta carpeta.

```powershell
$env:WEB_API_BASE_URL = "http://localhost:4000/api/v1"
$env:WEB_SESSION_KEY = "use-a-random-secret-at-least-32-bytes-long"
npm start
```

Abre `http://localhost:4173`. Para producción establece `NODE_ENV=production`, `WEB_API_BASE_URL` con HTTPS y una clave aleatoria de al menos 32 bytes. El proxy conserva los tokens en una cookie cifrada, `HttpOnly` y `SameSite=Lax`; las operaciones de escritura exigen el token CSRF de doble envío. El navegador nunca recibe tokens del API. Mantén una sola instancia BFF por sesión hasta añadir coordinación distribuida para refresh; la instancia actual comparte renovaciones concurrentes dentro de su proceso.

## Superficie disponible

- Inicio de sesión, renovación y revocación de sesión; las capacidades salen de `/auth/me/capabilities`.
- Dashboard de red para gerencia general y dashboard de sucursal para perfiles locales.
- Sucursales, cortes, inventario, detalle de bombas/tanques, lecturas de medidor, incidencias, compras, precios, personal, tienda, gastos, mantenimiento y reportes, según permisos del usuario.
- Cambios de precio con vigencia futura: propuesta, aprobación por otra persona y programación; avisos de mercado con zona, fuente y fecha conocida.
- Incidencias con evaluación de daños, costo histórico/referencia para combustible, aprobación independiente y descuento de inventario solo después de aprobar.
- Personal con búsqueda y filtro por estado en el servidor, paginación, alta y cambio de estado; programación/cancelación de turnos, marcación autorizada de entrada/salida y filtro de turnos por un periodo validado de hasta 31 días. Los filtros se conservan en la URL. Los turnos de despacho requieren bomba activa y alcance de infraestructura.
- Administración de cuentas permite buscar usuarios y sus roles dentro del alcance permitido, cambiar el alcance de un rol entre sucursales autorizadas, suspender/reactivar cuentas y revocar sus sesiones. La invitación y el restablecimiento que devuelven tokens de un solo uso siguen bloqueados en producción hasta configurar entrega segura por correo.
- Tienda permite buscar productos y servicios, publicar nuevas versiones de precio/estado, ajustar el surtido y el mínimo por sucursal, revisar alertas, lotes y vencimientos, registrar recepciones, capturar conteos, aprobar ajustes con separación de funciones, clasificar mermas y poner/quitar lotes de cuarentena.
- Caja permite administrar cajas, abrir sesiones, registrar entradas/retiros/depósitos, consultar movimientos y cerrar con efectivo contado y liquidación de tarjeta. El detalle expone valores cero correctamente, esperado/contado/liquidado y variaciones del servidor. También registra cobros de ventas pendientes por efectivo o tarjeta manual/simulada y permite conciliar un resultado de terminal incierto; exige referencia para respuestas de terminal definitivas. La simulación está rotulada y el servidor calcula la conciliación y conserva las revisiones de cierre.
- Alta de sucursales como borradores, ficha de preparación con bloqueos que devuelve el servidor y activación condicionada a su verificación de inventario, activos, precios y personal.
- Asistente de alta reanudable: edición de identidad con control de versión, pasos enlazados a sus módulos y bloqueos calculados en servidor. Personal puede quedar pendiente y retomarse; activar exige al menos una persona activa y una confirmación cuya cantidad coincida con el registro vigente.
- Órdenes de compra de combustible, recepción documentada asociada a tanque y producto, con inventario actualizado únicamente al aceptar la descarga. El panel impide iniciar la orden si faltan combustibles o proveedor activo.
- El alta del proveedor puede asociar combustibles ofrecidos, código y cotización; la ficha muestra esas ofertas y contacto, y permite iniciar una orden precargada. La orden limita sus líneas a los combustibles ofertados por el proveedor elegido y precarga el último precio/unidad cotizados, indicando si la cotización venció.
- Reportes con filtros guardados, snapshot de servidor, descarga CSV/XLSX/PDF, progreso y cancelación.
- La API vuelve a validar permisos, alcance y estado. El panel no implementa lógica de negocio propia.
- La URL conserva módulo y sucursal seleccionada para restaurar el contexto al recargar; el panel solo acepta sucursales que sigan dentro del alcance del usuario.

La ficha de bomba muestra boquillas, producto, modalidad de servicio, tanque conectado y última lectura; desde cada boquilla se abre el historial del totalizador. Los perfiles autorizados pueden crear producto de combustible, habilitarlo en la sucursal, dar de alta tanques y bombas, agregar mangueras y conectar cada una con un tanque compatible. También pueden registrar y resolver bloqueos operativos con causa y resolución. Los límites físicos y permisos se vuelven a validar en el API. Desde una ficha se puede iniciar una incidencia vinculada al activo. El módulo de incidencias permite filtrar por texto y estado, registrar daños al local o a activos, y consultar la cronología que devuelve el servidor. El panel no estima pérdidas: el impacto financiero requiere evaluación y aprobación en los flujos del API.

Algunas áreas siguen siendo de consulta desde esta interfaz. Una acción solo se muestra cuando existe un flujo respaldado por el API; no se ofrecen botones que simulen cambios sin persistencia.

Los módulos muestran datos devueltos por la API; no usan fixtures ni métricas inventadas. Si una operación depende de un permiso ausente, el módulo no aparece. La lista y los detalles conservan el ámbito de sucursal validado en el servidor.

## Tema, países, gráficos y validación

- **Tema claro/oscuro/sistema**: el interruptor de la cabecera (y del login) guarda la preferencia en `localStorage` (`dlc.theme`, con `try/catch`). La paleta vive en variables CSS de `styles.css`; el modo oscuro solo redefine esos tokens (`prefers-color-scheme` salvo que se fuerce claro, y `data-theme="dark"`). `theme.js` se carga como script clásico externo porque la CSP prohíbe scripts en línea.
- **Filtro por país**: el dashboard consolidado combina país y sucursal y consulta `/metrics/network/dashboard?days=&branchId=&countryCode=`. Las opciones salen de `countries` en la respuesta y, si el servidor es anterior, se derivan de la lista de sucursales (país por defecto `SV`). El alta e identidad de sucursal envían `countryCode`.
- **Gráficos**: niveles de tanque por combustible (crítico ≤ 30 %, medio ≤ 60 %, óptimo > 60 %, con texto e icono) y tendencia diaria de ventas en SVG propio, con alternativa textual y sin animación si el sistema pide reducir movimiento. La CSP bloquea atributos `style`; las dimensiones dinámicas usan `data-w`/`data-h` que `panel-ui.js` aplica por CSSOM.
- **Validación en tiempo real**: `panel-ui.js` añade mensajes por campo (`aria-invalid`, `aria-describedby`) y bloquea el envío hasta que el formulario sea válido. Atributos opcionales: `data-msg-min|max|pattern|cross|length`, `data-gt|gte|lt|lte="otroCampo"`, `data-positive` y `data-max-for` (límite según la opción elegida). `data-validate="off"` excluye un formulario y `data-validate="messages"` muestra mensajes sin bloquear.

## Pruebas

```powershell
npm test
```

La prueba de contrato comprueba que el cliente use el prefijo versionado `/api/v1` y el sobre de errores compartido. El entorno de desarrollo restringido donde se creó este panel no permite abrir sockets locales (`listen EPERM`), así que la prueba de extremo a extremo con API y navegador debe ejecutarse en Windows o CI.
