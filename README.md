# DLC Gasolineras · Laboratorio 22

Aplicación móvil en SwiftUI para supervisar estaciones DLC y registrar su operación diaria. El proyecto conserva el `.xcodeproj`, el esquema, los assets de marca y la organización MVVM que ya tenía. Requiere iOS 17 o posterior y no incorpora paquetes externos.

## Continuación y paquete de QA

- Para continuar el trabajo pendiente en la máquina local, sigue HANDOFF_TRABAJO_PENDIENTE_WORK.md.
- HANDOFF_QA_MAQUINA.md y docs/HANDOFF_QA_MAQUINA.md resumen verificaciones y límites conocidos.
- Los APK de QA están en artifacts/qa-2026-10-09/ y usan Git LFS. Después de clonar, ejecuta git lfs install y git lfs pull para descargar los binarios.
- Verifica los archivos del paquete con artifacts/qa-2026-10-09/SHA256SUMS.txt.

## Abrir y ejecutar en Mac

1. Descomprime el paquete y abre `DLCGasolineras.xcodeproj`.
2. Selecciona el esquema `DLCGasolineras` y un simulador iPhone con iOS 17 o posterior.
3. Ejecuta con `⌘R`.

## Cuentas de demostración locales

- Gerente General: `admin` / `admin123`
- Gerente de Sucursal: `santa` / `santa123`

Estas cuentas se usan en el modo **Demo local**; no son credenciales del servidor Supabase. La app identifica el perfil después de comprobar las credenciales. No hay selector de rol. El gerente local solo puede operar la sucursal que tiene asignada; una cuenta inactiva o sin sucursal activa no inicia sesión.

## Flujos incluidos

### Gerente General

- Dashboard de red o de una sucursal con periodos de hoy, 7 o 30 días.
- Galones vendidos, venta estimada de combustible en dólares, inventario de tanques, alertas, ventas de tienda y niveles bajos de inventario.
- Alta, edición y archivo/reactivación de sucursales.
- En modo servidor, alta reanudable de sucursal desde el directorio remoto: plantilla, cantidad de bombas, identidad, readiness por pasos, confirmación/diferimiento de personal, revisión de bloqueos y activación con control de versión.
- Alta y asignación de gerentes locales, edición de perfil, restablecimiento de contraseña y activación/desactivación de cuentas.
- Catálogo de tienda: alta y edición de productos, SKU y código de barras únicos, costo, precio, mínimo de existencia y disponibilidad.
- Proveedores: contactos, datos fiscales opcionales, tipo de abastecimiento y estado.
- Vista de existencias y lotes por sucursal, productos por vencer, personal y órdenes de mantenimiento.

### Gerente de Sucursal

- Dashboard de la estación asignada con niveles de tanques, autonomía estimada, avance de cortes y alertas de tienda.
- Dos cortes diarios: Matutino (06:00–14:00) y Vespertino (14:00–22:00).
- Registro de lectura inicial/final para Súper, Regular y Diésel en las seis bombas.
- Registro de compra/recepción de combustible y de pérdidas con causa y explicación.
- Historial de cortes con búsqueda, periodo, turno y vista de detalle.
- Punto de venta para efectivo, tarjeta y transferencia; valida existencias, calcula cambio y genera un ticket local.
- Recepción de productos por lote, inventario, ajustes con motivo, historial de movimientos y alertas de vencimiento.
- Registro y edición de colaboradores, estado laboral y turnos semanales.
- Inventario técnico, estado de bombas, tanques y otros equipos; órdenes de mantenimiento con prioridad, seguimiento y costo.

## Reglas principales

- El perfil académico exige seis bombas y sus lecturas esperadas. El perfil operativo usa las bombas, mangueras y combustibles configurados para cada sucursal. La lectura acumulada no puede disminuir; un cambio de totalizador se registra como evento autorizado.
- Los cortes son Matutino (06:00–14:00) y Vespertino (14:00–22:00). Las ventas se calculan desde totalizadores acumulados. La unidad de cada lectura se conserva; cuando se convierte, 1 galón estadounidense equivale a 3.785411784 litros.
- El corte descuenta las ventas y pérdidas, suma las recepciones y valida que el inventario quede entre cero y la capacidad del tanque. El cierre no se aplica dos veces.
- Los estados de tanque son crítico (≤30%), medio (>30% y ≤60%) y óptimo (>60%). Se muestran con texto e icono además de color.
- El punto de venta excluye productos inactivos, existencias insuficientes y lotes vencidos. Al vender, descuenta primero el lote con vencimiento más próximo (FEFO).
- Una anulación requiere motivo, conserva el ticket y repone unidades en sus lotes de origen con movimientos de retorno en el kardex. La devolución monetaria se gestiona fuera de la app.
- El sistema conserva el registro histórico: sucursales, productos, proveedores, cuentas y activos se desactivan o archivan en lugar de borrarse físicamente.

