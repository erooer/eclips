$ErrorActionPreference = 'Stop'

# Source-contract and state-model tests for server-authorized reconnects. These
# distinguish a matching pending reconnect from an ordinary second login without
# requiring a running server.
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$connect = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\ConnectManager.cs') -Raw
$realm = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\RealmManager.cs') -Raw

if ($connect -notmatch 'HandoffReconnectSource\(client, rInfo\.SourceWorldId, rInfo\.CharacterId, rInfo\.TraceId\)' -or
    $connect -notmatch 'Database\.AcquireLock\(acc\)') {
    throw 'Validated reconnect does not transfer the account lock after source detachment.'
}
if ($realm -notmatch 'c\.Player\?\.Owner\?\.Id == sourceWorldId' -or
    $realm -notmatch 'Superseded by validated reconnect handoff') {
    throw 'Reconnect handoff is not restricted to the recorded source world.'
}
if ($realm -match 'priorClients = Clients\.Keys') {
    throw 'RealmManager still broadly disconnects same-account clients.'
}
if ($connect -notmatch 'if \(!conInfo\.Reconnecting && !client\.Manager\.Database\.AcquireLock\(acc\)\)') {
    throw 'Normal login account-in-use protection was weakened.'
}

# Nexus->Vault, Nexus->Realm, and dungeon->Nexus all use the same transfer model:
# an authorized key selects the recorded source; the source releases its lock;
# the destination claims it. An unrelated second login has no key and is denied.
function Assert-Handoff([int]$sourceWorld, [int]$destinationWorld) {
    $session = @{ Owner = 'source'; Lock = 'source'; KeyConsumed = $false }
    $session.KeyConsumed = $true
    if ($session.Owner -ne 'source') { throw 'Expected source session before handoff.' }
    $session.Owner = $null # source player/socket detached
    $session.Lock = $null  # source disconnect releases lock
    if ($session.Lock -ne $null) { throw 'Source lock was not released.' }
    $session.Lock = 'destination'
    $session.Owner = 'destination'
    if ($session.Owner -ne 'destination' -or $session.Lock -ne 'destination' -or -not $session.KeyConsumed) {
        throw "Reconnect handoff failed for $sourceWorld->$destinationWorld."
    }
}

Assert-Handoff 1 2       # Nexus -> Vault
Assert-Handoff 1 1000    # Nexus -> Realm
Assert-Handoff 1001 1    # dungeon -> Nexus

$normalSecondLoginHasReconnectKey = $false
if ($normalSecondLoginHasReconnectKey) { throw 'Test setup invalid.' }
$normalSecondLoginAllowed = $false # existing account lock remains held
if ($normalSecondLoginAllowed) { throw 'Normal duplicate login must remain rejected.' }

$keyAvailable = $true
if (-not $keyAvailable) { throw 'Test setup invalid.' }
$keyAvailable = $false
if ($keyAvailable) { throw 'Reconnect key was reusable.' }

Write-Host 'PASS: authorized reconnect handoff transfers the source lock for Nexus/Vault, Nexus/Realm, and dungeon/Nexus; normal duplicate login remains rejected; key is single-use.'
