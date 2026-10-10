# Sesión del 5 de octubre de 2026 — Supabase

Se confirmó mobiles → sole → DLC, proyecto tgfnoxqwlasydphhlqmp, vacío y PostgreSQL 17.11. Se aplicaron 0001–0015 en cuatro despliegues. La creación duplicada de schema_migrations se corrigió antes del primer despliegue; desde ese momento se conservan los archivos y sus hashes.

Las 47 tablas tienen RLS y acceso exclusivo mediante backend. Se revocaron permisos explícitos de tablas, secuencias y funciones para los clientes Supabase. Se añadieron validaciones de organización en empleados/mangueras, ecuación de saldo de inventario y presencia del importe/volumen solicitado. No se cargaron cuentas ni credenciales de demostración.

Validación: 38 pruebas SQL remotas y 31 pruebas locales aprobadas; hashes de 15 migraciones coincidentes. Las primeras dos ejecuciones de la suite SQL requirieron corregir un nombre reservado y una colisión de códigos en las fixtures; no dejaron datos ni alteraron el esquema. Una prueba de rol adicional requirió conceder SET al administrador: PostgreSQL 17 entrega ADMIN sin SET al creador. La ejecución final pasó y revirtió sus filas. Se verificó lectura, bloqueo, actualización y anexos con el rol limitado; se retiraron locks innecesarios al consultar registros inmutables en los replays. Se conservaron los resultados en evidence/supabase.

Queda pendiente instalar y compilar la API, configurar secretos/certificado CA, probar TLS y operaciones desde los servicios, restaurar backups y configurar un login seguro miembro del rol limitado dlc_api_runtime ya creado. Los avisos INFO de índices requieren evaluación con carga real. E02 continúa implemented_pending_validation; no se certificó el sistema completo ni compilación iOS.

Siguiente subtarea de desarrollo: E11.04, adaptador manual/simulado determinista. Configuración cloud: docs/SUPABASE_DLC.md y server/.env.supabase.example.
