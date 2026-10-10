# Persistencia en Supabase

El proyecto DLC de la organización sole usa PostgreSQL administrado por Supabase. Referencia de proyecto: tgfnoxqwlasydphhlqmp. El panel y las apps consumen la API NestJS; no deben incluir credenciales PostgreSQL ni claves secretas de Supabase.

## Estado actual verificado

- Proyecto ACTIVE_HEALTHY, PostgreSQL 17.11, región us-east-1.
- El esquema público contiene 108 migraciones de aplicación, hasta 0108_operational_asset_events_append_only_privileges.sql. El ledger de la aplicación tiene 108 entradas; el historial interno de Supabase contiene 97, porque la base usa una línea base consolidada. Las 23 migraciones locales nuevas (0086–0108) están presentes en ambos historiales y sus SHA-256 coinciden: 23/23.
- Las migraciones 0086–0105 cubren puntos, campañas, reembolsos, descargas contaminantes y activos operativos. 0106 fija el search_path de la función inmutable; 0107 agrega 67 índices que cubren 68 FK nuevas; 0108 revoca UPDATE/DELETE al historial inmutable.
- Hay 0 organizaciones y 0 sucursales. La base no tiene datos operativos para recorridos de negocio o medición de carga.
- Las dos tablas de activos tienen RLS. anon, authenticated y service_role no tienen SELECT sobre ellas. dlc_api_runtime conserva las operaciones requeridas; el historial permite SELECT/INSERT, sin UPDATE/DELETE.
- El advisor de seguridad informa 0 hallazgos después de 0106. El smoke SQL remoto validó alta/asignación de equipo, historial inmutable, reporte de daño y transición a reparación; también rechazó un reporte inválido. Se ejecutó en transacción con ROLLBACK. No quedaron datos de prueba.

## Rendimiento y pendientes de plataforma

El advisor de rendimiento mantiene 331 avisos INFO de FK sin índice en tablas históricas. La nueva cadena no aumenta ese total: los 68 avisos de las FK nuevas se cubrieron con 67 índices. Hay 120 índices observados como no usados; la base está vacía y no tiene carga de negocio, así que esos avisos no justifican borrarlos. Hace falta medir con datos representativos antes de optimizar más.

La configuración de privilegios por defecto de supabase_admin todavía concede EXECUTE a roles cliente para funciones nuevas. El conector de esta sesión no tiene privilegios para cambiar esos defaults. Las funciones actuales están revocadas a roles cliente y el advisor no reporta exposición presente, pero este ajuste sigue siendo una tarea de plataforma antes de crear funciones públicas adicionales o aprobar producción. Una sesión administradora con el privilegio correspondiente debe ejecutar:

~~~sql
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;
~~~

El rol dlc_api_runtime es NOLOGIN y no administrativo. Aún falta configurar un usuario login de servicio, miembro de ese rol, en el entorno servidor de la API. El proyecto local no contiene un .env real; por eso esta sesión aplicó migraciones y smoke SQL vía el conector de Supabase, pero no ejecutó rutas autenticadas de la API contra esa base. En producción, usa DATABASE_SSL_MODE=verify-full y almacena credenciales en el gestor de secretos del despliegue.

## Alcance de QA

La conexión a la base real permitió aplicar y validar las migraciones directamente en Supabase; PostgreSQL local y Docker no son requisitos para esa comprobación. Compose sigue siendo solo una opción para reproducir una base local. La prueba SQL remota no reemplaza los recorridos API autenticados, pruebas entre organizaciones/sucursales, concurrencia con dos clientes ni aceptación visual en navegador y dispositivos.

No ejecutar seed:demo ni pruebas destructivas contra esta base compartida. La API conectada a datos representativos, la configuración de privilegios por defecto y las pruebas de despliegue/restore son puertas pendientes antes de producción.
