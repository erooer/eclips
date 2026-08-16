$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Resolve-Node.ps1')
$node = Get-NodeExecutable
& $node (Join-Path $root 'tools\OminousBelowMapGenerator\validate.js')
if ($LASTEXITCODE -ne 0) { throw 'Ominous Below static validation failed.' }
