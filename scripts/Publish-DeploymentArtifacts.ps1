[CmdletBinding()]
param(
    [switch]$StageOnly,
    [string]$CommitMessage = 'Publish verified deployment artifacts'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force
$verified = Add-DeploymentArtifactsToIndex -RepositoryRoot $root
if ($StageOnly) {
    Write-Host "PASS: artifact bundle is staged and ready to commit from source $($verified.SourceCommit)."
    return
}
& git -C $root commit -m $CommitMessage
if ($LASTEXITCODE -ne 0) { throw "Artifact bundle commit failed with exit code $LASTEXITCODE." }
$head = (& git -C $root rev-parse HEAD).Trim()
$committed = Test-DeploymentManifest -RepositoryRoot $root -ExpectedHead $head -RequireArtifactBundleCommit
Write-Host "PASS: published artifact bundle $head from source $($committed.SourceCommit) with $($committed.ArtifactPaths.Count) artifacts."
