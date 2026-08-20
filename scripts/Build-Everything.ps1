param([switch]$IncludeAir = $true)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Test-AirBootstrapResources.ps1')
& (Join-Path $PSScriptRoot 'Build-Server.ps1')
& (Join-Path $PSScriptRoot 'Build-Client.ps1')
if ($IncludeAir) {
    & (Join-Path $PSScriptRoot 'Build-AirClient.ps1')
    & (Join-Path $PSScriptRoot 'Package-AirClient.ps1')
    & (Join-Path $PSScriptRoot 'Package-WindowsAirClient.ps1')
}
& (Join-Path $PSScriptRoot 'Test-WorldStateSynchronization.ps1') `
    -ClientSwfPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\client-unchanged.swf') `
    -RequireSwfBytecode
& (Join-Path $PSScriptRoot 'Test-WorldGeometryRender.ps1')
& (Join-Path $PSScriptRoot 'Test-FameTokenContract.ps1')
& (Join-Path $PSScriptRoot 'Test-ClientBuildIdentity.ps1')
if ($IncludeAir) { & (Join-Path $PSScriptRoot 'Test-AirClientBuildIdentity.ps1') }
& (Join-Path $PSScriptRoot 'Test-ClientArtifactDelivery.ps1')
& (Join-Path $PSScriptRoot 'New-BuildManifest.ps1')
Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force
$verified = Test-DeploymentManifest -RepositoryRoot (Split-Path -Parent $PSScriptRoot)
Write-Host "PASS: deployment manifest contains and verifies $($verified.ArtifactPaths.Count) deployment artifacts."
if ($IncludeAir) {
    & (Join-Path $PSScriptRoot 'Launch-Client.ps1') -ValidateOnly
    & (Join-Path $PSScriptRoot 'Create-AirDesktopShortcut.ps1')
}
Write-Host 'PASS: validation, rebuilt server, and rebuilt client completed.'
