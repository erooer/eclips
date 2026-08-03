$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\Invoke-Validator.ps1" -Scope maps -Report (Join-Path $root 'docs\reports\MapValidationReport.md') -ReportOnly
