$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Invoke-Validator.ps1') -Scope performance -Report (Join-Path $root 'docs\reports\StaticPerformance.md') -ReportOnly
