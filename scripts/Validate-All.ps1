$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\Invoke-Validator.ps1" -Scope all -Report (Join-Path $root 'docs\reports\ValidationReport.md') -ReportOnly
