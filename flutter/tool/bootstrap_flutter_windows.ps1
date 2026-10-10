$ErrorActionPreference = 'Stop'
$Flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $Flutter) {
    throw 'No encuentro flutter en PATH. Instala Flutter estable (Dart 3.10+) y vuelve a ejecutar.'
}
$Version = (& flutter --version 2>&1 | Select-Object -First 1)
Write-Host "SDK detectado: $Version"
$FlutterRoot = Split-Path -Parent $PSScriptRoot
$Targets = @(
    @{ Name = 'dlc_operations'; Path = Join-Path $FlutterRoot 'apps/dlc_operations' },
    @{ Name = 'dlc_customers'; Path = Join-Path $FlutterRoot 'apps/dlc_customers' }
)
foreach ($Target in $Targets) {
    $Destination = $Target.Path
    if (-not (Test-Path (Join-Path $Destination 'pubspec.yaml'))) {
        throw "No existe el paquete Flutter: $Destination"
    }
    $Missing = @('android', 'windows', 'web') | Where-Object { -not (Test-Path (Join-Path $Destination $_)) }
    if ($Missing.Count -gt 0) {
        $Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("dlc_flutter_" + [guid]::NewGuid().ToString('N'))
        try {
            $Platforms = $Missing -join ','
            & flutter create "--platforms=$Platforms" --org=sv.com.dlc "--project-name=$($Target.Name)" $Temp
            if ($LASTEXITCODE -ne 0) { throw "flutter create falló para $($Target.Name)." }
            foreach ($Platform in $Missing) {
                $Source = Join-Path $Temp $Platform
                if (Test-Path $Source) { Copy-Item $Source (Join-Path $Destination $Platform) -Recurse -Force }
            }
            # Flutter's generated analysis_options.yaml includes flutter_lints,
            # which is not a dependency of these apps. Do not copy a config that
            # makes `flutter analyze` fail after a successful bootstrap.
            foreach ($File in @('.metadata', '.gitignore')) {
                $Source = Join-Path $Temp $File
                if ((Test-Path $Source) -and -not (Test-Path (Join-Path $Destination $File))) {
                    Copy-Item $Source (Join-Path $Destination $File)
                }
            }
        }
        finally { if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force } }
    }
    $DebugManifest = Join-Path $Destination 'android/app/src/debug/AndroidManifest.xml'
    if ((Test-Path (Join-Path $Destination 'android')) -and -not (Test-Path $DebugManifest)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DebugManifest) | Out-Null
        @'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:usesCleartextTraffic="true" />
</manifest>
'@ | Set-Content -Encoding UTF8 $DebugManifest
    }
    if ($Target.Name -eq 'dlc_customers') {
        $MainManifest = Join-Path $Destination 'android/app/src/main/AndroidManifest.xml'
        if (Test-Path $MainManifest) {
            $ManifestText = Get-Content -Raw $MainManifest
            $Scheme = 'sv.com.dlc.dlc_customers'
            if ($ManifestText -notmatch [regex]::Escape("android:scheme=`"$Scheme`"")) {
                $DeepLinkFilter = @"
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="$Scheme" android:host="login-callback" />
            </intent-filter>
"@
                $ManifestText = $ManifestText -replace '</activity>', "$DeepLinkFilter</activity>"
                Set-Content -Path $MainManifest -Value $ManifestText -Encoding UTF8
            }
        }
    }
    Push-Location $Destination
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get falló para $($Target.Name)." }
    }
    finally { Pop-Location }
}
Write-Host 'Andamiaje generado sin sobrescribir plataformas existentes.'
Write-Host 'HTTP solo está permitido en Android debug para el emulador. Usa HTTPS para dispositivos y builds release.'
Write-Host 'DLC Clientes incluye registro y recuperación con deep link; permite el redirect URI sv.com.dlc.dlc_customers://login-callback/ en Supabase Auth.'
