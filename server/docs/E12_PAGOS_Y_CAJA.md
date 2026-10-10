# Pagos y caja — núcleo de servidor

La migración `0021_payments_and_cash.sql` incorpora cajas, sesiones, intentos, confirmaciones, devoluciones, movimientos y arqueos. La venta conserva sus líneas, precios, costos y comprobante original. Su estado de cobro se calcula desde los eventos; no se modifica el comprobante.

## Cobro

1. Crear una caja con `POST /branches/{branchId}/cash/registers` y abrir sesión mediante `POST /cash/sessions`, con fondo inicial y el usuario autenticado como cajero.
2. Registrar cada medio con `POST /branches/{branchId}/payments`. Una venta mixta tiene varios intentos por el importe de cada medio, cuya suma no puede superar el total. Todos se vinculan a una sesión propia abierta.
3. Efectivo se confirma por el cajero y genera un único movimiento positivo. Tarjeta manual exige una referencia documental que identifique proveedor/terminal y transacción. No se guardan PAN, CVV ni credenciales de tarjeta. El registro manual no sustituye la consulta al procesador.
4. Un resultado desconocido conserva la reserva del importe y bloquea el cierre de la sesión. Se consulta mediante `GET /sales/{saleId}/payments` y se resuelve con `POST /payments/{attemptId}/resolve`, conservando el intento original. Un rechazo documentado libera la reserva.

Los comandos usan UUID y una huella de los datos normalizados, actor y sucursal. Un reintento idéntico devuelve el registro original; cambios de importe, ámbito o identidad se rechazan. La referencia de una confirmación no puede reutilizarse para otro intento. Nunca se vuelve a descontar inventario al cobrar.

El modo `simulated` de tarjeta almacena resultados deterministas explícitos y se bloquea en producción, incluido el reintento de escritura. No genera cobro real ni liquidación de caja. Las simulaciones se usan en datos de prueba; no se debe mezclar ensayo con operación comercial. La integración con proveedor físico sigue pendiente.

## Anticipos antes del despacho (E12.04)

Un anticipo se registra en un ledger separado, ligado a la autorización original de despacho; no requiere crear antes una venta. Solo se admite tender `manual`, nunca `simulated`. `tenderKind` distingue fondos ya cobrados (`captured`) de una retención aún no cobrada (`authorization_hold`); no se deduce del método. Una retención solo puede ser de tarjeta manual. Los resultados conservan `confirmed`, `declined` y `unknown`.

### Flujo y rutas

| Acción | Ruta y permiso | Campos esenciales del cuerpo |
|---|---|---|
| Registrar anticipo | `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/prepayments` — `payment.collect` | `commandId`, `cashSessionId`, `method`, `mode: manual`, `amountUsd`, `tenderKind`, `outcome`; tarjeta conocida requiere `evidenceReference`. |
| Resolver resultado desconocido | `POST /branches/{branchId}/prepayments/{advanceId}/resolve` — `payment.resolve` | `commandId`, `outcome: confirmed|declined`, `evidenceReference`. Resuelve el mismo anticipo, no crea otro intento. |
| Asignar a venta | `POST /branches/{branchId}/prepayments/{advanceId}/allocate` — `payment.collect` | `saleId`, `amountUsd` explícito, `commandId`; para `authorization_hold`, también el `paymentEventId` ya confirmado de esa venta. |
| Solicitar devolución de remanente capturado | `POST /branches/{branchId}/prepayments/{advanceId}/refund-requests` — `sale.refund.request` | `commandId`, `amountUsd`, `reason`. |
| Ejecutar devolución | `POST /branches/{branchId}/prepayments/{advanceId}/refunds` — `payment.refund` | `approvalId`, `commandId`, `cashSessionId`, `amountUsd`, `reason`, evidencia del tender original (`evidenceReference`). |
| Seleccionar liberación de retención | `POST /branches/{branchId}/prepayments/{advanceId}/release-requests` — `payment.resolve` | `commandId`, `amountUsd`. |
| Confirmar liberación | `POST /branches/{branchId}/prepayments/{advanceId}/release-confirmations` — `payment.resolve` | `commandId`, `confirmationReference` de la operación confirmada. |
| Consultar anticipos recientes | `GET /branches/{branchId}/prepayments` — `payment.read` | Hasta 100 registros de la sucursal; incluye importe asignado, saldo no aplicado, elegibilidad de devolución, aprobación y estado de liberación (`pending`/`released`). |

