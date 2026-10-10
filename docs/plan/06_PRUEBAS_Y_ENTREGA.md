# Pruebas, datos y aceptación

## Q01. Capas de evidencia

Unitarias para cálculos/transiciones; integración con PostgreSQL real para permisos, atomicidad y concurrencia; contratos/fixtures para Swift y web; UI e2e para recorridos; pruebas Mac de compilación/simulador; validación externa para equipo/procesador real. No sustituir una capa por mocks de otra.

Cada stage registra comando exacto, entorno, exit code, alcance, resultado y limitación en `docs/evidence/E##.md`. No escribir «probado» sin ejecución. Reutilizar pruebas relevantes; suite completa en gates G1/G2/G3 y al cambiar contratos/migraciones globales. No volver a ejecutar todo por una corrección de texto aislada.

## Q02. Datos de prueba deterministas

Reloj inyectable; UUID estables; ninguna prueba de cortes depende de Date.now o del día real. Seed separado de producción, comando explícito y sin contraseñas de demo en logs de producción.

F01: estación académica seis bombas, tres familias, dos cortes y gerente local/general. F02: pequeña dos bombas, solo diésel, una manguera temporalmente averiada. F03: 24 h, cambio de precio en un corte, recepción durante ventas, costo de apertura conocido. F04: histórico legado con precio/costo/autor desconocidos, corte abierto y lotes. F05: fraude de ámbito y usuario suspendido. F06: 20 estaciones×30 días completos para reportes/paginación; al menos una alta tardía y una archivada. Cantidades/precios son sintéticos y se indican.

## Q03. Vectores numéricos obligatorios

V01: 1 gal US → 3.785411784 L; 10 → 37.854117840 L. Alternar preferencia 100 veces sin modificar valor almacenado ni importe.
V02: apertura 1000 L con valor 800 USD; recepción 500 L por 450 USD → Q=1500, V=1250, costo promedio 0.833333333333... USD/L. Salida 120 L → costo 100 USD, saldo 1380 L/1150 USD. Pérdida 20 L → costo 16.66666667 a precisión de inventario, saldo 1360 L/1133.33333333. Presentación monetaria usa policy; al vaciar remanente, Q/V exactamente cero.
V03: tramo 100 gal×3.50 y 60×3.80 → 160 gal y 578.00 USD; cambiar precio actual a 4.00 no altera esos 578.00. Sin lectura intermedia/operaciones, no afirmar esa distribución.
V04: prepago 20.00, despacho 17.00 → venta17 y saldo3 pendiente de reembolso/liberación; reintento no devuelve6.
V05: caja abre100, cobra200 efectivo y80 tarjeta, devuelve30 efectivo, deposita50 → efectivo esperado220; tarjeta80 aparte. Depósito no es gasto.
V06: tienda consume 2 unidades de lote A a costo1.00 y 3 de B a1.50, vende5×2.00 → venta10, costo6.50, utilidad3.50, margen35% en fixture sin impuesto. Cambiar catálogo costo a1.80 no cambia histórico.
V07: tanque inicial1000, final1400; despacho durante recepción100, sin otros movimientos → entrada inferida500. No registrar400 por ignorar ventas.
V08: pérdida20 gal, costo3.20, precio3.90 → costo64 y equivalente comercial78; reparación120 → costo total184 si componentes confirmados y sin doble conteo. No sumar78 otra vez.
V09: dos estaciones ventas netas100/900 y utilidad50/90 → margen de red14%, no promedio30%.
V10: compra adelantar6000gal por diferencia0.03 → ventaja bruta180; flete extra100/financiación30 → escenario neto50; si capacidad solo4000gal, no recomendar6000.
V11: lectura final del corte anterior1000, nueva inicial990 → inconsistencia; diferencia no se corrige por max(0) ni edición libre.
V12: recibir500 y pulsar confirmar dos veces → una entrada500, mismo documento/resultado; cerrar corte no vuelve a añadir500.

## Q04. Integridad y concurrencia

Dos solicitudes simultáneas reservan misma posición; solo una gana. Dos ventas compiten por último lote/tanque: sin saldo negativo. Cierre y edición concurrentes: cierre bloquea copia anterior. Confirmación externa duplicada: un pago y una salida. Worker muere entre enviar y recibir: recupera sin duplicar. Migración repetida: mismos ids/saldos. Fallo SQL a mitad de recepción: rollback total. Documento físico capturado dos veces: detección por identidad/clave, sin confiar solo en timestamp.

