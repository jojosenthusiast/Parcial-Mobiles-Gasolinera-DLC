# Migración del respaldo local v1

## Exportar y preservar

El repositorio de la app guarda `DLCGasolineras/repository-v1.json` en Application Support; las contraseñas se guardan aparte en Keychain. Obtén una copia del JSON con el mecanismo de archivos/compartir de un build de desarrollo. No extraigas ni adjuntes Keychain. Conserva el archivo original en solo lectura.

```sh
node server/scripts/export-legacy.mjs /ruta/repository-v1.json /ruta/nuevo-paquete 11111111-1111-4111-8111-111111111111
node server/scripts/preview-legacy.mjs /ruta/nuevo-paquete 2026-10-04T08:00:00Z /ruta/preview.json
```

El UUID de instalación debe persistirse para nuevas exportaciones del mismo teléfono. El exportador crea `source.json` con los mismos bytes y `manifest.json` con SHA-256, versión y conteos; no sobrescribe paquetes existentes. Rechaza datos JSON que incluyan contraseñas, tokens o secretos.

## Guardar staging en API

`POST /api/v1/imports/preview` recibe `{manifest, sourceText, cutoverAt?}` con una sesión autenticada y `imports.preview`. El servidor vuelve a calcular tamaño/hash/conteos, valida relaciones y cantidades, produce mapeos UUID deterministas y guarda un batch único por organización + instalación + SHA-256. Repetir la misma fuente devuelve el batch previo.

El resultado queda en `review_required` o `blocked`; no publica saldos ni crea movimientos. Los cortes se guardan como histórico; saldo de tanque/lote queda como candidato de apertura con calidad/fuente, costo de combustible `null`, y no se vuelven a contabilizar ventas o compras. Los cortes abiertos/unaplicados requieren revisión por movimiento antes de E08. Usuario migrado no hereda credenciales ni puede iniciar sesión hasta activar su cuenta.

El endpoint exige JSON UTF-8 de hasta 32 MiB. Un reporte bloqueado necesita resolución antes de que el módulo de inventario considere un corte de migración. No existe un comando de publicación desde E05.
