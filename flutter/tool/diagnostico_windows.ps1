$ErrorActionPreference = 'Continue'
$FlutterRoot = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $FlutterRoot 'diagnostico_flutter.txt'
$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DLC Flutter diagnostics (no credentials or environment values are collected)')
$Lines.Add("Generated: $([DateTime]::UtcNow.ToString('o'))")
foreach ($Command in @('flutter', 'dart', 'adb', 'java')) {
    $Found = Get-Command $Command -ErrorAction SilentlyContinue
    $Lines.Add("$Command path: $(if ($Found) { $Found.Source } else { 'not found in PATH' })")
}
foreach ($Args in @(@('flutter','--version'), @('flutter','doctor','-v'), @('adb','version'), @('java','-version'))) {
    $Exe = $Args[0]
    if (Get-Command $Exe -ErrorAction SilentlyContinue) {
        $Lines.Add("`n> $($Args -join ' ')")
        $Result = & $Exe $Args[1..($Args.Length - 1)] 2>&1 | Select-Object -First 80
        foreach ($Line in $Result) { $Lines.Add([string]$Line) }
    }
}
$Lines | Set-Content -Encoding UTF8 $Out
Write-Host "Diagnóstico sanitizado guardado en $Out"
