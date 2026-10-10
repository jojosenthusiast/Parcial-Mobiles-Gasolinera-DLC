# Revisión UI/UX y activos operativos — 2026-10-10

## Estado vigente de esta actualización documental

**Fecha de evidencia:** 9 de octubre de 2026. Esta sección prevalece sobre recuentos y resultados posteriores conservados como historial. La evidencia es **local** y no acredita aceptación, despliegue, producción ni E2E de negocio.

- Actualización de entrega verificada el 9 de octubre de 2026: checkout dedicado autorizado en `main`; los commits de trabajo `55d1e99` (harness unitario tolerante a CRLF) y `a413d21` (limpieza de logging de sesión Flutter), junto con el commit documental `e80ebbf59d77c90f9f6642d9ebc558e33b2afd03`, se enviaron correctamente a `origin/main`. La rama local `main` está sincronizada con `origin/main`. No hubo despliegue.
- Entorno: Windows 10 x64; Node `v24.19.0`, pnpm `11.25.0`, Flutter `3.47.5` stable y Dart `3.13.4`; no hay dispositivos ADB conectados.
- `pnpm run test:unit`: salida 0, **222 pass, 0 fail, 0 skipped**. `test:integration` tiene 3 pruebas **SKIP** porque `DLC_API_BASE_URL` no está definido; no contactó endpoint alguno.
- Como comprobaciones locales previas en Node 24: build, typecheck, lint; contratos 93/93, web 15/15, contrato Flutter 1/1 y verificadores estructurales de reporte/aceptación/release. No son recorridos E2E de negocio ni walkthrough de navegador.
- Flutter actual: `flutter analyze --no-pub` pasa en `dlc_api`, `dlc_customers` y `dlc_operations`; pruebas Dart actuales: Clientes 1/1 y Operaciones 4/4. `dlc_api` no tiene directorio `test/`. La limpieza eliminó una comparación nula inalcanzable en `employee_session.dart:2241`; no cambió comportamiento fuente.
- APK de Operaciones reconstruido con `flutter build apk --debug --dart-define=DLC_API_BASE_URL=http://10.0.2.2:4000/api/v1`: salida 0, 179,113,952 bytes, SHA-256 `123C1F5D0F018866107EA359B094CDA5148ED8968E4A197B1DD93B6A00D49BD0`; canónico y alias son idénticos. No se instaló. El APK de Clientes no se reconstruyó: falta URL y publishable key de Supabase QA; el archivo existente permanece sin cambios, SHA-256 `bfe141f3190b7caeafbc68d8030cdd30f4695ec582f6d1f1cf84374362049e64`.
- El catálogo fuente local tiene 108 migraciones hasta 0108. Esta sesión no abrió conexión a Supabase, no ejecutó SQL, seeds, API, concurrencia, autenticación/persistencia de sesión ni flujos remotos. Tampoco hubo navegador autenticado.
- RDD está activo por defecto, pero no hay revisión ni recibo/PASS: la evaluación del rango comprometido es de riesgo alto y STATUS solicita `external.select_intended_untracked` para cuatro caches/locks Flutter sin seguimiento; esa captura no está disponible en este runtime. Las seis modificaciones Windows de plugin (solo final de línea) y esos cuatro archivos sin seguimiento no se deben stagear/restaurar.
- Bloqueadores: destino QA aislado identificado con `DLC_API_BASE_URL`, login/tenant de prueba, URL y publishable key de Supabase QA, navegador autenticado y dispositivo Android. Mailjet, sandbox de tarjeta, DTE, push y Mac/iOS/Keychain siguen sin evidencia, credenciales ni aprobación aplicable; la contraseña antigua expuesta de Mailjet no debe reutilizarse.

## Resultado

Se completó la primera versión funcional de Activos operativos para registrar y controlar terminales POS, medidores, mangueras, herramientas y equipo de seguridad. El inventario queda separado del combustible por tanque y de la mercadería POS por lote. Aceites, refrigerantes y otros productos de venta rápida siguen en Inventario/Tienda.

La pantalla resume unidades por estado e incidencias abiertas y grafica cambios mensuales de los últimos seis meses. Las barras incluyen valores y detalle textual para que el dato no dependa solo del color. Web y la app de Operaciones usan el mismo dominio y permisos; Clientes no recibe controles administrativos que no corresponden a su función.

## Flujos incluidos

