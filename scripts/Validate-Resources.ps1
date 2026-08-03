$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\Invoke-Validator.ps1" -Scope resources -Report (Join-Path $root 'docs\reports\ResourceValidationReport.md') -ReportOnly
