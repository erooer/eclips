$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Invoke-Validator.ps1') -Scope types -Report (Join-Path $root 'docs\reports\TypeIdValidation.md') -ReportOnly
