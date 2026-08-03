param([switch]$IncludeAir)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build-Server.ps1')
& (Join-Path $PSScriptRoot 'Build-Client.ps1')
if ($IncludeAir) { & (Join-Path $PSScriptRoot 'Build-AirClient.ps1') }
Write-Host 'PASS: validation, rebuilt server, and rebuilt client completed.'
