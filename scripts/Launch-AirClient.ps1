$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root 'tools\flex-air-32.0'
$build = Join-Path $root 'build\air'
if (!(Test-Path "$build\CosmicRealmsAir.swf")) { & "$PSScriptRoot\Build-AirClient.ps1" }
& "$sdk\bin\adl.exe" (Join-Path $root 'Cosmic-Realms-main\Client-src\air\application.xml') $build
if ($LASTEXITCODE -ne 0) { throw "ADL exited with code $LASTEXITCODE" }
