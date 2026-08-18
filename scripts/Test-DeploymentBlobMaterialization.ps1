[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Commit
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RepositoryRoot)
if (!$Commit) { $Commit = (& git -C $root rev-parse HEAD).Trim() }
if ($LASTEXITCODE -ne 0 -or $Commit -notmatch '^[0-9a-f]{40}$') { throw 'Unable to determine artifact commit.' }

Import-Module (Join-Path $root 'scripts\DeploymentArtifacts.psm1') -Force
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "EclipseBlobValidation-$([guid]::NewGuid().ToString('N'))"
$stageRoot = Join-Path $testRoot 'stage'
$copyRoot = Join-Path $testRoot 'copy'
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $verified = New-DeploymentArtifactStageFromGit -RepositoryRoot $root -Commit $Commit -DestinationRoot $stageRoot
    foreach ($relative in $verified.ArtifactPaths) {
        $source = Join-Path $verified.ArtifactRoot $relative.Replace('/', '\')
        $destination = Join-Path $copyRoot $relative.Replace('/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $expected = [string]$verified.Manifest.artifacts.PSObject.Properties[$relative].Value
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
            throw "Blob-staged deployment copy hash mismatch: $relative"
        }
    }
    $requestPath = 'Cosmic-Realms-main/Server-src/bin/resources/data/changePassword/request.txt'
    if ($requestPath -notin $verified.ArtifactPaths) { throw "Deployment manifest is missing regression artifact: $requestPath" }
    $requestHash = (Get-FileHash -LiteralPath (Join-Path $copyRoot $requestPath.Replace('/', '\')) -Algorithm SHA256).Hash
    Write-Host "PASS: blob-exact staging and deployment-copy simulation verified $($verified.ArtifactPaths.Count) artifacts at $Commit."
    Write-Host "PASS: changePassword/request.txt materialized to manifest SHA-256 $requestHash."
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
