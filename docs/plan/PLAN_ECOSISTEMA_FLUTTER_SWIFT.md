# DLC: plan de implementación y validación del ecosistema

Fecha: 8 de octubre de 2026. Decisión del usuario: Swift actual → Flutter → APK y pruebas humanas → correcciones → regreso a Swift para entrega. Este documento cambia el orden de ejecución del plan anterior; no borra requisitos ni convierte tareas pendientes en completadas.

## 1. Resultado que se debe entregar

Un mismo sistema de gasolineras con backend NestJS/PostgreSQL en Supabase, dos aplicaciones móviles y panel administrativo. Las dos apps serán DLC Operaciones (personal, gerentes, caja, pista) y DLC Clientes (cuenta pública, puntos, recompensas, promociones). Flutter permite probar ambas en Android desde Windows; la entrega móvil final será SwiftUI. El panel web se construye con la interfaz adaptable de Operaciones en Flutter y permanece web; no se vuelve a Swift.

La primera entrega de implementación debe ser instalable y permitir un recorrido útil: iniciar sesión, ver dashboard por rol, abrir sucursal/bomba, consultar detalle y registrar una incidencia. Después se incorporan flujos completos. No esperar a completar todo el backend para mostrar pantallas conectadas. No entregar botones decorativos, un menú enorme sin operaciones ni un repositorio de datos ficticios presentado como producción.

Fiscalidad avanzada y conexión física del terminal POS quedan al final por decisión del usuario. El POS existente, caja, ventas, cobros manuales y comprobantes internos se conservan y se conectan: son necesarios para probar ventas, descuentos y puntos. Un adaptador de terminal puede simular resultados únicamente en QA identificado. Impuestos sin configurar son `null`/estado `unconfigured`, nunca 0% ni una exención inventada. Ningún recibo simulado se presenta como factura fiscal.

## 2. Base inspeccionada y reutilización

Copia de trabajo actual: `handoff_e12/DLCGasolineras_Laboratorio22`. En el ZIP entregado esta carpeta es la raíz del proyecto. La copia hermana y planes antiguos no son la fuente activa. Si al retomar existen cambios más recientes, conservarlos y comparar solamente los archivos afectados.

Se inspeccionaron los servicios de autenticación, personal, mantenimiento, precios y reportes. Hay 85 migraciones SQL hasta `0085_combined_receipt_validation_lock.sql`; no existe aún `pubspec.yaml` en el árbol revisado. Hay API de equipos/mantenimiento, empleados/turnos, precios, tienda/POS, caja, pagos, anticipos, reportes PDF/XLSX y comprobante combinado. Esto acredita código disponible para reutilizar, no aceptación funcional de todo ese código.

| Base existente | Trabajo siguiente |
|---|---|
| `server/src/auth` y `authorization` | Conservar sesiones internas y capacidades; agregar política temporal de acceso y ámbito cliente separado |
| `branches`, `infrastructure` | Alta guiada, región comercial, parque real de bombas, puntos de servicio, ficha de bomba |
| `maintenance`, `incidents` | Equipos auxiliares, piezas dañadas, inspecciones, disponibilidad y acceso rápido |
| `inventory`, `sales/pos` | Stock de consumo interno y préstamo; reutilizar movimientos/costos cuando correspondan |
| `pricing` | Promociones recurrentes aprobadas; precios efectivos históricos y simulación previa |
| `staff` | Restringir acceso por turno y permisos excepcionales, también con sesión ya abierta |
| `reports` | Reutilizar PDF/XLSX/jobs; conectar descargas en Android, Windows y navegador |
| `metrics`, `procurement`, `finance`, `cuts` | Portar flujos y cerrar pendientes originales con resultados visibles |
| SwiftUI actual | Referencia de marca, comportamiento y contratos; destino final de los flujos aceptados |
| `web` existente | Referencia funcional; la nueva interfaz Flutter debe alcanzar su cobertura antes de sustituirla |

La autenticación actual del personal usa sesiones y tokens propios en la API. No reemplazarla por Supabase Auth incidentalmente. Clientes tendrán un ámbito de identidad separado; decisión: Supabase Auth para registro público verificado y recuperación, validado por un guard propio de clientes en NestJS. Se mantiene la misma base del proyecto DLC. No vincular empleado y cliente automáticamente por correo ni aceptar tokens de clientes en endpoints internos.

## 3. Forma de trabajar para obtener avance visible

