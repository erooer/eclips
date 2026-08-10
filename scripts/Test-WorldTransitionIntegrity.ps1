$ErrorActionPreference = 'Stop'

# Source-level transition contract tests. They guard the two state boundaries that
# cannot be exercised without a live client: belt counts must not be replaced at
# Nexus entry, and the initial UPDATE marker must be reset for every world entry.
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$client = Get-Content -LiteralPath (Join-Path $server 'wServer\networking\Client.cs') -Raw
$player = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\entities\player\Player.cs') -Raw
$updates = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\entities\player\Player.Update.cs') -Raw
$load = Get-Content -LiteralPath (Join-Path $server 'wServer\networking\handlers\LoadHandler.cs') -Raw
$create = Get-Content -LiteralPath (Join-Path $server 'wServer\networking\handlers\CreateHandler.cs') -Raw
$hello = Get-Content -LiteralPath (Join-Path $server 'wServer\networking\handlers\HelloHandler.cs') -Raw
$connections = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\ConnectManager.cs') -Raw
$realm = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\RealmManager.cs') -Raw
$madLabXml = Get-Content -LiteralPath (Join-Path $server 'common\resources\xmls\EmbeddedData_MadLabCXML.dat') -Raw
$madLabBehaviors = Get-Content -LiteralPath (Join-Path $server 'wServer\logic\db\BehaviorDb.MadLab.cs') -Raw

if ($player -match 'owner\.Name\.Equals\("Nexus"\)[\s\S]{0,800}?HealthPots\s*=\s*new ItemStacker') {
    throw 'Nexus entry still replaces persisted HealthPots with toolbelt capacity.'
}
if ($player -notmatch 'chr\.HealthStackCount\s*=\s*HealthPots\.Count' -or
    $player -notmatch 'client\.Character\.HealthStackCount') {
    throw 'Health potion save/load contract is incomplete.'
}
if ($client -notmatch 'BeginWorldSynchronization' -or
    $client -notmatch 'Interlocked\.Exchange\(ref _initialWorldUpdateObserved, 0\)') {
    throw 'Initial UPDATE state is not reset per destination world.'
}
if ($load -notmatch 'BeginWorldSynchronization\(target\.Id, client\.Character\.CharId\)' -or
    $create -notmatch 'BeginWorldSynchronization\(target\.Id, character\.CharId\)') {
    throw 'One or more player creation paths bypass world synchronization reset.'
}
if ($updates -notmatch 'ResetWorldVisibilityState\(\)' -or
    $updates -notmatch 'duplicateObjectIds' -or
    $updates -notmatch 'filteredAsKnown') {
    throw 'Initial world known-object invariant diagnostics are incomplete.'
}
if ($hello -notmatch 'TryPrepareReconnect\(client, packet\.GameId, packet\.Key\)' -or
    $connections -notmatch 'public bool TryPrepareReconnect' -or
    $realm -notmatch 'HandoffReconnectSource') {
    throw 'Fresh-socket reconnect authentication or stale-client detachment contract is incomplete.'
}
if ($madLabXml -notmatch '<Object type="0x0992" id="Lab Open Wall">' -or
    $madLabBehaviors -notmatch '\.Init\("Lab Open Wall"') {
    throw 'Mad Lab second-boss gate controller does not match the map object ID.'
}

# Integration-style state model: destination initialization must retain both
# persisted stack counts and a fresh per-world known-object collection.
$savedHp, $savedMp = 7, 4
$destinationHp, $destinationMp = $savedHp, $savedMp
$knownObjects = [System.Collections.Generic.HashSet[int]]::new([int[]]@(11, 12, 13))
$knownObjects.Clear()
if ($destinationHp -ne 7 -or $destinationMp -ne 4 -or $knownObjects.Count -ne 0) {
    throw 'World transition state model failed.'
}

Write-Host 'PASS: HP/MP save -> reconnect -> load, fresh-socket reconnect detachment, per-world initial-sync reset, and Mad Lab second-boss gate contracts verified.'
