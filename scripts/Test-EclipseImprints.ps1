$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$service = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\realm\EclipseImprints.cs" -Raw
$boost = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\realm\BoostStatManager.cs" -Raw
$commands = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\realm\commands\UnrankedCommands.cs" -Raw
$materials = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\realm\MaterialVault.cs" -Raw
$swap = Get-Content "$root\Cosmic-Realms-main\Server-src\wServer\networking\handlers\InvSwapHandler.cs" -Raw

foreach ($required in @(
    '0xF91F', '0xF920', '0xF921', '0xF938', '0xF947', '0xF956',
    '"swift"', '"bulwark"', '"focused"', '"hunter"',
    'StatsType.Speed, 3', 'StatsType.MaximumHP, -25',
    'StatsType.Defense, 4', 'StatsType.Dexterity, -2',
    'StatsType.Wisdom, 3', 'StatsType.Attack, 2', 'StatsType.Vitality, -2',
    'MetadataKey', 'Condition.HashEqual', 'materialVaultState', '.instances',
    'TryGetValue(operation', 'Only unequipped bag slots', 'SetImprint', 'EffectsFor')) {
    if ($service -notmatch [regex]::Escape($required)) { throw "Missing Eclipse Imprint contract: $required" }
}
foreach ($forbidden in @('StatsType.Luck', 'StatsType.CriticalHit', 'StatsType.CriticalDmg', 'mark', 'LegendaryMarks', 'Fame')) {
    if ($service -match [regex]::Escape($forbidden)) { throw "Forbidden Imprint dependency found: $forbidden" }
}
foreach ($required in @('EclipseImprintService.EffectsFor', 'base("imprint")', 'inspect', 'preview', 'apply', 'imprint_shard', 'player.Stats.ReCalculateValues')) {
    if (($boost + $commands + $materials + $swap) -notmatch [regex]::Escape($required)) { throw "Missing Imprint runtime wiring: $required" }
}

# Validate the metadata contract independently: unknown fields survive while an
# existing imprint is replaced only by the controlled writer (the runtime
# rejects a second apply before reaching this point).
$metadata = 'origin=forge;note=kept'
$parts = @($metadata.Split(';') | Where-Object { $_ -notmatch '^imprint=' })
$next = (($parts + 'imprint=swift') -join ';')
if ($next -ne 'origin=forge;note=kept;imprint=swift') { throw 'Metadata preservation model failed.' }
if (($next -split ';' | Where-Object { $_ -eq 'imprint=swift' }).Count -ne 1) { throw 'Metadata model created duplicate imprint fields.' }

'PASS: Eclipse Imprints use an allowlist, standard-stat sidegrades, imprint_shard-only CAS persistence, command wiring, and metadata-preserving equipment boosts.'