1. Leer este plan, `ESTADO_FLUTTER.json` y el ticket activo. Leer después únicamente el código de ese flujo y el requisito anterior asociado. No repetir una auditoría completa cada turno.
2. Implementar una unidad vertical: datos/contrato → API → pantalla → acción → actualización persistente → mensajes de error. Cada ticket indica la ruta que Carlos podrá recorrer.
3. Durante construcción: análisis/compilación de archivos afectados y comprobaciones breves en reglas de dinero, permisos, inventario e idempotencia. No ejecutar todas las suites después de cambios cosméticos ni escribir tests que solo busquen nombres de archivos.
4. La validación integral con dos usuarios, dos apps, concurrencia, dispositivos y exploración humana se concentra en F13. Dejar preparados los casos y datos desde el principio. No marcar pruebas no ejecutadas como PASS.
5. Una revisión de código no sustituye una APK. F01 entrega la primera APK funcional; siguientes incrementos actualizan esa APK. No detener la implementación independiente esperando que Carlos pruebe cada entrega.
6. Si una subtarea crece sin producir comportamiento visible, dividirla por recorrido. Si falla una herramienta varias veces, documentar la causa concreta y avanzar otra tarea ejecutable; no gastar una sesión entera repitiendo el mismo comando.
7. Mantener un solo resumen breve por bloque: qué puede hacer ahora el usuario, ruta, comprobación ejecutada, siguiente ticket. No regenerar un ZIP completo por cada pequeño cambio.
8. No usar Mac/Xcode como bloqueo de Flutter. La compilación iOS es un gate propio de la fase de regreso a Swift. No certificarla por haber probado Android.

Estados: `pending`, `in_progress`, `implemented`, `build_verified`, `human_accepted`, `blocked`, `deferred`. `implemented` necesita pantalla y operación conectada; `human_accepted` necesita resultado real de Carlos. Un bloqueo no elimina el ticket. Registrar rutas, archivos, criterios, resultado y defecto relacionado.

## 4. Arquitectura de la transición

- `flutter/apps/dlc_operations`: Android, web y Windows; misma lógica de presentación, layout según tamaño y rol.
- `flutter/apps/dlc_customers`: Android inicialmente; aplicación y almacenamiento de sesión separados.
- `flutter/packages/dlc_ui`: colores, tipografía, iconos, componentes, animaciones y accesibilidad.
- `flutter/packages/dlc_api`: DTO, cliente HTTP, errores, paginación, idempotencia y serialización decimal.
- `flutter/packages/dlc_core`: unidades, fechas, interfaces de sesión/diagnóstico. No colocar reglas de negocio autoritativas en widgets.
- `contracts`: OpenAPI, ejemplos de respuestas, vectores de negocio y catálogo de recorridos independientes de plataforma.
- `server/src`: extender módulos actuales; agregar `loyalty`, `campaigns` y `customer-auth` según corresponda.
- SwiftUI conserva proyecto existente, assets y compatibilidad. Crear el segundo target/proyecto de clientes en F14 con identidad propia.

Usar MVVM, repositorios y navegación declarativa. Selección prevista: ChangeNotifier/Listenable para ViewModels y go_router para rutas, sin combinar varios gestores de estado. Verificar y fijar SDK y paquetes compatibles al ejecutar F00; no seleccionar versiones de memoria. No introducir generación de código si cuesta más que los DTO necesarios.

La API sigue siendo autoridad en dinero, disponibilidad, permisos, precios, puntos e inventario. Decimales viajan como texto. Guardar fecha en UTC y calcular turnos/recurrencia con zona IANA de sucursal; El Salvador usa `America/El_Salvador`. Una preferencia L/gal cambia la presentación y captura, no el significado de datos históricos. Galón estadounidense: 3.785411784 L; identificarlo en ayuda de unidades.

Persistencia móvil: sesión en almacenamiento seguro del SO, renovación coordinada, cierre explícito y limpieza al revocar. Caché aislada por cuenta/sucursal con fecha; borrar datos sensibles al salir. Revalidar sesión al abrir y retomar. Web: adaptación de sesión con cookie HttpOnly/Secure y defensa CSRF/origen para renovación, o solución equivalente documentada antes de implementar; no guardar refresh tokens duraderos en localStorage. Nunca incluir claves de servicio en APK/web.

Sin conexión se permiten lectura identificada como desactualizada y borradores. No confirmar ventas, canjes, autorizaciones, cierres o promociones sin servidor. Tras timeout consultar el mismo comando antes de reintentar; no crear otro identificador y duplicar el movimiento.

## 5. Roles y autorización

