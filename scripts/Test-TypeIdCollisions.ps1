$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$xmlRoot = Join-Path $root 'Cosmic-Realms-main\Server-src\common\resources\xmls'
$seen = @{}
$files = Get-ChildItem $xmlRoot -Filter '*.dat'
$baseFiles = $files | Where-Object { $_.Name -ne 'EmbeddedData_OminousBelowCXML.dat' }
foreach ($file in $baseFiles) {
    [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($object in @($xml.Objects.Object)) {
        if (!$object.type) { continue }
        $id = [Convert]::ToInt32(([string]$object.type).Substring(2), 16)
        $name = [string]$object.id
        if (!$seen.ContainsKey($id)) { $seen[$id] = $name }
    }
}
$newSeen = @{}
[xml]$ominous = Get-Content -LiteralPath (Join-Path $xmlRoot 'EmbeddedData_OminousBelowCXML.dat') -Raw
foreach ($object in @($ominous.Objects.Object)) {
    $id = [Convert]::ToInt32(([string]$object.type).Substring(2), 16); $name = [string]$object.id
    if ($seen.ContainsKey($id)) { throw ('Ominous Below type 0x{0:X4} collides with {1}' -f $id, $seen[$id]) }
    if ($newSeen.ContainsKey($id)) { throw ('Duplicate Ominous Below type 0x{0:X4}: {1} and {2}' -f $id, $newSeen[$id], $name) }
    $newSeen[$id] = $name
}
$expected = 0xF900..0xF921
foreach ($id in $expected) { if (!$newSeen.ContainsKey($id)) { throw ('Missing Ominous Below type 0x{0:X4}' -f $id) } }
Write-Host ('PASS: {0} unique object types; Ominous Below reservation F900-F921 is collision-free.' -f $seen.Count)