Para reembolsar, la solicitud sigue requiriendo aprobación de otra persona: la decisión existente usa `POST /approvals/{approvalId}/decision` con `approval.decide`; es un paso distinto de solicitar y ejecutar. La ejecución conserva el tender original, requiere su evidencia y una sesión de caja propia abierta. No se simula una respuesta del procesador ni se invoca un proveedor; la evidencia manual no es integración con procesador.

### Asignación y saldo no consumido

La venta debe existir y corresponder al despacho original completado, conciliado con la cantidad realmente dispensada. El anticipo no crea ventas. Un despacho sin flujo, `unknown` o interrumpido no habilita venta ni asignación: se reconcilia el mismo despacho antes de continuar.

- Una asignación `captured` suma una sola vez al saldo cobrado de la venta. Asignaciones capturadas y pagos activos de la venta comparten el límite del total vendido.
- Una asignación `authorization_hold` enlaza el pago de venta ya confirmado mediante `paymentEventId`; ese pago cuenta una sola vez y el hold no agrega otro cobro. Solo cubre el importe exacto del pago ligado a la venta.
- El remanente solo usa estados C07 `refundPending`, `refunded` o `released`. Elegir su disposición congela nuevas asignaciones: fondos `captured` se reembolsan; una retención de tarjeta manual confirmada se libera, no se reembolsa como dinero cobrado. El remanente de anticipo no cambia `sale.refunded_usd`, que corresponde a devoluciones de pagos de venta.
- La devolución monetaria no repone combustible ni modifica inventario o cantidad vendida. Cualquier corrección física es un flujo separado.

Los comandos son idempotentes: repetir los mismos datos devuelve el registro existente; reutilizar el comando con datos distintos se rechaza. Los movimientos de caja los registra un trigger de base de datos, no una inserción directa del servicio. Un anticipo `unknown` conserva su importe reservado y bloquea el cierre de la sesión hasta resolverse con evidencia en el mismo anticipo. Si se selecciona una disposición, permanece pendiente hasta confirmación verificable; `released` o `refunded` no se infieren por método ni por una referencia sin confirmar.

## Devolución autorizada

Se solicita con `POST /payment-events/{paymentEventId}/refund-requests`, vinculando pago confirmado, importe y motivo. El aprobador usa la ruta existente `/approvals/{approvalId}/decision` y necesita `approval.decide` y `sale.refund.approve`. Otra persona debe aprobar. El ejecutor usa `POST /payment-events/{paymentEventId}/refunds` con `approvalId`, sesión propia abierta y permiso `payment.refund`.

La base comprueba coincidencia de organización, sucursal, solicitante, pago, importe y motivo. Una aprobación permite una sola ejecución. La suma de devoluciones no supera el pago original. Una devolución de tarjeta requiere evidencia y permanece en tarjeta; una devolución de efectivo genera salida de caja. Una devolución financiera no reincorpora combustible o artículos al inventario ni abre nuevamente la deuda de la venta.

`GET /branches/{branchId}/sales/{saleId}/refund-requests` devuelve, en orden cronológico inverso y con límite de 100, las solicitudes de devolución ligadas a pagos de esa venta. Incluye importe y medio original, solicitante, motivo, estado, resolución y fecha/ID del reembolso cuando existe. Requiere `payment.read` y valida la venta en la organización y sucursal solicitadas. Para solicitar otra devolución sobre el mismo pago, no debe haber una solicitud pendiente o aprobada sin ejecutar; el servicio bloquea el pago, revisa su saldo neto vigente y serializa la creación contra los reembolsos concurrentes. Las restricciones y el trigger de PostgreSQL siguen siendo la última validación de saldo y aprobación.

## Caja y arqueo

`POST /cash/sessions/{sessionId}/movements` permite entrada, retiro y depósito con motivo. El depósito reduce efectivo y no constituye gasto o venta. Solo el propietario de una sesión abierta puede actuar. Un registro de caja no puede tener dos sesiones abiertas.

`POST /cash/sessions/{sessionId}/close` recibe efectivo contado y liquidación de tarjetas por separado. PostgreSQL calcula los esperados y las variaciones. Las devoluciones de una sesión posterior afectan esa sesión, sin reescribir un arqueo anterior. Una diferencia requiere motivo y queda `pending_review`; no se aprueba automáticamente mediante límites inventados. La revisión independiente está implementada; el relevo formal de cajeros sigue pendiente.

