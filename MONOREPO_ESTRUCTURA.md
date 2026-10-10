# Estructura de trabajo del sistema DLC

`DLCGasolineras/` conserva el proyecto iOS existente y su ruta Xcode. Los siguientes directorios fijan destinos de código y documentación; E00 solo los prepara y no incorpora lógica ni dependencias.

- `server/`: API NestJS y worker modular.
- `web/`: panel React/TypeScript.
- `contracts/`: OpenAPI, vectores numéricos y fixtures de contrato.
- `infra/`: configuración local reproducible y servicios auxiliares.
- `scripts/`: migración, pruebas y tareas de desarrollo.
- `fixtures/`: datos sintéticos versionados, sin datos personales reales.
- `docs/`: alcance, arquitectura y manuales.
- `evidence/`: resultados de compilación, pruebas, capturas y gates con fecha.

No hay ramas Git en este workspace. No inicializar Git en la raíz, porque contiene además planes y archivos de otros entregables. Crear un repositorio dedicado solo si se acuerda una ruta de checkout propia.
