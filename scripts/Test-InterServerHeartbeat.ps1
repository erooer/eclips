$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$serverRoot = Join-Path $root 'Cosmic-Realms-main\Server-src'
$bin = Join-Path $serverRoot 'bin'
$redisExe = Join-Path $serverRoot 'Redis-x64-3.2.100\redis-server.exe'
$realmSource = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\realm\RealmManager.cs') -Raw
$fastTickerSource = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\realm\FLLogicTicker.cs') -Raw
$legacyTickerSource = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\realm\LogicTicker.cs') -Raw
$managerSource = Get-Content -LiteralPath (Join-Path $serverRoot 'common\ISManager.cs') -Raw

if ($realmSource -notmatch 'public void Run\(\)[\s\S]*?InterServer\.Run\(\)') {
    throw 'RealmManager does not start the ISManager heartbeat lifecycle.'
}
if ($fastTickerSource -match 'InterServer\.Tick' -or $legacyTickerSource -match 'InterServer\.Tick') {
    throw 'World registration is still coupled to a gameplay ticker.'
}
if ($managerSource -notmatch 'if \(_running\)\s*return;' -or
    $managerSource -notmatch '_tmr\.Elapsed \+= OnTimerElapsed' -or
    $managerSource -notmatch '_tmr\.Elapsed -= OnTimerElapsed') {
    throw 'ISManager timer lifecycle is not idempotent.'
}

foreach ($required in @('common.dll', 'StackExchange.Redis.dll', 'Newtonsoft.Json.dll', 'log4net.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bin $required))) {
        throw "Missing $required. Run scripts\Build-Server.ps1 before this validator."
    }
}
if (-not (Test-Path -LiteralPath $redisExe)) { throw 'Bundled Redis executable is missing.' }

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()

$redis = $null
$observer = $null
$world = $null
$observerDb = $null
$worldDb = $null
try {
    $redis = Start-Process -FilePath $redisExe -ArgumentList @(
        '--bind', '127.0.0.1', '--port', $port, '--save', '""',
        '--appendonly', 'no', '--protected-mode', 'no'
    ) -WindowStyle Hidden -PassThru

    $ready = $false
    for ($attempt = 0; $attempt -lt 50 -and -not $ready; $attempt++) {
        Start-Sleep -Milliseconds 100
        try {
            $client = [Net.Sockets.TcpClient]::new()
            $client.Connect('127.0.0.1', $port)
            $client.Dispose()
            $ready = $true
        } catch { }
    }
    if (-not $ready) { throw 'Isolated Redis did not become ready.' }

    foreach ($assembly in @('StackExchange.Redis.dll', 'Newtonsoft.Json.dll', 'log4net.dll', 'common.dll')) {
        [void][Reflection.Assembly]::LoadFrom((Join-Path $bin $assembly))
    }

    $observerConfig = [common.ServerConfig]::new()
    $observerConfig.serverInfo.type = [common.ServerType]::Account
    $observerConfig.serverInfo.name = 'heartbeat-observer'
    $observerConfig.serverInfo.instanceId = 'heartbeat-observer-id'
    $worldConfig = [common.ServerConfig]::new()
    $worldConfig.serverInfo.type = [common.ServerType]::World
    $worldConfig.serverInfo.name = 'heartbeat-world'
    $worldConfig.serverInfo.instanceId = 'heartbeat-world-id'

    $observerDb = [common.Database]::new('127.0.0.1', $port, '', 15, $null)
    $worldDb = [common.Database]::new('127.0.0.1', $port, '', 15, $null)
    $observer = [common.ISManager]::new($observerDb, $observerConfig)
    $world = [common.ISManager]::new($worldDb, $worldConfig)
    $observer.Run()
    $world.Run()
    $world.Run() # lifecycle start is intentionally idempotent

    # Run beyond ServerTimeout (30 seconds). A Join-only world would be gone;
    # a healthy timer-driven world remains refreshed by Ping messages.
    Start-Sleep -Seconds 33
    $registered = $observer.GetServerInfo('heartbeat-world-id')
    if ($null -eq $registered -or $registered.name -ne 'heartbeat-world') {
        throw 'Running world server timed out of ISManager registration.'
    }

    Write-Host 'PASS: world registration remained healthy beyond ISManager ServerTimeout using isolated non-persistent Redis.'
} finally {
    if ($null -ne $world) { $world.Dispose() }
    if ($null -ne $observer) { $observer.Dispose() }
    if ($null -ne $worldDb) { $worldDb.Dispose() }
    if ($null -ne $observerDb) { $observerDb.Dispose() }
    if ($null -ne $redis -and -not $redis.HasExited) {
        Stop-Process -Id $redis.Id -Force -ErrorAction SilentlyContinue
        [void]$redis.WaitForExit(5000)
    }
}
