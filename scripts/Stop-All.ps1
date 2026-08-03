$base = Split-Path -Parent $PSScriptRoot
$state = Join-Path $base 'runtime\processes.json'
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
if (Test-Path $state) {
    $procs = Get-Content -Raw $state | ConvertFrom-Json
    @($procs.psobject.Properties | Where-Object { $_.Name -ne 'redis' } | ForEach-Object { $_.Value }) | ForEach-Object {
        Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
    if ((& $redisCli -p 6379 ping 2>$null) -eq 'PONG') {
        & $redisCli -p 6379 -n 15 SAVE | Out-Null
        & $redisCli -p 6379 SHUTDOWN SAVE 2>$null | Out-Null
    }
    if ($procs.redis) { Stop-Process -Id $procs.redis -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $state -Force
}
