# Trabajo pendiente para Work — cierre de DLC Gasolineras

**Este es el handoff prioritario para continuar en la máquina del usuario.** Completa lo posible en esta copia del repositorio y deja evidencia reproducible. Compilar no equivale a terminar el sistema ni a aceptar sus recorridos.

Proyecto: work/DLCGasolineras_Laboratorio22
Handoff QA previo: HANDOFF_QA_MAQUINA.md
Auditoría: docs/AUDITORIA_CIERRE_2026-10-09.md
Supabase: docs/SUPABASE_DLC.md
Sesiones/concurrencia: docs/SEGURIDAD_SESIONES_CONCURRENCIA.md
Repaso UI activos: docs/UX_UI_AUDITORIA_ACTIVOS_2026-10-10.md

## Objetivo

Resolver desarrollo incompleto y defectos reproducibles, ejecutar la suite Flutter y el QA integrado que faltaron, probar servidor, Supabase, web y ambas apps Flutter, y entregar evidencia para QA humano. Separa hechos, hipótesis, bloqueos externos y funciones realmente aceptadas.

## Evidencia que se debe revalidar

El handoff del 10-oct-2026 registra: build TypeScript/ESLint, 222 pruebas unitarias, 93 contratos API, 15 pruebas web, un contrato Flutter/API ejecutado con Node, análisis Flutter en ambas apps, APK debug de ambas, migraciones Supabase 0086–0108 y smoke SQL transaccional de activos con rollback. También registra que flutter test no llegó a iniciar por error del lanzador/entorno Windows y que no se instalaron APK en teléfonos ni se recorrió la web autenticada.

Hay notas anteriores que afirman que pruebas Dart sí se ejecutaron. No elijas una nota como cierta por conveniencia: inspecciona el repo y vuelve a correrlas. Registra fecha, versiones, comando, resultado y conteos. Un test Node de contrato no es un test Dart; analyze y build tampoco equivalen a flutter test.

Supabase DLC recibió 0086–0108 y el smoke dejó cero datos de prueba. No necesitas Docker ni PostgreSQL local para esa conexión. No ejecutes pruebas destructivas en producción. Confirma si faltan tenant/sucursal QA y login SQL dlc_api_runtime para rutas autenticadas.

## Reglas de ejecución

1. Lee AGENTS.md y estos handoffs; revisa git status y versiones/disponibilidad de Node, pnpm, Flutter/Dart, Android SDK, navegador y dispositivos. Conserva trabajo existente.
2. Trabaja en QA aislado. No hagas commits, pushes, publicación ni cambios irreversibles.
3. No apliques migraciones a ciegas: compara ledger/checksums, respalda QA y usa una migración nueva para correcciones. No borres historial ni alteres migraciones aplicadas.
4. No muestres secretos en terminal, logs, capturas o artefactos. La contraseña compartida en el chat se considera expuesta y debe rotarse; no la reutilices. Mailjet requiere API key/secret, remitente verificado y DNS. Guarda secretos fuera del repo.
5. No presentes integraciones simuladas como reales. Mantén canje de puntos desactivado fuera de QA hasta validar devoluciones y concurrencia. El ticket PDF es interno/no fiscal; tarjeta es simulada/manual.
6. Si algo está bloqueado, prueba alternativas seguras y registra evidencia exacta, impacto y siguiente acción; continúa tareas independientes.

## P0 — Suite Flutter, APK y dispositivos

En flutter/apps/dlc_operations y flutter/apps/dlc_customers, y en paquetes compartidos con tests:

- Ejecuta flutter pub get, flutter analyze y flutter test --reporter expanded en cada paquete. Identifica todos los tests Dart; genera cobertura si la configuración existente lo permite.
- Reproduce el fallo previo: PROGRAMFILES(X86) ausente o error test_core._globalConfigPath. Comprueba Windows, versión SDK y runner. Corrige la causa mínima; no ocultes tests ni marques error de entorno como aprobación. Si es incompatibilidad SDK, usa versión estable compatible y anota versiones.
- Añade pruebas significativas donde falten para reglas, errores, expiración, reintentos, permisos y límites.
- Recompila ambos APK desde el código final. Verifica configuración por ambiente, permisos y ausencia de secretos embebidos. Actualiza SHA-256 y artefactos.
- Si hay emulador o teléfono, instala ambas apps y prueba cierre forzado/reapertura, sesión persistida, cámara/QR, red intermitente, formularios y navegación. Indica claramente emulador o dispositivo físico.
- SwiftUI/Keychain y QA iOS requieren Mac. Si no hay Mac, registra el bloqueo; no afirmes paridad basada en el prototipo de laboratorio.

Cierre P0: suites Dart ejecutadas y contadas, analyze limpio, APK reproducibles y evidencia de dispositivo o bloqueo concreto.

## P0 — Integración API/Supabase y concurrencia

