# Trazabilidad del alcance

Las auditorías están en referencias. Esta tabla asigna sus hallazgos a etapas; no declara que estén corregidos. E24 verifica toda la matriz. Los casos T01–T40 conservan la intención de la auditoría profunda y se ejecutan con las reglas definitivas del plan.

## Hallazgos de código y flujo

| ID | Hallazgo | Etapas |
| --- | --- | --- |
| A01 | Copia obsoleta modifica corte cerrado | E01,E13 |
| A02 | Autorización desigual entre operaciones | E01,E03 |
| A03 | Precio actual recalcula historia | E09,E12,E20 |
| A04 | Bomba física sin entidad propia | E04,E11 |
| A05 | Tres combustibles impuestos por bomba | E04,E07 |
| A06 | Seis bombas codificadas en todas partes | E04,E07,E13 |
| A07 | Recepción/pérdida solo cambia saldo al cierre | E08,E10,E14 |
| A08 | Balance neto oculta capacidad o saldo inválido | E08,E10 |
| A09 | Lectura inicial editable sin continuidad | E01,E11,E13 |
| A10 | Cierre sin actor/hora/conciliación | E03,E13 |
| A11 | Detalle cerrado inaccesible | E01,E06,E13 |
| A12 | Acceso a bomba enterrado tras movimientos | E06,E11 |
| A13 | Tarjetas sucursal sin detalle útil | E06,E07,E20 |
| A14 | Vista de bombas muestra cortes | E06,E11 |
| A15 | Edición directa sin ficha recurso | E06,E22 |
| A16 | Cortes esperados con población actual | E13,E20 |
| A17 | Población histórica/activa inconsistente | E20,E21 |
| A18 | Autonomía considera días incompletos completos | E19,E20 |
| A19 | Turno nocturno fuera de cortes | E07,E13,E17 |
| A20 | Costo catálogo en vez de lote vendido | E08,E16 |
| A21 | Anulación sin devolución real | E12,E16 |
| A22 | Mínimos para productos no manejados | E04,E16 |
| A23 | Sesión/sucursal obsoleta | E01,E03,E06 |
| A24 | JSON corrupto sobrescrito por demo | E01,E05,E23 |
| A25 | Sin reportes/series/exportación suficientes | E20,E21,E22 |
| A26 | Alta rígida sin wizard | E07 |
| A27 | Datos/auth locales sin web compartida | E02,E03,E06,E22 |
| A28 | Sin datos técnicos/incidentes/compras con costo | E08,E10,E14,E15 |

## Casos de aceptación de la auditoría

| Caso | Escenario | Etapas responsables |
| --- | --- | --- |
| T01 | Sucursal pequeña diésel | E04,E07 |
| T02 | Perfil académico incompleto | E04,E07 |
| T03 | Falla de una manguera | E04,E11 |
| T04 | Tanque compartido vacío | E04,E08,E11 |
| T05 | Cierre por falta de personal | E11,E17 |
| T06 | Consultar corte cerrado | E01,E06,E13 |
| T07 | Sobrescritura obsoleta | E01,E13 |
| T08 | Suspensión de usuario | E03,E06 |
| T09 | Incidencia desde bomba | E11,E14 |
| T10 | Regreso conserva filtros | E06,E22 |
| T11 | Precio cambia dentro de corte | E09,E12,E13 |
| T12 | Precio futuro cambia | E09 |
| T13 | Costo compra fijado en operación | E09,E10,E19 |
| T14 | Baja futura pero poca autonomía | E19 |
| T15 | Descarga durante venta | E08,E10,E11 |
| T16 | Compartimentos/producto compatible | E10 |
| T17 | Recepción/factura parcial y reclamo | E10 |
| T18 | Cambio unidad sin deriva | E08 |
| T19 | Doble envío de operación | E08,E10,E23 |
| T20 | Doble autorización bomba | E11,E23 |
| T21 | Prepago y remanente | E11,E12 |
| T22 | Timeout desconocido | E11,E12,E23 |
| T23 | Agua/temperatura ausentes | E08,E15 |
| T24 | Volumen observado/compensado | E08,E15 |
| T25 | Anomalía no acusa robo | E14,E15 |
| T26 | Incidencia/ajuste sin doble pérdida | E08,E14 |
| T27 | Manguera rota sin derrame | E14 |
| T28 | Reparación no elimina otro bloqueo | E14,E15 |
| T29 | Cruce medianoche | E13,E17 |
| T30 | Inventario vivo/histórico cerrado | E13,E20 |
| T31 | Costos por lotes reales | E08,E16 |
| T32 | Devolución dañada | E12,E16 |
| T33 | Depósito no es gasto | E12,E18 |
| T34 | Vigencia sucursal y cobertura | E13,E20 |
| T35 | Exportación completa filtrada | E21,E22 |
| T36 | Gráfico sin datos suficientes | E19,E20 |
| T37 | Recuperación corrupción | E01,E05,E23 |
| T38 | Wizard reanudable | E07 |
| T39 | Exportación ajena denegada | E03,E21,E22 |
| T40 | Offline no confirma despacho | E06,E11,E23 |