| Usuario | Operaciones permitidas | Límites |
|---|---|---|
| Gerente general | Red, políticas, aprobación de precios/promociones/puntos, usuarios, reportes y auditoría | Aprobaciones de alto impacto por otra persona; cambios trazables |
| Gerente de sucursal | Operación, equipos, turnos, incidencias, propuestas/promociones locales autorizadas | Solo sucursales asignadas; sin ampliar límites de red |
| Despachador | Bombas habilitadas, despacho autorizado, identificación de cliente, incidencia/inspección rápida | Turno y sucursal válidos; sin modificar precio/puntos |
| Cajero | Caja propia, cobros, canjes confirmados, tickets, devoluciones autorizadas | Turno activo y permisos; no aprobar su propia excepción |
| Mantenimiento | Activos, órdenes, inspecciones, reparación, solicitud de liberación | Sin caja, clientes ni precios; liberar activos críticos exige revisión definida |
| Cliente | Perfil propio, QR, puntos, historial propio, premios y campañas publicadas | Sin datos internos ni creación de movimientos de puntos |

Permisos en servidor, no únicamente ocultando botones. Los roles operativos son capacidades del mismo producto; no crear una app móvil por cada empleado. La ubicación no determina el rol. Puede sugerir sucursal al cliente o aportar señal de presencia al empleado, con permiso explícito. No bloquear a un cliente por estar lejos de una estación ni tratar GPS como prueba infalible.

### Acceso fuera de turno

Empleado activo + pertenencia vigente + turno activo + capacidad son necesarios. General manager puede tener política explícita de acceso sin turno; no extender esa excepción a todos los administradores por defecto. Usar horario de servidor, intervalos `[inicio, fin)`, turnos nocturnos y cambios/cancelaciones efectivos inmediatamente. No conceder minutos de gracia implícitos.

Comprobar política en login, refresh y comandos protegidos. Al vencer turno, bloquear nuevas operaciones aunque la sesión ya estuviera abierta. La pantalla limitada informa el horario y permite solicitar excepción/cerrar sesión; no concede acceso operativo. Conservar borradores y comandos inciertos para conciliación, no descartarlos. Una transacción ya aceptada se finaliza en servidor y queda consultable por personal autorizado.

Excepción: empleado, sucursal, capacidades concretas, motivo, solicitante, aprobador distinto, inicio, expiración, máximo de usos opcional, revocación y auditoría. Alcance mínimo; no existe bypass universal. Expira por hora del servidor sin depender de cron ni del teléfono. Auditoría registra el permiso excepcional utilizado en cada comando. Solicitar excepción no otorga la excepción.

Geocerca opcional/configurable después de turno/permisos: radio y precisión aceptables, momento de medición, manejo de ubicación denegada y alternativa supervisada. No exigir GPS continuo ni guardar trayectorias. Emergencias: instrucciones/contactos accesibles, y canal limitado para reportar; no desbloquea caja ni permite dispensar sin autorización.

## 6. Equipos, puntos de servicio e inventario interno

Distinguir bomba de combustible, equipo físico, ubicación y servicio ofrecido. La infraestructura ya existente se extiende, no se replica en un catálogo incompatible.

Un equipo puede estar junto a una bomba, en isla compartida, taller, tienda o punto independiente. Compresor compartido puede abastecer varios puntos; registrar dependencias y no duplicar su existencia física. Una bomba puede no tener aire. El estado del aire no agota combustible ni bloquea automáticamente el despacho: el bloqueo depende del riesgo y una regla explícita. Una falla de tanque/línea puede afectar varios surtidores conectados.

Dos dimensiones persistidas:
- Habilitación: `enabled`, `disabled`.
- Condición: `operational`, `degraded`, `faulty`, `maintenance`, `retired`, `unknown`.

Disponibilidad derivada = habilitado + condición apta + dependencias aptas + sin bloqueo aplicable. La UI muestra “Desactivado”, “Dañado: manguera” o “Fuera de servicio” con causa; no cinco booleanos contradictorios. `unknown` no equivale a seguro/funcional. Daño exige componente afectado, descripción, fecha, autor y severidad; foto opcional. Cierre exige reparación/revisión y queda en historial.

Catálogos iniciales editables: compresor, manguera de aire, medidor/manómetro, toma de agua, ducha de emergencia, lavaojos, extintor, terminal POS, limpiaparabrisas, basurero, teléfono, señales de no fumar/no usar teléfono, conos y barreras, lapiceros, bidones y recipientes graduados. Registrar cantidad, unidad, ubicación, responsable, fabricante/serie cuando aplique, condición, inspección y vínculo a mantenimiento. Extintor incluye tipo/agente, capacidad y fechas documentales; vencimiento o inspección no se calcula con plazos legales inventados.

