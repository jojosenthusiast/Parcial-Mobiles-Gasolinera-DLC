# Entorno local

El stack local con Docker Compose incluye PostgreSQL, migraciones, API, worker de reportes y panel web. Funciona en Docker Desktop para Windows y no requiere Xcode. Desde PowerShell, en la raíz del proyecto:

```powershell
Copy-Item .env.example .env
$secret = [byte[]]::new(32)
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($secret)
$rng.Dispose()
$hex = [Convert]::ToHexString($secret).ToLower()
```

Pon `$hex` como `POSTGRES_PASSWORD`, vuelve a generar otro `$hex` para cada uno de `RUNTIME_DATABASE_PASSWORD`, `AUTH_RATE_LIMIT_KEY` y `WEB_SESSION_KEY` dentro de `.env`. El usuario y el servidor de migraciones crean un login local separado, miembro solo del rol `dlc_api_runtime`; API y worker usan esa cuenta restringida. Luego inicia:

```powershell
docker compose -f infra/compose.yaml up --build
```

Abre `http://localhost:4173`; API local `http://localhost:4000/api/v1`. No se cargan datos de demostración automáticamente: ejecuta `pnpm db:seed:demo` solo en la base local si necesitas datos para probar el panel. El seed no está expuesto al servicio API.

La configuración solo habilita el adaptador manual de despacho. El backend, panel y base local pueden ejecutarse en Windows; la compilación de la app SwiftUI y las capturas del simulador todavía requieren el gate macOS del plan.

## Alertas para un despliegue supervisado

Las reglas iniciales para Prometheus están en `infra/monitoring/dlc-alerts.yml`. Revísalas con `promtool check rules infra/monitoring/dlc-alerts.yml` y conecta un receptor antes de usarlas. La API no publica métricas de forma anónima: `GET /api/v1/metrics/http` exige sesión autorizada y `branch.manage`. Mantén el scrape en una red privada y configura autenticación de servicio en el entorno de despliegue. Compose local no levanta Prometheus ni abre un endpoint público.
