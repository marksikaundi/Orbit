# Launch Orbit detached (Windows).
# Called by `zig build run`.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Exe = Join-Path $Root "zig-out\bin\orbit.exe"

if (-not (Test-Path $Exe)) {
    Write-Error "orbit.exe not found at $Exe — run zig build first"
    exit 1
}

$foreground = $env:ORBIT_FOREGROUND -eq "1"
if ($foreground) {
    & $Exe @args
    exit $LASTEXITCODE
}

Start-Process -FilePath $Exe -ArgumentList $args -WorkingDirectory $Root | Out-Null
Write-Host "Orbit terminal opened successfully"
