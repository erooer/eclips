$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$data = Join-Path $runtime 'redis-data'
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$destination = Join-Path $runtime "redis-backups\\$stamp"
if ((& $redisCli -p 6379 ping) -ne 'PONG') { throw 'Redis must be running on 127.0.0.1:6379 to create a consistent backup.' }
& $redisCli -p 6379 -n 15 SAVE | Out-Null
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item -LiteralPath (Join-Path $runtime 'redis.conf') -Destination $destination -Force
Get-ChildItem -LiteralPath $data -File | Where-Object { $_.Name -in 'matching-rebuild.rdb','appendonly.aof' } | Copy-Item -Destination $destination -Force
"Created Redis backup: $destination"
