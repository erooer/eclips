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
    for ($position = 0; $position -lt $map.width * $map.height; $position++) {
        $dictIndex = ($indices[$position * 2] -shl 8) -bor $indices[$position * 2 + 1]
        $entry = $map.dict[$dictIndex]
        $x = $position % $map.width
        $y = [Math]::Floor($position / $map.width)
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
            $objects.Add($type); $objects.Add($x); $objects.Add($y)
            if ($null -ne $object.SelectSingleNode('OccupySquare') -or
                $null -ne $object.SelectSingleNode('FullOccupy') -or
                $null -ne $object.SelectSingleNode('EnemyOccupySquare')) { $collidable++ }
        }
    }
    $probe = [WorldUpdateWireProbe]::Run($tiles.ToArray(), $objects.ToArray())
    if ($probe.MaxFrameLength -gt $bufferSize) { throw "$worldName emitted an oversized UPDATE frame." }
    $worldResults += [pscustomobject]@{
        World = $worldName
        Tiles = $probe.TileCount
        Objects = $probe.ObjectCount
        Collidable = $collidable
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

foreach ($result in $worldResults) {
    Write-Host ("PASS: {0} authored state -> UPDATE -> client parser: tiles={1}, objects={2}, collidable={3}, packets={4}, maxFrame={5}." -f
        $result.World, $result.Tiles, $result.Objects, $result.Collidable, $result.Packets, $result.MaxFrame)
}
Write-Host "PASS: client registers all $($serverObjectsByType.Count) server object and $($serverGroundsByType.Count) ground types representable by UPDATE."
Write-Host "PASS: oversized initial/subsequent UPDATE probe preserved $($stress.TileCount) tiles and $($stress.ObjectCount) objects across $($stress.PacketCount) bounded frames."
