# Alta reanudable de sucursales

`0006_branch_onboarding.sql` conserva el estado del alta y agrega versión optimista. La verificación de Supabase del 5 de octubre de 2026 registra esta estructura dentro del esquema inicial aplicado. La sucursal nace como `draft`; el alta no crea saldos ni habilita despacho.

## Rutas

- `POST /api/v1/branches`: crea borrador con código, nombre, zona, zona horaria y perfil. `academicLab22` fija seis dispensadores; `operational` exige el número construido.
- `GET /api/v1/branches`: búsqueda y cursor; `branchId` limita la consulta de un gerente con alcance local.
- `GET /api/v1/branches/:branchId`: recupera el borrador entre sesiones/dispositivos.
- `PATCH /api/v1/branches/:branchId/onboarding`: guarda un paso con `expectedVersion`. Repetir una versión antigua devuelve conflicto, y cada cambio se audita dentro de la transacción.
- `GET /api/v1/branches/:branchId/readiness`: entrega códigos de bloqueo y el paso donde resolverlos.
- `POST /api/v1/branches/:branchId/activate`: vuelve a comprobar readiness bajo bloqueo transaccional. Ahora devuelve 409 mientras falten libro de inventario, precios y disponibilidad de despacho.
- `PATCH /api/v1/branches/:branchId/onboarding` con `step=staff`: registra `confirmed` o `deferred` y la cantidad activa revisada. `confirmed` requiere por lo menos una persona activa.

La readiness consulta el número real de empleados activos y exige que coincida con la revisión guardada. Si cambia la plantilla, la revisión vuelve a quedar pendiente. La activación vuelve a evaluar estos datos dentro de su propia transacción; una confirmación de pantalla por sí sola no habilita la sucursal.

El panel web presenta el alta como una lista guiada de identidad, combustibles, tanques, bombas/mangueras, saldos, precios, personal y revisión. La ficha recupera el borrador y los bloqueos desde el servidor, permite editar la identidad con control optimista de versión y enlaza cada pendiente con su módulo. El paso de personal puede guardarse para después sin habilitar la activación.

En iOS, el directorio remoto de gerencia general permite crear el borrador y reabrir su configuración mientras siga en estado `draft`. El flujo guarda código, nombre, zona, zona horaria y perfil; consulta readiness, confirma o difiere el conteo de personal activo, presenta los bloqueos actuales, abre las vistas disponibles de bombas y tanques y activa únicamente si readiness devuelve `canActivate` y la cuenta incluye `branch.activate`. Cada escritura usa la versión del servidor. La API vuelve a validar los requisitos dentro de la transacción de activación.

La lógica tiene pruebas de servicio con consultas simuladas para cantidad de personal, revisión obsoleta, rechazo de confirmación vacía y bloqueo transaccional de activación. Los contratos estáticos verifican que el cliente Swift use las rutas del OpenAPI y que decodifique la forma real de respuesta de `BranchesService`. Falta ejecutarla contra PostgreSQL real, probar el flujo en navegador autenticado y compilar el cliente iOS con Xcode.
