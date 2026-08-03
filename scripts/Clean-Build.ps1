$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$targets = @((Join-Path $root 'build'), (Join-Path $root 'docs\reports'))
foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
}
Write-Host 'Cleaned generated build output and validator reports only.'
