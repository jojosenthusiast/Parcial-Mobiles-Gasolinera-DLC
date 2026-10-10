# Continuidad y resolución de bloqueos

## Estados

`pending`: no iniciado. `in_progress`: existe trabajo activo. `implemented_pending_validation`: código terminado, gate requerido sin ejecutar. `blocked`: falta requisito que impide esa subtarea. `completed`: aceptación y pruebas aplicables verificadas. No usar porcentajes subjetivos de terminado.

Cada entrada de prueba contiene ID, comando o recorrido, entorno, resultado, fecha y ruta de evidencia. Un bloqueo contiene alcance afectado, causa observada, evidencia, siguiente acción y tareas independientes posibles. Nunca guardar tokens, claves o información personal real en el estado.

El archivo ESTADO contiene un estado inicial, no una evaluación del código ya realizado. La primera sesión debe contrastarlo con la base. Si se trabaja con git, registrar commit; si no, registrar archivos y hash de copia de seguridad. Mantener solo una etapa activa salvo trabajo independiente documentado; no abrir todo el sistema a la vez.

## Dependencias que cruzan etapas

- E05 entrega staging/preview. E08 publica saldos iniciales y completa el cambio de autoridad; no hay importación operativa anterior al ledger.
- E07 entrega wizard/readiness. La activación comercial exige saldo E08, precios E09 y disponibilidad E11. El botón debe explicar faltantes, no inventar una estación completa.
- E10 registra cuentas por pagar/pagos externos. Pagos desde caja utilizan el movimiento E12/E18; nunca una segunda salida independiente.
- E11 emite hechos de despacho; E12 agrega ventas/cobro y E13 consolida. La lectura acumulada reconcilia los mismos hechos y no vuelve a descontar inventario.
- E02 entrega infraestructura jobs/outbox; E09 y E15 implementan tareas concretas. E23 comprueba fallos/recuperación, no posterga toda automatización hasta el final.
- E08 provee ajustes/pérdidas con permisos; E14 agrega expediente/incidencia que referencia ese movimiento. No dos pérdidas para el mismo evento.

## Entradas externas y tratamiento

| Entrada | Se puede avanzar | Condición para cerrar |
| --- | --- | --- |
| Rúbrica del parcial | Alcance solicitado y laboratorio conocido | Comparación expresa contra documento oficial |
| Mac/Xcode | API/web, análisis Swift y pruebas independientes | Build/test en SDK y dispositivo/simulador registrado |
| Horario y estructura real | Fixtures identificados, wizard configurable | Validación de datos antes de activar estación real |
| Impuestos/facturación | Políticas versionadas y recibo interno | Reglas y conexión fiscal verificadas; no emitir como fiscal sin ello |
| Hardware/sensores/pagos | Contratos, simulador, operación manual | Prueba de integración con proveedor/equipo concreto |
| Costos históricos ausentes | Importación marcada y margen parcial | Fuente documental o mantener desconocido; nunca completar con precio actual |
| Hosting real | Compose local y entrega reproducible | Dominio/secretos/backups/configuración de despliegue autorizados |

## Corrección de una decisión

Si aparece incompatibilidad demostrada, registrar: decisión, evidencia, alternativas, solución mínima y contratos/pruebas afectados. Mantener los objetivos y la base. No cambiar lenguaje, framework, base de datos o política de costos simplemente para ahorrar implementación. Un cambio del usuario prevalece y se refleja en trazabilidad antes de seguir.

## Plantilla breve de cierre de sesión

Etapa/subtarea completada. Archivos/commit. Migraciones aplicadas. Pruebas ejecutadas y resultado. Pruebas pendientes con causa. Defectos nuevos. Próxima subtarea exacta. No incluir un nuevo ensayo de arquitectura en cada sesión.
