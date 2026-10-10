# Pantallas, navegación y analítica

## U01. Rutas y estado

iOS gerente sucursal: Inicio / Operación / Ventas / Reportes / Gestión. General: Resumen / Sucursales / Aprobaciones / Reportes / Gestión. Cuenta en encabezado. Ruta tipada por recurso id, sección, scope y filtros; NavigationStack estable por pestaña. Web usa sidebar y URL enlazable con query validada. Volver conserva scroll/filtro. Un enlace desde notificación revalida permiso antes de mostrar dato.

Operación abre bombas, con acceso fijo a Tanques/Cortes. Dentro de ficha una sección seleccionable no exige deslizar ocho páginas. Guardar abre/vuelve al recurso actualizado; no regresa siempre al dashboard. Edición es acción secundaria de ficha, no sustituto de ficha. Ante acción deshabilitada por estado, mostrar motivo y vínculo a resolver; sin permiso, ocultar acción sensible o explicar según contexto.

## U02. Inventario de pantallas a completar

| Módulo | Lista y detalle | Flujos adicionales |
| --- | --- | --- |
| Acceso | Login, cuenta, sesiones | Activación, recuperación, expiración, revocación |
| Sucursales | Listado, ficha, estado de configuración | Asistente, revisión, activar/suspender, gerente |
| Combustibles | Catálogo, ficha y especificación | Variante, fuente documental y oferta local |
| Pista | Bombas, bomba, posición/manguera | Lectura, habilitación según integración, bloqueo, incidencia rápida, auditoría |
| Tanques | Tanques, ficha y movimiento | Medición, conciliación, compra, recepción, ajuste |
| Precios | Vigentes/próximos, detalle de vigencia | Proponer, aprobar, programar, verificar aplicación |
| Compras | Proveedores/pedidos, fichas | Cotización, compra multiartículo, aprobación, recepción parcial, discrepancia, factura/pago |
| POS | Caja, ticket, despacho | Prepago/pospago, cobro mixto, devolución, arqueo |
| Cortes | Hoy/historial, detalle completo | Lecturas esperadas, revisión, caja, excepción, cierre, ajuste |
| Incidencias | Lista/ficha/cronología | Registro rápido, evidencia, pérdida, costo, recuperación, cierre técnico/financiero |
| Mantenimiento | Activos/órdenes/planes y ficha | Programar, ejecutar, consumir repuesto, verificar, liberar |
| Tienda | Productos/lotes/movimientos y ficha | Recepción, venta, devolución, cuarentena, conteo, traslado |
| Personas | Empleado/usuario/horario y ficha | Alta, permisos, turnos por fecha, relevo, ausencia, suspensión |
| Finanzas/servicios | Gastos, órdenes, cuentas | Aprobación/pago, consumo material, entrega/cobro, liquidación crédito |
| Planificación | Escenarios/entregas | Comparar compra ahora/espera/puente, aprobar orden |
| Reportes | Catálogo/favoritos/resultado | Filtros, tabla/gráfico, drilldown, exportación, programación |
| Alertas/auditoría | Bandeja/ficha | Asignar, reconocer, resolver, consultar cambios |

Toda pantalla: cargando, error recuperable, vacía con acción, resultado sin coincidencias, sin permiso, stale, offline y success/pending cuando aplique. No meter explicación del módulo como párrafo decorativo en todos los encabezados. Sí explicar unidades, fuente y razón de una restricción.

## U03. Ficha de bomba

Encabezado código/sucursal, servicio y estado con motivo. Posiciones muestran producto, precio/unidad, tanque, disponibilidad y última actualización. Acciones inmediatas: lectura, incidencia, acción de operación permitida. Secciones Actividad / Rendimiento / Incidencias / Mantenimiento / Auditoría. Configuración administrativa en menú propio. La ficha no depende de que exista un corte abierto.

Al abrir desde corte, conservar contexto y ofrecer lectura del período; desde reporte conservar filtro; el recurso es el mismo, no tres copias incoherentes. Corte cerrado permite leer todas las bombas. Se puede pasar a siguiente pendiente durante captura sin volver a la lista, con indicador de avance y confirmación de guardado.

## U04. Asistente de sucursal

Identidad → plantilla/productos → tanques → pista/conexiones → horario/precios/caja → gerente/personal → saldo inicial → revisión/activación. Cada paso guarda borrador con versión. Skip solo en datos opcionales; datos necesarios aparecen como pendiente, no se llenan falsamente. Plantilla seis bombas/tres familias es editable en perfil operativo; instanciación nunca inventa saldos. Reanudar y clonar estructura sin copiar historial/credenciales.

## U05. Dashboards

Sucursal primera pantalla: día/intervalo y fuente/frescura, alerta prioritaria, acceso directo a pista y corte; a continuación tanques, caja/resumen y pendientes. Cada alerta lleva al expediente/sección exacta. No desplazar acceso a bomba debajo de lista de movimientos. General: alcance/fechas, cobertura, indicadores económicos, estaciones prioritarias, tendencia; drilldown a estación, tanque, bomba y documento.

