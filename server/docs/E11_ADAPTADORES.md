# Adaptadores de despacho

El backend admite `DISPENSE_ADAPTER_MODE=manual` (valor por defecto) y `simulated` únicamente fuera de producción. No hay conexión con un dispensador físico. El modo manual devuelve `operator_required`, sin inventar litros, confirmar flujo ni modificar la autorización; el operador utiliza el flujo manual existente para registrar y conciliar los hechos observados.

El simulador ejecuta tres guiones deterministas: respuesta normal, timeout después de completar y timeout antes de iniciar. Un inicio normal pasa a despacho; un timeout pasa a desconocido y conserva la reserva. La consulta siguiente devuelve el volumen reservado o una comprobación de cero flujo. Solo entonces se registra la venta o se libera la reserva. Cada respuesta identifica su procedencia simulada. Se usa exclusivamente para pruebas sobre inventario de desarrollo; no representa una lectura física.

## Persistencia y recuperación

`dispense_device_operations` conserva el comando original, versión solicitada, escenario, snapshot, resultado, actor, correlación y fechas. Solo admite un inicio por autorización. La clave `(organización, commandId)` distingue un reintento de otro comando; reutilizarla con otro contenido devuelve conflicto.

La intención se guarda antes de consultar el adaptador y el resultado se guarda antes de publicar el hecho de negocio. Los estados `prepared → observed → applied` permiten recuperar un proceso interrumpido. Los subcomandos de inicio, desconocido y finalización mantienen UUID estables. Si el ledger ya recibió la venta y falla la finalización, el reintento retoma ese mismo comando. Nunca genera otra autorización para resolver un timeout.

Un lock de sesión coordina las operaciones de una autorización. Se obtiene con `pg_try_advisory_lock`; si está ocupado devuelve conflicto sin enviar otro inicio. El pool del coordinador tiene como máximo dos conexiones y es independiente del pool de negocio para evitar que ambos esperen entre sí. El presupuesto de conexiones del despliegue debe contar esas dos conexiones adicionales por proceso. No se mantiene una transacción abierta durante las llamadas a otros servicios. Si falla la liberación del lock se descarta la conexión.

Las nuevas filas tienen RLS y acceso exclusivo al rol backend. Ese rol solo puede actualizar resultado/estado/fechas, no cambiar los campos de la intención. Las consultas comprueban organización y sucursal incluso en un replay. El simulador tampoco puede recuperar y publicar una operación pendiente cuando el entorno cambia a producción.

## API y app

- `GET /dispense-device/capabilities`: modo, escenarios y declaración explícita de que no hay hardware conectado.
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/device-start`: commandId, expectedVersion y escenario opcional de desarrollo.
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/device-query`: commandId y expectedVersion. Consulta el escenario original; no admite elegir otro.
- `GET /branches/{branchId}/dispense-authorizations/{authorizationId}/device-operations`: últimos 20 comandos con autor, resultado y fechas.

Las mutaciones requieren `dispense.authorize`; las lecturas requieren `dispense.read`. La ficha SwiftUI muestra el simulador solo cuando el servidor lo habilita. La app conserva el commandId y la versión al reintentar; después de una respuesta confirmada crea una nueva clave para la siguiente acción. Reabrir un despacho desconocido permite consultar el inicio persistido, sin recrearlo. El contrato de proveedor físico define autorización y consulta por comando/transacción original; su implementación queda pendiente de protocolo y equipo reales.

## Pruebas

Pasaron 47 pruebas locales de adaptadores, coordinación, configuración, contratos y regresión. Los tests de coordinación ejecutan la clase real con repositorios stub y decoradores sustituidos; prueban ramas y recuperación, no transacciones PostgreSQL de los servicios ni arranque de Nest. La suite SQL ampliada pasó otras 47 comprobaciones en Supabase y revirtió sus fixtures. La migración 0016 y su hash se verificaron: 48 tablas y 16 migraciones internas. Seguridad terminó sin avisos; rendimiento mantiene solo INFO.

Pendiente: build estricto de Nest, pruebas HTTP y concurrentes con servicios reales, login del servidor/TLS, compilación SwiftUI en Mac y pruebas de hardware. E11.04 queda implementada con validación de integración pendiente; no certifica el cierre de toda E11.
