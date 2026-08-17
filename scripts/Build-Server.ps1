$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$server = Join-Path $here 'Cosmic-Realms-main\Server-src'
$compiledBin = Join-Path $server 'bin'
$runtime = Join-Path $here 'runtime'
$nuget = Join-Path $here 'tools\nuget.exe'
Import-Module (Join-Path $PSScriptRoot 'MSBuild.psm1') -Force
$msbuild = Resolve-MSBuild
Write-Host "Using $($msbuild.Kind) MSBuild $($msbuild.Version): $($msbuild.MSBuildPath)"
& (Join-Path $PSScriptRoot 'Validate-Preflight.ps1')
Push-Location $server
try {
    & $nuget restore server.sln -NonInteractive
    if (!(Test-Path 'packages\Microsoft.Tpl.Dataflow.4.5.23')) {
        & $nuget install Microsoft.Tpl.Dataflow -Version 4.5.23 -OutputDirectory packages -NonInteractive
    }
    $referenceArgument = "/p:ReferencePath=$($msbuild.NetStandardReferencePath)"
    & $msbuild.Executable @($msbuild.ArgumentPrefix) common\common.csproj /t:Rebuild /p:Configuration=Release $referenceArgument /m
    if ($LASTEXITCODE -ne 0) { throw "common rebuild failed with exit code $LASTEXITCODE" }
    & $msbuild.Executable @($msbuild.ArgumentPrefix) server\server.csproj /t:Rebuild /p:Configuration=Release $referenceArgument /m
    if ($LASTEXITCODE -ne 0) { throw "account-server rebuild failed with exit code $LASTEXITCODE" }
    & $msbuild.Executable @($msbuild.ArgumentPrefix) wServer\wServer.csproj /t:Rebuild /p:Configuration=Release $referenceArgument /m
    if ($LASTEXITCODE -ne 0) { throw "world-server rebuild failed with exit code $LASTEXITCODE" }
    # Reflection loads lock .NET Framework executables for the lifetime of the
    # process. Run the compiled-artifact check out of process so a later rebuild
    # in this same shell can still replace wServer.exe.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-ClientHandshakeProtocol.ps1') -WorldServerPath (Join-Path $compiledBin 'wServer.exe')
    if ($LASTEXITCODE -ne 0) { throw "compiled world-server protocol validation failed with exit code $LASTEXITCODE" }
    & (Join-Path $PSScriptRoot 'Test-TypeIdCollisions.ps1') -IncludeCompiled

    # Server-src\bin is the only compiled server-artifact source. Keep the local
    # runtime executable payload derived from it; runtime must never become a
    # competing/stale source of binaries or game resources.
    foreach ($file in @('server.exe', 'wServer.exe')) {
        $source = Join-Path $compiledBin $file
        $destination = Join-Path $runtime $file
        Copy-Item -LiteralPath $source -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
            throw "Runtime synchronization hash mismatch: $file"
        }
    }
    Get-ChildItem -LiteralPath $compiledBin -File | Where-Object { $_.Extension -in @('.dll', '.pdb') } | ForEach-Object {
        $destination = Join-Path $runtime $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
            throw "Runtime synchronization hash mismatch: $($_.Name)"
        }
    }
    foreach ($resourceName in @('xmls', 'worlds', 'data')) {
        $source = Join-Path $compiledBin "resources\\$resourceName"
        $destination = Join-Path $runtime "resources\\$resourceName"
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $runtime 'resources') -Recurse -Force
            Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
                $relative = $_.FullName.Substring($source.Length).TrimStart('\\')
                $runtimeFile = Join-Path $destination $relative
                if ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $runtimeFile -Algorithm SHA256).Hash) {
                    throw "Runtime resource synchronization hash mismatch: $resourceName\\$relative"
                }
            }
        }
    }
} finally { Pop-Location }
