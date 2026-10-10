# Contrato de dominio

Este archivo manda sobre decisiones incompletas de las auditorías. Nombres son contratos propuestos; E02 los fija en OpenAPI y esquema sin cambiar semántica. UUID para entidades; códigos visibles únicos por ámbito y no reutilizables tras archivar. Registros operativos incluyen branchId, occurredAt, recordedAt, actorId, source, version y references pertinentes. Organización única inicial; organizationId en límites de acceso para no mezclar instalaciones futuras.

## C01. Cantidades, dinero, tiempo y origen

API decimales como texto. PostgreSQL volumen `numeric(24,12)`, precio/costo unitario `numeric(24,12)`, valor de inventario `numeric(24,8)` e importes monetarios registrados `numeric(20,2)`; conservar cálculo no redondeado cuando corresponda. Swift Decimal y decimal.js leen cadenas. Rechazar overflow, NaN/infinito, escalas no admitidas y textos ambiguos. No usar Float/Double para dinero.

Conversión exacta: 1 gal US = 3.785411784 L. Registrar cantidad original, unidad, base (`observed`/`temperatureCompensated`), normalizada y versión de conversión. Conservar lectura de medidor en su unidad original. Cambiar preferencia visual no genera movimiento. Redondeo comercial inicial HALF_UP a dos decimales al confirmar línea; reembolsos revierten/importan montos originales. Impuestos pueden requerir otra política: TaxPolicy versionada define base, componentes y redondeo validados; fixtures sin impuesto se identifican como sintéticos, no normativa salvadoreña. Total = suma de líneas y componentes publicados, sin centavos invisibles.

Fecha/hora UTC en eventos, zona IANA `America/El_Salvador` por defecto de estación y `operationalDate` explícita. Intervalos [inicio, fin). Fechas de cumpleaños/ingreso/vencimiento son fechas civiles. Dos períodos cubren horario abierto; para 24 h se configura 06–14 y 14–06 siguiente día como plantilla demostrativa, confirmable por estación. No suponer 14–22 para una estación 24 h.

Origen: manual, imported, pos, controller, sensor, migration, demo. Calidad: confirmed, provisional, estimatedLegacy, missing, stale, disputed. `null` significa desconocido; cero es un dato. Toda agregación devuelve cobertura y cantidad/importe sin costo conocido si existe.

## C02. Identidad y organización

User: id, usernameNormalized, fullName, email, status, credentialVersion; Employee separado. RoleAssignment: userId, role, scope, validFrom/To; PermissionGrant y ApprovalPolicy. Session: tokenHash, userId, scopeVersion, expiry, revokedAt. ActivityAudit: actor, command, target, branch, happenedAt, reason, requestId, before/after permitidos; sin contraseñas ni datos completos de pago.

Branch: código, nombre, dirección, zona, timezone, horarios versionados, profile, status, activatedAt/archivedAt. Estados draft/configuring/ready/active/suspended/archived. Suspensión impide operaciones nuevas pero permite lectura y acciones de conciliación/reparación específicamente autorizadas. No cambiar fecha de alta para manipular cobertura.

## C03. Infraestructura y productos

FuelProduct: sku, displayName, family(super/regular/diesel), brand, specificationRef, status. TechnicalSpecification: atributo, valor/unidad, método RON/MON/AKI/cetano cuando aplica, límite vs medido, fuente, vigencia. Etanol/biodiésel/azufre opcionales; jamás inferidos del nombre premium.

BranchFuelOffer enlaza productos efectivamente vendidos. Tank: assetId, productId, nominalCapacity, safeFillLimit, unusableReserve, chartRef, status. Capacidades verificadas antes de activación. Measurement: tank, valores de altura/volumen/agua/temperatura disponibles, base, timestamps y quality.

Dispenser: assetId, código, branch, status; Position: dispenserId, sideCode, serviceMode; Nozzle: positionId, productId, meterId, validFrom/To; SupplyLink: nozzle, tank/line y vigencia. En la implementación inicial cada manguera tiene un suministro único; configuraciones físicas mezcladas requieren adapter/receta validada y se marcan no habilitables si aún no se soportan. No simplificar una instalación real a un tanque incorrecto.

AvailabilityResult devuelve selectable, reasons[], computedAt y fuente. Combina técnico, operativo, ocupación, producto/inventario y conexión. TechnicalBlock y OperationalClosure separados con inicio/fin, motivo, actor y referencia. No liberar automáticamente un activo por completar una orden si quedan otros bloqueos.

## C04. Libro de inventario y costos

InventoryMovement es inmutable: product/tank o lot, signedQty, valueDelta, sourceDocument/line, occurredAt, postedAt, reason, actor, uniquePostingKey, reversalOf. Saldo materializado se mantiene en la misma transacción, reconstruible a partir de apertura y movimientos. Lectura física no modifica saldo contable; diferencia aprobada genera ajuste.

Combustible: promedio ponderado móvil por tanque/producto en base comparable. Si Q,V antes de recepción y q,v aceptados, nuevo costo medio=(V+v)/(Q+q). Salida x registra x*costo medio y valor remanente; al vaciar completamente asignar residuo de precisión a última salida, saldo final Q=0,V=0. Costos desconocidos impiden margen confirmado, no bloquean necesariamente registrar cantidad física con `costPending`.

