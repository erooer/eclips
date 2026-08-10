$ErrorActionPreference = 'Stop'

# Static regression contract: the three existing Ominous marks remain physical
# consumables and reuse the already-persisted Legendary mark quest-chest path.
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$xml = Get-Content -LiteralPath (Join-Path $server 'common\resources\xmls\EmbeddedData_OminousBelowCXML.dat') -Raw
$useItem = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\entities\player\Player.UseItem.cs') -Raw
$behavior = Get-Content -LiteralPath (Join-Path $server 'wServer\logic\db\BehaviorDb.OminousBelow.cs') -Raw

foreach ($mark in 'Mark of the Ferryman', 'Mark of the Warden', 'Mark of the Ominous One') {
    $node = [regex]::Match($xml, '<Object[^>]+id="' + [regex]::Escape($mark) + '".*?</Object>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
    if ([string]::IsNullOrEmpty($node) -or $node -notmatch '<Activate>LegendaryMarks</Activate>' -or $node -notmatch '<Consumable/>') {
        throw "$mark is not an established consumable Legendary Mark."
    }
}
if ($xml -match 'Material|Forge|Storage') { throw 'Ominous mark XML must not introduce material, forge, or storage behavior.' }
if ($useItem -notmatch 'private void AELegendaryMarks' -or
    $useItem -notmatch 'Manager\.Database\.AddGift\(acc, 0x3037\)') {
    throw 'The persistent Legendary mark quest-chest path is missing.'
}
foreach ($entry in '"Mark of the Ferryman", 1', '"Mark of the Warden", 1', '"Mark of the Ominous One", 1') {
    if ($behavior -notmatch [regex]::Escape($entry)) { throw "Expected guaranteed major-boss mark roll '$entry'." }
}

Write-Host 'PASS: all Ominous marks are consumable Legendary marks, progress the persisted quest counter, grant the established quest chest, and are guaranteed major-boss drops.'
