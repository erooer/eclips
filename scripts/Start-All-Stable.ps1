$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$logs = Join-Path $runtime 'logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$large = Get-ChildItem -LiteralPath $logs -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 10MB }
if ($large) { Write-Warning "Oversized logs detected: $($large.Name -join ', ')" }
$plan = (powercfg /getactivescheme 2>$null | Out-String).Trim()
Write-Host "Power plan: $plan"
$conflicts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 80,843,2050,6379 }
if ($conflicts) { Write-Warning "Existing listeners: $($conflicts.LocalPort -join ', ')" }
& "$PSScriptRoot\Start-All.ps1"
Get-Process -Name server,wServer -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_.PriorityClass = 'AboveNormal'; Write-Host "Set $($_.ProcessName) ($($_.Id)) to AboveNormal priority." } catch { Write-Warning "Could not set priority for $($_.ProcessName): $_" }
}
& "$PSScriptRoot\Health-Check.ps1"