No contabilizar venta y totalizador como dos salidas. `MeterInterval` tiene una fuente de contabilización elegida: aggregateManual o transactional. En modo transaccional, lecturas solo concilian; en manual, un tramo confirmado genera la salida una vez. Cambiar modo requiere frontera/lectura de transición, no reconstruir ventas históricas automáticamente.

Recepción aceptada aumenta cantidad; calidad/quarantine decide disponible. Reserva para autorización reduce disponible, no existencia física. Despacho confirmado consume reserva y existencia; expiración solo libera si estado externo resuelto. Ventas simultáneas al mismo tanque bloquean saldo/reservas en transacción.

Backdating: entrada tardía conserva occurredAt real y postedAt actual. No reordenar promedio de costos ya cerrado silenciosamente; ajuste de costo autorizado referencia intervalo original y período de contabilización. En período abierto una reconstrucción versionada puede recalcular con aprobación y reporte de cambios. Cambio de costo en factura luego de recepción se distribuye entre existencia y costo vendido de forma trazable o queda discrepancia pendiente; jamás sustituir simplemente el costo unitario de toda la historia.

## C05. Precios y tributación

ReferencePrice, SupplierQuote y SalePriceSchedule son entidades separadas. Schedule: product, branch/zone/serviceMode/override, value, currency, unit, validFrom/To, status, source, approval. Resolución: override aprobado de posición > precio de sucursal/modalidad > precio de zona/modalidad; a igual prioridad, solapamiento es error. Al aprobar, generar asignaciones resueltas por destino y vigencia para evitar fallback ambiguo. Precio aplicado queda copiado en venta/tramo y conserva scheduleId.

Cambio programado: draft/submitted/approved/scheduled/applying/applied/partial/failed/cancelled. PriceApplication registra destino y acuse. Fuente manual requiere confirmación explícita del responsable; simulador no se presenta como acuse físico. Una sesión de despacho conserva precio acordado al autorizar salvo regla del equipo documentada; no cambiar a mitad de venta.

TaxPolicy/TaxComponent versionados: producto, base, rate/fixedAmount, included/excluded, vigencia y método de redondeo. Datos oficiales pendientes se configuran antes de operación real. No aplicar `total/1.13` a todo combustible ni doble sumar contribuciones ya incorporadas. `FinancialBreakdown` guarda subtotal, descuentos, devoluciones, bases, componentes, total, coste y calidad de cálculo.

## C06. Compras y recepción

Supplier: datos/contactos, alcance, activo; SupplyTerms: producto, plazo, mínimo, unidad, crédito, ventana y priceFixingEvent. Quote: costo, cargos, impuestos/base, validez y fuente. PurchaseOrder: status(draft/submitted/approved/sent/partial/received/cancelled/closed), proveedor, líneas, cantidades, fecha comprometida/versiones y política. Approval separada con decisión/motivo.

Shipment y compartment; DeliveryReceipt con ReceiptAllocation por producto/tanque/compartimento, mediciones y cantidades documentadas/aceptadas/rechazadas. Recepción parcial no cierra saldo pendiente. Límite de capacidad al momento de llegada considera movimientos contemporáneos y base compatible; recepción física no se infiere solo de factura.

SupplierInvoice/InvoiceLine, CreditNote, Payable, PaymentAllocation: separar entrega/factura/pago y permitir parcialidad. Recepción pendiente de factura usa costo provisional documentado. Conciliación de tres documentos: orden/recepción/factura. Transferencia intersucursal: despacho origen → en tránsito → recepción destino; no dos compras/ventas; diferencia en tránsito es expediente.

## C07. Despacho, ventas y pagos

DispenseSession: posición/manguera, actor/operador, priceSnapshot, requestAmount o requestVolume, reservationId, sourceMode, controllerRef y state. Estados created/paymentPending/authorizing/authorized/dispensing/completed/settlementPending/settled/cancelled/exception. Transiciones requieren confirmación apropiada. Falla de comunicación da unknown/pending, no `cancelled` por defecto. No repetir habilitación sin consultar estado.

FuelTransaction: volumen real, precio/base, importe fuente, inicio/fin y número externo único. Importe informado por equipo se conserva y compara con cálculo; diferencias de redondeo solo dentro de tolerancia configurada. DispenseBatchManual valora intervalos y crea venta agregada claramente identificada; no inventa clientes ni tickets individuales desde dos lecturas.

Sale/Ticket y SaleLine de fuel/store/service; PaymentAttempt, Payment, Refund y allocations. Prepago es anticipo/obligación hasta despacho; venta reconoce cantidad real; remanente tiene refundPending/refunded/released. Transfer/card confirmed exige fuente. Pagos mixtos suman importe, reembolso no excede cobrado neto, devolución física no equivale a devolución financiera. Emisión fiscal es adaptador separado del comprobante interno.