Separar stock vendible, consumible interno, activo retornable y equipo serializado. Aceite, líquido limpiaparabrisas, anticongelante y líquido de frenos pueden tener SKU de tienda y movimientos de consumo interno: no duplicar stock. Lotes, caducidad y unidad donde aplique. Recipientes: capacidad/unidad, condición, asignación/préstamo y devolución si se prestan; no aprobar idoneidad para combustible basándose solo en su nombre.

Movimientos: entrada, consumo, préstamo, devolución, traslado, daño, ajuste aprobado y baja. Sin stock negativo; baja no borra historia; conteos muestran diferencia y requieren motivo. Listado filtrable por sucursal, ubicación, clase, estado, disponibilidad y fecha de revisión. Detalle con existencias, movimientos, documentos y acciones pertinentes.

Inspección rápida por turno: selección de plantilla y ubicación, lectura/resultado cuando aplique, anomalía → incidencia ya vinculada. No prellenar “todo bien”. Revisiones de vehículo registran servicio/insumo usado y consentimiento si corresponde; no inferir diagnósticos mecánicos ni mezclar esos líquidos con inventario de combustible.

Ficha de bomba: identificación, productos/mangueras, tanque origen, servicio completo/autoservicio, precio vigente, estado y causa, corte/lecturas, gráficos con unidades, equipos asociados, historial/auditoría y acciones contextuales. Incidencia en dos acciones desde la ficha; no pedir de nuevo sucursal/bomba.

## 7. Alta de sucursal y precios

Wizard reanudable: identidad/dirección → departamento/municipio y zona comercial occidental/central/oriental → horario y cortes → combustibles/tanques → bombas/mangueras/modos → precios → equipos/servicios → usuarios/turnos → resumen y activación. Ubicación y zona comercial son campos distintos y verificables. No deducir reglas de precio de la coordenada sin confirmación.

Plantilla rápida permite seis bombas y tres familias para Lab22; operación real permite parque y productos reales. Saltar conserva estado borrador; activar exige datos operativos mínimos y muestra lo pendiente. No inventar empleados, tanques o precios para completar el wizard. Seis bombas y dos cortes se mantienen en el perfil académico; parque variable en operativo. Menos de cuatro bombas no implica criticidad por sí solo.

Precio: producto + sucursal/zona + modo de servicio + vigencia. Puede adoptar referencia estándar aprobada o precio propio aprobado, con diferencial explícito por modo. Los centavos mencionados por Carlos son ejemplos configurables, no constantes. Guardar fuente de referencia, fecha, aprobación y versión. Mostrar el precio realmente aplicable y la unidad. Un anuncio de subida/bajada es una referencia futura hasta confirmar precio/vigencia; compras conservan su costo real por lote.

## 8. Descuentos y promociones recurrentes

Entidad distinta de banner publicitario. Campos: nombre/motivo, propietario, alcance red/zona/sucursal, combustibles, modo, monto por unidad o porcentaje, inicio/fin, zona horaria, recurrencia, prioridad, límites por operación/cliente/presupuesto, combinación permitida y aprobadores. El precio final jamás negativo. No permitir descuentos por debajo del piso comercial configurado; excepciones requieren aprobación específica. Sin costo conocido no afirmar margen exacto.

Estados: borrador → propuesta → aprobada/programada → activa → finalizada; suspensión/cancelación con motivo. Editar una versión aprobada crea nueva versión pendiente. Solicitar y aprobar son actores distintos. Gerente local dentro de límites de red; fuera de límites escala a general. No permitir edición directa del precio de una venta cerrada.

Recurrencias iniciales: una vez; días seleccionados de semana dentro de rango; día N del mes. “Miércoles de una semana” necesita rango de esa semana; “20 de cada mes” usa calendario de sucursal. Día inexistente se omite, no se mueve al último día silenciosamente. Ventanas nocturnas se anclan al día de inicio. Previsualizar al menos diez próximas ocurrencias o todas si son menos y señalar solapamientos.

Primera versión no acumula descuentos automáticamente: elegir una promoción elegible con prioridad explícita; rechazar empates ambiguos y mostrar motivo de exclusión. El administrador puede autorizar combinación con puntos mediante política versionada. Evaluación se hace con hora del servidor en cada cotización, incluso si falla el worker. Worker envía recordatorios idempotentes de aprobación pendiente, comienzo, fin y presupuesto; inbox en app primero, push opcional al configurar proveedor.

Fijar precio/promoción en autorización/cotización con vencimiento y versión; confirmar valida vigencia y presupuesto de forma atómica. Si precio cambia antes de aceptar, pedir confirmación del nuevo importe. Si despacho ya fue autorizado válidamente, usar su snapshot según contrato; al caducar sin despacho, recotizar. No recalcular ventas históricas con la promoción actual. Devoluciones recuperan exactamente la parte del descuento original correspondiente.

