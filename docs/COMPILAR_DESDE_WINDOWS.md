# Compilar desde Windows

La API NestJS/PostgreSQL sí puede instalarse, compilarse y probarse en Windows. El proyecto fija Node `>=24.15 <25` y pnpm `11.25.0`; Node 20 no satisface ese requisito. El paquete ya incluye `pnpm-lock.yaml`; conserva ese archivo para instalar exactamente las dependencias probadas.

En PowerShell, instala fnm y usa la versión de Node prevista:

```powershell
winget install --id Schniz.fnm
fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
fnm install 24.19.0
fnm use 24.19.0
npm install --global pnpm@11.25.0
```

Abre una terminal nueva si Windows aún no reconoce `fnm`, `node` o `pnpm`. Desde la carpeta `DLCGasolineras_Laboratorio22`, ejecuta:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./server/scripts/verify-windows.ps1
```

El script instala las dependencias con el lockfile congelado y ejecuta `typecheck`, `build`, pruebas unitarias, contratos y web. Si pnpm detecta que el lockfile no coincide con los manifiestos, detente y revisa el cambio antes de regenerarlo. No conectes el proceso a Supabase hasta tener la URL TLS de PostgreSQL y las credenciales runtime preparadas; nunca uses claves de servicio en el cliente.

## Compilación de SwiftUI

Instalar Swift para Windows permite trabajar con el lenguaje y algunos paquetes multiplataforma. No incluye los SDK de iOS, SwiftUI, simuladores ni `xcodebuild`; por eso no compila este target iOS. Darling reimplementa APIs de macOS sobre Linux y tampoco proporciona el toolchain/SDK de iOS de Xcode.

La ruta sin comprar una Mac es subir el proyecto a un repositorio privado de GitHub y ejecutar el workflow manual `.github/workflows/ios-build.yml`. No se activa en cada push. GitHub lo compila en un runner macOS con Xcode 16.4 sin firma; los logs quedan disponibles siete días. El job comprueba la compilación para simulador, pero no ejecuta el simulador, no genera una app firmada para instalar en iPhone y no reemplaza una prueba visual.

Para usarlo, crea un repositorio privado, coloca dentro los contenidos de esta carpeta (el `.xcodeproj`, `DLCGasolineras/` y `.github/` deben quedar al nivel raíz), carga el proyecto y abre la pestaña **Actions**. Ejecuta **iOS build** con **Run workflow**. GitHub puede consumir cuota de Actions o cobrar minutos macOS según el plan y la configuración de facturación; revisa la cuota antes de activar el workflow. Un repositorio público permite uso gratuito de runners estándar, pero expone el código a cualquiera y no es necesario para este flujo.

El acuerdo de desarrollo de Apple limita el uso de sus SDK a equipos Apple; montar una VM de macOS en esta PC no es una salida admitida por esos términos. Para depuración visual interactiva, simulador y capturas sigue haciendo falta acceso a un Mac físico o remoto. El workflow resuelve el chequeo de compilación, no esa parte.

## Qué sí puede cerrarse ahora

1. Ejecutar desde Windows los chequeos estáticos y tests del API cuando su registro npm esté accesible.
2. Generar el lockfile de pnpm durante la primera instalación y conservarlo.
3. Pedir a GitHub Actions una compilación real del target iOS y conservar el resultado con su log.
4. Dejar pendiente el simulador, las capturas y la prueba interactiva hasta tener un Mac.

Fuentes oficiales consultadas el 6 de octubre de 2026: [instalar Swift en Windows](https://www.swift.org/install/windows/), [requisitos de Xcode](https://developer.apple.com/xcode/system-requirements/), [términos del Apple Developer Program](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/), [imágenes macOS de GitHub Actions y Xcode 16.4](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md), [runners macOS de GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) y [cuotas/facturación de Actions](https://docs.github.com/en/actions/concepts/billing-and-usage). El proyecto Darling indica en su README que Xcode aún no corre allí: https://github.com/darlinghq/darling.
