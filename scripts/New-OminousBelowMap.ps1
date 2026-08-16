param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Resolve-Node.ps1')
$node = Get-NodeExecutable
& $node (Join-Path $root 'tools\OminousBelowMapGenerator\generate.js')
if ($LASTEXITCODE -ne 0) { throw 'Ominous Below map generation failed.' }
