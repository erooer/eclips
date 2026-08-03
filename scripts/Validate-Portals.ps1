$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Invoke-Validator.ps1') -Scope portals -Report (Join-Path $root 'docs\reports\PortalValidation.md') -ReportOnly
