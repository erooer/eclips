[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\deployment-manifest.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force
New-DeploymentManifest -RepositoryRoot $RepositoryRoot -OutputPath $OutputPath | Out-Null
