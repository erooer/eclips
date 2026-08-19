$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'Cosmic-Realms-main'
$server = Join-Path $source 'Server-src'

function Read-Source([string]$relative) {
    Get-Content -LiteralPath (Join-Path $source $relative) -Raw
}
function Require([bool]$condition, [string]$message) {
    if (!$condition) { throw $message }
}

[xml]$custom = Read-Source 'Server-src\common\resources\xmls\EmbeddedData_CustomObjectsCXML.dat'
[xml]$clientCustom = Read-Source 'Client-src\src\kabam\rotmg\assets\EmbeddedData_CustomObjectsCXML.dat'
[xml]$ominous = Read-Source 'Server-src\common\resources\xmls\EmbeddedData_OminousBelowCXML.dat'
$useItem = Read-Source 'Server-src\wServer\realm\entities\player\Player.UseItem.cs'
$vault = Read-Source 'Server-src\wServer\realm\worlds\logic\Vault.cs'
$forge = Read-Source 'Server-src\wServer\realm\ForgeV1.cs'
$imprints = Read-Source 'Server-src\wServer\realm\EclipseImprints.cs'
$handler = Read-Source 'Server-src\wServer\networking\handlers\ForgeListHandler.cs'
$behavior = Read-Source 'Server-src\wServer\logic\db\BehaviorDb.OminousBelow.cs'
$starfallBehavior = Read-Source 'Server-src\wServer\logic\db\BehaviorDb.StarfallObservatory.cs'
$starfallWorld = Read-Source 'Server-src\wServer\realm\worlds\logic\StarfallObservatory.cs'
$portalService = Read-Source 'Server-src\wServer\realm\EclipseCitadelAccess.cs'
$threat = Read-Source 'Server-src\wServer\realm\RealmThreatController.cs'
$give = Read-Source 'Server-src\wServer\realm\commands\RankedCommands.cs'
$clientPacket = Read-Source 'Client-src\src\kabam\rotmg\messaging\impl\incoming\ForgeListResult.as'
$clientUi = (Read-Source 'Client-src\src\ToolForge\forgeList\ForgeServiceStrip.as') +
    (Read-Source 'Client-src\src\ToolForge\ToolForgeFrame.as') +
    (Read-Source 'Client-src\src\com\company\assembleegameclient\objects\ImprintStation.as')

$fame = $custom.Objects.Object | Where-Object id -eq '100K Fame Token'
Require ($fame.type -eq '0xF971') '100K Fame Token must retain collision-reviewed type 0xF971.'
Require ($fame.Consumable -ne $null -and $fame.Activate.'#text' -eq 'Fame' -and [int]$fame.Activate.amount -eq 100000) '100K Fame Token must be a 100,000 Fame consumable.'
Require ($useItem -match 'item\.ObjectId == "100K Fame Token"' -and $useItem -match 'FlushAsync\(\)\.Wait\(\)' -and $useItem -match 'You gained 100,000 Fame\.') '100K Fame Token must synchronously persist and send the exact confirmation.'

Require (($custom.Objects.Object | Where-Object id -eq 'Blacksmith').Class -eq 'ForgeStation') 'Blacksmith must reuse ForgeStation interaction architecture.'
Require (($custom.Objects.Object | Where-Object id -eq 'Imprint Station').Class -eq 'ImprintStation') 'Imprint Station must expose the Imprint UI.'
foreach ($objectId in '100K Fame Token', 'Blacksmith', 'Imprint Station', 'Eye Blueprint', 'Mantle Blueprint', 'Judgement Blueprint') {
    $serverObject = $custom.Objects.Object | Where-Object id -eq $objectId
    $clientObject = $clientCustom.Objects.Object | Where-Object id -eq $objectId
    Require ($clientObject -ne $null -and $clientObject.type -eq $serverObject.type) "Client/server registration differs for $objectId."
}
foreach ($needle in 'Cloth Bazaar Portal', 'LeaveWorld(clothPortal)', 'PlaceHubObject("Blacksmith"', 'PlaceHubObject("Imprint Station"') {
    Require ($vault -match [regex]::Escape($needle)) "Vault crafting hub is missing: $needle"
}
Require ($handler -match 'packet\.Category == 5 \|\| packet\.Category == 6') 'Forge/Imprint NPC UI categories are not server-backed.'
foreach ($needle in 'eye_blueprint', 'mantle_blueprint', 'judgement_blueprint', 'owned ', 'Craftable', '/forge salvage ') {
    Require ($forge -match [regex]::Escape($needle)) "Forge UI/service contract is missing: $needle"
}
foreach ($needle in 'imprint_shard', 'DescribeEffects', 'Craftable', '/imprint apply ') {
    Require ($imprints -match [regex]::Escape($needle)) "Imprint UI/service contract is missing: $needle"
}
foreach ($needle in 'ServiceKind', 'Details', 'Command', 'ActionLabel', 'Craftable') {
    Require ($clientPacket -match [regex]::Escape($needle)) "Client ForgeListResult is missing $needle."
}
Require ($clientUi -match 'playerText\(this\.command\)' -and $clientUi -match 'mode == "imprint"') 'The NPC UI must route visible actions through the established service commands.'
$commands = Read-Source 'Server-src\wServer\realm\commands\UnrankedCommands.cs'
Require ($commands -match 'base\("forge", alias: "f", listCommand: false\)' -and $commands -match 'base\("imprint", listCommand: false\)') 'Forge and Imprint compatibility commands must remain executable but hidden from player help clutter.'