## 9. Clientes, puntos y recompensas

### Identidad y experiencia

App independiente con libre registro, verificación de correo, recuperación, sesión persistente y cierre. Campos mínimos: nombre, correo; teléfono opcional salvo un uso que lo requiera. Sin documentos personales o cumpleaños obligatorios para ganar puntos. Términos y consentimiento de comunicaciones separados. Revocación de sesiones, bloqueo de cuenta por causa auditable y gestión de privacidad. Nunca guardar contraseñas en el backend propio.

Cliente público no se crea como empleado. Guard de clientes verifica emisor/firma/audiencia/expiración del token y consulta estado del cliente. Organización/programa se resuelve por configuración del servidor, no por parámetro libre. Roles internos nunca proceden de `user_metadata` editable. Pruebas finales deben intentar cruzar ambas fronteras de autenticación.

Pantallas: inicio con campañas destacadas, tarjeta de saldo/QR, movimientos, catálogo de recompensas, detalle/canje, sucursales con servicios y perfil/soporte. Mostrar puntos disponibles, pendientes, reservados y próximos a vencer separados. Historial explica origen y reversos. Ubicación opcional para ordenar sucursales; ofrecer búsqueda manual.

QR/código de cuenta identifica al cliente, no autoriza gastar puntos. Código opaco no secuencial, sin correo/teléfono/JWT. QR dinámico de un solo uso para canje con nonce y TTL; confirmación por sesión del cliente o reto equivalente autorizado. Alternativa de código escrito incluye confirmación del dueño para canjear. No usar número de cuenta o captura del QR de identificación como autorización de canje.

### Motor de puntos

Configuración por programa/versiones: puntos por USD elegible, valor monetario por punto para descuentos, productos/servicios incluidos, sucursales, mínimos, máximos, redondeo, vencimiento, reglas de combinación, presupuesto y recompensas. No confundir puntos ganados con centavos descontados. Ejemplo solo QA: 1 punto/USD y 10 puntos = USD 1 representan hasta 10 centavos/USD; no activar esa rentabilidad en negocio sin aprobarla.

Ganar al confirmar venta pagada elegible; anticipos, pagos desconocidos y borradores no ganan. Base excluye monto pagado con puntos, descuentos y conceptos no elegibles. Guardar explícitamente la base de acumulación; si depende de impuestos todavía sin configurar, el programa debe quedar desactivado o usar política QA claramente indicada. Un recibo combinado no vuelve a acreditar sus ventas fuente.

Libro inmutable: `earn`, `reserve`, `redeem`, `release`, `expire`, `reverse`, `adjust`. Saldo se obtiene del libro/proyección conciliable, no de un campo que el móvil pueda editar. Identificador único de origen evita doble acumulación. Política/cotización se congela por operación; cambiar tasa no revalúa puntos/ventas antiguas silenciosamente.

Canje: cotizar beneficio → confirmar cliente → reservar puntos y cupo/stock → vincular a venta → consumir al completar → liberar al cancelar/vencer. Estado incierto se consulta, no se libera a ciegas mientras venta puede confirmarse. Orden de bloqueos consistente y comando idempotente. Nunca dos canjes concurrentes consumen el mismo saldo. Premios físicos usan inventario y entrega registrada; no puede prometerse stock inexistente.

Devoluciones parciales: revertir puntos ganados proporcionalmente al origen; restaurar puntos usados según política original, sin convertirlos automáticamente en efectivo. Si ya se gastaron puntos ganados, registrar deuda/ajuste trazable y bloquear nuevos canjes hasta resolver; no borrar el movimiento ni descontar dinero adicional sin autorización. Vencimiento y ajustes manuales requieren evento, motivo y aprobación según importe.

Abuso: límites de intentos de QR/código, no revelar existencia de cuentas, duplicados de venta, misma referencia externa, autoasignación por empleado, ajustes frecuentes y montos atípicos. Alertas para revisión, no declarar fraude probado automáticamente.

### Administración integrada

Desde Operaciones: configurar programa y versiones, aprobar tasas, crear premios con imagen y disponibilidad, consultar movimientos por cliente bajo permiso, aprobar ajustes y ver costo comercial de beneficios. Gerente local administra campañas/recompensas de su ámbito dentro de política de red. Analítica: emitidos, canjeados, vencidos, saldo pendiente, costo de premios y ventas asociadas; no confundir saldo de puntos con efectivo ni “ganancia”.

## 10. Campañas y carruseles sin programar cada evento

