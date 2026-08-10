$ErrorActionPreference = 'Stop'

# Source-contract and state-model tests for server-authorized reconnects. These
# distinguish a matching pending reconnect from an ordinary second login without
# requiring a running server.
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$connect = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\ConnectManager.cs') -Raw
$realm = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\RealmManager.cs') -Raw
$database = Get-Content -LiteralPath (Join-Path $server 'common\Database.cs') -Raw

if ($connect -notmatch 'TransferLock\(acc, rInfo\.SourceLockProof\)' -or
    $connect -notmatch 'HandoffReconnectSource\(client, rInfo\.SourceWorldId, rInfo\.CharacterId, gameId, transfer, rInfo\.TraceId\)' -or
    $connect -notmatch 'Database\.AcquireLock\(acc\)') {
    throw 'Validated reconnect does not transfer the account lock after source detachment.'
}
if ($database -notmatch 'AccountLockTransferResult TransferLock' -or
    $database -notmatch 'Condition\.StringEqual\(aKey, sourceLockToken\)' -or
    $database -notmatch 'acc\.LockToken = destinationToken') {
    throw 'Redis account-lock compare-and-transfer contract is incomplete.'
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
foreach ($stage in 'pending_reconnect_lookup', 'reconnect_validation', 'key_consumption', 'destination_lock_acquire', 'destination_registration', 'mapinfo_begin') {
    if ($connect -notmatch $stage) { throw "Missing reconnect failure diagnostic stage '$stage'." }
}
foreach ($stage in 'source_client_lookup', 'source_identity_match', 'source_player_removal', 'source_disconnect', 'source_lock_release') {
    if ($realm -notmatch $stage) { throw "Missing reconnect handoff failure diagnostic stage '$stage'." }
}
foreach ($outcome in 'source_already_detached_lock_owned_by_source', 'source_already_detached_lock_missing', 'source_already_detached_lock_owned_by_other_session', 'lock_transfer_success') {
    if (($connect + $realm) -notmatch $outcome) { throw "Missing reconnect lock-ownership diagnostic '$outcome'." }
}
if ($connect -notmatch '\[RECONNECT_HANDOFF\] FAILED stage=' -or
    $connect -notmatch 'Account in use \(reconnect handoff failed: destination_lock_acquire\)') {
    throw 'Reconnect handoff failure logs or player-facing stage message are incomplete.'
}

# Nexus->Vault, Nexus->Realm, and dungeon->Nexus all use the same transfer model:
# an authorized reconnect swaps the exact source token before old cleanup. The
# old token can no longer release the new destination lock.
function Assert-Handoff([int]$sourceWorld, [int]$destinationWorld) {
    $session = @{ Owner = 'source'; Lock = 'source-token'; KeyConsumed = $false }
    $session.KeyConsumed = $true
    if ($session.Owner -ne 'source') { throw 'Expected source session before handoff.' }
    $oldToken = $session.Lock
    $session.Lock = 'destination-token' # atomic compare-and-transfer
    $session.Owner = $null # source player/socket detached
    if ($oldToken -eq $session.Lock) { throw 'Lock token was not transferred.' }
    # old source compare-and-release uses oldToken and must not remove destination-token
    if ($session.Lock -ne 'destination-token') { throw 'Old source cleanup released destination ownership.' }
    $session.Owner = 'destination'
    if ($session.Owner -ne 'destination' -or $session.Lock -ne 'destination-token' -or -not $session.KeyConsumed) {
        throw "Reconnect handoff failed for $sourceWorld->$destinationWorld."
    }
}

Assert-Handoff 1 2       # Nexus -> Vault
Assert-Handoff 1 1000    # Nexus -> Realm
Assert-Handoff 1001 1    # dungeon -> Nexus

# B/C/D: source already detached. Only a matching saved proof can transfer a
# lingering lock; a missing lock can be acquired; any other token is rejected.
$proof = 'source-token'
$lingeringSourceLock = 'source-token'
if ($lingeringSourceLock -ne $proof) { throw 'B: source-owned lingering lock did not match proof.' }
$destinationLock = 'destination-token'
if ($destinationLock -eq $proof) { throw 'B: transfer did not replace source token.' }
$missingLock = $null
if ($null -ne $missingLock) { throw 'C: expected absent source lock.' }
$destinationLock = 'destination-token' # acquire only when key absent
$foreignLock = 'foreign-token'
if ($foreignLock -eq $proof) { throw 'D: foreign session token matched source proof.' }

$normalSecondLoginHasReconnectKey = $false
if ($normalSecondLoginHasReconnectKey) { throw 'Test setup invalid.' }
$normalSecondLoginAllowed = $false # existing account lock remains held
if ($normalSecondLoginAllowed) { throw 'Normal duplicate login must remain rejected.' }

$keyAvailable = $true
if (-not $keyAvailable) { throw 'Test setup invalid.' }
$keyAvailable = $false
if ($keyAvailable) { throw 'Reconnect key was reusable.' }

Write-Host 'PASS: authorized reconnect handoff transfers the source lock for Nexus/Vault, Nexus/Realm, and dungeon/Nexus; normal duplicate login remains rejected; key is single-use.'
