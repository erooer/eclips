$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$forge = Get-Content (Join-Path $server 'wServer\realm\ForgeV1.cs') -Raw
$vault = Get-Content (Join-Path $server 'wServer\realm\MaterialVault.cs') -Raw
$models = Get-Content (Join-Path $server 'common\DbModels.cs') -Raw
$commands = Get-Content (Join-Path $server 'wServer\realm\commands\UnrankedCommands.cs') -Raw
foreach ($required in 'SalvageValues', 'echo_dust', 'slot < 4', 'TryDeposit', 'TrySpend', 'refund', 'ValidateResources', 'OperationCooldownSeconds', 'eye_blueprint', 'judgement_blueprint') { if (($forge + $vault) -notmatch [regex]::Escape($required)) { throw "Missing Forge requirement: $required" } }
if ($models -notmatch 'forgeState') { throw 'Forge idempotency state must be additive persistence.' }
if ($commands -notmatch 'class ForgeV1Command' -or $commands -notmatch 'base\("forge"') { throw 'Forge command-backed V1 is unavailable.' }
if ($forge -match 'Mark of |PotionStorage|Quest Chest') { throw 'Marks, Potion Storage, and quest chests must be excluded from Forge inputs.' }
Write-Host 'PASS: Forge V1 salvages only explicit unequipped special items, spends Material Vault resources deterministically, validates recipes, and excludes marks.'