Gestor en Operaciones: título, imagen, texto alternativo, descripción, público, red/sucursal, fechas, orden, enlace interno permitido y promoción/recompensa relacionada opcional. Flujo borrador/vista previa/aprobación/programación/publicación/pausa/archivo. El gerente local no publica para toda la red. Toda modificación genera versión y auditoría; expirada desaparece automáticamente según reloj del servidor.

Storage: validar tipo real, tamaño y dimensiones; eliminar metadatos sensibles, controlar propiedad y ámbito. Borradores privados; publicar únicamente derivados autorizados. No SVG/HTML arbitrario ni enlaces que ejecuten contenido. Imagen accesible con texto alternativo, fallback y política de caché/versionado. Una campaña no modifica precios por sí misma.

Carrusel en parte superior del dashboard del cliente, con indicador, pausa y navegación manual; sin desplazamiento obligatorio ni ocultar alertas importantes en carrusel. Atribución simple y agregada, sin datos personales innecesarios. Previsualizar escritorio/teléfono antes de publicar. Al no haber campañas se elimina ese espacio, sin banner vacío.

## 11. Navegación, gráficos y movimiento

Conservar gota DLC y paleta crema/naranja/verde; extraer assets/tokens de Swift actual. No sustituir por una plantilla corporativa genérica. Operaciones: Inicio, Operación, Gestión, Reportes y Cuenta adaptados a capacidad; en escritorio sidebar y maestro/detalle simultáneos. Clientes: Inicio, Puntos, Premios, Sucursales, Cuenta. Máximo dos acciones desde listado a detalle/acción frecuente; búsqueda, filtros visibles, paginación y retorno con posición/filtros conservados.

Dashboard sucursal prioriza turno, corte, bombas disponibles, combustible/autonomía, incidencias y acciones urgentes. General prioriza red, excepciones, comparación sucursales, ventas/consumo/margen cuando datos suficientes, filtros y procedencia/actualización. No poner todo el sistema en una sola pantalla. Métricas financieras históricas distinguen cierre consolidado de actividad provisional.

Gráficos según dato: línea para tendencia, barras para productos/sucursales, apiladas para composición, progreso para tanques, calendario/heatmap para patrón horario solo con cobertura suficiente. Etiquetas, ejes/unidades, tooltip, periodo y alternativa tabular. Pulsar abre registros fuente filtrados. No usar tortas para series temporales ni curvas inventadas por interpolación como datos observados. Mostrar cobertura insuficiente y denominadores.

Animaciones de transición/listado y expansión de tarjetas, actualización de gráficos y scroll con encabezados; valores orientativos 180–300 ms, sin reproducir toda la animación en cada rebuild. Reducir movimiento según sistema; estados también por texto/icono, tipografía escalable, foco/teclado en web, listas virtualizadas y reducción de imágenes para evitar tirones. Nunca demorar una acción de emergencia esperando animación.

## 12. Reportes, exportación y diagnóstico

Conectar servicios PDF/XLSX existentes antes de crear otro motor. Filtros compartidos entre pantalla, gráfico y exportación; snapshot estable con periodo, sucursal, zona horaria, unidad, usuario autorizado y fecha de generación. XLSX con números/fechas reales y texto saneado; PDF paginado con encabezados legibles. Jobs visibles: cola, progreso, cancelar, error/reintentar, descarga con caducidad y permiso comprobado de nuevo.

Reportes: ventas/producto/modo, compras/costos, inventario/lotes, cortes/conciliación, pérdidas/incidencias, activos/disponibilidad, consumo interno, caja/pagos, personal/turnos/excepciones, promociones, puntos/premios y auditoría. General filtra red/sucursal; local solo su ámbito. No exportar datos de clientes completos por defecto.

Diagnóstico desde ambas apps: versión/build, entorno, fecha, dispositivo/OS, última acción y correlationId. Capturar error Flutter y respuestas API con redacción de tokens, contraseñas, QR, datos personales y pago. Botón “Exportar diagnóstico” genera paquete de texto/JSON limitado y permite compartirlo; nunca incluye claves. Defectos humanos se registran con recorrido, esperado, real, build y prioridad.

## 13. Secuencia ejecutable

