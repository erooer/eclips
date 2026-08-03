$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Invoke-Validator.ps1') -Scope resources -Report (Join-Path $root 'docs\reports\ProjectileValidation.md') -ReportOnly
