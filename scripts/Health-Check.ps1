$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$data = Join-Path $runtime 'redis-data'
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
if ((& $redisCli -p 6379 ping) -ne 'PONG') { throw 'Redis is not reachable on 127.0.0.1:6379.' }
$info = @{}
(& $redisCli -p 6379 info persistence) | ForEach-Object { if ($_ -match '^([^:]+):(.*)$') { $info[$matches[1]] = $matches[2] } }
"REDIS reachable=127.0.0.1:6379"
"REDIS dataDirectory=$data"
"REDIS aofEnabled=$($info['aof_enabled']) aofLastRewriteStatus=$($info['aof_last_bgrewrite_status']) rdbLastSaveStatus=$($info['rdb_last_bgsave_status']) lastSave=$(& $redisCli -p 6379 LASTSAVE)"
Get-ChildItem -LiteralPath $data -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in 'matching-rebuild.rdb','appendonly.aof' } | ForEach-Object { "REDIS file=$($_.Name) bytes=$($_.Length) modified=$($_.LastWriteTime.ToString('o'))" }
foreach ($port in 2050,843) { if (-not (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)) { throw "Required world/policy listener is absent on port $port." } }
foreach ($request in @(@{ Uri = 'http://127.0.0.1/crossdomain.xml'; Method = 'Get'; Body = $null }, @{ Uri = 'http://127.0.0.1/app/init'; Method = 'Post'; Body = @{} }, @{ Uri = 'http://127.0.0.1/rotmg.swf'; Method = 'Get'; Body = $null })) { $response = Invoke-WebRequest -UseBasicParsing -Uri $request.Uri -Method $request.Method -Body $request.Body -TimeoutSec 15; if ($response.StatusCode -ne 200 -or $response.RawContentLength -eq 0) { throw "Unhealthy endpoint: $($request.Uri)" }; "$($response.StatusCode) $($response.RawContentLength) $($request.Method) $($request.Uri)" }