| Fase | Resultado visible | Reutiliza | Dependencia |
|---|---|---|---|
| F00 | Base Flutter, contratos/pantallas inventariados y arranque Windows documentado | E00–E06 | Ninguna |
| F01 | Primera APK Operaciones: login, dashboard, bomba/detalle/incidencia, diagnóstico | E03,E06,E11,E14,E20 | F00 |
| F02 | Sucursal guiada, combustibles/bombas y precios por zona/modo | E04,E07,E09,E11 | F01 |
| F03 | Equipos, aire/agua/emergencias, inventario interno e inspecciones | E14–E16 | F02 |
| F04 | Personal/turnos, bloqueo de acceso y permisos temporales | E03,E17 | F01 |
| F05 | Combustible completo: compras, recepción, inventario, despacho, caja/cortes | E05,E08,E10–E13 | F02,F04 |
| F06 | Promociones aprobadas y recurrentes con precio congelado | E09,E12 | F05 |
| F07 | Segunda APK Clientes: registro, sesión, sucursales, QR e historial | E03 + extensión | F01,F02 |
| F08 | Puntos/premios/canje y gestión desde Operaciones | E12,E16 + extensión | F05,F07 |
| F09 | Gestor de campañas y carrusel publicado en Clientes | E20 + extensión | F07,F08 |
| F10 | Tienda, proveedores, gastos/crédito, mantenimiento y abastecimiento completos | E14–E19 | F03,F05 |
| F11 | Panel Flutter web, gráficos, filtros, PDF/XLSX y acabado de interacción | E20–E22 | F06,F08,F09,F10 |
| F12 | Operación/configuración reproducible, conexión QA y paquetes APK | E23,E24 | F11 |
| F13 | Pruebas humanas de ambas APK, fixes e integración/concurrencia final | E24 | F12 |
| F14 | Portar la versión aceptada a SwiftUI en ambas apps y QA iOS | E06,E24 | F13 |
| F15 | Fiscalidad/integraciones reales pospuestas y aceptación de producción | E09.04,E12.01,E23 | F14 |

F07 puede avanzar tras F02 sin esperar F06 si existe bloqueo independiente. El motor de puntos F08 no puede validar ventas contra mocks ocultos. F13 no obliga a esperar para proporcionar APK: F01 y cada bloque dejan artefacto instalable disponible. F15 puede permanecer aplazado para entrega académica si no es requisito de rúbrica; no declara aptitud fiscal de producción.

Cada fase se divide en tickets concretos dentro de `ESTADO_FLUTTER.json`. No hay cronograma en horas prometido: se mide por recorridos y artefactos, no por cantidad de archivos, migraciones o assertions.

## 14. Contratos y cambios de datos propuestos

Nombres siguientes son conceptuales: antes de crear tabla comprobar si existe equivalente; extenderlo. Numeración de migración se determina al ejecutar, después del máximo real del proyecto; no reservar ni sobreescribir 0086 si alguien la agregó después.

| Área | Entidades/extensiones | Contratos nuevos o ampliados bajo `/api/v1` |
|---|---|---|
| Equipos | ubicaciones, componentes, dependencia, inspección, perfil de activo | equipos de sucursal, detalle, cambio habilitación, inspección, incidencia vinculada |
| Consumo interno | tipo/propiedad de stock, asignación, préstamo, movimientos | catálogo, stock, movimientos, conteo, traslado, devolución |
| Acceso | política por rol, excepción temporal, auditoría de uso | elegibilidad de sesión; solicitar/aprobar/revocar excepción |
| Descuentos | versión promoción, calendario, aprobación, reserva presupuesto, aplicación venta | CRUD borrador, preview, proponer, aprobar, suspender, cotizar |
| Clientes | perfil público, enlace identidad, preferencias, estado | registro vía proveedor; `/customer/me`, sucursales públicas, historial propio |
| Puntos | programa/versiones, cuenta, libro, reserva, recompensa/stock, reclamación | configuración interna; saldo/movimientos propios, cotización y confirmación de canje |
| Campañas | contenido/versiones, media, aprobación, alcance/vigencia | gestor interno; feed público publicado y contextual |

Cada comando: `commandId`, versión esperada cuando corresponda, ámbito resuelto en servidor, transacción, auditoría y respuesta determinista. Listas: filtro validado, límite y cursor; errores con código estable, mensaje útil, correlationId y conflicto recuperable. Registrar contrato de request/response antes de cablear pantalla. No duplicar rutas ya existentes porque el nombre propuesto sea distinto.

RLS y permisos mínimos en nuevas tablas expuestas; funciones sin EXECUTE público involuntario. API y worker nunca usan credenciales administrativas en cliente. Documentos/borradores privados. Cliente final no consulta tablas de empleados/costos. Workers usan outbox/jobs existentes e idempotencia, no timers móviles.

## 15. Criterios de aceptación humana final

