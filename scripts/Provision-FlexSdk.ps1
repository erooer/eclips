[CmdletBinding()]
param([string]$SdkRoot)
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'FlexSdk.psm1') -Force
$resolved = Resolve-FlexSdk -RepositoryRoot $repositoryRoot -SdkRoot $SdkRoot -ProvisionIfMissing
Write-Host "PASS: Apache Flex $($resolved.Version) is ready at $($resolved.Root)"
