[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$assetRoot = Join-Path $root 'Cosmic-Realms-main\Client-src\src\kabam\rotmg\assets'
$groundFiles = @(
    (Join-Path $root 'Cosmic-Realms-main\Server-src\common\resources\xmls\EmbeddedData_GroundCXML.dat'),
    (Join-Path $assetRoot 'EmbeddedData_GroundCXML.dat'),
    (Join-Path $assetRoot 'EmbeddedData_stPatricksGroundCXML.dat'),
    (Join-Path $assetRoot 'EmbeddedData_hanaminexusGroundCXML.dat'),
    (Join-Path $assetRoot 'EmbeddedData_mountainTempleGroundCXML.dat'),
    (Join-Path $assetRoot 'EmbeddedData_summerNexusGroundCXML.dat')
)
$xmlListSensitiveChildren = @('Animate', 'Edge', 'Corner', 'InnerCorner', 'Top', 'TopAnimate')
$groundCount = 0

foreach ($file in $groundFiles) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing AIR bootstrap ground resource: $file" }
    try {
        $document = New-Object Xml.XmlDocument
        $document.LoadXml((Get-Content -LiteralPath $file -Raw))
    } catch {
        throw "AIR bootstrap ground resource is not well-formed XML: $file`n$($_.Exception.Message)"
    }
    foreach ($ground in $document.SelectNodes('//Ground')) {
        $groundCount++
        foreach ($childName in $xmlListSensitiveChildren) {
            $count = @($ground.SelectNodes($childName)).Count
            if ($count -gt 1) {
                throw "AIR GroundProperties would fail XML-list coercion: $file ground '$($ground.id)' type=$($ground.type) has $count <$childName> elements."
            }
        }
    }
}

$embeddedData = Get-Content -LiteralPath (Join-Path $assetRoot 'EmbeddedData.as') -Raw
foreach ($required in @('new ServerGroundCXML()', 'new GroundCXML()', 'new EmbeddedData_summerNexusGroundCXML()')) {
    if (!$embeddedData.Contains($required)) { throw "AIR ground resource list is missing $required" }
}

$serverEquipmentPath = Join-Path $root 'Cosmic-Realms-main\Server-src\common\resources\xmls\EmbeddedData_EquipCXML.dat'
$serverEquipment = New-Object Xml.XmlDocument
$serverEquipment.LoadXml((Get-Content -LiteralPath $serverEquipmentPath -Raw))
$invalidAnimatedSheetTextures = @($serverEquipment.SelectNodes("//Object/Texture[File='petsDivine']"))
if ($invalidAnimatedSheetTextures.Count -ne 0) {
    $invalidIds = @($invalidAnimatedSheetTextures | ForEach-Object { $_.ParentNode.id }) -join ', '
    throw "AIR bootstrap object resources use animated sheet petsDivine as a static texture: $invalidIds"
}
$swBoss = $serverEquipment.SelectSingleNode("//Object[@id='SW Boss']")
if (!$swBoss -or !$swBoss.SelectSingleNode("AnimatedTexture[File='petsDivine' and Index='09']")) {
    throw 'SW Boss must use petsDivine index 09 through AnimatedTexture.'
}

$assetLoaderPath = Join-Path $root 'Cosmic-Realms-main\Client-src\src\com\company\assembleegameclient\util\AssetLoader.as'
$assetLoader = Get-Content -LiteralPath $assetLoaderPath -Raw
$staticSheets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$animatedSheets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($match in [regex]::Matches($assetLoader, 'AssetLibrary\.addImageSet\("([^"]+)"')) {
    [void]$staticSheets.Add($match.Groups[1].Value)
}
foreach ($match in [regex]::Matches($assetLoader, 'AnimatedChars\.add\("([^"]+)"')) {
    [void]$animatedSheets.Add($match.Groups[1].Value)
}

$serverObjectFiles = @(
    'EmbeddedData_AshenFoundryCXML.dat',
    'EmbeddedData_EclipseCitadelCXML.dat',
    'EmbeddedData_EquipCXML.dat',
    'EmbeddedData_ObjectsCXML.dat',
    'EmbeddedData_PetsCXML.dat',
    'EmbeddedData_SkinsCXML.dat',
    'EmbeddedData_StarfallObservatoryCXML.dat',
    'EmbeddedData_summerNexusObjectCXML.dat',
    'EmbeddedData_SunkenReliquaryCXML.dat'
)
$serverXmlRoot = Join-Path $root 'Cosmic-Realms-main\Server-src\common\resources\xmls'
foreach ($serverObjectFile in $serverObjectFiles) {
    $path = Join-Path $serverXmlRoot $serverObjectFile
    $document = New-Object Xml.XmlDocument
    $document.LoadXml((Get-Content -LiteralPath $path -Raw))
    foreach ($texture in $document.SelectNodes('//Object//Texture[File]')) {
        $sheet = [string]$texture.File
        if (!$staticSheets.Contains($sheet)) {
            throw "AIR bootstrap object '$($texture.SelectSingleNode('ancestor::Object').id)' uses unavailable static texture sheet '$sheet' in $serverObjectFile."
        }
    }
    foreach ($texture in $document.SelectNodes('//Object//AnimatedTexture[File]')) {
        $sheet = [string]$texture.File
        if (!$animatedSheets.Contains($sheet)) {
            throw "AIR bootstrap object '$($texture.SelectSingleNode('ancestor::Object').id)' uses unavailable animated texture sheet '$sheet' in $serverObjectFile."
        }
    }
}

Write-Host "PASS: all $groundCount AIR bootstrap grounds are well-formed and safe for GroundProperties XML coercion."
Write-Host 'PASS: server object resources use petsDivine through the client-compatible animated-texture contract.'
Write-Host "PASS: all server completeness-layer object textures resolve through the client AssetLoader."