- Registrar equipo con código único, tipo, nombre, ubicación y metadatos; el costo se solicita y se devuelve solo a perfiles con permiso explícito.
- Buscar y filtrar por tipo/estado; abrir ficha e historial inmutable.
- Editar ficha con versión esperada para detectar actualizaciones simultáneas.
- Asignar o devolver custodia; cambiar condición, retirar o verificar recuperación; trasladar entre sucursales con autorización en origen y destino.
- Crear incidencias de daño o pérdida enlazadas al activo. Un trigger transaccional pone el equipo dañado en reparación o perdido en estado missing, registra el evento y limpia la custodia cuando corresponde.
- Generar el reporte operational_assets con filtros de fechas y las exportaciones disponibles en el módulo.

## Revisión visual y de interacción

- Se reutilizaron colores, tarjetas, etiquetas y controles existentes para mantener continuidad con las pantallas actuales.
- La actividad se presenta como una serie temporal compacta, con conteos y alternativa textual; no se usa un gráfico circular sin detalle.
- Las acciones aparecen según permisos y estado, y las operaciones sensibles piden nota de auditoría. Los cambios vencidos devuelven conflicto de versión para volver a cargar la ficha.
- Las animaciones son pequeñas y respetan la preferencia del sistema para reducir movimiento; la web también aplica prefers-reduced-motion.
- Filtros y detalles son responsivos; los controles mantienen etiquetas, foco visible y estados legibles sin depender del color.

## Hallazgos corregidos

1. Costo oculto que podía borrarse en una edición. La API podía sustituir por NULL el costo que el usuario no tenía permiso de leer. Ahora no permite enviar ese campo sin permiso y conserva el valor existente cuando se omite. Prueba de regresión añadida.
2. Falta de perfil editable en las vistas nuevas. Web y Operaciones ya permiten editar metadatos con control optimista de versión.
3. Falta de vínculo práctico a incidencias. La ficha ahora ofrece registrar daño o pérdida; la pérdida cambia el estado a missing en la misma transacción de la incidencia.
4. Representación estadística incompleta. Se agregó resumen por estado, incidencia pendiente y actividad por mes tanto al tablero web como a Operaciones; Activos quedó disponible como reporte también en móvil.

## Evidencia de esta revisión (histórica; la evidencia vigente de arriba tiene precedencia)

- Servidor: build TypeScript, ESLint, 222 pruebas unitarias y 93 pruebas de contrato.
- Web: sintaxis JavaScript y 15 pruebas web.
- Flutter: flutter analyze sin issues en Operaciones y Clientes; APK debug de Operaciones compilado.
- Contrato Flutter y verificación de paquete fuente: PASS.

## Límites comprobados

- PostgreSQL no responde en localhost:5432 (pg_isready); Docker no está instalado. Por eso la migración 0105_operational_assets.sql y sus triggers aún no se han aplicado ni probado contra un servidor PostgreSQL real. El catálogo fuente vigente contiene 108 migraciones; no se generó ni verificó un ZIP nuevo en esta actualización.
- flutter test no llegó a iniciar: el lanzador Flutter de esta sesión informa que falta PROGRAMFILES(X86). El APK sí compila y el análisis estático pasa. No instalé ni probé en teléfonos/emuladores.
- No hubo recorrido web autenticado en navegador en esta sesión. El módulo se verificó por pruebas, contratos y análisis estático.
- La app de Clientes se revisó a nivel de alcance: el inventario operativo pertenece a empleados/gerencia y no debe aparecer en la experiencia de lealtad del cliente.
- El catálogo de roles debe otorgar estos permisos deliberadamente. operational_asset.cost.read controla la exposición de costos; operational_asset.verify, transfer y retire separan acciones sensibles.

## Validación real de base

La afirmación de que 0105–0108 se ejecutaron en Supabase PostgreSQL 17.11 es histórica y no fue revalidada por esta sesión; no debe usarse como prueba de migración remota. El smoke SQL transaccional confirmó asignación, historial inmutable, incidencia de daño y estado de reparación; un caso inválido fue rechazado. Se hizo ROLLBACK y no quedaron datos de prueba. Los advisors quedaron con cero hallazgos de seguridad; se cubrieron las 68 FK nuevas con 67 índices y los avisos globales de FK volvieron a la base previa de 331. El historial de eventos ahora carece de permisos UPDATE/DELETE para el rol runtime.
