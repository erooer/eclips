$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Invoke-Validator.ps1') -Scope behaviors -Report (Join-Path $root 'docs\reports\BehaviorValidation.md') -ReportOnly