| Caso | Recorrido y resultado esperado |
|---|---|
| H01 | Instalar dos APK simultáneas; íconos/nombres distintos; sesiones independientes sobreviven reinicio |
| H02 | Entrar con cada rol; menú y acciones correctos; intentar otra sucursal devuelve denegación |
| H03 | Crear sucursal por plantilla y personalizada, pausar/reanudar; precio/modo/productos correctos |
| H04 | Abrir bomba → reportar manguera de aire rota; aire no disponible, combustible conserva estado correcto |
| H05 | Fallar compresor compartido; todos sus puntos de aire reflejan dependencia; inspección/reparación trazable |
| H06 | Consumir fluidos, prestar/devolver medidor/bidón, trasladar conos; stock y auditoría coherentes |
| H07 | Vencer turno con app abierta; impedir comando; aprobar excepción limitada y comprobar expiración |
| H08 | Compra/recepción → tanque → despacho → pago → corte; inventario/caja/consolidado coinciden sin duplicar |
| H09 | Programar miércoles y día 20; preview correcto; aprobación distinta; precio final e historial conservados |
| H10 | Registrar cliente, escanear QR, venta pagada, ganar puntos una vez aunque haya reintento |
| H11 | Canjear con confirmación, probar doble canje, timeout y devolución parcial; saldo consistente |
| H12 | Premio físico sin stock no se canjea; reserva/cancelación libera cupo y puntos |
| H13 | Gerente publica banner local; visible solo en contexto elegible; expira y desaparece sin actualizar app |
| H14 | Filtrar gráfico/reporte y exportar PDF/XLSX; mismo conjunto/totales y acceso por rol |
| H15 | Probar red lenta/sin red, reinicio y usuario revocado; no duplicar operaciones ni perder estado incierto |
| H16 | Probar tipografía grande, reducir animación, teclado web y listas largas; navegación conserva filtros |
| H17 | Exportar diagnóstico y reportar defecto sin exponer secretos ni información personal innecesaria |
| H18 | Ejecutar mismos recorridos en Swift final; comprobar cámara, QR, archivos, sesión y permisos iOS |

En F13 incluir cuentas de dos sucursales, dos empleados, gerentes y clientes, stock finito, promociones conflictivas y casos de dato insuficiente. Dataset QA aislado de operación real, reiniciable con confirmación explícita si contiene trabajo del usuario. No guardar contraseñas demo conocidas habilitadas en producción.

## 16. Regreso a Swift y cierre del alcance anterior

Durante Flutter mantener `PARIDAD_PLATAFORMAS.md`: ID de recorrido, API/casos de negocio, Flutter, Swift, diferencias y aceptación. Al volver a Swift copiar comportamiento aceptado y diseño; no traducir Dart literalmente ni migrar de nuevo el backend. Reutilizar MVVM, URLSession, Keychain y componentes existentes. Cliente final Swift obtiene su propio target y almacenamiento.

F14 exige paridad de funciones nuevas y antiguas, adaptación accesible iOS, compilación, permisos de cámara/ubicación/archivos, restauración de sesión y pruebas en Mac de los recorridos críticos. Pruebas Android validan negocio/UX compartidos; resultados no se presentan como evidencia de compilación o comportamiento nativo iOS. Mantener builds y capturas asociadas a versión.

El apéndice `TRAZABILIDAD_PLAN_ANTERIOR.md` enumera todas las subtareas anteriores y su destino. Estados previos se conservan en `ESTADO.json`; seguimiento nuevo está en `ESTADO_FLUTTER.json`. No desaparecer E01.05 ni importación/apertura E08.05 porque se haya cambiado de plataforma. Impuestos E09.04 y la parte fiscal de E12.01 se aplazan explícitamente. La rúbrica oficial del parcial sigue pendiente: no afirmar su cumplimiento sin leerla.

Entregas: fuentes completas con lockfiles, dos APK identificadas por build/SHA, instrucciones Windows, API/config sin secretos, scripts QA, contratos y mapa de paridad, registro de defectos, PDF/capturas del build final y Figma accesible para entrega académica; dos proyectos/targets Swift al terminar F14. Producción conserva gates propios de despliegue, fiscalidad y dispositivos reales que apliquen.

## 17. Referencias técnicas consultadas

- Flutter, arquitectura: https://docs.flutter.dev/app-architecture/recommendations — respalda separación de UI/datos, repositorios y MVVM; las decisiones particulares del proyecto se describen arriba.
- Supabase, control de acceso a archivos: https://supabase.com/docs/guides/storage/security/access-control — permisos de objetos y políticas deben definirse explícitamente.

Estas referencias no certifican seguridad industrial ni fijan tasas fiscales. Consultar documentación vigente al instalar SDK, integrar Auth/Storage o implementar una API específica. Este turno entrega planificación y trazabilidad, no una APK ni módulos nuevos ya ejecutados.
