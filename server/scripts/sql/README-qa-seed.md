# Siembra operativa QA (DLC)

`server/scripts/seed-qa-operations.mjs` lleva `QA-SV-01` y `QA-GT-01` de `draft` a `active` usando solo la API HTTP (como gerente general, credenciales de `server/.qa-credentials.local.txt`). No toca SQL ni imprime contraseñas o tokens.

## Cómo correrlo
```
cd server
node scripts/seed-qa-operations.mjs --api https://<host>/api/v1     # por defecto http://127.0.0.1:4000/api/v1
node scripts/seed-qa-operations.mjs --api <url> --dry-run           # solo lee y lista lo que haría
node scripts/seed-qa-operations.mjs --api <url> --branch QA-SV-01   # una sola sucursal
```
Requisitos: tenant creado con `qa-setup.generated.sql`, API accesible y, en producción, https (por http solo `localhost`, salvo `--allow-insecure-http`).

## Qué crea (por sucursal)
- Perfil `academicLab22` (6 dispensadores), combustibles Súper/Regular/Diésel y su oferta.
- 3 tanques de 20,000 L con saldo inicial: SV 75% / 45% / 25%, GT 27% / 85% / 50% (óptimo, medio y crítico en ambas).
- 6 dispensadores x 3 mangueras (1-3 servicio completo, 4-6 autoservicio), conectadas a su tanque, con línea base del totalizador.
- 3 empleados activos y la revisión de personal confirmada.
- Precios USD/galón vigentes por combustible y modalidad (propuesta, aprobación y programación).
- Activación, umbrales de inventario 60%/30% y los dos cortes de hoy: matutino 06:00-14:00 y vespertino 14:00-22:00 (hora local de la sucursal). El periodo 22:00-06:00 NO es un corte (ver abajo). Requiere la migración 0110.

## Cortes 06-14 / 14-22 (migración 0110)
- Plantilla `academicLab22`: `POST /branches/{id}/cuts/profiles` con solo `effectiveDate` crea el perfil fijo 06:00 / 14:00 / `dayEnd` 22:00; otros horarios se rechazan con 400. Las demás plantillas no cambian (dos ventanas contiguas de 24 h; `dayEnd` no se admite).
- Reglas que se mantienen: ventanas sin solapamiento (también entre días), un corte por ventana y día, los dos cortes del día son contiguos, un hueco entre días solo existe si el perfil lo declara con `dayEnd`, y la continuidad de totalizadores y tanques pasa por `previous_operational_cut()` (el corte vespertino de ayer es el anterior del matutino de hoy; un corte no cierra hasta que el anterior cierre).
- Consecuencia 22:00-06:00: ventas, lecturas y movimientos de inventario registrados en ese periodo no pertenecen a ninguna ventana. Se concilian en el primer corte posterior (su `accountingStartsAt` es el fin del corte anterior; el cierre lo guarda en el snapshot), de modo que el delta del totalizador (que abarca la noche) y los litros vendidos sigan siendo comparables. La ventana nominal del corte sigue siendo 06:00-14:00. No se bloquea vender de noche.
- Datos QA remotos con el corte viejo 14:00-06:00: no se pueden editar (un corte por ventana y día, ventanas contiguas). El script los deja intactos (conservan su historia y terminan a las 06:00 de mañana) y crea el par correcto desde mañana. Para corregir también hoy, un administrador puede ejecutar `qa-replace-legacy-cuts.sql` (opcional, solo QA, solo cortes nunca abiertos) y repetir el script.
- Orden en el remoto: `qa-migration-0110.sql` (SQL editor) -> desplegar la API -> `seed-qa-operations.mjs`. `node scripts/generate-qa-migration-0110.mjs` lo regenera.

## Notas
- Aprobar precios exige un usuario distinto al proponente: el script sube al gerente de sucursal QA a alcance de red solo durante las aprobaciones y lo devuelve a `QA-SV-01` (si se interrumpe, volver a correrlo lo restaura).
- Los precios entran en vigor ~60 s después (`--price-lead-seconds`); el script espera.
- Reejecución segura: lee el estado y no crea nada existente (segunda corrida = 0 escrituras, código 0). Si falla a medias, repite el comando y continúa.
- Requiere que la API tenga corregido `saveStep` (`jsonb_build_object($3::text, ...)` en `branches.service.ts`); sin eso el paso de personal devuelve 500.
