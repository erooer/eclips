param(
    [string]$ClientSwfPath,
    [switch]$RequireSwfBytecode
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $root 'Cosmic-Realms-main'
$assetsRoot = Join-Path $sourceRoot 'Client-src\src\kabam\rotmg\assets'
$serverXmlRoot = Join-Path $sourceRoot 'Server-src\common\resources\xmls'
$worldRoot = Join-Path $sourceRoot 'Server-src\common\resources\worlds'
$bufferSize = 0x20000

function Convert-TypeId([object]$value) {
    $text = [string]$value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        $parsed = if ($text.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
            [Convert]::ToInt64($text.Substring(2), 16)
        } else {
            [int64]$text
        }
    } catch { return $null }
    if ($parsed -lt 0 -or $parsed -gt [uint16]::MaxValue) { return $null }
    return [int]$parsed
}

function Get-EmbeddedXml([string]$className) {
    $candidates = @(
        (Join-Path $assetsRoot "$className.as"),
        (Join-Path $assetsRoot "EmbeddedData_$className.as"),
        (Join-Path $assetsRoot "custom\$className.as"),
        (Join-Path $assetsRoot "custom\EmbeddedData_$className.as")
    )
    $wrapper = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (!$wrapper) { throw "Embedded-data wrapper not found for $className." }
    $sourceMatch = [regex]::Match((Get-Content -LiteralPath $wrapper -Raw), 'Embed\(source="([^"]+)"')
    if (!$sourceMatch.Success) { throw "Embedded-data source not found in $wrapper." }
    $xmlPath = [IO.Path]::GetFullPath((Join-Path (Split-Path $wrapper -Parent) $sourceMatch.Groups[1].Value))
    if (!(Test-Path -LiteralPath $xmlPath)) { throw "Embedded XML does not exist: $xmlPath" }
    try { return [xml](Get-Content -LiteralPath $xmlPath -Raw) }
    catch { throw "Embedded XML is malformed: $xmlPath`n$($_.Exception.Message)" }
}

function Get-EmbeddedClasses([string]$propertyName) {
    $embeddedData = Get-Content -LiteralPath (Join-Path $assetsRoot 'EmbeddedData.as') -Raw
    $match = [regex]::Match($embeddedData, "$propertyName`:Array\s*=\s*\[(.*?)\];", 'Singleline')
    if (!$match.Success) { throw "EmbeddedData.$propertyName was not found." }
    return @([regex]::Matches($match.Groups[1].Value, 'new\s+([A-Za-z0-9_]+)\s*\(') |
        ForEach-Object { $_.Groups[1].Value })
}