## Cobertura adicional solicitada

| Área | Entrega concreta | Etapas |
| --- | --- | --- |
| Roles local/general y personal operativo | Permisos, alcance y tareas diferenciadas | E03,E06,E17,E22 |
| Ganancia sin impuestos/margen bruto | Política fiscal versionada; ingreso neto de impuesto y costo real, margen ponderado | E08,E09,E18,E20 |
| Precios por zona/modalidad/bomba | Calendario, origen, aprobación, vigencia y snapshot de venta | E09,E11,E12 |
| Compra antes de subidas/después de bajas | Escenario con cotización proveedor, capacidad, demanda y riesgo | E10,E19 |
| Uno/dos/tres combustibles y productos especiales | Catálogo documentado, producto por manguera y conexión tanque | E04,E07 |
| Dos cortes y seis bombas académicas | Perfil académico y estructura dinámica para operación real | E04,E07,E13 |
| Automatización | Jobs idempotentes, recopilación y propuesta de cierre, política de aprobación | E02,E09,E13,E15,E23 |
| Unidades | Galón US/litro coherentes, costo por unidad y volumen observado/compensado | E08,E09,E21 |
| Pérdidas/daños/terceros | Expediente, costos separados, recuperación, bloqueo y mantenimiento | E14,E15,E18 |
| POS/efectivo/tarjeta/caja | Venta, pago, arqueo, depósito, refund y conciliación | E11,E12,E13 |
| Proveedores/compras | Orden, descarga, parciales, facturas, reclamos y pagos | E10 |
| Tienda/lubricantes | Surtido, lotes, costos, caducidad, transferencias, devoluciones | E16 |
| Empleados/turnos | Ficha, asistencia, cobertura y relevo; independiente del corte | E17 |
| Gastos/servicios/clientes comerciales | Devengo/pago, materiales, cuentas y límites | E18 |
| Dashboards útiles | Prioridad por rol, cobertura, frescura, acción y desglose | E20 |
| Gráficos/reportes | Series adecuadas, cifras/unidades, filtros, detalle y exportación consistente | E20,E21 |
| Web general | Administración y supervisión con mismo backend/datos | E22 |
| Agua/temperatura/fuga/pruebas/ambiente | Observaciones, fuente, calibración, inspecciones y adaptador real condicionado | E08,E15,E23 |
| Seguridad y continuidad | Sesiones, auditoría, permisos servidor, backup, restauración y conflictos | E03,E05,E23 |
| Diseño DLC | Colores/assets actuales, accesibilidad, maestro–detalle y menos navegación | E06,E11,E20,E22 |
| Entrega académica | Proyecto compilado, documentación/capturas de versión y Figma si aplica | E00,E24 |

## Pruebas adicionales del plan

QA41 costo desconocido → E08/E20; QA42 offline → E06/E23; QA43 rotación/reutilización de sesión → E03/E23; QA44 recibo/factura → E12/E24; QA45 restauración → E23; QA46 corrección retroactiva → E08/E09; QA47 cobertura horaria → E13; QA48 base volumétrica → E08; QA49 gasto/caja sin duplicación → E12/E18; QA50 recuperación de jobs → E09/E23.

Vectores V01–V12 y resultados esperados están en 06. Toda prueba fallida produce defecto con etapa responsable y evidencia. Ningún requisito se elimina porque el fixture actual no lo muestre.

## Límites explícitos

La rúbrica oficial del parcial no está incorporada como fuente verificada; cotejar al recibirla. Lecturas automáticas, control de dispensadores, cobro de tarjeta y facturación electrónica necesitan equipos/proveedores reales para cerrar integración. El software de demostración implementa contratos y adaptadores manuales/simulados identificados, sin fingir certificación. No se incluye nómina legal completa, contabilidad general certificada, construcción física, calibración profesional ni cliente Android nativo como si fueran requisitos ya implementados. Nuevos requisitos confirmados se añaden como delta trazable, no se esconden dentro de una etapa terminada.
