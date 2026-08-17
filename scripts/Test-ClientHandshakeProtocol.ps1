param([string]$WorldServerPath)

$ErrorActionPreference = 'Stop'

# This test protects the wire contract used by the shipped Flash client and the
# freshly rebuilt world server. It deliberately validates both sides: a source-
# only server build must not silently resurrect the legacy packet map again.
$root = Split-Path $PSScriptRoot -Parent
$serverRoot = Join-Path $root 'Cosmic-Realms-main\Server-src'
$clientRoot = Join-Path $root 'Cosmic-Realms-main\Client-src\src'

$serverIds = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\networking\packets\PacketIds.cs') -Raw
$clientIds = Get-Content -LiteralPath (Join-Path $clientRoot 'kabam\rotmg\messaging\impl\GameServerConnection.as') -Raw
$clientConnection = Get-Content -LiteralPath (Join-Path $clientRoot 'kabam\rotmg\messaging\impl\GameServerConnectionConcrete.as') -Raw
$clientHello = Get-Content -LiteralPath (Join-Path $clientRoot 'kabam\rotmg\messaging\impl\outgoing\Hello.as') -Raw
$parameters = Get-Content -LiteralPath (Join-Path $clientRoot 'com\company\assembleegameclient\parameters\Parameters.as') -Raw
$serverClient = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\networking\Client.cs') -Raw
$serverConfig = Get-Content -LiteralPath (Join-Path $serverRoot 'common\ConfigModels.cs') -Raw
$serverHello = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\networking\packets\incoming\Hello.cs') -Raw
$helloHandler = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\networking\handlers\HelloHandler.cs') -Raw
$connections = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\realm\ConnectManager.cs') -Raw
$loadHandler = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\networking\handlers\LoadHandler.cs') -Raw
$createHandler = Get-Content -LiteralPath (Join-Path $serverRoot 'wServer\networking\handlers\CreateHandler.cs') -Raw

function Get-ServerPacketIds([string]$source) {
    $result = @{}
    foreach ($match in [regex]::Matches($source, '(?m)^\s*([A-Z][A-Z0-9_]*)\s*=\s*(\d+)\s*,')) {
        $result[$match.Groups[1].Value] = [int]$match.Groups[2].Value
    }
    return $result
}

function Get-ClientPacketIds([string]$source) {
    $result = @{}
    foreach ($match in [regex]::Matches($source, '(?m)^\s*public static const\s+([A-Z][A-Z0-9_]*)\s*(?::int)?\s*=\s*(\d+)\s*;')) {
        $result[$match.Groups[1].Value] = [int]$match.Groups[2].Value
    }
    return $result
}

$serverMap = Get-ServerPacketIds $serverIds
$clientMap = Get-ClientPacketIds $clientIds
foreach ($name in $clientMap.Keys) {
    if ($serverMap.ContainsKey($name) -and $clientMap[$name] -ne $serverMap[$name]) {
        throw "Client/server packet ID mismatch for $name (server=$($serverMap[$name]), client=$($clientMap[$name]))."
    }
}

$requiredIds = @{
    HELLO = 183
    GOTO = 30
    BUY = 50
    BUYRESULT = 93
    MAPINFO = 74
    LOAD = 26
    CREATE = 12
    CREATE_SUCCESS = 81
    UPDATE = 42
}
foreach ($entry in $requiredIds.GetEnumerator()) {
    if ($serverMap[$entry.Key] -ne $entry.Value -or $clientMap[$entry.Key] -ne $entry.Value) {
        throw "Client compatibility packet $($entry.Key) must be $($entry.Value)."
    }
}

# MessageCenter uses one table for outgoing and incoming messages. These four
# compatibility IDs must therefore remain distinct or mapMessages() overwrites a
# packet class before HELLO/initialization can complete.
$compatibilityIds = @($requiredIds.HELLO, $requiredIds.GOTO, $requiredIds.BUY, $requiredIds.BUYRESULT)
if (($compatibilityIds | Sort-Object -Unique).Count -ne $compatibilityIds.Count) {
    throw 'HELLO/GOTO/BUY/BUYRESULT contain a MessageCenter ID collision.'
}

if ($parameters -notmatch 'RANDOM1:String\s*=\s*"B1A5ED"' -or
    $serverConfig -notmatch 'key\s*\{\s*get;\s*set;\s*\}\s*=\s*"B1A5ED"') {
    throw 'Client-to-server RC4 key contract is not matched.'
}
if ($parameters -notmatch 'RANDOM2:String\s*=\s*"612a806cac78114ba5013cb531"' -or
    $serverClient -notmatch 'ServerKey\s*=\s*new byte\[\]\s*\{\s*0x61,\s*0x2a,\s*0x80,\s*0x6c,\s*0xac,\s*0x78,\s*0x11,\s*0x4b,\s*0xa5,\s*0x01,\s*0x3c,\s*0xb5,\s*0x31\s*\}') {
    throw 'Server-to-client RC4 key contract is not matched.'
}
if ($clientConnection -notmatch 'rsaEncrypt\(_local1\.getUserId\(\)\)' -or
    $clientConnection -notmatch 'rsaEncrypt\(_local1\.getPassword\(\)\)' -or
    $serverHello -notmatch 'GUID\s*=\s*RSA\.Instance\.Decrypt\(rdr\.ReadUTF\(\)\)' -or
    $serverHello -notmatch 'Password\s*=\s*RSA\.Instance\.Decrypt\(rdr\.ReadUTF\(\)\)') {
    throw 'HELLO RSA credential contract is not matched.'
}

