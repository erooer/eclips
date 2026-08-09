$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$state = Join-Path $runtime 'processes.json'
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
. (Join-Path $PSScriptRoot 'Redis-Helpers.ps1')

# Stop the processes recorded by the previous launch first. Invalid state data is
# deliberately not hidden: it indicates a genuine runtime management problem.
if (Test-Path -LiteralPath $state) {
    $procs = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    @($procs.psobject.Properties | Where-Object { $_.Name -ne 'redis' } | ForEach-Object { $_.Value }) | ForEach-Object {
        if ($_ -and [int]$_ -gt 0) {
            Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
        }
    }
}

# A stale state file can miss processes that survived an interrupted launch. Only
# stop server processes whose executable is inside this runtime directory.
$runtimeProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.Name -in @('server.exe', 'wServer.exe') -and
    $_.ExecutablePath.StartsWith($runtime, [System.StringComparison]::OrdinalIgnoreCase)
})
foreach ($process in $runtimeProcesses) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

if (Test-RedisPong -RedisCli $redisCli) {
    $save = Invoke-RedisCli -RedisCli $redisCli -Arguments @('-h', '127.0.0.1', '-p', '6379', '-n', '15', 'SAVE')
    if ($save.ExitCode -ne 0) {
        if (Test-RedisPong -RedisCli $redisCli) { throw "Redis SAVE failed with exit code $($save.ExitCode)." }
        Write-Host 'Redis stopped before SAVE completed.'
    }

    $shutdown = Invoke-RedisCli -RedisCli $redisCli -Arguments @('-h', '127.0.0.1', '-p', '6379', 'SHUTDOWN', 'SAVE')
    if ($shutdown.ExitCode -ne 0 -and (Test-RedisPong -RedisCli $redisCli)) {
        throw "Redis SHUTDOWN failed with exit code $($shutdown.ExitCode)."
    }
} else {
    Write-Host 'Redis is already stopped on 127.0.0.1:6379.'
}

if (Test-Path -LiteralPath $state) {
    Remove-Item -LiteralPath $state -Force
}
