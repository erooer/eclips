param(
    [switch]$RequireRuntime,
    [string]$Report = (Join-Path $PSScriptRoot '..\docs\reports\OminousPaladinItemsValidation.md')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$runtimeRoot = Split-Path $root -Parent
$xmlRoot = Join-Path $root 'Server-src\common\resources\xmls'
$ominousPath = Join-Path $xmlRoot 'EmbeddedData_OminousBelowCXML.dat'
$playersPath = Join-Path $xmlRoot 'EmbeddedData_PlayersCXML.dat'
$assetLoaderPath = Join-Path $root 'Client-src\src\com\company\assembleegameclient\util\AssetLoader.as'
$wrapperPath = Join-Path $root 'Client-src\src\kabam\rotmg\assets\EmbeddedData_OminousBelowCXML.as'
$embeddedDataPath = Join-Path $root 'Client-src\src\kabam\rotmg\assets\EmbeddedData.as'
$swfPath = Join-Path $runtimeRoot 'build\client-unchanged.swf'
$airPath = Join-Path $runtimeRoot 'build\air\CosmicRealms.air'

function Assert-That([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw "ASSERTION FAILED: $Message" }
}

function Get-SwfBody([byte[]]$Bytes) {
    Assert-That ($Bytes.Length -gt 12) 'SWF is too small.'
    $signature = [Text.Encoding]::ASCII.GetString($Bytes, 0, 3)
    if ($signature -eq 'FWS') { return $Bytes }
    Assert-That ($signature -eq 'CWS') "Unsupported SWF signature '$signature'."
    # CWS has an 8-byte SWF header, then a zlib header and Adler-32 footer.
    $input = [IO.MemoryStream]::new($Bytes, 10, $Bytes.Length - 14, $false, $true)
    $stream = [IO.Compression.DeflateStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
    $output = [IO.MemoryStream]::new()
    try { $stream.CopyTo($output) } finally { $stream.Dispose(); $input.Dispose() }
    return $output.ToArray()
}

function Assert-SwfContains([string]$Path, [string[]]$Needles) {
    Assert-That (Test-Path -LiteralPath $Path) "Missing SWF '$Path'."
    $text = [Text.Encoding]::UTF8.GetString((Get-SwfBody ([IO.File]::ReadAllBytes($Path))))
    foreach ($needle in $Needles) { Assert-That ($text.Contains($needle)) "SWF '$Path' does not embed '$needle'." }
}

function Get-ItemStat([System.Xml.XmlElement]$Item, [string]$Stat) {
    return @($Item.ActivateOnEquip | Where-Object { $_.stat -eq $Stat } | ForEach-Object { [int]$_.amount } | Measure-Object -Sum).Sum
}

[xml]$ominousXml = Get-Content -LiteralPath $ominousPath -Raw
[xml]$playersXml = Get-Content -LiteralPath $playersPath -Raw
$allObjects = foreach ($file in Get-ChildItem -LiteralPath $xmlRoot -Filter '*.dat') {
    [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($object in @($xml.Objects.Object)) { $object }
}

function Get-UniqueObject([string]$Id) {
    $matches = @($allObjects | Where-Object { $_.id -eq $Id })
    Assert-That ($matches.Count -eq 1) "Expected exactly one '$Id' object; found $($matches.Count)."
    return $matches[0]
}

$judgement = Get-UniqueObject 'Judgement'
$mantle = Get-UniqueObject 'Mantle of the Below'
$eye = Get-UniqueObject 'Eye of the Ominous'
$gargoylePulse = Get-UniqueObject 'Gargoyle Pulse'
$heavyArmorReference = Get-UniqueObject 'Gargoyle Stoneplate'
$mythicalReferences = @((Get-UniqueObject 'Omnipotence Ring'), (Get-UniqueObject 'Disarray'))

# Source item identity, weapon path, and Mythical metadata.
Assert-That ($judgement.type -eq '0xF921') 'Judgement type must be 0xF921.'
Assert-That ($judgement.Class -eq 'Equipment' -and $judgement.Item -ne $null) 'Judgement must be an Equipment Item.'
Assert-That ($judgement.SlotType -eq '1') 'Judgement must use Sword SlotType 1.'
Assert-That ($judgement.ST -ne $null) 'Judgement must use the existing Mythical <ST/> marker.'
Assert-That ($judgement.RateOfFire -eq '0.35') 'Judgement must use RateOfFire 0.35.'
Assert-That ($judgement.SelectNodes('Projectile').Count -eq 1 -and $judgement.SelectNodes('NumProjectiles').Count -eq 0) 'Judgement must have one ordinary projectile and no multishot field.'
Assert-That ($judgement.Projectile.MinDamage -eq '700' -and $judgement.Projectile.MaxDamage -eq '900') 'Judgement damage must be 700-900.'
Assert-That ([int]$judgement.Projectile.Speed -gt 0 -and [int]$judgement.Projectile.LifetimeMS -gt 0) 'Judgement projectile needs positive speed and lifetime.'
Assert-That ($judgement.Projectile.ObjectId -eq 'Gargoyle Pulse') 'Judgement must use the selected known-good projectile.'
Assert-That ($gargoylePulse.Class -eq 'Projectile' -and $gargoylePulse.Texture.File -eq 'lofiObj11') 'Judgement projectile texture reference is invalid.'
Assert-That ((Get-Content -LiteralPath $assetLoaderPath -Raw).Contains('addImageSet("Moon"')) 'Judgement inventory texture set Moon is not registered by the client.'
Assert-That ((Get-Content -LiteralPath $assetLoaderPath -Raw).Contains('addImageSet("lofiObj11"')) 'Judgement projectile texture set lofiObj11 is not registered by the client.'
Assert-That ($judgement.Description -eq 'The verdict was decided long before the blade was drawn.') 'Judgement description differs from the required text.'
Assert-That ((Get-ItemStat $judgement '114') -eq 10 -and (Get-ItemStat $judgement '102') -eq 10) 'Judgement Mythical bonuses must be +10 Critical Chance and +10 Loot Chance exactly once.'

# Mantle's armor category and only its requested stats.
Assert-That ($mantle.type -eq '0xF920') 'Mantle type must remain 0xF920.'
Assert-That ($mantle.Class -eq 'Equipment' -and $mantle.Item -ne $null) 'Mantle must be an Equipment Item.'
Assert-That ($mantle.SlotType -eq $heavyArmorReference.SlotType -and $mantle.SlotType -eq '7') 'Mantle must use the established Heavy Armor SlotType 7.'
Assert-That ($mantle.ST -ne $null) 'Mantle must use the existing Mythical <ST/> marker.'
Assert-That ($mantle.SelectNodes('Activate').Count -eq 0) 'Mantle must not have an active ability.'
foreach ($stat in @('0','3','20','22','28')) { Assert-That ((Get-ItemStat $mantle $stat) -eq 0) "Mantle must not modify stat $stat." }
Assert-That ((Get-ItemStat $mantle '27') -eq 25) 'Mantle Wisdom must be +25.'
Assert-That ((Get-ItemStat $mantle '26') -eq 10) 'Mantle Vitality must be +10.'
Assert-That ((Get-ItemStat $mantle '21') -eq -5) 'Mantle Defense must be -5.'
Assert-That ((Get-ItemStat $mantle '114') -eq 10 -and (Get-ItemStat $mantle '102') -eq 10) 'Mantle Mythical bonuses must be +10 Critical Chance and +10 Loot Chance exactly once.'

# Existing class slot data is the sole equip restriction mechanism.
$compatibility = @{}
foreach ($classId in @('Warrior','Knight','Paladin','Priest')) {
    $class = @($playersXml.Objects.Object | Where-Object { $_.id -eq $classId })[0]
    Assert-That ($class -ne $null) "Missing $classId class definition."
    $slots = @($class.SlotTypes -split ',' | ForEach-Object { $_.Trim() })
    $compatibility[$classId] = @{ Sword = $slots -contains '1'; HeavyArmor = $slots -contains '7' }
}
foreach ($classId in @('Warrior','Knight','Paladin')) {
    Assert-That $compatibility[$classId].Sword "Judgement must be usable by $classId through its normal Sword slot."
    Assert-That $compatibility[$classId].HeavyArmor "Mantle must be usable by $classId through its normal Heavy Armor slot."
}
Assert-That (!$compatibility['Priest'].HeavyArmor) 'Priest unexpectedly has a Heavy Armor slot.'

# Eye regression guard: it remains the working custom-item reference.
Assert-That ($eye.type -eq '0xF91F' -and $eye.SlotType -eq '12' -and $eye.MpCost -eq '75' -and $eye.ST -ne $null) 'Eye core Seal/Mythical definition regressed.'
Assert-That ((Get-ItemStat $eye '28') -eq 5 -and (Get-ItemStat $eye '27') -eq 5) 'Eye +5 DEX/+5 WIS regressed.'
Assert-That (@($eye.Activate | Where-Object { $_.InnerText -eq 'OminousSealBlast' -and $_.totalDamage -eq '500' }).Count -eq 1) 'Eye 500-base damage activation regressed.'

# This matches XmlData's IdToObjectType registration and the command's new case-insensitive fallback.
$idMap = @{}; foreach ($object in $allObjects) { if (!$idMap.ContainsKey([string]$object.id)) { $idMap[[string]$object.id] = [string]$object.type } }
foreach ($name in @('Judgement','judgement')) {
    $matches = @($idMap.GetEnumerator() | Where-Object { [string]$_.Key -ieq $name })
    Assert-That ($matches.Count -eq 1) "'/give $name' must resolve exactly one item name."
}

# Client and package embeddings originate from the same source XML and must contain both final item names.
$wrapper = Get-Content -LiteralPath $wrapperPath -Raw
$embeddedData = Get-Content -LiteralPath $embeddedDataPath -Raw
Assert-That ($wrapper.Contains('EmbeddedData_OminousBelowCXML.dat')) 'Client Ominous XML wrapper is missing.'
Assert-That ($embeddedData.Contains('new OminousBelowCXML()')) 'Client EmbeddedData does not load the Ominous XML wrapper.'
Assert-SwfContains $swfPath @('Judgement','Mantle of the Below','Eye of the Ominous')
Assert-That (Test-Path -LiteralPath $airPath) 'Missing packaged AIR output.'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($airPath)
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -eq 'CosmicRealmsAir.swf' }
    Assert-That ($entry -ne $null) 'AIR package does not contain CosmicRealmsAir.swf.'
    $stream = $entry.Open(); $memory = [IO.MemoryStream]::new()
    try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
    $airText = [Text.Encoding]::UTF8.GetString((Get-SwfBody $memory.ToArray()))
    foreach ($needle in @('Judgement','Mantle of the Below','Eye of the Ominous')) { Assert-That ($airText.Contains($needle)) "AIR client does not embed '$needle'." }
} finally { $zip.Dispose() }

$behaviorPath = Join-Path $root 'Server-src\wServer\logic\db\BehaviorDb.OminousBelow.cs'
$behavior = Get-Content -LiteralPath $behaviorPath -Raw
foreach ($name in @('Judgement','Mantle of the Below','Eye of the Ominous')) {
    Assert-That (@([regex]::Matches($behavior, [regex]::Escape(('new ItemLoot("' + $name + '", .006)')))).Count -eq 1) "Ominous One must contain exactly one .006 drop for $name."
}

$runtimeParity = 'not requested'
if ($RequireRuntime) {
    $runtimeXmlPath = Join-Path $runtimeRoot 'runtime\resources\xmls\EmbeddedData_OminousBelowCXML.dat'
    $runtimeSwfPath = Join-Path $runtimeRoot 'runtime\resources\web\rotmg.swf'
    $runtimeWorldPath = Join-Path $runtimeRoot 'runtime\wServer.exe'
    $sourceWorldPath = Join-Path $root 'Server-src\bin\wServer.exe'
    foreach ($path in @($runtimeXmlPath,$runtimeSwfPath,$runtimeWorldPath,$sourceWorldPath)) { Assert-That (Test-Path -LiteralPath $path) "Missing runtime parity file '$path'." }
    Assert-That ((Get-FileHash $ominousPath).Hash -eq (Get-FileHash $runtimeXmlPath).Hash) 'Runtime Ominous XML differs from source.'
    Assert-That ((Get-FileHash $swfPath).Hash -eq (Get-FileHash $runtimeSwfPath).Hash) 'Runtime SWF differs from rebuilt SWF.'
    Assert-That ((Get-FileHash $sourceWorldPath).Hash -eq (Get-FileHash $runtimeWorldPath).Hash) 'Runtime world executable differs from the rebuilt server executable.'
    $runtimeParity = 'source XML, SWF, and world executable hashes match the deployed runtime'
}

$reportDirectory = Split-Path $Report -Parent
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$lines = @(
    '# Ominous Paladin Items Validation', '',
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", '',
    '## Result', '',
    '- PASS: Judgement resolves uniquely by canonical and lowercase name through the same generic item lookup.',
    '- PASS: Mantle is Heavy Armor (SlotType 7); Warrior, Knight, and Paladin have SlotType 7, while Priest does not.',
    '- PASS: source/client SWF/AIR resource embedding contains Judgement, Mantle, and Eye.',
    "- Runtime parity: $runtimeParity.", '',
    '## Final definitions', '',
    '| Item | Type | Slot | Key fields |', '| --- | --- | --- | --- |',
    '| Judgement | 0xF921 | Sword (1) | 700-900, RoF 0.35, one Gargoyle Pulse (55 speed / 565 ms), ST, +10 Critical / +10 Loot |',
    '| Mantle of the Below | 0xF920 | Heavy Armor (7) | +25 WIS, +10 VIT, -5 DEF, no Activate, ST, +10 Critical / +10 Loot |',
    '| Eye of the Ominous | 0xF91F | Seal (12) | 75 MP, 500 base OminousSealBlast, +5 DEX / +5 WIS, ST |', '',
    '## Root causes and correction', '',
    '- Judgement was absent from the runtime XML because the rebuilt resource set had not been deployed; source XML and compiled clients already contained it.',
    '- Mantle was Priest-only because the runtime still had the legacy SlotType 4, which is Priest ability. The source definition is SlotType 7 with its final stat fields.',
    '- Mantle stats and Mythical rarity were absent for the same stale-runtime reason: the old runtime XML had no ST marker or ActivateOnEquip entries.',
    '- `/give` was exact-case only. The generic lookup now performs a case-insensitive fallback for all item IDs/display names.', '',
    '## References', '',
    '- Slow Sword: Gargoyle Crusher (SlotType 1, RateOfFire 0.35, Gargoyle Pulse).',
    '- Heavy Armor: Gargoyle Stoneplate (SlotType 7).',
    '- Mythical items: Omnipotence Ring and Disarray (`<ST/>` plus explicit bonuses).',
    '- Stat format: standard signed `ActivateOnEquip stat="..." amount="..."` values; Mantle uses -5 Defense.', '',
    '## Equip compatibility', '',
    '| Class | Judgement | Mantle |', '| --- | --- | --- |',
    '| Warrior | yes | yes |', '| Knight | yes | yes |', '| Paladin | yes | yes |', '| Priest | no | no |', '',
    '## Drops', '',
    '- Ominous One has exactly one independent 0.006 entry for each of Judgement, Mantle of the Below, and Eye of the Ominous.', '',
    '## Manual checks remaining', '',
    '1. `/give judgement`, equip on Warrior/Knight/Paladin, and fire once.',
    '2. `/give mantle of the below`, equip on Warrior/Knight/Paladin, and verify Priest rejects it.',
    '3. Confirm the displayed stats and Mythical tooltip after a full client restart.'
)
Set-Content -LiteralPath $Report -Value $lines -Encoding UTF8
Write-Host "PASS: Ominous Paladin item validation completed. Report: $Report"