$blueprints = @(
    @{ Id='Eye Blueprint'; Type='0xF974'; Material='eye_blueprint'; Boss='The Faceless Ferryman'; Chance='.04' },
    @{ Id='Mantle Blueprint'; Type='0xF975'; Material='mantle_blueprint'; Boss='Veyra, Warden of Chains'; Chance='.03' },
    @{ Id='Judgement Blueprint'; Type='0xF976'; Material='judgement_blueprint'; Boss='The Ominous One'; Chance='.02' }
)
foreach ($blueprint in $blueprints) {
    $node = $custom.Objects.Object | Where-Object id -eq $blueprint.Id
    Require ($node.type -eq $blueprint.Type -and $node.Consumable -ne $null) "$($blueprint.Id) item registration is invalid."
    Require ($node.Activate.'#text' -eq 'MaterialVaultDeposit' -and $node.Activate.id -eq $blueprint.Material -and [int]$node.Activate.amount -eq 1) "$($blueprint.Id) does not deposit its canonical material."
    $dropPattern = 'Init\("' + [regex]::Escape($blueprint.Boss) + '"[\s\S]*?ItemLoot\("' + [regex]::Escape($blueprint.Id) + '", ' + [regex]::Escape($blueprint.Chance) + '\)'
    Require ($behavior -match $dropPattern) "$($blueprint.Id) has no reachable drop from $($blueprint.Boss) at $($blueprint.Chance)."
}
Require ($useItem -match 'ActivateEffects\.MaterialVaultDeposit' -and $useItem -match 'MaterialVaultService\.TryDeposit') 'Blueprint consumption is not connected to the persisted Material Vault.'

foreach ($markName in 'Mark of the Ferryman', 'Mark of the Warden', 'Mark of the Ominous One') {
    $mark = $ominous.Objects.Object | Where-Object id -eq $markName
    Require ($mark.Consumable -ne $null -and $mark.Treasure -ne $null -and $mark.LegendaryMarks -ne $null) "$markName does not satisfy the standard mark flags."
    Require ($mark.Soulbound -eq $null -and [int]$mark.BagType -eq 5 -and [int]$mark.feedPower -eq 50) "$markName differs from the standard tradable BagType 5/feed 50 mark contract."
}

[xml]$citadel = Read-Source 'Server-src\common\resources\xmls\EmbeddedData_EclipseCitadelCXML.dat'
$portal = $citadel.Objects.Object | Where-Object id -eq 'Eclipse Citadel Portal'
$key = $citadel.Objects.Object | Where-Object id -eq 'Eclipse Citadel Key'
Require ($portal.type -eq '0xF960' -and $portal.Class -eq 'Portal') 'Eclipse portal registration is invalid.'
Require ($key.type -eq '0xF961' -and $key.Class -eq 'Equipment' -and $key.Consumable -ne $null -and $key.Activate.id -eq 'Eclipse Citadel Portal') 'Eclipse key registration is invalid.'
$world = Read-Source 'Server-src\common\resources\worlds\EclipseCitadel.jw'
Require ($world -match '"name"\s*:\s*"EclipseCitadel"' -and $world -match '0xF960') 'Eclipse portal does not map to the EclipseCitadel world.'
Require ($portalService -match 'class EclipsePortalService' -and $portalService -match 'already open here' -and $portalService -match 'Worlds\.Data\.Values') 'Shared Eclipse portal creation must validate destination registration and reject duplicates.'
Require ($starfallBehavior -notmatch 'DropPortalOnDeath\("Eclipse Citadel Portal"' -and $starfallWorld -match 'random\.NextDouble\(\)<\.05' -and $starfallWorld -match 'EclipsePortalService\.TryOpen') 'Starfall natural access must use its authoritative completion path at 5%.'
Require ($threat -match 'EclipsePortalService\.TryOpen' -and $useItem -match 'item\.ObjectId == "Eclipse Citadel Key"' -and $useItem -match 'EclipsePortalService\.CanOpen') 'Threat and key paths must share duplicate-safe portal creation.'
Require ($give -match 'alias: "give"' -and $give -match 'DisplayIdToObjectType' -and $give -match 'IdToObjectType') '/give must resolve the Eclipse key by its authored name.'

Write-Host 'PASS: Eclipse gameplay cleanup validates Fame token persistence, Vault NPC/UI access, Forge/Imprint service wiring, natural blueprints, standard marks, and duplicate-safe natural/key Citadel access.'
