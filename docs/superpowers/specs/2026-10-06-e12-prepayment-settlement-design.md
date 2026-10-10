# Diseño E12.04 — Anticipo y saldo no consumido

## Decisiones aprobadas

- El remanente se resuelve **por caso**: una persona operadora autorizada inicia explícitamente la disposición. El backend valida que la opción corresponda al tender registrado; no hay elección ni confirmación automática por método.
- Los anticipos usan un **ledger separado** de los intentos de cobro ligados a una venta.
- El remanente permanece pendiente hasta que la operación correspondiente tenga confirmación verificable.

## Problema observado

El pago actual requiere `sale_id`, pero la venta de combustible solo se crea desde un despacho completado. Por tanto, el flujo actual no puede registrar un anticipo previo al despacho. El contrato C07 requiere tratar el prepago como obligación hasta el despacho, reconocer la cantidad realmente entregada y mantener el remanente como `refundPending`, `refunded` o `released` (`DLC_Plan_Desarrollo/02_DOMINIO_Y_REGLAS.md`, C07). V04 requiere que un prepago de $20 con despacho real de $17 genere venta por $17 y deje $3 pendientes de reembolso/liberación; reintentar no debe duplicar la devolución (`DLC_Plan_Desarrollo/06_PRUEBAS_Y_ENTREGA.md`).

## Diseño recomendado

Agregar un ledger inmutable de anticipos previo a la venta, vinculado al despacho autorizado y a su intento/tender original. Registrar eventos idempotentes para recepción del anticipo, asignación a una venta real al confirmarse el despacho, selección de disposición del remanente y confirmación terminal. El estado del saldo se deriva de esos eventos y solo usa los estados de remanente definidos por C07: `refundPending`, `refunded`, `released`.

La venta se crea únicamente desde el volumen medido y confirmado por el flujo existente. La asignación al anticipo nunca cambia la cantidad, el precio capturado ni el importe de esa venta. Una asignación de fondos capturados se refleja una vez en `sale_collection_balances`, sin un segundo movimiento de cobro; una autorización retenida solo cubre el importe realmente cobrado a través del flujo de pago ya asociado a la venta, y la asignación enlaza a ese evento confirmado. Las asignaciones capturadas y los pagos ligados a la venta comparten el tope del total vendido; una autorización no puede sobredimensionar el cobro. Un anticipo sin despacho confirmado no se convierte en venta ni se da por reembolsado. Una interrupción o resultado `unknown` espera la reconciliación del despacho original; no habilita otro despacho ni una terminalización financiera por inferencia.

Cada anticipo financiero usa el modo manual y registra explícitamente si representa `captured` (fondos cobrados) o `authorization_hold` (fondos retenidos, aún no cobrados); los tenders simulados no crean obligaciones ni cuentan como cobros. `authorization_hold` solo es válido para tarjeta manual con referencia documental cuando el resultado ya se conoce; efectivo siempre es `captured`. Esta clasificación no es el resultado del tender: se reutilizan los resultados existentes `confirmed`, `declined` y `unknown`. Un `unknown` puede no tener referencia terminal inicial; permanece vinculado al intento original, retiene su importe y bloquea el cierre de esa sesión hasta resolverse con evidencia mediante `payment.resolve` sobre el mismo anticipo; no se convierte en anticipo cobrado ni en venta.

Para registrar/resolver el anticipo se reutilizan `payment.collect` y `payment.resolve`. Una vez iniciada la disposición C07 (`refundPending`), no se admiten nuevas asignaciones que puedan cambiar su importe. La persona operadora inicia explícitamente la disposición por remanente; el servidor solo acepta una acción compatible con la clase de tender: fondos `captured` se reembolsan, nunca se “liberan”; un `authorization_hold` confirmado se libera, no se reembolsa como dinero cobrado. El reembolso conserva separación solicitante/aprobador/ejecutor y permisos `sale.refund.request`, `approval.decide` y `payment.refund`, vinculando la solicitud al anticipo y tender originales; como las rutas actuales están limitadas a `paymentEventId`, se agrega una referencia alternativa y excluyente a anticipo sin debilitar restricciones actuales. El reembolso del remanente del anticipo es una liquidación de esa obligación, no una devolución de la venta; se registra en el ledger del anticipo y no altera `sale_collection_balances.refunded_usd`, que conserva su semántica de reembolsos de pagos ligados a una venta. `refunded` solo se registra después de confirmación. La liberación queda asociada al mismo hold y solo pasa a `released` con evidencia de confirmación. El remanente permanece en el estado C07 pendiente hasta su terminalización. El registro de decisión y los reintentos conservan actor, importe, moneda, vínculo original y clave idempotente; no hay selección automática ni llamada a un proveedor.

