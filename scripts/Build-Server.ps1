$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$server = Join-Path $here 'Cosmic-Realms-main\Server-src'
$nuget = Join-Path $here 'tools\nuget.exe'
$msbuild = 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe'
& (Join-Path $PSScriptRoot 'Validate-Preflight.ps1')
Push-Location $server
try {
    & $nuget restore server.sln -NonInteractive
    if (!(Test-Path 'packages\Microsoft.Tpl.Dataflow.4.5.23')) {
        & $nuget install Microsoft.Tpl.Dataflow -Version 4.5.23 -OutputDirectory packages -NonInteractive
    }
    & $msbuild common\common.csproj /t:Rebuild /p:Configuration=Release /m
    if ($LASTEXITCODE -ne 0) { throw "common rebuild failed with exit code $LASTEXITCODE" }
    & $msbuild server\server.csproj /t:Rebuild /p:Configuration=Release /m
    if ($LASTEXITCODE -ne 0) { throw "account-server rebuild failed with exit code $LASTEXITCODE" }
    & $msbuild wServer\wServer.csproj /t:Rebuild /p:Configuration=Release /m
    if ($LASTEXITCODE -ne 0) { throw "world-server rebuild failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
