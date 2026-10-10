# E01 — Cambios críticos locales

Fecha: 2026-10-04. La revisión encontró salvaguardas ya existentes en el proyecto para usuarios activos, alcance de sucursal y validaciones locales. Se añadieron dos protecciones y se mantienen pendientes las pruebas de compilación en Mac.

## Corte cerrado

`MockRepository.saveOpenCut` ahora comprueba el estado que conserva el repositorio antes de aceptar el borrador. Si el formulario se abrió antes del cierre y envía después una copia `isClosed == false`, el repositorio rechaza la escritura cuando su corte actual está cerrado o ya consolidó inventario. `closeCut` rechaza explícitamente cierres repetidos. Esto protege el almacenamiento, además de las guardas de `CutFlowViewModel`.

## Archivo local ilegible

En primer inicio, la falta del JSON permite cargar la demo. Si el archivo ya existe y no decodifica o no supera integridad, se conserva copia con nombre único, se conserva también el original, se evita sembrar/escribir datos demo y se presenta el motivo en login con el acceso deshabilitado. La recuperación manual aún requiere procedimiento probado en iOS; no se afirma que exista una herramienta de restauración.

## Comprobaciones

- Revisión estática: los dos caminos mutantes del corte consultan el estado del repositorio antes de guardar/aplicar.
- Revisión estática: el constructor distingue archivo ausente de archivo existente ilegible antes de sembrar.
- No se ejecutaron XCTest, Xcode ni Simulator: el entorno es Linux y no contiene `swift` o `xcodebuild`.
- Aún pendientes en E01: revisar/actualizar sesión activa tras suspensión o reasignación; validar continuidad entre lecturas de cortes; añadir pruebas dirigidas que puedan ejecutarse en Xcode.

## Sesión y continuidad de totalizadores

`AppState` observa cambios de usuarios y sucursales del repositorio local. Al desactivar una cuenta, cambiar su rol, reasignar un gerente de sucursal o desactivar su sucursal, cierra la sesión activa y limpia su alcance. Una reasignación exige volver a iniciar sesión para que la autoridad visible no cambie silenciosamente.

Antes de guardar una lectura, el ViewModel consulta el corte operativo anterior de la misma sucursal. Si existe, debe estar cerrado y consolidado, y las lecturas iniciales de los tres productos deben continuar las lecturas finales de la misma bomba con tolerancia máxima de 0.01 gal. Si aún no hay un corte anterior, se acepta la lectura como línea base inicial. La discrepancia devuelve un error y no guarda el borrador.

La tolerancia, el cruce matutino/vespertino y los escenarios sin corte previo necesitan pruebas XCTest en Mac; el código solo recibió verificación estática en este entorno.
