$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
if (!(Test-Path $cli)) { throw "redis-cli not found: $cli" }
if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 6379 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw 'Redis is not listening on 127.0.0.1:6379. Start the stack before running this report.'
}
function Redis([string[]]$arguments) { & $cli -h 127.0.0.1 -p 6379 @arguments }
Write-Host 'PING'; Redis @('PING')
Write-Host 'SLOWLOG GET 32'; Redis @('SLOWLOG','GET','32')
Write-Host 'LATENCY LATEST'; Redis @('LATENCY','LATEST')
Write-Host 'PERSISTENCE'; Redis @('INFO','PERSISTENCE')
Write-Host 'CLIENTS'; Redis @('INFO','CLIENTS')
Write-Host 'MEMORY'; Redis @('INFO','MEMORY')
Write-Host 'STATS'; Redis @('INFO','STATS')
