$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$sourceBin = Join-Path $base 'Cosmic-Realms-main\Server-src\bin'
$redis = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-server.exe'
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
$redisConfig = Join-Path $runtime 'redis.conf'
$data = Join-Path $runtime 'redis-data'
$logs = Join-Path $runtime 'logs'
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
$procs.redis = (Start-Process -FilePath $redis -ArgumentList "`"$redisConfig`"" -WorkingDirectory $runtime -WindowStyle Hidden -PassThru).Id
Start-Sleep -Seconds 1
if ((& $redisCli -p 6379 ping) -ne 'PONG') { throw 'Fresh isolated Redis did not start on port 6379.' }
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
