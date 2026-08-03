$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root 'tools\flex-air-32.0'
$client = Join-Path $root 'Cosmic-Realms-main\Client-src'
$output = Join-Path $root 'build\air\CosmicRealmsAir.swf'
if (!(Test-Path "$sdk\bin\mxmlc.bat")) { throw 'AIR SDK 32.0 is not installed. Run this after the isolated SDK download completes.' }
$env:AIR_HOME = $sdk
$env:FLEX_HOME = $sdk
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
Copy-Item (Join-Path $root 'runtime\air\client.json') (Join-Path (Split-Path $output) 'client.json') -Force
Push-Location $client
try {
    $nativeErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & "$sdk\bin\mxmlc.bat" "-load-config+=$sdk\frameworks\air-config.xml" "-library-path+=$sdk\frameworks\libs\air\airglobal.swc" '-source-path+=src' '-library-path+=libs' "-output=$output" '-locale=en_US' '-default-size=800,600' '-default-frame-rate=60' '-default-background-color=#000000' '-swf-version=32' '-target-player=32.0' '-optimize=true' '-keep-as3-metadata+=Inject' '-keep-as3-metadata+=Embed' '-keep-as3-metadata+=PostConstruct' '-keep-as3-metadata+=ArrayElementType' 'src\AirMain.as'
    $ErrorActionPreference = $nativeErrorPreference
    if ($LASTEXITCODE -ne 0) { throw "AIR mxmlc failed with exit code $LASTEXITCODE" }
} finally { $ErrorActionPreference = $nativeErrorPreference; Pop-Location }
Write-Host "Built $output"