Los cobros, reembolsos y liberaciones se concilian según su clasificación original y conservan las reglas de caja existentes. Solo fondos `captured` generan entrada de efectivo/liquidación; una autorización retenida no cuenta como cobro. Un reembolso de efectivo registra salida en la sesión de ejecución; reembolso de tarjeta reduce la liquidación correspondiente; liberar un hold no simula una devolución cobrada. La devolución monetaria **no** repone combustible ni crea un ajuste de inventario. Si una corrección física procede, es una operación de inventario separada, fuera de E12.04.

## Superficies y secuencia

1. Migración SQL aditiva nueva, sin modificar ni ejecutar migraciones existentes; constraints para vínculo al despacho/tender original, una asignación única por venta/anticipo, importe asignado no mayor que el anticipo y eventos terminales idempotentes.
2. DTO/servicio/controlador de anticipos para iniciar y resolver el mismo intento, con permisos existentes (`payment.collect`, `payment.resolve`, y el flujo de reembolso existente); reusar auditoría, idempotencia y límites de sucursal/organización existentes. Resolver `unknown` requiere evidencia, solo permite resultado final `confirmed` o `declined`, y no crea otro intento.
3. Extensión acotada del vínculo de aprobación/reembolso para referenciar exactamente un `payment_event` o un anticipo; mantener intactas las validaciones actuales de importe, sucursal, actor distinto y medio original.
4. Integración mínima con finalización/reconciliación de despacho: crear/asignar la venta por cantidad real y mantener el saldo no consumido pendiente, sin duplicar venta ni descontar inventario otra vez.
5. Pruebas deterministas del servicio y del contrato SQL para V04, repetición, despacho cero, despacho interrumpido/unknown y referencias al pago original. Actualizar `server/docs/E12_PAGOS_Y_CAJA.md` con el flujo implementado y sus límites.
6. Ejecutar solo suites locales pertinentes y el verificador Windows completo. No conectar Supabase ni ejecutar migraciones en una base de datos.

## Invariantes de aceptación

- Anticipo capturado de $20 + despacho confirmado de $17 → una venta de $17, asignación de $17 visible como cobrada una sola vez, saldo de $3 pendiente. Un hold autorizado de $20 + venta de $17 solo captura $17 mediante el pago ligado a la venta y deja $3 para liberación confirmada. Un reintento idéntico no crea otra venta/asignación/cobro/refund.
- Un despacho cero no crea una venta combustible. El anticipo conserva vínculo y trazabilidad hasta que una persona autorizada elija la disposición y exista confirmación.
- Un resultado de tender `unknown` conserva la reserva original y bloquea el cierre de caja hasta que se resuelva con evidencia; no se repite como un nuevo intento. Un despacho interrumpido/unknown conserva su reserva y se consulta/reconcilia el mismo despacho.
- Un anticipo `captured` no puede usar `released`; un `authorization_hold` confirmado no puede usar `refunded`. La selección del operador debe coincidir con la clasificación y confirmación original.
- El reembolso no supera el saldo disponible, referencia el anticipo/pago original y sigue los controles de aprobación existentes. No altera inventario físico.
- Una liberación de hold se registra como completada solo al contar con confirmación verificable; no aparece como liquidación de tarjeta; un reintento no duplica eventos.
- E12.01–E12.03/E12.05 continúan compatibles: precio/volumen real, cobro reservado, refund original, eventos de caja y cierre inmutable mantienen sus contratos.

## Límites y asuntos que detienen la implementación

No se determina cómo un procesador real confirma una liberación; no existe integración física configurada. La implementación puede registrar referencias/evidencias manuales según contratos existentes, pero no simular confirmación externa ni invocar proveedor. La clasificación `authorization_hold` solo puede originarse en evidencia manual del intento original; no se infiere por `method='card'`. Si el esquema actual no permite enlazar aprobación y devolución al anticipo sin debilitar sus restricciones, detenerse y presentar la incompatibilidad antes de ampliar el alcance. No se inventan impuestos, costos, volúmenes físicos, permisos, confirmaciones ni comportamiento del proveedor.

No se ejecutará ninguna migración, se mutarán datos ni se contactará Supabase durante este bloque. El proyecto no tiene `.git` propio y el usuario prohibió commits; este diseño queda sin commit.