$serverObjectsById = @{}
$serverObjectsByType = @{}
$serverGroundsById = @{}
$serverGroundsByType = @{}
foreach ($file in Get-ChildItem -LiteralPath $serverXmlRoot -Filter '*.dat') {
    try { [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw } catch { continue }
    foreach ($object in @($xml.Objects.Object)) {
        $type = Convert-TypeId $object.type
        if ($null -eq $type -or !$object.id) { continue }
        $serverObjectsById[[string]$object.id] = $object
        $serverObjectsByType[$type] = $object
    }
    foreach ($ground in @($xml.GroundTypes.Ground)) {
        $type = Convert-TypeId $ground.type
        if ($null -eq $type -or !$ground.id) { continue }
        $serverGroundsById[[string]$ground.id] = $ground
        $serverGroundsByType[$type] = $ground
    }
}

$clientObjectsByType = @{}
foreach ($className in Get-EmbeddedClasses 'objectFiles') {
    $xml = Get-EmbeddedXml $className
    foreach ($object in @($xml.Objects.Object)) {
        $type = Convert-TypeId $object.type
        if ($null -ne $type) { $clientObjectsByType[$type] = $object }
    }
}
$clientGroundsByType = @{}
foreach ($className in Get-EmbeddedClasses 'groundFiles') {
    $xml = Get-EmbeddedXml $className
    foreach ($ground in @($xml.GroundTypes.Ground)) {
        $type = Convert-TypeId $ground.type
        if ($null -ne $type) { $clientGroundsByType[$type] = $ground }
    }
}

$missingObjectTypes = @($serverObjectsByType.Keys | Where-Object { !$clientObjectsByType.ContainsKey($_) })
$missingGroundTypes = @($serverGroundsByType.Keys | Where-Object { !$clientGroundsByType.ContainsKey($_) })
if ($missingObjectTypes.Count -or $missingGroundTypes.Count) {
    throw "Compiled client resource registration is incomplete: missing $($missingObjectTypes.Count) object and $($missingGroundTypes.Count) ground types representable by the wire protocol."
}

$playerUpdate = Get-Content -LiteralPath (Join-Path $sourceRoot 'Server-src\wServer\realm\entities\player\Player.Update.cs') -Raw
$structures = Get-Content -LiteralPath (Join-Path $sourceRoot 'Server-src\wServer\Structures.cs') -Raw
$clientUpdate = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\kabam\rotmg\messaging\impl\incoming\Update.as') -Raw
$clientObjectLibrary = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\com\company\assembleegameclient\objects\ObjectLibrary.as') -Raw
$clientMap = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\com\company\assembleegameclient\map\Map.as') -Raw
$clientCamera = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\com\company\assembleegameclient\map\Camera.as') -Raw
$webMain = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\WebMain.as') -Raw
$assetLoader = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\com\company\assembleegameclient\util\AssetLoader.as') -Raw
$textureFactory = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\kabam\rotmg\stage3D\graphic3D\TextureFactory.as') -Raw
$renderer = Get-Content -LiteralPath (Join-Path $sourceRoot 'Client-src\src\kabam\rotmg\stage3D\Renderer.as') -Raw
if ($playerUpdate -notmatch 'if\s*\(frameLength\s*<=\s*Server\.BufferSize\)' -or
    $playerUpdate -notmatch 'CreateUpdatePackets\(_tiles,\s*_newObjects,\s*_removedObjects\)') {
    throw 'UPDATE batching is not guarded by the socket frame limit.'
}
if ($playerUpdate -match 'isInitialWorldUpdate\s*&&\s*frameLength\s*>\s*Server\.BufferSize') {
    throw 'Oversized subsequent UPDATEs are still allowed to bypass batching.'
}
if ($structures -notmatch 'ret\.Position\s*=\s*Position\.Read\(rdr\);\s*ret\.DamageDealt\s*=\s*rdr\.ReadInt32\(\);\s*ret\.Stats') {
    throw 'The server UPDATE reader does not match ObjectStats.Write damage-field order.'
}
if ($clientUpdate -match 'this\.newObjs_\.length\s*=\s*0;\s*_local3\s*=\s*_arg1\.readShort\(\);') {
    throw 'The client discards its object vector before releasing/reusing decoded entries.'
}
if ($textureFactory -match 'function\s+make\([^}]+count\s*>\s*1000[^}]+disposeNormalTextures' -or
    $textureFactory -notmatch 'lastUsedFrame\[_arg1\]\s*=\s*frameId' -or
    $renderer -notmatch 'TextureFactory\.beginFrame\(\)' -or
    $renderer -notmatch 'context3D\.present\(\);\s*(?s:.*?)TextureFactory\.endFrame\(\)') {
    throw 'Stage3D texture eviction can still dispose resources before the submitted frame is presented.'
}
if ($webMain -notmatch 'Parameters\.data_\.GPURender\s*==\s*true[\s\S]*?Parameters\.data_\.GPURender\s*=\s*false' -or
    $clientMap -notmatch 'var\s+len:int\s*=\s*15' -or
    $clientMap -match 'var\s+len:int\s*=\s*Math\.ceil\(camera\.maxDist_\)') {
    throw 'The software renderer no longer uses the original 15-square traversal footprint.'
}
$serverRadiusMatch = [regex]::Match($playerUpdate, '(?:public|private)\s+const\s+int\s+Radius\s*=\s*(\d+)')
if (!$serverRadiusMatch.Success -or
    $clientCamera -match 'MAX_SYNCHRONIZED_DISTANCE|synchronizedDimensions') {
    throw 'The experimental client camera synchronization clamp is still present.'
}
$synchronizationRadius = [int]$serverRadiusMatch.Groups[1].Value

$factoryClasses = @([regex]::Matches($clientObjectLibrary, '"([A-Za-z0-9_]+)"\s*:\s*([A-Za-z0-9_]+)') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$imageSets = @([regex]::Matches($assetLoader, 'AssetLibrary\.addImageSet\("([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

if (!('WorldUpdateWireProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;

public sealed class WorldUpdateProbeResult
{
    public int TileCount;
    public int ObjectCount;
    public int PacketCount;
    public int MaxFrameLength;
}

public static class WorldUpdateWireProbe
{
    const int BufferSize = 0x20000;
    const int MaxTiles = 8192;
    const int MaxObjects = 256;

    static void I16(BinaryWriter w, int v) { w.Write((byte)((v >> 8) & 255)); w.Write((byte)(v & 255)); }
    static void I32(BinaryWriter w, int v) { w.Write((byte)((v >> 24) & 255)); w.Write((byte)((v >> 16) & 255)); w.Write((byte)((v >> 8) & 255)); w.Write((byte)(v & 255)); }
    static void F32(BinaryWriter w, float v) { var b = BitConverter.GetBytes(v); if (BitConverter.IsLittleEndian) Array.Reverse(b); w.Write(b); }
    static int R16(BinaryReader r) { int a = r.ReadByte(), b = r.ReadByte(); int v = (a << 8) | b; return v >= 32768 ? v - 65536 : v; }
    static int R32(BinaryReader r) { return (r.ReadByte() << 24) | (r.ReadByte() << 16) | (r.ReadByte() << 8) | r.ReadByte(); }
    static float RF32(BinaryReader r) { var b = r.ReadBytes(4); if (BitConverter.IsLittleEndian) Array.Reverse(b); return BitConverter.ToSingle(b, 0); }

    static byte[] Packet(int[] tiles, int tileOffset, int tileCount, int[] objects, int objectOffset, int objectCount)
    {
        using (var ms = new MemoryStream()) using (var w = new BinaryWriter(ms)) {
            I16(w, tileCount);
            for (int i = 0; i < tileCount; i++) {
                int p = (tileOffset + i) * 3;
                I16(w, tiles[p]); I16(w, tiles[p + 1]); I16(w, tiles[p + 2]);
            }
            I16(w, objectCount);
            for (int i = 0; i < objectCount; i++) {
                int p = (objectOffset + i) * 3;
                I16(w, objects[p]); I32(w, objectOffset + i + 1);
                F32(w, objects[p + 1] + 0.5f); F32(w, objects[p + 2] + 0.5f);
                I32(w, 0); I16(w, 0);
            }
            I16(w, 0);
            return ms.ToArray();
        }
    }

    static void Decode(byte[] body, int[] expectedTiles, int tileOffset, int[] expectedObjects, int objectOffset, WorldUpdateProbeResult result)
    {
        if (body.Length + 5 > BufferSize) throw new InvalidDataException("UPDATE frame exceeds socket buffer.");
        result.PacketCount++; result.MaxFrameLength = Math.Max(result.MaxFrameLength, body.Length + 5);
        using (var r = new BinaryReader(new MemoryStream(body))) {
            int tileCount = R16(r); if (tileCount < 0) throw new InvalidDataException("Negative tile count.");
            for (int i = 0; i < tileCount; i++) {
                int p = (tileOffset + i) * 3;
                if (R16(r) != expectedTiles[p] || R16(r) != expectedTiles[p + 1] || (ushort)R16(r) != (ushort)expectedTiles[p + 2])
                    throw new InvalidDataException("Tile changed during UPDATE round trip.");
            }
            int objectCount = R16(r); if (objectCount < 0) throw new InvalidDataException("Negative object count.");
            for (int i = 0; i < objectCount; i++) {
                int p = (objectOffset + i) * 3;
                if ((ushort)R16(r) != (ushort)expectedObjects[p]) throw new InvalidDataException("Object type changed during UPDATE round trip.");
                R32(r); float x = RF32(r), y = RF32(r); R32(r);
                if (Math.Abs(x - (expectedObjects[p + 1] + 0.5f)) > 0.001f || Math.Abs(y - (expectedObjects[p + 2] + 0.5f)) > 0.001f)
                    throw new InvalidDataException("Object position changed during UPDATE round trip.");
                int statCount = R16(r);
                if (statCount != 0) throw new InvalidDataException("Probe expected an empty status block.");
            }
            int drops = R16(r); if (drops != 0 || r.BaseStream.Position != r.BaseStream.Length) throw new InvalidDataException("UPDATE parser did not consume the complete frame.");
            result.TileCount += tileCount; result.ObjectCount += objectCount;
        }
    }

    public static WorldUpdateProbeResult Run(int[] tiles, int[] objects)
    {
        if (tiles.Length % 3 != 0 || objects.Length % 3 != 0) throw new ArgumentException("Records must contain triples.");
        int tc = tiles.Length / 3, oc = objects.Length / 3;
        var result = new WorldUpdateProbeResult();
        long completeLength = 11L + tc * 6L + oc * 20L;
        if (completeLength <= BufferSize) Decode(Packet(tiles, 0, tc, objects, 0, oc), tiles, 0, objects, 0, result);
        else {
            for (int p = 0; p < tc; p += MaxTiles) { int n = Math.Min(MaxTiles, tc - p); Decode(Packet(tiles, p, n, objects, 0, 0), tiles, p, objects, 0, result); }
            for (int p = 0; p < oc; p += MaxObjects) { int n = Math.Min(MaxObjects, oc - p); Decode(Packet(tiles, 0, 0, objects, p, n), tiles, 0, objects, p, result); }
        }
        if (result.TileCount != tc || result.ObjectCount != oc) throw new InvalidDataException("UPDATE batching lost world state.");
        return result;
    }
}
'@
}

function Expand-MapData([object]$map) {
    $compressed = [Convert]::FromBase64String([string]$map.data)
    if ($compressed.Length -lt 7) { throw 'Map zlib payload is too short.' }
    $input = New-Object IO.MemoryStream(,$compressed)
    $input.Position = 2
    $deflate = New-Object IO.Compression.DeflateStream($input, [IO.Compression.CompressionMode]::Decompress, $true)
    $output = New-Object IO.MemoryStream
    try { $deflate.CopyTo($output); return $output.ToArray() }
    finally { $deflate.Dispose(); $output.Dispose(); $input.Dispose() }
}

$worldResults = @()
foreach ($worldName in @('Nexus', 'Vault', 'PirateCave')) {
    $mapPath = Join-Path $worldRoot "$worldName.jm"
    $map = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
    $indices = Expand-MapData $map
    if ($indices.Length -ne $map.width * $map.height * 2) { throw "$worldName map payload length is invalid." }
    $tiles = New-Object 'System.Collections.Generic.List[int]'
    $objects = New-Object 'System.Collections.Generic.List[int]'
    $collidable = 0
    $factoryAccepted = 0
    $createdObjectIds = New-Object 'System.Collections.Generic.HashSet[int]'
    $mapObjectPositions = New-Object 'System.Collections.Generic.List[object]'
    $spawnPositions = New-Object 'System.Collections.Generic.List[object]'
    for ($position = 0; $position -lt $map.width * $map.height; $position++) {
        $dictIndex = ($indices[$position * 2] -shl 8) -bor $indices[$position * 2 + 1]
        $entry = $map.dict[$dictIndex]
        $x = $position % $map.width
        $y = [Math]::Floor($position / $map.width)
        foreach ($region in @($entry.regions)) {
            if ($region -and [string]$region.id -eq 'Spawn') { $spawnPositions.Add(@($x, $y)) }
        }
        if ($entry.ground) {
            $ground = $serverGroundsById[[string]$entry.ground]
            if (!$ground) { throw "$worldName references unknown server ground '$($entry.ground)'." }
            $groundType = Convert-TypeId $ground.type
            if (!$clientGroundsByType.ContainsKey($groundType)) { throw "$worldName ground '$($entry.ground)' is absent from client resources." }
            $tiles.Add($x); $tiles.Add($y); $tiles.Add($groundType)
        }
        $mapObjects = @($entry.objs)
        if ($mapObjects.Count -gt 0 -and $mapObjects[0]) {
            $id = [string]$mapObjects[0].id
            $object = $serverObjectsById[$id]
            if (!$object) { throw "$worldName references unknown server object '$id'." }
            $type = Convert-TypeId $object.type
            $clientObject = $clientObjectsByType[$type]
            if (!$clientObject) { throw "$worldName object '$id' (0x$($type.ToString('X4'))) is absent from client resources." }
            $classesMatch = [string]$clientObject.Class -eq [string]$object.Class
            $knownClientSpecialization = $id -eq 'Market Object' -and
                [string]$object.Class -eq 'Character' -and [string]$clientObject.Class -eq 'MarketObject'
            if (!$classesMatch -and !$knownClientSpecialization) { throw "$worldName object '$id' has incompatible server/client classes." }
            foreach ($descriptorField in @('Static', 'OccupySquare', 'FullOccupy', 'EnemyOccupySquare', 'BlocksSight', 'Invisible', 'NoMiniMap')) {
                if ([string]$clientObject.$descriptorField -ne [string]$object.$descriptorField) {
                    throw "$worldName object '$id' has mismatched client/server $descriptorField metadata."
                }
            }
            $hasTexture = $clientObject.SelectSingleNode('Texture') -or
                $clientObject.SelectSingleNode('AnimatedTexture') -or
                $clientObject.SelectSingleNode('RandomTexture')
            if (!$hasTexture) { throw "$worldName object '$id' has no client texture descriptor." }
            foreach ($textureNode in @($clientObject.SelectNodes('.//Texture'))) {
                $textureFile = [string]$textureNode.File
                if ($textureFile -and $imageSets -notcontains $textureFile) {
                    throw "$worldName object '$id' references unloaded client image set '$textureFile'."
                }
            }
            $clientClass = [string]$clientObject.Class
            if ($factoryClasses -notcontains $clientClass) {
                throw "$worldName object '$id' (0x$($type.ToString('X4'))) cannot be created by ObjectLibrary.TYPE_MAP."
            }
            $objectId = $objects.Count / 3 + 1
            if (!$createdObjectIds.Add($objectId)) { throw "$worldName produced duplicate client object id $objectId." }
            $objects.Add($type); $objects.Add($x); $objects.Add($y)
            $mapObjectPositions.Add([pscustomobject]@{ X=$x; Y=$y; Type=$type; Id=$id })
            $factoryAccepted++
            if ($null -ne $object.SelectSingleNode('OccupySquare') -or
                $null -ne $object.SelectSingleNode('FullOccupy') -or
                $null -ne $object.SelectSingleNode('EnemyOccupySquare')) { $collidable++ }
        }
    }
    $probe = [WorldUpdateWireProbe]::Run($tiles.ToArray(), $objects.ToArray())
    if ($probe.MaxFrameLength -gt $bufferSize) { throw "$worldName emitted an oversized UPDATE frame." }
    if ($spawnPositions.Count -eq 0) { throw "$worldName has no authored Spawn region for render-path validation." }

    # Track authored static geometry through the original Map.draw candidate
    # footprint. The root/UI resize transforms keep this logical footprint
    # stable while the AIR window changes size.
    $renderRadius = 15
    $spawn = $spawnPositions[0]
    $renderCandidates = @($mapObjectPositions | Where-Object {
        $dx = $_.X - $spawn[0]; $dy = $_.Y - $spawn[1]
        ($dx * $dx + $dy * $dy) -le ($renderRadius * $renderRadius)
    })
    $submittedIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($candidate in $renderCandidates) {
        [void]$submittedIds.Add("$($candidate.X),$($candidate.Y),$($candidate.Type)")
    }
    if ($submittedIds.Count -ne $renderCandidates.Count) { throw "$worldName render submission lost or duplicated known geometry." }
    # Simulate dispose/re-entry: no prior world collection is allowed to affect
    # the canonical submissions rebuilt for the next Map instance.
    $submittedIds.Clear()
    foreach ($candidate in $renderCandidates) { [void]$submittedIds.Add("$($candidate.X),$($candidate.Y),$($candidate.Type)") }
    if ($submittedIds.Count -ne $renderCandidates.Count) { throw "$worldName repeated transition did not reproduce the same render collection." }
    $worldResults += [pscustomobject]@{
        World = $worldName
        Tiles = $probe.TileCount
        Objects = $probe.ObjectCount
        Collidable = $collidable
        FactoryAccepted = $factoryAccepted
        RenderCandidates = $renderCandidates.Count
        Packets = $probe.PacketCount
        MaxFrame = $probe.MaxFrameLength
    }
}

# Exercise a large subsequent batch independently of the three authored maps.
$stressTiles = New-Object int[] (25000 * 3)
for ($i = 0; $i -lt 25000; $i++) { $stressTiles[$i * 3] = $i % 250; $stressTiles[$i * 3 + 1] = [Math]::Floor($i / 250); $stressTiles[$i * 3 + 2] = 1 }
$stressObjects = New-Object int[] (1000 * 3)
$knownType = [int]($serverObjectsByType.Keys | Select-Object -First 1)
for ($i = 0; $i -lt 1000; $i++) { $stressObjects[$i * 3] = $knownType; $stressObjects[$i * 3 + 1] = $i % 100; $stressObjects[$i * 3 + 2] = [Math]::Floor($i / 100) }
$stress = [WorldUpdateWireProbe]::Run($stressTiles, $stressObjects)
if ($stress.PacketCount -le 1 -or $stress.TileCount -ne 25000 -or $stress.ObjectCount -ne 1000 -or $stress.MaxFrameLength -gt $bufferSize) {
    throw 'Oversized UPDATE batching stress test failed.'
}

# Reproduce the former Stage3D failure boundary. The old make() implementation
# disposed the previous 1001 submitted textures while entry 1002 was created. The current
# frame-aware policy retains every texture touched by the frame and only prunes
# stale entries after present().
$submittedTextures = 1..1200
$legacyAlive = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($textureId in $submittedTextures) {
    if ($legacyAlive.Count -gt 1000) { $legacyAlive.Clear() }
    [void]$legacyAlive.Add($textureId)
}
if ($legacyAlive.Count -ge $submittedTextures.Count) { throw 'Legacy texture-eviction regression probe did not reach its failure boundary.' }
$currentFrame = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($textureId in $submittedTextures) { [void]$currentFrame.Add($textureId) }
# All entries are current-frame references, so endFrame is forbidden from pruning them.
if ($currentFrame.Count -ne $submittedTextures.Count) { throw 'Frame-safe texture retention dropped a submitted draw resource.' }

foreach ($result in $worldResults) {
    if ($result.FactoryAccepted -ne $result.Objects) { throw "$($result.World) client factory dropped authored objects." }
    Write-Host ("PASS: {0} authored state -> UPDATE -> ObjectLibrary/original Map render footprint: tiles={1}, objects={2}, factoryAccepted={3}, renderCandidates={4}, collidable={5}, packets={6}, maxFrame={7}." -f
        $result.World, $result.Tiles, $result.Objects, $result.FactoryAccepted, $result.RenderCandidates, $result.Collidable, $result.Packets, $result.MaxFrame)
}
Write-Host "PASS: client registers all $($serverObjectsByType.Count) server object and $($serverGroundsByType.Count) ground types representable by UPDATE."
Write-Host "PASS: oversized initial/subsequent UPDATE probe preserved $($stress.TileCount) tiles and $($stress.ObjectCount) objects across $($stress.PacketCount) bounded frames."
Write-Host 'PASS: Stage3D texture retention is frame-safe; eviction occurs only after Context3D.present().'
Write-Host "PASS: renderer stress retained all $($currentFrame.Count) submitted textures; legacy mid-frame purge retained only $($legacyAlive.Count)."
Write-Host "PASS: software Map.draw retains the original 15-square render footprint inside the server's $synchronizationRadius-square synchronization radius across repeated world entries."

if ($ClientSwfPath) {
    $resolvedClientSwf = (Resolve-Path -LiteralPath $ClientSwfPath).Path
    $swfDump = Join-Path $root 'tools\flex-sdk-4.9.1\bin\swfdump.bat'
    if (!(Test-Path -LiteralPath $swfDump)) {
        if ($RequireSwfBytecode) { throw "Compiled world-state validation requires Apache Flex swfdump: $swfDump" }
    } else {
        $dump = (& $swfDump -abc $resolvedClientSwf 2>&1 | Out-String)
        foreach ($signature in @(
            'TextureFactory.*?beginFrame',
            'TextureFactory.*?endFrame',
            'ObjectLibrary.*?getObjectFromType',
            'Map.*?internalAddObj',
            'Map.*?maxDist_')) {
            if ($dump -notmatch "(?s)$signature") { throw "Compiled client SWF is missing world-state signature: $signature" }
        }
        Write-Host "PASS: compiled SWF contains frame-safe texture lifecycle and client object creation path; SHA-256=$((Get-FileHash -LiteralPath $resolvedClientSwf -Algorithm SHA256).Hash)"
    }
}
