param([ValidateSet('object','ground')][string]$Kind='object',[string]$Range='F000-FFFF')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Resolve-Node.ps1')
$node = Get-NodeExecutable
& $node (Join-Path $root 'tools\TypeIdManager\index.js') --kind $Kind --range $Range
if($LASTEXITCODE -ne 0){ throw 'Type ID lookup failed.' }
