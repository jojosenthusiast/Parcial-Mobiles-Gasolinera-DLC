# Artefactos QA

Instala preferentemente los APK canónicos y verifica SHA256SUMS.txt antes de instalarlos:

- dlc_operations-qa-debug.apk
- dlc_customers-qa-debug.apk

Los nombres dlc-operations-debug-qa.apk y dlc-customers-debug-qa.apk son copias idénticas de los canónicos y también aparecen en el archivo de sumas.

Ambos APK apuntan a http://10.0.2.2:4000/api/v1 para emulador Android. Clientes requiere configurar un proyecto Supabase de QA. No se instalaron en dispositivos.

## Reconstrucción y empaquetado verificados

Operaciones se reconstruyó desde la fuente actual con el endpoint de emulador; Clientes no se reconstruyó porque faltan URL y publishable key de Supabase QA. El paquete fuente QA verificado contiene 692 entradas y 108 migraciones locales hasta 0108. No se inspeccionó ni aplicó estado remoto de Supabase. El ZIP excluye build outputs, .env, claves y respaldos según la verificación de empaquetado. Su SHA-256 verificado es d461b1717e51a63746688df6e0e187e22de96836e98233f17ea673b09a0760ae. Operaciones y su alias comparten el hash actual; Clientes y su alias conservan el hash del APK sin cambios. La compilación y las sumas no sustituyen instalación ni recorrido autenticado en dispositivo.
## Actualización del handoff

El ZIP fuente QA incluye HANDOFF_TRABAJO_PENDIENTE_WORK.md y las referencias desde ambos handoffs de QA. Consulta SHA256SUMS.txt para el hash regenerado.