- Repite build, typecheck, ESLint, unitarias, contratos, integración HTTP, web y verificadores de aceptación/release definidos en package.json. Usa Node >=24.15 y <25; registra comandos y conteos.
- Prepara organización, sucursal, usuarios y capacidades QA; conecta la API con rol restringido dlc_api_runtime. No uses service role para simular autorización runtime.
- En Supabase QA valida migraciones pendientes, constraints, triggers, RLS, grants, FK/índices, aislamiento y rollback. El smoke previo de activos no reemplaza los recorridos autenticados.
- Ejecuta rutas autenticadas de venta/despacho, caja, pagos parciales/devoluciones, puntos, inventario, descarga contaminante, activos, turnos, reportes y exportaciones.
- Prueba dos sesiones editando el mismo agregado: una recibe conflicto/versionado legible, recarga y resuelve sin pérdida silenciosa. Incluye carreras en caja/venta, inventario/despacho, puntos/devolución, activos/incidencias y cierre de turno. Repite requests tras timeout con la misma clave idempotente; comprueba que no se dupliquen ledger, tender, movimientos, tickets ni notificaciones.
- Verifica inicio, refresh y revocación de sesión; cierre forzado/reapertura; suspensión/cambio de rol; accesos fuera del turno y justo en sus límites según reloj del servidor; aislamiento por organización/sucursal.
- Revisa autorización y logs: no filtrar JWT, secretos, datos QR, correo/teléfono o información financiera innecesaria.
- Confirma advisors Supabase actuales. La auditoría registró 331 avisos INFO de FK sin índice, 120 índices sin uso en una DB sin carga, cero lints de seguridad y default ACL EXECUTE de supabase_admin que requiere privilegio de administrador. Mide antes de eliminar índices y registra lo que exija al propietario.

## P0 — Descarga contaminante / tanque incorrecto

El flujo existe en migraciones 0095–0097, API, web y Flutter, pero falta aceptación integrada. Prueba y corrige todo el ciclo:

1. Entrega enlazada a orden/línea/proveedor/documento; combustible previsto, tanque, unidad, capacidad y saldo anterior.
2. Registrar accidente de producto/tanque equivocado con tanque y gravedad alta/crítica; producto previsto y real, cantidades reales, costo, unidad, actor, hora, proveedor, orden y evidencia.
3. Separar pérdida del contenido previo, pérdida de lo realmente recibido y remanente recuperable. No asumir perdido el pedido completo si se detectó antes. Validar litros/galones, moneda y redondeos.
4. Bloquear tanque/boquilla inmediatamente y rechazar venta/descarga incompatible. No poner inventario a cero automáticamente: conservar saldo físico contaminado/no vendible y trazabilidad de disposición.
5. Probar aprobaciones independientes, conciliación del proveedor, retiro verificado, inspección y desbloqueo autorizado; también rechazo, falta de permiso, cancelación, reintento y concurrencia.
6. Verificar maestro/detalle en web y Flutter; informes, gráficos y exportaciones deben distinguir saldo previo, entrada, pérdida, costos, remanente, unidad y bloqueo.
7. Confirmar que ninguna ruta alternativa de API salte aprobaciones.

## P1 — Desarrollo funcional por cerrar

Audita backend, SQL, pantallas, permisos e informes. No des por terminado un módulo porque exista un endpoint.

