$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Test-FlexSdkResolution.ps1')
& (Join-Path $PSScriptRoot 'Test-MSBuildResolution.ps1')
& (Join-Path $PSScriptRoot 'Test-TypeIdCollisionValidator.ps1')

$deploy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Deploy-VPS.ps1') -Raw
$buildClient = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Build-Client.ps1') -Raw
$buildEverything = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Build-Everything.ps1') -Raw

$buildPosition = $deploy.IndexOf('New-CurrentHeadBuild $newCommit', [StringComparison]::Ordinal)
$backupPosition = $deploy.IndexOf("`$DeploymentPhase = 'backup'", [StringComparison]::Ordinal)
$stopPosition = $deploy.IndexOf("`$DeploymentPhase = 'stop'", [StringComparison]::Ordinal)
if ($buildPosition -lt 0 -or $backupPosition -lt 0 -or $stopPosition -lt 0 -or $buildPosition -gt $backupPosition -or $buildPosition -gt $stopPosition) {
    throw 'Deploy-VPS.ps1 must build and validate current HEAD before backup/service stop.'
}
foreach ($required in @('$SourceServerBin', '$SourceClientSwf', 'Test-CurrentHeadBuild', 'Get-GeneratedCheckoutChanges', 'git -C $GitRoot restore --worktree')) {
    if (!$deploy.Contains($required)) { throw "Deploy-VPS.ps1 is missing current-HEAD artifact control: $required" }
}
if ($buildClient -notmatch 'deployableSwf' -or $buildClient -notmatch 'deployableHash') {
    throw 'Build-Client.ps1 must synchronize and verify the deployable server web SWF.'
}
if ($buildEverything -notmatch 'New-BuildManifest\.ps1') {
    throw 'Build-Everything.ps1 must generate the commit-bound artifact manifest.'
}

& (Join-Path $PSScriptRoot 'Test-ClientHandshakeProtocol.ps1')
Write-Host 'PASS: portable Flex resolution, protocol mappings, pre-stop build ordering, and current-HEAD artifact controls verified.'
