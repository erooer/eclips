param([ValidateSet('object','ground')][string]$Kind='object',[string]$Range='F000-FFFF')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$node='C:\Users\erooe\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
if(!(Test-Path $node)){ $node=(Get-Command node.exe -ErrorAction Stop).Source }
& $node (Join-Path $root 'tools\TypeIdManager\index.js') --kind $Kind --range $Range
if($LASTEXITCODE -ne 0){ throw 'Type ID lookup failed.' }
