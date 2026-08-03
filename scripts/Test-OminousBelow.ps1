$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$node = 'C:\Users\erooe\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
& $node (Join-Path $root 'tools\OminousBelowMapGenerator\validate.js')
if ($LASTEXITCODE -ne 0) { throw 'Ominous Below static validation failed.' }
