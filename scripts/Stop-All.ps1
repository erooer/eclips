$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$state = Join-Path $runtime 'processes.json'
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'

function Test-RedisRunning {
    if (!(Test-Path -LiteralPath $redisCli -PathType Leaf)) {
        throw "Missing redis-cli.exe: $redisCli"
    }

    # A fresh reboot normally leaves processes.json behind while Redis is not yet
    # listening. Capture native stdout and stderr so connection refusal cannot be
    # promoted by the caller's ErrorActionPreference.
    $pingOutput = @()
    $pingExitCode = $null
    try {
        $pingOutput = @(& $redisCli -h 127.0.0.1 -p 6379 ping 2>&1)
        $pingExitCode = $LASTEXITCODE
    }
    catch {
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Redis is already stopped on 127.0.0.1:6379.'
            return $false
        }
        throw
    }

    $pingReply = ($pingOutput -join [Environment]::NewLine).Trim()
    if ($pingExitCode -eq 0 -and $pingReply -eq 'PONG') {
        return $true
    }

    Write-Host 'Redis is already stopped on 127.0.0.1:6379.'
    return $false
}

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

if (Test-RedisRunning) {
    & $redisCli -h 127.0.0.1 -p 6379 -n 15 SAVE | Out-Null
    & $redisCli -h 127.0.0.1 -p 6379 SHUTDOWN SAVE 2>$null | Out-Null
}

if (Test-Path -LiteralPath $state) {
    Remove-Item -LiteralPath $state -Force
}
