[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\deployment-manifest.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force
& (Join-Path $PSScriptRoot 'Test-ClientHandshakeProtocol.ps1') `
    -WorldServerPath (Join-Path $RepositoryRoot 'Cosmic-Realms-main\Server-src\bin\wServer.exe') `
    -ClientSwfPath (Join-Path $RepositoryRoot 'build\client-unchanged.swf') `
    -RequireSwfBytecode
& (Join-Path $PSScriptRoot 'Test-ClientBuildIdentity.ps1') `
    -ClientSwfPath (Join-Path $RepositoryRoot 'build\client-unchanged.swf')
& (Join-Path $PSScriptRoot 'Test-AirClientBuildIdentity.ps1') `
    -AirSwfPath (Join-Path $RepositoryRoot 'build\air\CosmicRealmsAir.swf') `
    -DesktopSwfPath (Join-Path $RepositoryRoot 'build\air\CosmicRealms-Desktop\CosmicRealmsAir.swf')
New-DeploymentManifest -RepositoryRoot $RepositoryRoot -OutputPath $OutputPath -ProtocolValidationPassed | Out-Null
