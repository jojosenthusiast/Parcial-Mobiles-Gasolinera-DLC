# Migración del proyecto y datos

## M01. Base reproducible

`base/DLC_Base_SwiftUI_Sin_Modificar.zip` contiene 41 archivos de la carpeta de trabajo revisada. `base/manifest.json` identifica contenido con SHA-256. No contiene una prueba de compilación. El ZIP antiguo del laboratorio tiene modelos/repositorio anteriores; no iniciar desde él.

Antes de editar: `git status` si hay repo; conservar cambios del usuario; crear rama de trabajo si procede. Si no hay Git, inicializarlo solo para esta base tras comprobar estructura y excluir claves/datos operativos. Primer commit/reporte captura baseline. Comprobar proyecto/scheme mediante `xcodebuild -list`; seleccionar simulador disponible con `xcodebuild -showdestinations`. No inventar UUID de dispositivo ni declarar build limpio sin log. Si no hay Mac, estado `implemented_unverified` para iOS y continuar trabajo independiente verificable.

## M02. Protección del proyecto Xcode

Referencias explícitas PBX: cada archivo Swift nuevo necesita PBXFileReference, PBXBuildFile, grupo y Sources correspondiente. Identificadores únicos; rutas relativas estables. No convertir a formatos nuevos de Xcode innecesariamente. El target actual es iPhone iOS17; adaptar web/iPad no implica activar iPad sin verificar diseño. No importar UIKit/AppKit/SwiftUI en pruebas puras que se pretenda ejecutar fuera de Apple.

AppState deja de instanciar `.shared` por todas partes; inyectar AppContainer con autenticación, repositorios por función, reloj y navegación. Los ViewModels son @MainActor y las operaciones de red/serialización no bloquean UI. Cancelar tareas al cambiar sesión/ámbito y evitar que una respuesta vieja rellene datos de otra sucursal. No compartir objetos de UI entre actores para eliminar warnings a fuerza.

## M03. Migración funcional de archivos

| Actual | Destino gradual |
| --- | --- |
| DomainModels.swift | Models/Legacy/LegacySnapshotV1.swift + Models/DTO + Domain por módulo; conservar decodificación v1 |
| MockRepository.swift | Data/Legacy/LegacyImporter + repositorios remotos; código legado aislado mientras se porta |
| AppState.swift | SessionState/AppContainer, revocación y ámbito; no copia permanente de permiso sin refresco |
| AuthViewModel.swift | API login y errores; navegación por rol de servidor |
| GeneralManagerViewModel.swift | Consultas tipadas de dashboard/reportes con cobertura |
| BranchManagerViewModel.swift | Resumen operativo y navegación; fuentes explícitas |
| CutFlowViewModel.swift | Captura/validación remota, versión, reanudación y cierre idempotente |
| OperationsViewModel.swift | ViewModels de tienda, personal, mantenimiento y compras por responsabilidad |
| OperationsViews.swift | Extraer por módulo cuando se porte, sin duplicar tipos |
| PumpsOverviewView.swift | CutHistoryView; crear DispenserListView/DispenserDetailView reales |
| PumpsStatusView.swift | Lista de detalle esperado; lectura siempre accesible, edición según permisos |
| NewBranchView.swift | BranchSetupWizard con borrador reanudable |
| BranchDetailView.swift | Ficha con enlaces a activos/cortes/reportes y permiso |
| TabViews | Rutas definidas en 05; Cuenta en encabezado |

No borrar archivos antiguos hasta que sus llamadas y targets estén migrados. Al extraer cada módulo, compilar y ejecutar el recorrido afectado antes de otra extracción grande.

## M04. Exportación v1 y previsualización

Crear exportador en versión local que incluya JSON v1 y metadatos no secretos; Keychain no se exporta. El importador acepta archivo con hash, versión, counts y `sourceInstallationId`. Guarda copia original privada y un informe de validación. Importación `preview` no muta datos. Detecta ids duplicados, relaciones faltantes, capacidades/saldos inválidos, unidades y cortes inconsistentes. Problemas se clasifican bloqueantes o datos históricos incompletos. No crear usuarios/empleados fantasma para resolver relaciones.