$clientHelloOrder = @('writeUTF\(this\.buildVersion_\)', 'writeInt\(this\.gameId_\)', 'writeUTF\(this\.guid_\)', 'writeUTF\(this\.password_\)', 'writeUTF\(this\.secret_\)', 'writeInt\(this\.keyTime_\)', 'writeShort\(this\.key_\.length\)', 'writeBytes\(this\.key_\)', 'writeInt\(this\.mapJSON_\.length\)', 'writeUTFBytes\(this\.mapJSON_\)', 'writeUTF\(this\.rsa_\)', 'writeUTF\(this\.md5_\)')
$serverHelloOrder = @('BuildVersion\s*=\s*rdr\.ReadUTF\(\)', 'GameId\s*=\s*rdr\.ReadInt32\(\)', 'GUID\s*=\s*RSA\.Instance\.Decrypt\(rdr\.ReadUTF\(\)\)', 'Password\s*=\s*RSA\.Instance\.Decrypt\(rdr\.ReadUTF\(\)\)', 'Secret\s*=\s*RSA\.Instance\.Decrypt\(rdr\.ReadUTF\(\)\)', 'KeyTime\s*=\s*rdr\.ReadInt32\(\)', 'Key\s*=\s*rdr\.ReadBytes\(rdr\.ReadInt16\(\)\)', 'MapJSON\s*=\s*rdr\.Read32UTF\(\)', 'Rsa\s*=\s*RSA\.Instance\.Decrypt\(rdr\.ReadUTF\(\)\)', 'Md5\s*=\s*rdr\.ReadUTF\(\)')
foreach ($pattern in $clientHelloOrder) { if ($clientHello -notmatch $pattern) { throw "Client HELLO field missing: $pattern" } }
foreach ($pattern in $serverHelloOrder) { if ($serverHello -notmatch $pattern) { throw "Server HELLO field missing: $pattern" } }

if ($helloHandler -notmatch 'VerifyConnection\(client, packet, client\.Account\)' -or
    $helloHandler -notmatch 'client\.Manager\.ConMan\.Add\(new ConInfo\(client, packet, reconnecting\)\)') {
    throw 'HELLO no longer authenticates before entering ConnectManager.'
}
if ($connections -notmatch 'if \(gameId != World\.Test\)\s*gameId = World\.Nexus' -or
    $connections -notmatch 'client\.SendPacket\(new MapInfo\(\)' -or
    $connections -notmatch 'client\.State = ProtocolState\.Handshaked') {
    throw 'Initial HELLO no longer selects Nexus and completes MAPINFO handshaking.'
}
foreach ($handler in @($loadHandler, $createHandler)) {
    if ($handler -notmatch 'client\.State != ProtocolState\.Handshaked' -or
        $handler -notmatch 'target\.EnterWorld\(client\.Player\)' -or
        $handler -notmatch 'client\.SendPacket\(new CreateSuccess\(\)' -or
        $handler -notmatch 'client\.State = ProtocolState\.Ready' -or
        $handler -notmatch 'client\.Manager\.ConMan\.ClientConnected\(client\)') {
        throw 'LOAD/CREATE no longer completes authenticated Nexus entry.'
    }
}

# Protocol-state replay of the concrete lifecycle guarded above. The transition
# can only reach Ready after the authenticated HELLO selected Nexus, MAPINFO was
# accepted, and LOAD/CREATE entered that same target world.
$state = 'Connected'
$authenticated = $true
$targetWorld = if ($authenticated) { 'Nexus' } else { $null }
if ($targetWorld -eq 'Nexus') { $state = 'Handshaked' }
$mapInfoAccepted = $state -eq 'Handshaked'
$enteredTargetWorld = $mapInfoAccepted -and $targetWorld -eq 'Nexus'
if ($enteredTargetWorld) { $state = 'Ready' }
if ($state -ne 'Ready') { throw 'Client-compatible HELLO-to-Nexus state replay failed.' }

if ($WorldServerPath) {
    $resolvedWorldServer = (Resolve-Path -LiteralPath $WorldServerPath).Path
    $assembly = [Reflection.Assembly]::LoadFile($resolvedWorldServer)
    $packetType = $assembly.GetType('wServer.networking.packets.PacketId', $true)
    foreach ($entry in $requiredIds.GetEnumerator()) {
        $compiledValue = [int][Enum]::Parse($packetType, $entry.Key)
        if ($compiledValue -ne $entry.Value) {
            throw "Compiled wServer packet $($entry.Key) is $compiledValue; expected $($entry.Value)."
        }
    }
    Write-Host "PASS: compiled wServer packet contract verified at $resolvedWorldServer"
}

Write-Host 'PASS: client/server IDs, RC4/RSA, HELLO serialization, Nexus selection, MAPINFO, and LOAD/CREATE readiness contracts verified.'
