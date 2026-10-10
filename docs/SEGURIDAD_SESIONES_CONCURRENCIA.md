# Auditoría de concurrencia, sesiones y correo de invitación — 2026-10-09

## Estado vigente de esta actualización documental

**Fecha de evidencia:** 9 de octubre de 2026. Esta sección prevalece sobre recuentos y resultados posteriores conservados como historial. La evidencia es **local** y no acredita aceptación, despliegue, producción ni E2E de negocio.

- Checkout dedicado autorizado en `main`; commits locales `55d1e99` (harness unitario tolerante a CRLF) y `a413d21` (limpieza de logging de sesión Flutter). No hubo push ni despliegue.
- Entorno: Windows 10 x64; Node `v24.19.0`, pnpm `11.25.0`, Flutter `3.47.5` stable y Dart `3.13.4`; no hay dispositivos ADB conectados.
- `pnpm run test:unit`: salida 0, **222 pass, 0 fail, 0 skipped**. `test:integration` tiene 3 pruebas **SKIP** porque `DLC_API_BASE_URL` no está definido; no contactó endpoint alguno.
- Como comprobaciones locales previas en Node 24: build, typecheck, lint; contratos 93/93, web 15/15, contrato Flutter 1/1 y verificadores estructurales de reporte/aceptación/release. No son recorridos E2E de negocio ni walkthrough de navegador.
- Flutter actual: `flutter analyze --no-pub` pasa en `dlc_api`, `dlc_customers` y `dlc_operations`; pruebas Dart actuales: Clientes 1/1 y Operaciones 4/4. `dlc_api` no tiene directorio `test/`. La limpieza eliminó una comparación nula inalcanzable en `employee_session.dart:2241`; no cambió comportamiento fuente.
- APK de Operaciones reconstruido con `flutter build apk --debug --dart-define=DLC_API_BASE_URL=http://10.0.2.2:4000/api/v1`: salida 0, 179,113,952 bytes, SHA-256 `123C1F5D0F018866107EA359B094CDA5148ED8968E4A197B1DD93B6A00D49BD0`; canónico y alias son idénticos. No se instaló. El APK de Clientes no se reconstruyó: falta URL y publishable key de Supabase QA; el archivo existente permanece sin cambios, SHA-256 `bfe141f3190b7caeafbc68d8030cdd30f4695ec582f6d1f1cf84374362049e64`.
- El catálogo fuente local tiene 108 migraciones hasta 0108. Esta sesión no abrió conexión a Supabase, no ejecutó SQL, seeds, API, concurrencia, autenticación/persistencia de sesión ni flujos remotos. Tampoco hubo navegador autenticado.
- RDD está activo por defecto, pero no hay revisión ni recibo/PASS: la evaluación del rango comprometido es de riesgo alto y STATUS solicita `external.select_intended_untracked` para cuatro caches/locks Flutter sin seguimiento; esa captura no está disponible en este runtime. Las seis modificaciones Windows de plugin (solo final de línea) y esos cuatro archivos sin seguimiento no se deben stagear/restaurar.
- Bloqueadores: destino QA aislado identificado con `DLC_API_BASE_URL`, login/tenant de prueba, URL y publishable key de Supabase QA, navegador autenticado y dispositivo Android. Mailjet, sandbox de tarjeta, DTE, push y Mac/iOS/Keychain siguen sin evidencia, credenciales ni aprobación aplicable; la contraseña antigua expuesta de Mailjet no debe reutilizarse.

## Trabajo aplicado

- Las cuentas vinculadas a una ficha de empleado ahora solo pueden iniciar sesión si su empleado está activo y existe un turno programado vigente para su sucursal, según el reloj de PostgreSQL.
- La misma condición se vuelve a comprobar en la renovación del token y en cada autenticación de acceso. Al vencer el turno, los siguientes comandos protegidos se rechazan aunque la app siga abierta. La vigencia del turno es starts_at <= hora_servidor < ends_at; el empleado debe tener estado activo y el turno no estar cancelado.
- Las cuentas sin employee_id (por ejemplo, cuentas administrativas de organización no asociadas a una ficha de empleado) conservan la política de sesión existente.
- Se añadieron pruebas que verifican que login fuera de turno no crea sesión y que un token de empleado sin turno vigente no autentica.

