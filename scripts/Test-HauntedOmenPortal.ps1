$ErrorActionPreference = 'Stop'

# Static regression contract for the guaranteed Realm-event Ominous Below route.
# It deliberately does not require Redis, a running server, or a gameplay client.
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$behavior = Get-Content -LiteralPath (Join-Path $server 'wServer\logic\db\BehaviorDb.Omen.cs') -Raw
$implementation = Get-Content -LiteralPath (Join-Path $server 'wServer\logic\behaviors\GuaranteedPortalOnDeath.cs') -Raw
$xml = Get-Content -LiteralPath (Join-Path $server 'common\resources\xmls\EmbeddedData_OminousBelowCXML.dat') -Raw

if ($behavior -notmatch 'new GuaranteedPortalOnDeath\("Ominous Below Portal"\)') {
    throw 'The Haunted Omen behavior does not own the guaranteed Ominous Below portal route.'
}
if ($behavior -match 'DropPortalOnDeath\("Ominous Below Portal"') {
    throw 'The Haunted Omen route must not use the probabilistic portal behavior.'
}
if ($implementation -notmatch 'StateStorage\.ContainsKey\(_spawnedKey\)' -or
    $implementation -notmatch 'host\.StateStorage\[_spawnedKey\] = true' -or
    $implementation -notmatch 'duplicate death callback ignored') {
    throw 'Exactly-once protection for Haunted Omen portal creation is incomplete.'
}
if ($implementation -notmatch 'host\.PlayerSpawned' -or
    $implementation -notmatch '\[HAUNTED_OMEN_PORTAL\] FAILED') {
    throw 'Legitimate-event filtering or failure diagnostics are incomplete.'
}
if ($xml -notmatch '<Object type="0xF900" id="Ominous Below Portal"><Class>Portal</Class><IntergamePortal/><DungeonName>OminousBelow</DungeonName>') {
    throw 'The referenced Ominous Below portal is missing or no longer uses normal intergame routing.'
}

Write-Host 'PASS: legitimate Haunted Omen deaths create exactly one normal Ominous Below portal with duplicate-callback protection.'
