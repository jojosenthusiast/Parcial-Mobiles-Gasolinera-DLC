# API, seguridad y transacciones

## Contrato común

Base `/api/v1`. UUID, RFC3339 UTC y decimales como cadenas. Queries incluyen cursor/limit (default 50, máximo 200), filtros permitidos y orden estable por fecha+id. Nunca aceptar SQL/columnas arbitrarias desde query. Respuesta `{data, meta:{requestId, asOf, source, coverage, nextCursor}}`. Mutación retorna recurso y versión, o referencia al job/confirmación pendiente.

Comandos irreversibles operativos usan `Idempotency-Key`. Almacenamiento único por organización+actor+comando+clave, hash del payload y respuesta/estado. Misma clave/mismo contenido devuelve mismo resultado; misma clave/contenido distinto → 409. Alcance/id/permisos se revalidan incluso al consultar resultado. Expiración no permite volver a ejecutar un documento ya contabilizado: postingKey del hecho permanece único.

`expectedVersion` obligatorio al actualizar recurso existente y al cerrar/aprobar. Error `{code,message,fieldErrors[],retryable,currentVersion,requestId}`. Códigos base: VALIDATION, FORBIDDEN, NOT_FOUND, CONFLICT, INVALID_STATE, INSUFFICIENT_STOCK, INCOMPATIBLE_PRODUCT, PRICE_UNAVAILABLE, APPROVAL_REQUIRED, COST_PENDING, EXTERNAL_PENDING, STALE_DATA. 400 forma inválida; 401 sesión; 403 permiso; 404 inexistente/no visible según política; 409 versión/estado; 422 regla de negocio; 503 indisponibilidad temporal. No devolver detalles internos ni fallar silenciosamente.

## Superficie API por dominio

El patrón `:id/<acción>` es comando auditado, no edición directa de flags.

| Módulo | Consultas | Comandos principales |
| --- | --- | --- |
| Sesión | GET /me, /me/capabilities | POST /auth/login, /refresh, /logout, /sessions/revoke |
| Usuarios | GET /users, /users/:id/activity | POST /users, /users/:id/assign-role, /suspend, /activate, /reset-access |
| Sucursales | GET /branches, /branches/:id, /configuration/check | POST /branches, PATCH /branches/:id/draft, POST /activate, /suspend, /archive |
| Catálogo combustible | GET /fuel-products, /:id/specifications | POST /fuel-products, /:id/specifications; PATCH /:id |
| Infraestructura | GET /branches/:id/dispensers, /tanks; GET /dispensers/:id, /positions/:id/availability, /tanks/:id | POST /configurations, /configurations/:id/approve, /positions/:id/close, /reopen |
| Inventario | GET /tanks/:id/movements, /measurements, /balance, /reconciliation | POST /measurements, /opening-balances, /adjustments, /adjustments/:id/approve |
| Precios | GET /prices/current, /schedules, /references, /quotes | POST /schedules, /:id/submit, /approve, /schedule, /cancel; POST /applications/:id/confirm |
| Abastecimiento | GET /suppliers, /suppliers/:id, /purchase-orders, /receipts, /invoices | POST /purchase-orders, /:id/submit, /approve, /send, /cancel; POST /receipts, /:id/accept, /reject; POST /supplier-invoices, /payments |
| Pista | GET /positions, /dispenses/:id, /meters/:id/history | POST /dispenses, /:id/authorize, /cancel, /resolve; POST /readings, /meter-intervals/:id/confirm |
| Ventas/caja | GET /sales, /sales/:id, /cash-sessions/:id | POST /cash-sessions, /sales, /payments, /refunds, /cash-sessions/:id/count, /reconcile, /close |
| Cortes | GET /cuts, /cuts/:id, /cuts/:id/validation | POST /cuts/:id/prepare, /submit, /return, /close, /adjustment-requests |
| Incidencias | GET /incidents, /incidents/:id/timeline | POST /incidents, /:id/assign, /impacts, /loss-assessments, /costs, /recoveries, /resolve, /close |
| Mantenimiento | GET /assets, /work-orders, /plans, /technical-tests | POST /plans, /work-orders, /:id/start, /complete, /verify, /release; POST /technical-tests |
| Tienda | GET /products, /assortment, /lots, /stock, /stock-counts, /transfers | POST /lots/receive, /stock-counts, /:id/approve, /transfers, /:id/dispatch, /receive; POST /returns |
| Personal | GET /employees, /shifts, /coverage, /handovers | POST /employees, /shifts, /attendance, /handovers; POST /employees/:id/change-status |
| Gastos/servicios | GET /expenses, /service-orders, /accounts/receivables | POST /expenses, /:id/approve, /pay; POST /service-orders, /:id/consume, /complete; POST /vouchers, /settlements |
| Planificación | GET /replenishment/scenarios/:id | POST /replenishment/scenarios, /:id/create-order |
| Analítica | GET /dashboard, /metrics/:name, /alerts, /reports/:name | POST /alerts/:id/acknowledge, /assign, /resolve; POST /saved-views, /exports |
| Soporte | GET /exports/:id, /jobs/:id, /audit, /sync/changes | POST /imports/preview, /imports/:id/commit; endpoints restringidos de recuperación |