Última medición != último registro != última sincronización. Mostrar las tres cuando cambia interpretación. Datos operativos actuales separados del consolidado cerrado. Costos desconocidos muestran venta/volumen y margen incompleto, no margen 100%.

## U06. Catálogo de métricas

| ID | Fórmula/población | Visual y detalle |
| --- | --- | --- |
| salesNet | Líneas confirmadas menos descuentos/devoluciones y componentes trasladados según policy | Línea diaria y tabla → tickets/tramos |
| fuelVolume | Despachos confirmados o tramos manuales únicos; por base/familia/variante | Barras apiladas → mangueras |
| grossProfit | salesNet − COGS conocido; desconocidos identificados | Barras por estación/producto → costos |
| grossMargin | sum(grossProfit)/sum(salesNet); nulidad cuando denominador cero o cálculo incompleto | KPI y tabla, no promedio de % |
| weightedPrice | Importe definido / volumen comparable | Serie/precio realizado con unidad/base |
| cutCoverage | Cerrados exigibles / esperados según horario/alta/baja y plazo | Estado y listado de faltantes |
| tankLevel | Última medición física y saldo calculado separados; % según capacidad explícita | Barra/serie → movimientos |
| autonomy | Volumen útil / consumo por hora de muestra suficientemente cubierta | Horas/días y proyección con fuente |
| variance | Medido − esperado; % con denominador explícito | Serie/cascada → conciliación |
| uptime | Tiempo técnico disponible / tiempo planificado con cobertura | Cronología y barras → órdenes |
| flowRate | Volumen/duración válida del despacho | Dispersión/tendencia → transacciones |
| losses | Costos confirmados de pérdida; valor comercial separado | Pareto → incidencias |
| cashVariance | Declarado − esperado efectivo; otros medios aparte | Tabla → arqueo/pagos |
| stockRisk | Artículos habilitados por estación con disponible<=mínimo; vencidos aparte | Lista → lote/producto |
| supplierPerformance | Entregas dentro compromiso vigente y diferencias | Tabla/tendencia → pedidos |
| expensesResult | Devengos pagados/pendientes separados; resultado sin doble costo | Tabla/cascada → documentos |
| receivableAge | Saldo según vencimiento y pagos aplicados | Barras antigüedad → cuenta |

Filtros y calidad comunes: asOf, fechas, operationalDate, timezone, scopes, producto, modalidad, sourceMode, estado/cerrado/provisional. Ausencia no es cero. Sucursal archivada conserva pasado; población de numerador/denominador idéntica. Cobertura de autonomía requiere períodos completos comparables: default mínimo tres días operativos completos de últimos siete, configurable y visible; si no se alcanza, no publicar autonomía confirmada. La política elegida es de producto, no regla del sector.

No crear gráfico horario ni caudal desde dos cortes al día. Una estimación puede ofrecerse solo con etiqueta y método propios, nunca puntos inventados. Comparaciones usan período equivalente y muestras comparables; tamaño de sucursal no se confunde con eficiencia.

## U07. Reportes

Plantillas: corte/manguera, consolidado diario, kardex, conciliación tanque, precio aplicado, compra/recepción/factura, pérdidas/recuperaciones, margen combustible, venta/caja, tienda/lotes, vencimiento, turnos/cobertura, mantenimiento/uptime, gastos, servicios, crédito y auditoría.

Schema `ReportDefinition`: id/version, question, columns/types/units, allowedFilters, groupBy, aggregates, permission, requiredSources, drilldownRoute. Resultado incluye `ReportRun` id, watermark/snapshot y parámetros. Exportar usa el mismo run, no nueva query sin filtros. Orden/paginación no alteran población anunciada. Favoritos por usuario y compartidos por permiso; edición de filtro no amplía ámbito.

PDF legible/paginado, XLSX con celdas tipadas, CSV UTF-8 y texto seguro frente a fórmulas. Resumen y detalle suman conforme a policy. Historial de exportación; enlace privado/caducidad; archivos grandes como job. Incluir fuente, filtros, unidad, fecha y estado, sin párrafos de conversación. Reporte programado ejecuta con permisos actuales, no credenciales del creador almacenadas.

## U08. Web y accesibilidad

Web general incluye resumen, sucursales/activos, aprobaciones, catálogo/precios, compras/proveedores, incidencias/mantenimiento, personas, finanzas/servicios, reportes/auditoría. No es una landing de estadísticas; sus acciones usan mismos comandos/permisos. Lista y detalle simultáneos en anchura suficiente; tablas con columnas elegibles, búsqueda, paginación y filtros guardados. Pantalla estrecha vuelve a lista → ficha.

Teclado/foco/lector de pantalla; contraste y texto escalable; números/etiquetas legibles en gráfico; alternativa tabular. Evitar texto gris pequeño para datos operativos. Mantener logo y tema DLC con colores semánticos de estado. Confirmaciones destructivas indican recurso/efecto; no confirmar cada lectura reversible. Test de ruta no debe depender solo de coordenadas ni color.
