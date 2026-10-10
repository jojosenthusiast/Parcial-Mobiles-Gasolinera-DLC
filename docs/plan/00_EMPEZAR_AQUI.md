> Actualización 2026-10-08: la ejecución activa es `PLAN_ECOSISTEMA_FLUTTER_SWIFT.md` y `ESTADO_FLUTTER.json`. Prioridad: Swift → Flutter/APK → pruebas humanas → Swift. El contenido histórico inferior conserva requisitos y evidencia; fiscalidad al final.

# DLC — Plan ejecutable de desarrollo

Versión 1.0 · 4 de octubre de 2026. Entrega: plan, contratos, control de avance y copia identificada de la base. No se ha implementado la ampliación ni se ha certificado compilación de la base.

## Resultado esperado

Aplicación iOS SwiftUI con operación completa de estación y panel web de supervisión, ambos sobre una API y datos comunes. Incluye infraestructura configurable; precios/costos históricos; compras/recepción; inventario; despacho manual e integración preparada; caja/cortes; incidencias/mantenimiento; tienda/lubricantes; personal/turnos; gastos/servicios; dashboards y reportes exportables. Mantiene identidad DLC y navegación por rol. La configuración académica sigue permitiendo demostrar seis bombas y dos cortes.

El producto se termina por recorridos verificables. Una pantalla con botones sin efectos, un campo sin fuente o un simulador presentado como integración real no completa una función.

## Cómo usar el paquete con Luna

1. Leer este archivo, `01_DECISIONES_Y_ARQUITECTURA.md` y `ESTADO.json`.
2. Comprobar que el código corresponde a `base/manifest.json`, o documentar las diferencias del proyecto más reciente. No reemplazar cambios del usuario con la copia incluida.
3. Abrir únicamente la primera etapa pendiente cuyos prerrequisitos estén satisfechos. Cada etapa dice qué contratos consultar, archivos tocar, pruebas ejecutar y qué evidencia registrar.
4. Implementar subtareas en su orden; actualizar el estado tras cada unidad verificable. Continuar dentro de la autorización existente sin pedir confirmación para cambios reversibles del alcance.
5. No releer las dos auditorías en cada turno. Están como referencia y sus hallazgos están asignados en `07_TRAZABILIDAD.md`.
6. Finalizar cada sesión con cambios, pruebas, bloqueos reales y siguiente subtarea exacta. Nunca marcar completado por haber escrito código únicamente.

`PROMPT_PARA_LUNA.md` contiene la instrucción de continuidad lista para usar. `ESTADO.json` arranca con todas las etapas pendientes. No supone que el archivo Xcode compila hasta comprobarlo.

## Orden de ejecución

| Etapa | Resultado |
| --- | --- |
| E00 | Base reproducible, inventario de requisitos y entorno fijado |
| E01 | Correcciones críticas pequeñas en la versión local existente |
| E02 | API, base de datos, contratos y pruebas de infraestructura |
| E03 | Sesiones, permisos, auditoría y autorizaciones |
| E04 | Catálogos e infraestructura de estación |
| E05 | Migración/importación del legado sin doble inventario |
| E06 | Cliente iOS remoto y navegación maestro–detalle |
| E07 | Alta reanudable de sucursal y activación |
| E08 | Inventario y costos: movimientos, mediciones y unidades |
| E09 | Precios con vigencia y aplicación histórica |
| E10 | Proveedores, compras, entregas, facturas y pagos |
| E11 | Pista, lecturas, despacho y fuentes de integración |
| E12 | Ventas, pagos, cajas, reembolsos y conciliación |
| E13 | Dos cortes, revisión, cierre y ajustes |
| E14 | Incidencias, daños, pérdidas y recuperaciones |
| E15 | Equipos, mantenimiento preventivo y observaciones técnicas |
| E16 | Tienda/lubricantes, lotes, traslados y devoluciones |
| E17 | Empleados, turnos, asistencia y relevos |
| E18 | Gastos, servicios y cuentas comerciales configurables |
| E19 | Planificación de abastecimiento y escenarios de precio |
| E20 | Consultas, métricas, alertas y dashboards |
| E21 | Reportes, exportaciones y vistas guardadas |
| E22 | Panel web completo sobre la API común |
| E23 | Sincronización, trabajos programados, recuperación e integraciones |
| E24 | Validación integral, entrega y documentación coincidente |

El orden es intencionalmente secuencial para reducir coordinación y consumo de contexto. No saltar a gráficos antes de tener cantidades/costos trazables. Se puede trabajar en una tarea independiente cuando una prueba Mac o una conexión externa esté bloqueada, registrando el pendiente y sin declarar esa etapa completada.

## Tres puertas de entrega

- G1, base coherente: E00–E13. Recorrido estación → recepción → despacho → pago → corte → consulta, con pruebas.
- G2, aplicación funcional completa: E14–E22 más validaciones pertinentes. Incidencias, tienda, personal, mantenimiento, planificación, reportes y web terminados.
- G3, operación conectada verificada: E23–E24, pruebas Mac/web/API, recuperación y aceptación con proveedores/equipos realmente disponibles.

La puerta G2 puede usar adaptadores simulados explícitos para equipos/pagos externos. Eso no certifica G3. Las capacidades de hardware se entregan con conector real validado o con estado de integración pendiente; nunca se presentan como mediciones existentes.

## Material incluido

- `01_DECISIONES_Y_ARQUITECTURA.md`: decisiones fijas y límites de la ampliación.
- `02_DOMINIO_Y_REGLAS.md`: entidades, estados y cálculos.
- `03_API_SEGURIDAD_Y_TRANSACCIONES.md`: contratos, permisos, errores y concurrencia.
- `04_MIGRACION_Y_COMPATIBILIDAD.md`: transformación de archivos existentes y Xcode.
- `05_PANTALLAS_REPORTES_Y_METRICAS.md`: rutas, maestros–detalle, dashboards y exportación.
- `06_PRUEBAS_Y_ENTREGA.md`: pruebas numéricas, QA y definición de terminado.
- `07_TRAZABILIDAD.md`: cobertura de hallazgos y observaciones.
- `08_CONTINUIDAD_Y_BLOQUEOS.md`: estados, dependencias cruzadas y tratamiento de entradas externas.
- `etapas/E00...E24.md`: tareas ejecutables por etapa.
- `base/`: copia sin cambios del proyecto actual y manifiesto SHA-256. El ZIP anterior no es la base de este plan.
- `referencias/`: auditorías completas que sustentan las decisiones.

## Pendientes externos delimitados

Rúbrica específica del parcial; confirmación de horario real; datos físicos de estación; proveedor/contrato y fichas de producto; tratamiento fiscal/contable validado; acceso a Mac/Xcode y a hardware/procesadores. La implementación de modelos, UI, pruebas y adaptadores de desarrollo puede avanzar con fixtures explícitos. La activación real del componente afectado requiere esos datos. No se inventan tasas, costos históricos, mediciones, credenciales ni certificaciones.