En E02 crear contrato base; cada etapa añade solo sus endpoints funcionales. No publicar endpoints ficticios que devuelvan 200 con arrays de demo sin fuente. Acciones en tabla relativas a su recurso; OpenAPI explicita ruta final, DTO y policy. Parámetros/filtros invalidan la query y no se ignoran silenciosamente.

## Autenticación

Contraseñas centrales con Argon2id y parámetros medidos/documentados; nunca texto recuperable. Sesión por dispositivo con token opaco aleatorio almacenado como hash en servidor. iOS guarda token/refresh en Keychain; web usa cookies HttpOnly/Secure con SameSite apropiado, validación Origin y token CSRF para mutaciones. Access/refresh con duración configurable, rotación, revocación y detección de reutilización. No localStorage con sesión persistente. Login limitado por intentos, respuesta sin revelar existencia de cuenta. Recuperación/alta con enlace o código de un solo uso, vencimiento y cambio inicial. Demo con credenciales documentadas solo en modo desarrollo.

Desactivar usuario o cambiar alcance incrementa versión de permisos y revoca/revalida sesiones. `/me/capabilities` alimenta UI, pero cada comando vuelve a comprobar política. `actorId` del cliente no autoriza. Un registro de empleado sin usuario no puede hacer login.

## Catálogo mínimo de permisos

`branch.read/manage/activate`; `infrastructure.read/propose/approve`; `fuel.read`; `price.read/propose/approve/apply`; `inventory.read/measure/receive/adjust/request/approve`; `purchase.read/create/approve/receive`; `dispense.read/authorize/resolve`; `sale.create/read/refund.request/refund.approve`; `cash.open/count/withdraw/close`; `cut.read/capture/submit/close/adjust.approve`; `incident.create/read/assign/resolve`; `loss.approve`; `maintenance.plan/work/verify/release`; `staff.read/manage/schedule`; `user.manage`; `expense.create/approve/pay`; `finance.cost.read/margin.read`; `report.read/export`; `audit.read`; `integration.manage`.

Asignaciones por rol basadas en la matriz de la auditoría, copiadas a tests. Cada permiso tiene ámbito organization/branch/assignedResource/ownSession, vigencia y límite. No basta `generalManager=true` para pasar todas las mutaciones. Mantener lista explícita. Aprobador puede ser distinto del solicitante según política; si no hay segundo usuario, la demo usa excepción explícita auditada, no una aprobación invisible.

## Concurrencia e integridad

Transacciones de saldo, reserva, pago/caja, recepción y cierre bloquean las filas agregadas afectadas en orden estable. `SELECT FOR UPDATE` más restricciones únicas para exclusividad; SERIALIZABLE y reintento acotado cuando el agregado/consulta lo exija. Revalidar tras adquirir bloqueo. No sostener transacción SQL mientras espera hardware/procesador.

Almacenar intento/estado → commit → worker/adaptador externo → confirmación idempotente → nueva transacción de conciliación. Inbox única por proveedor+externalEventId; validar autenticidad de callbacks y estado. Un timeout deja pendiente, el proceso de recuperación consulta referencia externa antes de reenviar. La tabla outbox guarda eventos/jobs con el cambio de negocio; entrega al menos una vez, consumidores idempotentes.

Índices: organización/sucursal+fecha/estado; meter+interval; document reference normalizado por proveedor y tipo; externalSource+externalId; source+postingKey; job type+scope+period. Restricción de una autorización activa por posición y una caja abierta por register. No borrar operaciones publicadas; comandos compensatorios.

Jobs: leases `lockedUntil`, retries/nextAttempt, estado pending/running/succeeded/failed/dead, error redacted. Tras caída expira lease y se reintenta con idempotencia. Programación de dos cortes crea los pendientes faltantes desde activación/calendario; no depende de abrir dashboard. Cierre automático desactivado por defecto; solo política explícita y validaciones equivalentes al manual permiten habilitarlo.

## Adjuntos, exportaciones y registros

Lista permitida de formatos, tamaño configurado, validación tipo real y análisis al habilitar archivos de terceros. Acceso autenticado o URL temporal que respete ámbito; no archivos de otros usuarios adivinando id. Auditoría y exportaciones excluyen secretos y minimizan datos personales. Un export vuelve a validar permiso al generar/descargar. PDF/CSV/XLSX usan snapshot o watermark consistente para que paginación concurrente no altere totales.

Objetivos de rendimiento propuestos, a medir: abrir ficha desde caché visible en menos de 300 ms; respuesta API p95 < 800 ms para detalle/lista con fixture de referencia; reporte estándar < 3 s, grandes como job; 30 días×20 estaciones de fixture analítico. Si no se cumplen, medir consulta/índice antes de optimizar UI a ciegas. Estos objetivos no son resultados ya logrados.
