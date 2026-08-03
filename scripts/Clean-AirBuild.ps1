$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$target = Join-Path $root 'build\air'
if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
New-Item -ItemType Directory -Force -Path $target | Out-Null
Write-Host 'Cleaned generated AIR output only.'