> **Límite de evidencia vigente:** la sesión actual solo comprobó analizadores y pruebas locales. No conectó API/Supabase, no ejecutó login, refresh, persistencia de sesión ni concurrencia de dos clientes. Las descripciones de abajo son revisión de código e historial; no son prueba de runtime. Mailjet sigue bloqueado: no hay API key/secret, remitente/DNS verificados ni envío, y la contraseña antigua expuesta no debe reutilizarse.
## Concurrencia observada

El servidor ya usa transacciones, bloqueos de fila, índices/constraints, claves de idempotencia y versiones optimistas en varios flujos críticos. Ejemplos comprobados: fichas de personal, alta de sucursal, turnos sin solapamiento, compras, cortes, precios, incidencias, activos y despachos. Cuando un formulario lleva una versión vieja, ciertos endpoints devuelven conflicto para que se recargue el registro.

Esto no equivale a un control de versión común aplicado a cada edición de todos los módulos. Antes de producción conviene exigir una prueba de concurrencia real (dos clientes guardando el mismo registro) para cada agregado editable, y confirmar que cada mutación financiera/de inventario usa transacción e idempotencia. Las pantallas deben mostrar el conflicto y permitir recargar; no deben reintentar una escritura con una versión nueva sin comparar el cambio.

## Sesión en el teléfono

Flutter guarda access token, refresh token y session id con flutter_secure_storage y al arrancar restaura la identidad y renueva el token si hace falta. Cerrar y abrir el proceso no equivale a cerrar sesión. El servidor tiene una vida máxima de sesión de 14 días; el bloqueo por turno tiene precedencia y no autoriza operaciones fuera del horario. Los cambios de permisos, suspensión y logout revocan sesiones.

La persistencia del almacén seguro está comprobada por código, no por una prueba de reinstalación/dispositivo físico en esta sesión. Desinstalar, borrar datos del sistema o invalidar la cuenta puede quitar la sesión.

## Seguridad de datos/API observada

- Contraseñas de usuario se verifican con Argon2id; access/refresh tokens se almacenan como hashes y la rotación de refresh detecta reutilización.
- PostgreSQL de producción exige TLS con verificación de certificado; la API opera con un rol SQL de runtime restringido y las migraciones aplican RLS/revocaciones según tabla.
- La API debe considerarse accesible desde los clientes y protegerse con autenticación/autorización; la base de datos no debe publicarse directamente. CORS y controles del proxy/hosting siguen siendo configuración del despliegue.
- Datos de contacto como correo y teléfono permanecen como texto de aplicación en PostgreSQL. El cifrado en reposo depende del proveedor/disco/backup configurado; no es cifrado de campo a campo en la aplicación. Las contraseñas/tokens sí tienen hash, no cifrado reversible.

## Mailjet y alta por invitación

El servidor ya tiene el flujo de cuenta invitada con token de activación aleatorio, hash en base de datos, expiración de 72 horas y uso único. En producción el endpoint no revela ese token, pero el envío por Mailjet ni una pantalla para completar la activación aún están configurados. Por tanto, Mailjet no quedó conectado y el alta no debe considerarse terminada.

La herramienta de navegador falló al iniciar por un error local del sandbox. Además, la contraseña de inicio de sesión de Mailjet no sustituye las credenciales de API. La integración requiere API key y secret de Mailjet, dirección remitente verificada, URL pública HTTPS para completar activación y configuración de SPF/DKIM del dominio. No se debe almacenar la contraseña de la cuenta en el repositorio ni enviarla desde el cliente. Se debe rotar la contraseña compartida en el chat.

Mailjet exige validar la dirección/dominio remitente y recomienda configurar SPF/DKIM antes de enviar: [Inicio rápido](https://documentation.mailjet.com/hc/es/articles/37251169295003--Inicio-r%C3%A1pido-con-Mailjet). Las API key/secret son credenciales distintas; el secret se muestra al crearlo y protege acceso de API/SMTP: [Claves API](https://documentation.mailjet.com/hc/es/articles/360043225693--Qu%C3%A9-son-las-claves-de-API).

## Verificación de esta modificación

- TypeScript server build: PASS.
- ESLint en archivos tocados: PASS.
- Suite unitaria servidor: 210/210 PASS (incluye 2 pruebas nuevas de acceso por turno).
- No se probó un teléfono físico ni se configuró la cuenta Mailjet, remitente, DNS o envío real.