Por endpoint de escritura: sin sesión, rol equivocado, sucursal ajena, sesión revocada, estado incorrecto, versión vieja, payload inválido y éxito. Por export: filtro de sucursal manipulado, campos restringidos, job compartido con usuario no autorizado. Datos sensibles fuera de logs y adjuntos sin URL pública indefinida.

## Q05. Casos funcionales

Los T01–T40 de la auditoría profunda están incluidos en `referencias/` y mapeados en `07_TRAZABILIDAD.md`; conservar identificadores. Agregar QA41: importación con costo desconocido produce margen incompleto; QA42: servidor caído conserva borrador sin anunciar recepción; QA43: refresh token reutilizado revoca familia; QA44: recibo interno no se anuncia fiscal; QA45: restore DB+adjuntos reproduce saldos y evidencias; QA46: backdated recepción no revalora silenciosamente costo cerrado; QA47: dos cortes 24h cubren intervalos sin huecos; QA48: unidades/base térmica incompatibles impiden comparación; QA49: pago de gasto vincula retiro y obligación sin duplicar resultado; QA50: tareas vencidas se recuperan tras reiniciar worker.

## Q06. Prueba UI mínima por rol

General: login → alta en borrador → completar estructura → activar → aprobar precio/compra → abrir alerta → ficha bomba → historial → reporte filtrado → exportar. Local: login → recepción → lectura/despacho → cobro/caja → corte → incidencia rápida → mantenimiento → tienda/devolución → relevo → consulta. Operativos: ver solo recursos/acciones autorizados; no costo/margen por defecto. Bloquear edición de cerrado pero mantener detalle.

Medir toques: bomba <=2 desde otra pestaña; incidencia desde ficha, abrir formulario+guardar en2 más captura; alerta a detalle1; reporte favorito exportar3. Verificar listas de100 registros y texto grande; acciones no se hunden debajo de movimientos. Regreso conserva filtros/scroll. Capturas de resultados reales; no reutilizar imágenes de versión anterior como evidencia.

## Q07. Comandos y gates

E02 implementará scripts con nombres fijos: `pnpm lint`, `pnpm typecheck`, `pnpm test:unit`, `pnpm test:integration`, `pnpm test:contract`, `pnpm test:web`, `pnpm build`; `pnpm db:migrate`, `pnpm db:seed:demo`, `pnpm report:verify`. Cada uno debe fallar con exit code no cero cuando corresponda. Tests integración usan DB desechable distinta de desarrollo.

En Mac usar proyecto/scheme descubiertos, destino existente y `xcodebuild ... build`/`test`; conservar comandos reales en evidencia. Añadir target XCTest/XCUITest con referencias correctas. Si runner Mac falta, registrar gate pendiente y continuar backend/web. No declarar G1/G2 completamente validados hasta cumplir pruebas de los clientes que se entregan.

G1: core numérico/concurrencia y recorrido E00–E13. G2: todos T01–T40 aplicables en modo manual/simulado, módulos/roles/exportes. G3: release build, recuperación, seguridad, performance y conexiones reales disponibles. Hardware no disponible queda como integración no certificada visible, no aprobación de producción.

## Q08. Paquete final de implementación

ZIP Xcode con proyecto completo, assets, esquemas y pruebas; backend/web con lockfiles, migraciones, seed sintético y compose; `.env.example` sin secretos; manual de instalación Mac/Windows y URLs locales; documento arquitectura/datos/reglas por rol; matriz permisos; pruebas/evidencia; guía exportar/restaurar; lista de adaptadores manual/simulado/real; registro de versión. PDF académico y Figma se actualizan contra esta versión si siguen siendo entregables; no mezclar requisitos desconocidos del parcial con los del laboratorio.

No empaquetar DerivedData, node_modules, claves, dumps reales ni tokens. Compilar desde copia limpia del paquete antes de emitir versión. La documentación distingue función implementada, probada, simulada y pendiente externa con precisión. Revisión final de trazabilidad: ninguna observación obligatoria sin etapa y evidencia.
