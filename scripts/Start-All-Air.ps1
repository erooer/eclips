$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\Start-All.ps1"
& "$PSScriptRoot\Health-Check.ps1"
& "$PSScriptRoot\Launch-AirClient.ps1"
