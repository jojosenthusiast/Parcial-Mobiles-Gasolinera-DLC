# Cuentas de trabajadores y cliente QA (DLC)

Agrega al tenant QA (org `00000000-0000-4000-8000-0000000000a1`) despachador, cajero, encargado de tienda, un cajero de Guatemala y un cliente de la app Clientes.

## Orden
1. Requisito: `qa-setup.generated.sql` ya aplicado (organización, gerente general, sucursales `QA-SV-01` y `QA-GT-01`).
2. `cd server && node scripts/generate-qa-workers.mjs` crea (ignorados por git):
   - `scripts/sql/qa-workers.generated.sql` (hashes argon2id; no lo compartas por chat).
   - `.qa-workers-credentials.local.txt` (contraseñas en texto plano).
3. Un administrador pega TODO `qa-workers.generated.sql` en el SQL editor de Supabase (rol `postgres`) y lo ejecuta. Es una sola transacción, repetible: nunca pisa contraseñas ni cuentas existentes. La última consulta debe devolver `worker_roles 3`, `worker_users 4`, `worker_assignments 4`, `future_or_current_shifts 480` (aprox.).
4. Cliente: `cd server && node scripts/create-qa-customer.mjs` (lee `SUPABASE_URL` y `SUPABASE_SECRET_KEY` de `server/.env`, no imprime secretos). Crea `qa.cliente@dlc-qa.example` con correo confirmado y escribe `.qa-customer-credentials.local.txt`. Con `--reset-password` cambia la clave de un cliente ya existente.
5. La API necesita `CUSTOMER_ORGANIZATION_ID` configurado (ver `README-qa-setup.md`).

## Cuentas y turnos
- Despachador (`qa.despachador@`), cajero (`qa.cajero@`) y encargado de tienda (`qa.tienda@`) en `QA-SV-01`; cajero GT (`qa.cajero.gt@`) en `QA-GT-01`. Todos con dominio `dlc-qa.example`.
- Roles mínimos: ninguno aprueba. Las aprobaciones (reembolsos, ajustes de inventario, diferencias de caja) las hacen los gerentes.
- Las cuentas ligadas a un empleado solo inician sesión con un turno activo. El SQL crea turnos de 24 h contiguos (todo el día, toda la semana) por 120 días desde ayer UTC. Pasado ese plazo, vuelve a ejecutar el mismo SQL para extenderlos.
- Para mostrar las cajas/bombas en los turnos, el gerente crea la caja (permiso `cash.register.manage`) y las bombas desde el alta de sucursal; el turno no depende de ello.

## Rotar o eliminar
- Rotar claves: `node scripts/generate-qa-workers.mjs --rotate` y ejecutar `qa-workers-rotate.generated.sql` como administrador (revoca sesiones).
- Quitar sin borrar historial: `UPDATE users SET status='suspended', permission_version=permission_version+1 WHERE organization_id='00000000-0000-4000-8000-0000000000a1' AND employee_id IS NOT NULL;`
- Cliente: eliminarlo en Supabase Auth (Authentication > Users). Borrar el tenant completo: `qa-remove.sql`.
