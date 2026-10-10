# Política y cobro con puntos

## Política central

Las migraciones `0089_loyalty_program_approval.sql` y `0091_customer_points_redemption_rate.sql` y la app de Operaciones permiten versionar la política a nivel de organización. El administrador general define puntos por USD elegible, compra mínima y valor USD por punto. Un valor de canje de cero deshabilita el medio de pago. Cada versión nueva pasa por borrador, envío y aprobación de otra persona. Las decisiones y sus actores quedan en eventos inmutables y auditoría. El vencimiento aún no se ofrece: falta un proceso que concilie puntos usados, vencidos y devueltos.

Asigna `loyalty.program.read`, `loyalty.program.manage` y `loyalty.program.approve` al rol autorizado de administración general mediante `role_permissions`, con asignación global (`branch_id IS NULL`). Quien crea o envía la versión no puede aprobarla. Las políticas históricas se marcan como anteriores al doble control.

## Pago monetario con puntos

La migración `0092_customer_points_sale_tender.sql` añade cotizaciones de un solo uso con vencimiento de 120 segundos y asientos de pago separados del efectivo/tarjeta. Operaciones solicita puntos para una venta que ya tiene una cuenta activa vinculada. El Cliente autenticado ve sucursal, venta, puntos e importe en USD y debe confirmar expresamente. El QR identifica la cuenta; nunca aprueba el canje. El servidor vuelve a comprobar política, cuenta, saldo, vínculo, sesión de caja, vencimiento y saldo pendiente de venta bajo locks; registra débito y tender en la misma transacción. El tender cuenta para pagar la venta, pero no altera el efectivo esperado de caja. En un pago mixto, solo la porción cobrada en efectivo/tarjeta/anticipo capturado es elegible para ganar puntos.

Rutas documentadas en `contracts/openapi.json`:

- `POST /branches/{branchId}/sales/{saleId}/customer/points/quotes`
- `GET /customer/me/points-payment-quotes`
- `POST /customer/me/points-payment-quotes/{quoteId}/confirm`
- `POST /customer/me/points-payment-quotes/{quoteId}/decline`

La app de caja puede volver a consultar el saldo de venta después de la decisión del Cliente y registrar el remanente con el flujo de cobro existente. Los comandos de solicitud y decisión son idempotentes; la cotización no reserva puntos, por lo que la confirmación falla de forma segura si el Cliente gastó el saldo por otro flujo mientras tanto.

## Límite de producción pendiente

La migración `0093_customer_points_refund_reversals.sql` genera un reverso acumulativo proporcional de los puntos ganados cuando se inserta un reembolso monetario aprobado. Aun así, el pago con puntos no debe habilitarse para transacciones reales: falta devolver/revertir el tender de puntos usado en ventas devueltas o canceladas, definir saldo negativo/recuperación, y cubrir devoluciones parciales mixtas. El catálogo/canje de premios también necesita reversos y conciliación. Mantén `redemptionUsdPerPoint` en `0` hasta que se implemente esa política, se definan reglas de devolución parciales y la matriz de aceptación del handoff pase. Tampoco se deben activar multiplicadores de campaña: la acumulación todavía no asocia cada crédito con una versión de promoción ni revierte puntos por devolución.

Las migraciones `0086`–`0093` necesitan aplicarse y probarse en PostgreSQL QA. Este entorno no tiene PostgreSQL, Flutter ni Android SDK; el typecheck, lint y pruebas Node/contrato no equivalen a ejecutar migraciones ni a probar las apps en dispositivo. Ver `docs/HANDOFF_QA_MAQUINA.md`.
