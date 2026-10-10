# Observabilidad HTTP

La API expone `GET /api/v1/metrics/http` en formato Prometheus. El endpoint requiere una sesión válida y el permiso global `branch.manage`, por lo que queda reservado a administración de red.

Las métricas registran solicitudes completadas, duración HTTP por intervalos, uptime del proceso, memoria residente y uso del pool de PostgreSQL. Las etiquetas HTTP se limitan a método, plantilla de ruta y estado; se descartan URL, query string, IP, usuario, identificadores y datos de negocio. Rutas desconocidas se agregan bajo `unmatched` y los segmentos numéricos o UUID se normalizan como `:id` para evitar cardinalidad accidental.

El registro vive en memoria del proceso: se reinicia al reiniciar la API y cada instancia mantiene sus propios contadores. El operador debe configurar el recolector para autenticarse con un usuario técnico de privilegio mínimo y consultar cada instancia por su red privada. No se incluye ni se registra un token de scrape.

Las pruebas unitarias cubren acumulación, buckets, normalización, etiquetas, middleware y gauges. La verificación de scraping real, alertas operativas y comportamiento con múltiples instancias queda como gate de despliegue en Compose/CI.

## Reglas iniciales de alerta

`infra/monitoring/dlc-alerts.yml` propone reglas Prometheus para error 5xx sostenido, latencia p95, espera del pool PostgreSQL, memoria residente superior a 1 GiB y reinicio de proceso. Antes de activarlas, el operador debe ejecutar `promtool check rules infra/monitoring/dlc-alerts.yml`, asignar un receptor de alertas y definir quién atiende cada severidad.

El archivo contiene reglas, no credenciales ni una configuración de scrape. El endpoint continúa protegido por sesión y `branch.manage`; se debe recoger por una red privada y mediante un mecanismo de autenticación de servicio administrado. El paquete local no instala Prometheus, no abre otro puerto y no expone métricas públicamente. Sin un scrape autenticado funcionando, las alertas permanecen configuradas como artefacto y no se consideran activas.
