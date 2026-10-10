# Artefactos QA

Instala preferentemente los APK canónicos y verifica SHA256SUMS.txt antes de instalarlos:

- dlc_operations-qa-debug.apk
- dlc_customers-qa-debug.apk

Los nombres dlc-operations-debug-qa.apk y dlc-customers-debug-qa.apk son copias idénticas de los canónicos y también aparecen en el archivo de sumas.

Ambos APK apuntan a http://10.0.2.2:4000/api/v1 para emulador Android. Clientes requiere configurar un proyecto Supabase de QA. No se instalaron en dispositivos.

## Rebuild 2026-10-10

Operaciones recompilada con Activos operativos; Clientes recompilada sin cambios funcionales de ese módulo. Fuente QA con 698 archivos, 105 migraciones y sin build outputs, .env, claves ni respaldos. El APK de Operaciones incluye lectura QR existente y la nueva ficha de activos. La verificación confirma compilación; faltan pruebas de instalación y recorrido autenticado en dispositivos.

Ver SHA256SUMS.txt para las sumas actuales.

## Actualización del handoff

El ZIP fuente QA incluye HANDOFF_TRABAJO_PENDIENTE_WORK.md y las referencias desde ambos handoffs de QA. Consulta SHA256SUMS.txt para el hash regenerado.
