param([Parameter(Mandatory = $true)][string]$BackupPath)
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$data = Join-Path $runtime 'redis-data'
if (Test-Path (Join-Path $runtime 'processes.json')) { throw 'Stop the game stack with Stop-All.ps1 before restoring Redis.' }
if (-not (Test-Path $BackupPath)) { throw "Backup path does not exist: $BackupPath" }
$required = Join-Path $BackupPath 'redis.conf'
if (-not (Test-Path $required)) { throw 'Selected folder is not a Redis backup created by Backup-Redis.ps1.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safety = Join-Path $runtime "redis-backups\\pre-restore-$stamp"
New-Item -ItemType Directory -Force $safety | Out-Null
Get-ChildItem -LiteralPath $data -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in 'matching-rebuild.rdb','appendonly.aof' } | Copy-Item -Destination $safety -Force
Get-ChildItem -LiteralPath $data -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in 'matching-rebuild.rdb','appendonly.aof' } | Remove-Item -Force
Get-ChildItem -LiteralPath $BackupPath -File | Where-Object { $_.Name -in 'matching-rebuild.rdb','appendonly.aof' } | Copy-Item -Destination $data -Force
Copy-Item -LiteralPath $required -Destination (Join-Path $runtime 'redis.conf') -Force
"Restored Redis files from $BackupPath. Preserved prior files in $safety"
