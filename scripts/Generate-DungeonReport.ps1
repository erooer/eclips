$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Invoke-Validator.ps1') -Scope dungeons -Report (Join-Path $root 'docs\reports\DungeonValidation.md') -ReportOnly
