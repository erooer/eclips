$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

# These checks protect fresh authored content.  The broad reports retain known
# legacy findings without blocking an otherwise reproducible source build.
& (Join-Path $PSScriptRoot 'Test-TypeIdCollisions.ps1')
& (Join-Path $PSScriptRoot 'Test-OminousBelow.ps1')
& (Join-Path $PSScriptRoot 'Test-ItemXmlDescriptions.ps1')
& (Join-Path $PSScriptRoot 'Test-EclipseGameplayCleanup.ps1')
& (Join-Path $PSScriptRoot 'Test-ClientHandshakeProtocol.ps1')
& (Join-Path $PSScriptRoot 'Invoke-Validator.ps1') -Scope all -Report (Join-Path $root 'docs\reports\ValidationReport.md') -ReportOnly
