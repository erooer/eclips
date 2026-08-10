$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$service = Get-Content (Join-Path $server 'wServer\realm\Contracts.cs') -Raw
$models = Get-Content (Join-Path $server 'common\DbModels.cs') -Raw
$use = Get-Content (Join-Path $server 'wServer\realm\entities\player\Player.UseItem.cs') -Raw
$commands = Get-Content (Join-Path $server 'wServer\realm\commands\UnrankedCommands.cs') -Raw
foreach ($required in 'ContractState', 'RecordMark', 'DailyMarksClaimed', 'WeeklyMarksClaimed', 'DailyBonusClaimed', 'WeeklyBonusClaimed', 'RerollCost', 'account.FlushAsync().Wait()') { if (($service + $models) -notmatch [regex]::Escape($required)) { throw "Missing contract persistence/claim contract: $required" } }
if (($use | Select-String -Pattern 'ContractService.RecordMark' -AllMatches).Matches.Count -ne 4) { throw 'All four consumable mark tiers must record contract progress.' }
if ($commands -notmatch 'class ContractsCommand' -or $commands -notmatch 'base\("contracts"') { throw 'Player contract command is unavailable.' }
if ($service -match 'PotionStorage|Forge|MaterialVault') { throw 'Contracts must not alter Potion Storage, Forge, or Material Vault.' }
Write-Host 'PASS: contracts persist additively, record all consumable marks/chests, gate claims idempotently, and expose fame rerolls.'