## Persistencia y modos de ejecución

La app iOS tiene dos modos. **Demo local** guarda datos en JSON dentro de Application Support y secretos locales en el llavero; la primera ejecución crea datos de muestra. **Servidor** autentica contra la API NestJS, que conserva los datos operativos en PostgreSQL de Supabase. El teléfono y el navegador no se conectan directamente a la base ni reciben sus credenciales. El panel web utiliza una sesión cifrada en cookie y accede al mismo API.

El stack API, worker, PostgreSQL local y panel web se puede levantar en Windows con Docker Desktop siguiendo [infra/README.md](infra/README.md); también se puede conectar el API a Supabase con los secretos del servidor. La compra/venta física de combustible no se acciona automáticamente: el adaptador de despacho configurado es manual hasta integrar y validar el equipo real. POS, pagos y precios no sustituyen terminales, facturación fiscal ni fuentes oficiales. Los datos de demostración y las políticas fiscales deben reemplazarse o confirmarse antes de una operación real.

Para comprobar qué está validado y producir un ZIP de fuente portable, consulta [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md). Los comandos `node scripts/verify-release.mjs` y `node scripts/package-release.mjs` funcionan en Windows, macOS y Linux con Node 24.15 o superior; el ZIP excluye `.env` local, dependencias, compilados y respaldos.

La especificación funcional, las reglas de negocio, los contratos de seguridad, las pruebas de aceptación y la matriz de trazabilidad están dentro de [docs/plan](docs/plan/00_EMPEZAR_AQUI.md). El estado consolidado se mantiene en [docs/plan/ESTADO.json](docs/plan/ESTADO.json), y las evidencias por etapa están en [docs/evidence](docs/evidence/E24.md).

## Verificación manual en Xcode

1. Inicia sesión con ambas cuentas y comprueba que cada rol recibe sus pestañas y alcance de sucursal.
2. Como gerente general, crea y edita una sucursal, un gerente, un producto y un proveedor; verifica validación de campos y códigos duplicados.
3. Como gerente local, intenta completar el flujo de venta: recibe un lote, agrega productos al carrito, cobra con efectivo y revisa total, cambio e inventario.
4. Prueba una venta con inventario insuficiente y otra con un lote vencido; confirma que no se registran.
5. Anula una venta con motivo y verifica el estado del ticket y la reposición al lote original. Confirma que el motivo es obligatorio.
6. Registra daño, vencimiento y ajuste de inventario; revisa cantidades límite y movimientos del kardex.
7. Agrega personal, programa turnos, abre una orden de mantenimiento y comprueba el cambio de estado del activo.
8. Registra los tres combustibles en las bombas 1–6. Intenta cerrar incompleto; completa el corte y verifica la consolidación del tanque una sola vez.
9. Cierra y vuelve a abrir la app; comprueba la persistencia de los datos operativos y el acceso de demostración.

En este entorno no están instalados Xcode, `xcodebuild` ni el compilador Swift. La compilación y ejecución de Simulator deben confirmarse en un Mac con Xcode. La API sí se compiló y se probó por HTTP contra PostgreSQL 16.15; también pasaron migraciones limpias, smoke tests SQL y backup/restore aislado. Docker Compose y los recorridos web autenticados siguen pendientes.

Consulta [AUDITORIA-LAB22.md](AUDITORIA-LAB22.md) para el alcance, matriz de requisitos y límites de esta versión.

## Estado de implementación

El workspace contiene la app SwiftUI, API, worker de reportes, esquema PostgreSQL versionado hasta la migración `0083_prepayment_collection_after_credit`, contrato OpenAPI, panel web y despliegue local Docker Compose. Revisa `docs/plan/ESTADO.json` para el estado de subtareas y validaciones; [docs/SUPABASE_DLC.md](docs/SUPABASE_DLC.md) describe el despliegue cloud. La API y el panel usan datos del servidor; la app conserva además el modo demo local.

La evidencia distingue pruebas locales de PostgreSQL 16.15, esquema remoto Supabase y validaciones pendientes de Xcode/Simulator, navegador autenticado, carga y dispositivos reales. Build y typecheck por sí solos no certifican esas áreas.
