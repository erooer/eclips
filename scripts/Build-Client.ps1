$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$sdk = Join-Path $here 'tools\flex-sdk-4.9.1'
$client = Join-Path $here 'Cosmic-Realms-main\Client-src'
$output = Join-Path $here 'build\client-unchanged.swf'
$webRoot = Join-Path $here 'runtime\resources\web'
$servedSwf = Join-Path $webRoot 'rotmg.swf'
$env:PLAYERGLOBAL_HOME = Join-Path $sdk 'frameworks\libs\player'
& (Join-Path $PSScriptRoot 'Validate-Preflight.ps1')
New-Item -ItemType Directory -Force (Split-Path $output) | Out-Null
Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
Push-Location $client
try {
    & "$sdk\bin\mxmlc.bat" '-source-path+=src' '-library-path+=libs' "-output=$output" '-locale=en_US' '-default-size=800,600' '-default-frame-rate=60' '-default-background-color=#000000' '-swf-version=15' '-target-player=15.0' '-optimize=true' '-use-direct-blit=true' '-keep-as3-metadata+=Inject' '-keep-as3-metadata+=Embed' '-keep-as3-metadata+=PostConstruct' '-keep-as3-metadata+=ArrayElementType' 'src\WebMain.as'
    if ($LASTEXITCODE -ne 0) { throw "mxmlc failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

New-Item -ItemType Directory -Force $webRoot | Out-Null
Copy-Item -LiteralPath $output -Destination $servedSwf -Force
$buildHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
$servedHash = (Get-FileHash -LiteralPath $servedSwf -Algorithm SHA256).Hash
if ($buildHash -ne $servedHash) { throw "SWF deployment verification failed: $servedSwf does not match $output" }
Write-Host "Deployed SWF: $servedSwf ($($buildHash.Substring(0, 12)))"