CashSession: branch/register/cashier/openingFund/time, movimientos y conteos. Una caja no tiene dos sesiones abiertas; transferencia de responsabilidad requiere relevo. CashMovement distingue venta, devolución, entrada, retiro, depósito y pago de gasto. ExpectedCash=opening+cashIn-cashOut; card y transferencia se concilian aparte. No usar total ventas como efectivo esperado.

## C08. Cortes

Cut: branch, operationalDate, slotId, startsAt/endsAt, configSnapshotId, expectedDispenserIds, status, version, submitted/closed actor/time, ledgerWatermark. Detail por bomba y manguera; esperadas aunque fuera de servicio, con evidencia. Estados scheduled/open/prepared/inReview/closed; devolución a open mantiene historial. Ajustes postcierre no reabren original.

Reading: meter, initialRef, finalValue, unit, resetEvent si existe, actor/time. Inicial proviene del intervalo anterior; primer dato es apertura documentada. Disminución solo mediante cambio/rollover reconocido con regla/evidencia; nunca `max(diff,0)` como solución.

CloseCut: bloquear corte/ámbito y validar versión; comprobar identidad, conjunto esperado, intervalos completos, precio/costo/calidad, lectura continua, documentos, comparación de totalizadores/ventas, tank reconciliation, cash reconciliation y excepciones aprobadas; registrar firma y watermark; generar agregados sin volver a aplicar movimientos. Resultado repetible por idempotencyKey. Si dato no permite cierre ordinario, estado en revisión; no completar cero por ausencia.

El período siguiente puede capturar hechos mientras anterior está en revisión; el cierre final respeta dependencias y no altera lecturas ya usadas. Ajuste posterior registra período original y actual; reportes permiten ver tal como se emitió y versión ajustada con etiqueta.

## C09. Incidencias, pérdidas y mantenimiento

Incident: tipo, severidad, activo/contexto, descripción, responsibleId, occurredAt, evidence, state(reported/triaged/inProgress/resolved/closed). Un informe rápido no exige costos; tareas de evaluación quedan pendientes. TechnicalResolution y FinancialResolution distintos.

IncidentImpact: combustible, cantidad/base, persona/tercero/activo según pertinencia; LossAssessment guarda costo, valor comercial y fuente/calidad separados. Approval genera un InventoryMovement único. IncidentCost enlaza factura/orden/gasto, no copia importes contabilizados dos veces. RecoveryClaim != RecoveryReceipt; el cobro recibido se registra separadamente. No tasar lesiones con litros.

MaintenancePlan, WorkOrder, WorkTask, PartConsumption, AssetStateInterval y TechnicalTest. Plan por tiempo/uso, generación idempotente; completar con resultado/evidencia; liberación técnica autorizada si no quedan bloqueos. Water/temperature/leak observation guarda instrumento/fecha/calidad; si no disponible, nulo. AnomalyRule genera alerta de revisión y permite confirmar/descartar; nunca robo definitivo sin investigación.

## C10. Tienda, personas y gastos

StoreProduct y BranchAssortment separan catálogo de oferta/minStock por estación. Lot: costo y qty por condición; Allocation almacena qty/costo por lote consumido. FEFO ordena salida elegible; retorna al lote/condición apropiada. No modificar lotes ya consumidos para alterar costos. StockCount ajusta diferencia aprobada; Transfer tiene origen/transit/destino. Descuento/promo versionados, límites por permiso y snapshot de venta.

Employee separado de User, ScheduledShift con fechas concretas, puesto y branch; WeeklyTemplate genera asignaciones, Attendance y Handover. Intervalos solapados y cobertura se validan; baja conserva historia; actualiza futuras asignaciones con razón. Legislación laboral no se codifica como límites inventados.

Expense: categoría, documento, fecha de devengo, monto/componentes, estado, pago y centro de costo. ServiceOrder: catálogo local, presupuesto/precio, responsable, materiales, ejecución, entrega/cobro. Materiales consumidos enlazan movimientos. CorporateAccount/Vehicle/Voucher/Limits/Receivable/Settlement para crédito; no marcar crédito como efectivo.

## C11. Abastecimiento y métricas

ReplenishmentScenario conserva forecastAsOf, método, muestra/cobertura, existencia útil, recepciones confirmadas, leadTime, ventana, costo pactable, capacidad segura y razones. InventoryAtArrival=currentUsable-demandUntilArrival+confirmedReceiptsBeforeArrival. RecommendedQty=min(target-InventoryAtArrival, safeHeadroomAtArrival), ajustada a mínimos y compartimentos sin superar capacidad; si restricciones son incompatibles, `noFeasiblePlan`, no cantidad negativa o falsa solución.

Ahorro potencial=qty*(costAlternative-costNow)-additionalFreight-financing-otherComparableCosts. No llamarlo utilidad realizada. Si costo no confirmado, escenario incierto. Una caída futura no permite esperar hasta agotarse: compra puente. Usuario aprueba orden; la sugerencia no compra automáticamente.

Métricas y agregaciones se definen en `05_PANTALLAS_REPORTES_Y_METRICAS.md`. Las alertas son registros con responsable/estado y referencia al origen, no contadores independientes sin detalle.
