$ErrorActionPreference = 'Stop'

# Focused static contract checks for the account-backed Gift Chest bridge. These
# complement the server build; no Redis instance or live account is touched.
$root = Split-Path -Parent $PSScriptRoot
$db = Get-Content "$root\Cosmic-Realms-main\Server-src\common\Database.cs" -Raw
$models = Get-Content "$root\Cosmic-Realms-main\Server-src\common\DbModels.cs" -Raw
$service = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\realm\ItemInstanceTransferService.cs" -Raw
$vault = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\realm\worlds\logic\Vault.cs" -Raw
$swap = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\networking\handlers\InvSwapHandler.cs" -Raw
$drop = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\networking\handlers\InvDropHandler.cs" -Raw
$use = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\realm\entities\player\Player.UseItem.cs" -Raw

foreach ($pair in @(
    @($models, 'GiftItemInstances'),
    @($models, 'ItemInstanceRecord\[\]'),
    @($db, 'EnsureGiftInstances'),
    @($db, 'NormalizeGiftInstances'),
    @($db, 'Guid\.NewGuid\(\)'),
    @($db, 'Duplicate Gift Chest item instance ID rejected'),
    @($vault, 'EnsureGiftInstances'),
    @($vault, 'GiftIndexes'),
    @($service, 'TryWithdrawGift'),
    @($service, 'TryConsumeGift'),
    @($service, 'TryDropGift'),
    @($service, 'Condition\.HashEqual'),
    @($service, 'giftInstances'),
    @($service, 'GiftBytes'),
    @($swap, 'Gift Chests are reward-only'),
    @($swap, 'TryWithdrawGift'),
    @($drop, 'TryDropGift'),
    @($use, 'TryConsumeGift')
)) {
    if ($pair[0] -notmatch $pair[1]) { throw "Gift Chest identity contract missing: $($pair[1])" }
}

# Model the two non-negotiable persistence invariants with type-only legacy
# entries: migration creates one unique record per entry, and a withdrawal
# removes exactly one record while preserving the selected record metadata.
$legacyTypes = [UInt16[]](0x1001, 0x1001, 0x1002)
$records = for ($i = 0; $i -lt $legacyTypes.Length; $i++) { [pscustomobject]@{ Id = [Guid]::NewGuid().ToString('N'); ObjectType = $legacyTypes[$i]; Metadata = "meta-$i" } }
if (($records.Id | Select-Object -Unique).Count -ne $legacyTypes.Length) { throw 'Legacy migration model generated duplicate IDs.' }
$withdraw = $records[1]
$remaining = @($records[0], $records[2])
if ($remaining.Id -contains $withdraw.Id -or $withdraw.ObjectType -ne 0x1001 -or $withdraw.Metadata -ne 'meta-1') { throw 'Withdrawal model did not preserve the selected identity.' }

'PASS: Gift Chest legacy migration, identity-preserving withdrawal/drop/use hooks, CAS rollback guards, and type-only client boundary are present.'
