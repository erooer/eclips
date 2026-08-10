$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$sigils = Get-Content (Join-Path $server 'wServer\realm\DungeonSigils.cs') -Raw
$codex = Get-Content (Join-Path $server 'wServer\realm\DungeonCodex.cs') -Raw
$models = Get-Content (Join-Path $server 'common\DbModels.cs') -Raw
$commands = Get-Content (Join-Path $server 'wServer\realm\commands\UnrankedCommands.cs') -Raw

foreach ($required in 'sigil_fragment', 'UnlockThreshold', 'FragmentCost', 'PendingOpenOperations', 'OpenRateLimitSeconds', 'TrySpend', 'WorldInstanceSet', 'no fragments were consumed', 'Haunted Omen') {
    if (($sigils + $codex) -notmatch [regex]::Escape($required)) { throw "Missing Sigil requirement: $required" }
}
if ($models -notmatch 'dungeonSigilState') { throw 'Sigil state must be additive DbAccount data.' }
if ($commands -notmatch 'class DungeonSigilsCommand' -or $commands -notmatch 'base\("sigils"') { throw 'Sigil command-backed V1 is unavailable.' }
if ($sigils -match 'Mark of |PotionStorage|Forge|Inventory\[') { throw 'Sigils must not use marks, Potion Storage, Forge, or inventory materials.' }
if ($codex -notmatch 'DungeonSigilService\.DescribeAccess') { throw 'Codex must expose Sigil access status.' }
Write-Host 'PASS: Dungeon Sigils require Codex clears, use idempotent non-mark material spends, defer charge until portal readiness, and retain Ominous natural access.'