El cierre de caja es independiente del corte operativo; no cierra Matutino ni Vespertino. Los permisos financieros nuevos no se asignan automáticamente a ningún rol. El gerente general también necesita permiso y sesión propia para operar caja.

## Verificación y alcance pendiente

Verificación local del 8 de octubre de 2026, con Node `v24.19.0` y pnpm `11.25.0`: typecheck/build, `test:unit` (28 archivos), `test:contract` (15 archivos), `test:web` (1 archivo), lint y verificadores de plan/aceptación/release pasan. En esta pasada no está configurada `DLC_API_BASE_URL`; el runner de integración solo ejecutó el chequeo local de health y no verificó rutas financieras autenticadas. Las pruebas de servicios usan clientes PostgreSQL stub; esta corrida no valida concurrencia en una base real. Las migraciones 0022–0083 figuran aplicadas en `sole/DLC`, con validaciones documentadas en la evidencia E24.

La app móvil incluye consulta, captura, conciliación y asignación de anticipos. Antes de iniciar un despacho autorizado, el usuario con `payment.collect` y `cash.read` puede registrar efectivo confirmado o el resultado manual de una tarjeta como capturado, rechazado, desconocido o retención; el servidor crea el movimiento de efectivo y conserva la referencia requerida. En **Anticipos y devoluciones** se muestran hasta 100 registros, saldo asignado/no aplicado y estado. Un anticipo capturado y confirmado se puede aplicar a la venta completada del mismo despacho, con límite local y validación final del servidor. Un resultado `unknown` puede resolverse con `payment.resolve` y evidencia. Una retención confirmada se solicita liberar por su saldo exacto y se cierra solo al registrar la referencia de terminal; no se contabiliza como efectivo ni como devolución cobrada. La devolución monetaria conserva su flujo separado de solicitud, aprobación independiente y ejecución en caja propia. Siguen pendientes paginación financiera general, detalle de movimientos, conteos intermedios/relevos, fiscalidad POS y conexión a terminal físico. El comprobante interno combinado muestra por separado cobro e impuestos de cada venta; no crea una sola operación de pago. La vista de ventas distingue pagado/pendiente y muestra saldo/reembolsado desde el servidor.

Esta verificación no sustituye recorridos HTTP autenticados ni pruebas de carga. El servicio de API todavía no tiene un usuario restringido con `LOGIN` ni secreto de despliegue. Faltan PostgreSQL 18.6 de QA con datos representativos, terminal físico y Mac/Xcode. Las pruebas stub y contractuales no acreditan compilación Swift, integración HTTP ni comportamiento concurrente en base de datos.
# Revisión de diferencias de caja (E12.05)

El cierre de caja calcula el efectivo esperado, la liquidación de tarjeta y sus diferencias en la base de datos. Si hay faltante o sobrante, el cierre original conserva `pending_review` y se crea una solicitud `cash.variance.approve` ligada a ese cierre. La decisión se guarda aparte; no cambia el conteo ni las cifras originales. Un usuario distinto del cajero, con `approval.decide` y el permiso específico `cash.variance.approve`, puede aprobar o rechazar con motivo desde `POST /approvals/:approvalId/decision` (incluyendo `branchId`). La organización debe asignar esos permisos a sus revisores de caja.

`GET /branches/:branchId/cash/reviews?status=pending` permite encontrar cierres que necesitan revisión. `GET /branches/:branchId/cash/sessions/:sessionId/review` devuelve el detalle y la decisión. `GET /branches/:branchId/cash/sessions/:sessionId/movements` devuelve movimientos por tipo, hasta 100 por página; `beforeAt` y `beforeId` forman el cursor siguiente. Las tres consultas exigen `cash.read` y filtran por organización y sucursal. En móvil, el revisor con `approval.decide` y `cash.variance.approve` ve la acción solo si no cerró ese turno. El comando se guarda localmente; antes de reintentar se consulta la solicitud, y la base serializa decisiones concurrentes y audita actor, fecha y motivo.

Las migraciones 0022 y 0023 se verificaron con casos transitorios en PostgreSQL del proyecto DLC. Los contratos móviles de caja y aprobación pasan; falta validar HTTP autenticado, concurrencia real y la compilación/recorrido visual de las pantallas iOS en Xcode.
