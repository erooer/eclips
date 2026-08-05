$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$sourceBin = Join-Path $base 'Cosmic-Realms-main\Server-src\bin'
$redis = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-server.exe'
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
$redisConfig = Join-Path $runtime 'redis.conf'
$data = Join-Path $runtime 'redis-data'
$logs = Join-Path $runtime 'logs'

# Redis can accept its first connection slightly after Start-Process returns.  A
# successful PONG is the authoritative readiness signal; it is not necessary for
# this invocation to have created a new redis-server.exe process.
function Wait-ForRedisHealthy {
    param([int]$TimeoutSeconds = 30)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $reply = @(& $redisCli -h 127.0.0.1 -p 6379 ping 2>$null)
        if ((($reply -join [Environment]::NewLine).Trim()) -eq 'PONG') {
            return $true
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    return $false
}

New-Item -ItemType Directory -Force $data, $logs | Out-Null
& "$PSScriptRoot\Stop-All.ps1"
Copy-Item -LiteralPath "$sourceBin\server.exe", "$sourceBin\wServer.exe" -Destination $runtime -Force
Copy-Item -Path "$sourceBin\*.dll", "$sourceBin\*.pdb" -Destination $runtime -Force
# Deploy rebuilt game resources as a matched unit.  The web root remains runtime-owned,
# but XML and worlds must never be left behind from an older server build.
Copy-Item -LiteralPath "$sourceBin\resources\xmls" -Destination "$runtime\resources" -Recurse -Force
Copy-Item -LiteralPath "$sourceBin\resources\worlds" -Destination "$runtime\resources" -Recurse -Force
Copy-Item -LiteralPath (Join-Path $base 'build\client-unchanged.swf') -Destination (Join-Path $runtime 'resources\web\rotmg.swf') -Force
$procs = @{}
if (Wait-ForRedisHealthy -TimeoutSeconds 1) {
    # A healthy local instance is sufficient.  Retaining it avoids failing a
    # deployment merely because Redis completed startup after a prior attempt.
    $procs.redis = $null
    Write-Host 'Redis is already healthy on 127.0.0.1:6379; reusing it.'
} else {
    $redisArguments = '"{0}"' -f $redisConfig
    $procs.redis = (Start-Process -FilePath $redis -ArgumentList $redisArguments -WorkingDirectory $runtime -WindowStyle Hidden -PassThru).Id
}
if (!(Wait-ForRedisHealthy -TimeoutSeconds 30)) {
    throw 'Redis did not become healthy on 127.0.0.1:6379 within 30 seconds.'
}
Start-Sleep -Seconds 2
$procs.account = (Start-Process -FilePath "$runtime\server.exe" -WorkingDirectory $runtime -WindowStyle Hidden -PassThru).Id
$procs.world = (Start-Process -FilePath "$runtime\wServer.exe" -WorkingDirectory $runtime -WindowStyle Hidden -PassThru).Id
$procs | ConvertTo-Json | Set-Content "$runtime\processes.json"
$lastError = $null
for ($attempt = 1; $attempt -le 45; $attempt++) {
    try {
        & "$PSScriptRoot\Health-Check.ps1"
        exit 0
    } catch {
        $lastError = $_
        Start-Sleep -Seconds 2
    }
}
throw "Fresh runtime did not become healthy. $lastError"
