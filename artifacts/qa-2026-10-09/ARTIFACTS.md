# Artefactos QA

Instala preferentemente los APK canónicos y verifica las sumas de `SHA256SUMS.txt`. Los aliases son copias idénticas.

## Builds verificados — 2026-10-10

| App | Archivo canónico | Tamaño | SHA-256 |
|---|---|---:|---|
| Clientes | `dlc_customers-qa-debug.apk` | 164.015.074 bytes | `ce137a7c05c770100e91df385396e94e8f3002bc17289bcb7edfece69ec00f25` |
| Operaciones | `dlc_operations-qa-debug.apk` | 179.113.952 bytes | `123c1f5d0f018866107ea359b094cda5148ed8968e4a197b1dd93b6a00d49bd0` |

Clientes se construyó con Flutter 3.47.5 / Dart 3.13.4, URL del proyecto QA DLC `https://tgfnoxqwlasydphhlqmp.supabase.co` y clave publishable (el valor no se guarda en el repositorio). Operaciones usa `http://10.0.2.2:4000/api/v1`; Clientes también tiene ese endpoint de emulador, `CUSTOMER_TERMS_VERSION=qa-draft-v1` y callback `sv.com.dlc.dlc_customers://login-callback/`.

Ninguno se instaló ni se probó en dispositivo; no hay dispositivo ADB disponible. La URL del APK es una configuración de build, no prueba que la API esté activa. Las pruebas HTTP de integración quedaron omitidas porque `DLC_API_BASE_URL` runtime no está configurada.

## Paquete fuente

`DLCGasolineras_Laboratorio22_QA_source.zip` conserva 692 entradas, 108 migraciones locales hasta 0108 y SHA-256 `eba0c902d407b8c2966c04404b84c3f8c893345dd2d99d558493618ea77abb47`. La verificación previa confirmó que excluye secretos `.env` reales, cachés, salidas de build, artefactos y respaldos.
