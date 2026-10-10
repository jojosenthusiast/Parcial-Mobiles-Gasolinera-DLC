$ErrorActionPreference = 'Stop'

$serverRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectRoot = (Resolve-Path (Join-Path $serverRoot '..')).Path
Set-Location $projectRoot

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "No se encontró '$Name'. Instala la herramienta y vuelve a ejecutar este script."
    }
}

Require-Command 'node'
Require-Command 'pnpm'

$nodeVersion = (& node --version).Trim()
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.(\d+)\.(\d+)') {
    throw 'No se pudo determinar la versión de Node.js.'
}
$nodeMajor = [int]$Matches[1]
$nodeMinor = [int]$Matches[2]
if ($nodeMajor -ne 24 -or $nodeMinor -lt 15) {
    throw "El proyecto requiere Node >=24.15 y <25; se detectó $nodeVersion. Instala Node 24.19.0 con fnm: fnm install 24.19.0; fnm use 24.19.0."
}

$pnpmVersion = (& pnpm --version).Trim()
if ($LASTEXITCODE -ne 0 -or $pnpmVersion -ne '11.25.0') {
    throw "El proyecto fija pnpm 11.25.0; se detectó '$pnpmVersion'. Ejecuta npm install --global pnpm@11.25.0."
}

Write-Host "Node $nodeVersion y pnpm $pnpmVersion listos. Instalando paquetes fijados en package.json..."
$lockPath = Join-Path $projectRoot 'pnpm-lock.yaml'
if (Test-Path $lockPath) {
    & pnpm install --frozen-lockfile
} else {
    Write-Warning 'El paquete entregado aún no trae pnpm-lock.yaml; la instalación inicial lo generará. Conserva ese archivo para las siguientes instalaciones.'
    & pnpm install
}
if ($LASTEXITCODE -ne 0) { throw "pnpm install falló con código $LASTEXITCODE." }

$checks = @('typecheck', 'build', 'test:unit', 'test:contract', 'test:web')
foreach ($check in $checks) {
    Write-Host "`n== pnpm $check =="
    & pnpm $check
    if ($LASTEXITCODE -ne 0) { throw "La comprobación '$check' falló con código $LASTEXITCODE." }
}

Write-Host "`nCompilación y suites locales terminadas. Las pruebas que requieren Supabase necesitan configuración aparte."
