[CmdletBinding()]
param([switch]$NoProvision)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'FlexSdk.psm1') -Force
$toolchain = Resolve-FlexSdk -RepositoryRoot $here -ProvisionIfMissing:(!$NoProvision)
$client = Join-Path $here 'Cosmic-Realms-main\Client-src'
$output = Join-Path $here 'build\client-unchanged.swf'
$webRoot = Join-Path $here 'runtime\resources\web'
$servedSwf = Join-Path $webRoot 'rotmg.swf'
$deployableWebRoot = Join-Path $here 'Cosmic-Realms-main\Server-src\bin\resources\web'
$deployableSwf = Join-Path $deployableWebRoot 'rotmg.swf'
$buildInfo = & (Join-Path $PSScriptRoot 'New-ClientBuildInfo.ps1') -RepositoryRoot $here
$env:PLAYERGLOBAL_HOME = $toolchain.PlayerGlobalHome
& (Join-Path $PSScriptRoot 'Validate-Preflight.ps1')
New-Item -ItemType Directory -Force (Split-Path $output) | Out-Null
Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
Push-Location $client
try {
    & $toolchain.Mxmlc '-source-path+=src' "-source-path+=$($buildInfo.SourceRoot)" '-library-path+=libs' "-output=$output" '-locale=en_US' '-default-size=800,600' '-default-frame-rate=60' '-default-background-color=#000000' '-swf-version=15' '-target-player=15.0' '-optimize=true' '-use-direct-blit=true' '-keep-as3-metadata+=Inject' '-keep-as3-metadata+=Embed' '-keep-as3-metadata+=PostConstruct' '-keep-as3-metadata+=ArrayElementType' 'src\WebMain.as'
    if ($LASTEXITCODE -ne 0) { throw "mxmlc failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

New-Item -ItemType Directory -Force $webRoot,$deployableWebRoot | Out-Null
Copy-Item -LiteralPath $output -Destination $servedSwf -Force
Copy-Item -LiteralPath $output -Destination $deployableSwf -Force
$buildHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
$servedHash = (Get-FileHash -LiteralPath $servedSwf -Algorithm SHA256).Hash
$deployableHash = (Get-FileHash -LiteralPath $deployableSwf -Algorithm SHA256).Hash
if ($buildHash -ne $servedHash -or $buildHash -ne $deployableHash) { throw 'SWF deployment verification failed: build, runtime web, and deployable server web copies differ.' }
Write-Host "Built SWF: $output; source=$($buildInfo.ShortCommit); synchronized runtime and deployable web copies ($($buildHash.Substring(0, 12)))"
