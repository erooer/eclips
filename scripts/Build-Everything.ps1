param([switch]$IncludeAir)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build-Server.ps1')
& (Join-Path $PSScriptRoot 'Build-Client.ps1')
if ($IncludeAir) { & (Join-Path $PSScriptRoot 'Build-AirClient.ps1') }
& (Join-Path $PSScriptRoot 'Test-ClientHandshakeProtocol.ps1') `
    -WorldServerPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Cosmic-Realms-main\Server-src\bin\wServer.exe') `
    -ClientSwfPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\client-unchanged.swf') `
    -RequireSwfBytecode
& (Join-Path $PSScriptRoot 'New-BuildManifest.ps1')
Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force
$verified = Test-DeploymentManifest -RepositoryRoot (Split-Path -Parent $PSScriptRoot)
Write-Host "PASS: deployment manifest contains and verifies $($verified.ArtifactPaths.Count) deployment artifacts."
Write-Host 'PASS: validation, rebuilt server, and rebuilt client completed.'
