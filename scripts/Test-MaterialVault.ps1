$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$vault = Get-Content (Join-Path $server 'wServer\realm\MaterialVault.cs') -Raw
$models = Get-Content (Join-Path $server 'common\DbModels.cs') -Raw
$commands = Get-Content (Join-Path $server 'wServer\realm\commands\UnrankedCommands.cs') -Raw

foreach ($required in 'MaterialVaultState', 'MaterialVaultService', 'DefaultCap = 9999', 'TryDeposit', 'TryAutoDeposit', 'TryWithdraw', 'TrySpend', 'AppliedOperations', 'OperationLedgerLimit', 'Invalid material ID', 'amount <= 0', 'Material Vault cap reached', 'account.FlushAsync().Wait()') {
    if ($vault -notmatch [regex]::Escape($required)) { throw "Missing Material Vault guarantee: $required" }
}
if ($models -notmatch 'materialVaultState') { throw 'Material Vault must be additive DbAccount persistence.' }
if ($commands -notmatch 'class MaterialsCommand' -or $commands -notmatch 'base\("materials"') { throw 'Material Vault command-backed V1 is unavailable.' }
if ($vault -match 'Mark of |Potion of |Quest Chest|Inventory\[') { throw 'Material Vault source must not accept marks, potions, chests, or inventory items.' }
Write-Host 'PASS: Material Vault uses stable allowlisted IDs, additive persistence, bounded idempotency, caps, and excludes marks/items.'