1. **Campañas financieras:** completar descuento/cashback/multiplicador transaccional, alcance congelado, vigencia, aprobación maker-checker, límites, idempotencia, liquidación, reverso y conciliación en POS, tienda, puntos y devoluciones. Excluir puntos por defecto; solo habilitarlos con política versionada aprobada. Sin reglas aprobadas, conservarlo deshabilitado.
2. **Premios:** administración, reserva atómica, inventario, canje, entrega, expiración/cancelación, devolución/restauración de puntos, permisos, auditoría, UI Cliente/gerencia e informes.
3. **Devolución de tender con puntos:** probar migración 0098 en QA; definir saldo negativo/recuperación y devolución mixta parcial/total. Probar idempotencia, concurrencia, rechazo, expiración y conciliación. Canje apagado fuera de QA hasta aceptar reglas.
4. **Push:** integrar FCM/APNs, registro/rotación/revocación de token, preferencias, reintentos, deduplicación y deep link solo si hay credenciales QA. Sin claves, deja preparado y registra el bloqueo; no envíes a usuarios reales.
5. **Mailjet/invitación:** completar envío, activación HTTPS y pantallas si faltan; probar correo preautorizado, token de un uso, expiración, reenvío/revocación y rate limit. Requiere API key/secret, sender verificado y SPF/DKIM. Usa solo destinatario QA autorizado, nunca password de cuenta ni secreto de cliente.
6. **Activos operativos:** probar alta, custodio, traslado, daño, reparación, inspección, pérdida/recuperación, retiro, versión optimista e historial append-only; enlace con incidencias/mantenimiento e informes. Separado de combustible y mercadería.
7. **Tienda:** catálogo/categorías, proveedores, lotes/vencimiento, venta, devolución física, merma, pago con puntos y acumulación solo sobre dinero elegible realmente cobrado. Aceites/fluidos rápidos son mercadería POS por lotes. Conciliar sin inflar efectivo con puntos.
8. **Despacho/caja:** bombas/productos disponibles, objetivo por volumen o monto con precio vigente, efectivo/vuelto, tarjeta claramente simulada, QR/código, confirmación de puntos por Cliente, remanente, ticket interno, reintentos, anulaciones, turno y corte. No mostrar porcentaje físico sin telemetría calibrada.
9. **Inventarios:** mantener separados combustible, mercadería POS y activos; validar cantidades, estado, transacciones, versionado, permisos, duplicados e informes.
10. **Resto de módulos:** sucursales/parque/precios, personal/turnos, compras/proveedores, gastos, crédito, servicios, mantenimiento, incidencias, perfil y configuración. Verifica recorridos y paridad web/Operaciones/Clientes con backend.
11. **Cliente/QR:** registro/consentimiento, confirmación, perfil, QR+código, saldo/equivalente USD, campañas/recompensas y alertas. El QR identifica, no autoriza; Cliente acepta el tender de puntos.
12. **Reportes/UI:** cada flujo aparece en filtros, detalle, gráficos etiquetados y exportaciones aplicables. Revisa web y ambas apps: carga/vacío/error/permisos, responsive, contraste/teclado, unidades/fechas, animaciones breves con reducir movimiento y gráficos claros sin saturación.

## P1 — Integraciones y decisiones externas

- **Mailjet:** verificar estado. Rotar contraseña expuesta. Se necesitan API credentials, remitente/dominio verificado, SPF/DKIM, callback HTTPS y autorización para prueba.
- **Tarjeta:** integrar solo con adquirente y sandbox provistos. Nunca capturar PAN/CVV; indicar simulado/manual hasta entonces.
- **Fiscalidad El Salvador:** el ticket actual es comprobante interno no fiscal. Factura/crédito fiscal/DTE requiere reglas y proveedor autorizados.
- **Push:** sin cuentas/llaves FCM/APNs no afirmar envío real.
- **Privacidad/consentimiento:** identificar textos legales que requieren aprobación.
- **iOS:** Keychain y QA SwiftUI requieren Mac.
- **Tanques:** sin telemetría calibrada mostrar solo saldo de libro, no nivel físico.

## P1 — Recorridos humanos visuales y de negocio

Con cuentas QA, recorre web autenticada en móvil/tablet/escritorio y ambas apps. Guarda evidencia sin PII. Revisa navegación, permisos, filtros, formularios, gráficos, exportaciones, carga/vacío/error, responsive y accesibilidad básica. Registra pantalla, pasos, defecto y verificación.

Casos mínimos:

- Gerente configura sucursal, personal/turno, precios, tanques, productos y permisos.
- Empleado inicia dentro del turno, despacha, cobra, emite ticket y cierra caja.
- Cliente confirma correo, muestra QR/código, ve puntos/equivalencia y acepta el pago con puntos.
- Pago mixto no supera saldo y reporta dinero/puntos correctamente.
- Tienda recibe lotes, vende, devuelve y reporta.
- Descarga equivocada bloquea tanque, separa pérdidas, concilia, retira e inspecciona.
- Activo perdido/dañado genera evento, incidencia, mantenimiento e informe.
- Dos usuarios cambian el mismo registro y reciben conflicto claro sin pérdida.

## Entregables

1. Actualiza HANDOFF_QA_MAQUINA.md, docs/HANDOFF_QA_MAQUINA.md y auditoría; corrige notas viejas o márcalas como historial.
2. Matriz de casos PASS/FAIL/BLOCKED/NOT RUN, ambiente, comando/pasos, fecha, versión/dispositivo, evidencia y defecto.
3. Resumen de código/migraciones y reglas de negocio aún pendientes de aprobación.
4. Conteos exactos de Flutter, API, web, SQL, concurrencia, seguridad, visual y dispositivo.
5. APKs QA reconstruidos, hashes, instrucciones de prueba y ZIP fuente actualizado sin secretos.
6. Lista de dependencias del propietario: Mailjet, adquirente, DTE, push, textos legales, acceso admin Supabase, Mac/teléfono.
7. Dictamen honesto de implementado/verificado/listo para QA/bloqueado. No declarar producción hasta aceptación, backup-restauración, observabilidad y revisión de seguridad.

## Criterio de cierre

Termina cuando los defectos reproducibles estén corregidos, las pruebas automatizables pasen en QA, los recorridos disponibles estén evidenciados, los artefactos correspondan al código final y cada bloqueo externo tenga causa y siguiente acción. “No se pudo” debe incluir evidencia precisa.