Mapa explícito legacyId → newId por instalación; reimportar mismo lote/hash devuelve resultado anterior. Una importación ejecutada tiene plan/hash estable, actor y checkpoint; al fallar no deja medias sucursales activas. Aplicar por sucursal en transacción con lote completo verificado; organización importada en estado revisión hasta terminar.

## M05. Saldos y cortes

Elegir `cutoverAt` confirmado y congelar la captura de legado durante exportación/importación. Importar `FuelTank.currentLiters` como apertura a esa frontera, sujeto a revisión física. No volver a sumar compras/restar ventas/pérdidas de cortes cerrados que ya estén reflejados en ese saldo. Importar los cortes anteriores a un archivo histórico consultable con su contenido original y `legacySource`, excluido del libro nuevo.

`inventoryApplied` ayuda a revisar, pero no demuestra por sí solo integridad. Si hay cortes cerrados no aplicados, saldos negativos o duplicados, detener publicación de esa estación y emitir discrepancia. No ajustar automáticamente al saldo que parezca conveniente.

Cortes abiertos: en v1 sus movimientos normalmente no se han aplicado. Importar como borradores pendientes de revisión, conservando cantidad/unidad/documento y origen. Antes de publicarlos, comprobar que no estén ya dentro del saldo físico elegido al corte de migración. Registrar decisión por movimiento; no aplicar todo por defecto. Si ya se recibió físicamente antes de `cutoverAt`, forma parte de apertura y el documento queda histórico, no otra entrada.

No inferir costo de gasolina desde precio de venta. Costo desconocido impide margen confirmado hasta apertura valorada aprobada. No inferir quién cerró ni hora exacta a partir de fecha del corte. Mantener null y etiqueta migrado. Precios actuales demo pueden conservarse como referencias de demo no vigentes; las ventas históricas que carezcan precio conservan volumen y estimación etiquetada, sin ingresar como ingresos confirmados nuevos.

## M06. Infraestructura y demás dominios

v1 tiene número de bomba en lecturas, no infraestructura real. Proponer seis registros lógicos por estación y productos de tres familias, con configuración pendiente de verificar; no inventar caras, tanques adicionales, números de serie ni conexiones físicas. Lecturas históricas permanecen en namespace legado; al abrir operación nueva capturar/configurar medidores y lectura inicial confirmada.

Tienda: saldos por lote y costo disponible se importan como apertura; ventas antiguas archivadas, no se descuentan otra vez. Los costos de línea v1 provienen de catálogo y pueden no coincidir con asignaciones: preservar raw, marcar verificación pendiente y usar movimientos/lotes solo si permiten reconstrucción exacta. Reposición por anulaciones existentes debe concordar con saldos; nunca aplicar por segunda vez. Proveedores y productos conservan ids mediante mapa; habilitación de surtido se propone y revisa.

Usuarios: importar identidad/asignación/estado; credenciales se crean mediante activación/recuperación, sin transmitir contraseñas en texto del Keychain. Empleados no se convierten automáticamente en usuarios. Turnos semanales son plantillas, no asistencia pasada; no crear historial ficticio. Equipos de categoría bomba no se enlazan por coincidencia de nombre sin revisión. Órdenes/costos conservan documentos y calidad; no generan pagos nuevos.

## M07. Verificación y cambio definitivo

Comparar counts e identidades, saldos por tanque/lote, cantidades de históricos y checksums del archivo raw. Ejecutar misma importación dos veces y demostrar ausencia de duplicación. Simular fallo y rollback. Una vez aceptada la migración, app ampliada usa API y se conserva archivo legado de solo lectura. Si se vuelve temporalmente al legado para consulta, no permitir dos fuentes que reciban operaciones reales simultáneas.

Respaldo y restauración: combinar dump de base, adjuntos e índice de versiones con ventana coherente. Probar restauración en entorno aislado, recuentos y saldos antes de declarar estrategia válida. Rollback de despliegue no significa eliminar movimientos nuevos; cambios de esquema deben ser compatibles o tener restauración/reconciliación planificada. JSON corrupto abre pantalla de recuperación, conserva evidencia y nunca siembra demo silenciosamente.
