$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Test-FlexSdkResolution.ps1')
& (Join-Path $PSScriptRoot 'Test-MSBuildResolution.ps1')
& (Join-Path $PSScriptRoot 'Test-TypeIdCollisionValidator.ps1')
& (Join-Path $PSScriptRoot 'Test-DeploymentArtifactBundle.ps1')

$deploy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Deploy-VPS.ps1') -Raw
$buildClient = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Build-Client.ps1') -Raw
$buildEverything = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Build-Everything.ps1') -Raw
$publisher = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Publish-DeploymentArtifacts.ps1') -Raw

$validationPosition = $deploy.IndexOf('Test-CheckedInArtifacts $newCommit', [StringComparison]::Ordinal)
$backupPosition = $deploy.IndexOf("`$DeploymentPhase = 'backup'", [StringComparison]::Ordinal)
$stopPosition = $deploy.IndexOf("`$DeploymentPhase = 'stop'", [StringComparison]::Ordinal)
if ($validationPosition -lt 0 -or $backupPosition -lt 0 -or $stopPosition -lt 0 -or $validationPosition -gt $backupPosition -or $validationPosition -gt $stopPosition) {
    throw 'Deploy-VPS.ps1 must validate checked-in artifacts before backup/service stop.'
}
foreach ($required in @('$SourceServerBin', '$SourceClientSwf', 'Test-DeploymentManifest', 'Get-GeneratedCheckoutChanges', 'git -C $GitRoot restore --worktree')) {
    if (!$deploy.Contains($required)) { throw "Deploy-VPS.ps1 is missing current-HEAD artifact control: $required" }
}
foreach ($forbidden in @('Build-Everything.ps1', 'Resolve-FlexSdk', 'Resolve-MSBuild', 'ECLIPSE_FLEX_SDK_HOME', 'New-CurrentHeadBuild')) {
    if ($deploy.Contains($forbidden)) { throw "Deploy-VPS.ps1 must not require a build toolchain: $forbidden" }
}
if ($buildClient -notmatch 'deployableSwf' -or $buildClient -notmatch 'deployableHash') {
    throw 'Build-Client.ps1 must synchronize and verify the deployable server web SWF.'
}
if ($buildEverything -notmatch 'New-BuildManifest\.ps1') {
    throw 'Build-Everything.ps1 must generate the commit-bound artifact manifest.'
}
foreach ($required in @('Add-DeploymentArtifactsToIndex', 'Test-DeploymentManifest', 'RequireArtifactBundleCommit')) {
    if (!$publisher.Contains($required)) { throw "Artifact publisher is missing guarded publishing behavior: $required" }
}

& (Join-Path $PSScriptRoot 'Test-ClientHandshakeProtocol.ps1')
Write-Host 'PASS: portable build tooling, protocol mappings, pre-stop artifact validation, and toolchain-free VPS deployment controls verified.'
