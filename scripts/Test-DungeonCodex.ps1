$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$codex = Get-Content (Join-Path $server 'wServer\realm\DungeonCodex.cs') -Raw
$models = Get-Content (Join-Path $server 'common\DbModels.cs') -Raw
$world = Get-Content (Join-Path $server 'wServer\realm\worlds\World.cs') -Raw
$player = Get-Content (Join-Path $server 'wServer\realm\entities\player\Player.cs') -Raw
$commands = Get-Content (Join-Path $server 'wServer\realm\commands\UnrankedCommands.cs') -Raw

foreach ($required in 'DungeonCodexState', 'DungeonCodexEntry', 'DungeonCodexDefinition', 'Discovered', 'Completions', 'Deaths', 'BestSoloClearMs', 'BestPartyClearMs', 'PortalSource', 'Haunted Omen — Guaranteed Portal', 'OminousBelow') {
    if ($codex -notmatch [regex]::Escape($required)) { throw "Missing Codex requirement: $required" }
}
if ($models -notmatch 'DungeonCodexState' -or $models -notmatch 'dungeonCodexState') { throw 'Codex state must be additive DbAccount data.' }
if ($world -notmatch 'RecordDiscovery' -or $world -notmatch 'OnCodexCompletionBossDeath' -or $world -notmatch '_codexCompletionRecorded') { throw 'World entry/completion must use the authoritative deduplicated Codex path.' }
if ($player -notmatch 'DungeonCodexService\.RecordDeath') { throw 'Permanent player deaths in supported dungeons must be recorded.' }
if ($commands -notmatch 'class DungeonCodexCommand' -or $commands -notmatch 'base\("codex"') { throw 'Command-backed Codex V1 is unavailable.' }
if ($codex -match 'PotionStorage|Forge|MaterialVault') { throw 'Codex must not modify Potion Storage, Forge, or Material Vault.' }
Write-Host 'PASS: Dungeon Codex data, additive persistence, source-aware Ominous entry, and exactly-once completion hooks are present.'
