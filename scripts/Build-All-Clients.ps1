$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\Build-Client.ps1"
& "$PSScriptRoot\Build-AirClient.ps1"
$root = Split-Path $PSScriptRoot -Parent
$titleAsset = Join-Path $root 'Cosmic-Realms-main\Client-src\src\kabam\rotmg\ui\view\TitleView_TitleScreenGraphic2.png'
$swfOutput = Join-Path $root 'build\client-unchanged.swf'
$airOutput = Join-Path $root 'build\air\CosmicRealmsAir.swf'
$servedSwf = Join-Path $root 'runtime\resources\web\rotmg.swf'
"Canonical title background: $titleAsset"
"SWF build output: $swfOutput"
"AIR build output: $airOutput"
"Deployed web-root SWF: $servedSwf"
Get-FileHash $titleAsset,$swfOutput,$airOutput,$servedSwf -Algorithm SHA256 | Format-Table -AutoSize
