$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\Invoke-Validator.ps1" -Scope types -Report (Join-Path $root 'docs\reports\TypeIdReport.md') -ReportOnly
