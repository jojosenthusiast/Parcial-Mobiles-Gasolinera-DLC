# E03 — Identidad y autorización

## Implementación

- Las cuentas están separadas del registro de empleado. Correo normalizado único, estado, versión de permisos y asignaciones temporales por sucursal.
- El catálogo de permisos es explícito. El gerente general no recibe bypass: sus roles deben tener permisos asignados. La guardia global valida sesión en cada ruta y la guardia de permisos exige ámbito organization o branch.
- Argon2id guarda hashes. El login no diferencia usuario inexistente de contraseña inválida; limita intentos por correo/IP mediante huellas HMAC y cuenta intentos de la cuenta existente.
- El servidor genera tokens aleatorios de acceso/refresh; PostgreSQL guarda SHA-256, no tokens recuperables. Refresh rota el token y revoca la sesión ante reutilización. Suspensión, cambio de contraseña y cambio de rol incrementan la versión y revocan sesiones.
- Invitación/recuperación son tokens de un solo uso. Mientras no haya canal seguro de correo, sus tokens se retornan solamente fuera de producción. Producción rechaza esas operaciones con 503 hasta configurar el envío seguro.
- Auditoría es append-only en base, excluye claves/tokens y comparte transacción con las operaciones de usuarios y aprobaciones implementadas. La aprobación propia se bloquea cuando la política lo exige; cada aprobación también necesita el permiso concreto de la acción.

## Rutas

`POST /auth/login`, `/auth/refresh`, `/auth/logout`, `GET /auth/me`, `/auth/me/capabilities`; alta y restablecimiento de acceso; cambio de estado/rol; `POST /approvals/:id/decision`.

## Verificación y pendientes

Las pruebas de contrato y referencias ESM se ejecutan sin dependencias externas. No se ha instalado Argon2/Nest ni se han aplicado migraciones porque este runtime no puede acceder al registro de paquetes o a PostgreSQL. Por tanto, la lógica necesita prueba de compilación, integración de base, 401/403, ámbito manipulado y replay de refresh antes de producción. Las cookies HttpOnly/CSRF del panel web y Keychain del cliente iOS corresponden a las etapas de cliente.
