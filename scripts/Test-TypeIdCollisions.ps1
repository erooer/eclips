[CmdletBinding()]
param(
    [string]$XmlRoot,
    [switch]$IncludeCompiled,
    [string]$CompiledXmlRoot
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$XmlRoot) { $XmlRoot = Join-Path $root 'Cosmic-Realms-main\Server-src\common\resources\xmls' }
if (!$CompiledXmlRoot) { $CompiledXmlRoot = Join-Path $root 'Cosmic-Realms-main\Server-src\bin\resources\xmls' }
$ominousFileName = 'EmbeddedData_OminousBelowCXML.dat'
$expectedReservation = 0xF900..0xF921

function Get-ObjectDefinitions([string]$ResourceRoot) {
    if (!(Test-Path -LiteralPath $ResourceRoot -PathType Container)) { throw "Object resource directory not found: $ResourceRoot" }
    $definitions = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $ResourceRoot -Filter '*.dat' -File | Sort-Object Name) {
        [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw
        $documentRoot = $xml.DocumentElement
        if ($null -eq $documentRoot) { throw "XML resource has no document element: $($file.FullName)" }

        # The resource directory intentionally also contains GroundTypes,
        # EquipmentSets, Regions, and Tutorial documents. Inspect the DOM root
        # instead of relying on PowerShell's shape-dependent $xml.Objects adapter.
        if ($documentRoot.LocalName -ne 'Objects') { continue }
        foreach ($node in $documentRoot.ChildNodes) {
            if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element -or $node.LocalName -ne 'Object') { continue }
            $typeText = $node.GetAttribute('type')
            if ([string]::IsNullOrWhiteSpace($typeText)) { continue }
            if ($typeText -notmatch '^0x([0-9A-Fa-f]+)$') { throw "Invalid object type '$typeText' in $($file.Name)." }
            $definitions.Add([PSCustomObject]@{
                Type = [Convert]::ToInt32($Matches[1], 16)
                Name = $node.GetAttribute('id')
                File = $file.Name
            })
        }
    }
    return @($definitions)
}

function Test-OminousReservation([object[]]$Definitions, [string]$Description) {
    $seen = @{}
    foreach ($definition in $Definitions | Where-Object File -ne $ominousFileName) {
        # Preserve the legacy resource set's first definition for an existing
        # duplicate. This validator owns the reserved Ominous Below range; the
        # broader report continues to inventory unrelated legacy duplicates.
        if (!$seen.ContainsKey($definition.Type)) { $seen[$definition.Type] = $definition.Name }
    }

    $newSeen = @{}
    foreach ($definition in $Definitions | Where-Object File -eq $ominousFileName) {
        if ($seen.ContainsKey($definition.Type)) {
            throw ('Ominous Below type 0x{0:X4} collides with {1} in {2}' -f $definition.Type, $seen[$definition.Type], $Description)
        }
        if ($newSeen.ContainsKey($definition.Type)) {
            throw ('Duplicate Ominous Below type 0x{0:X4}: {1} and {2} in {3}' -f $definition.Type, $newSeen[$definition.Type], $definition.Name, $Description)
        }
        $newSeen[$definition.Type] = $definition.Name
    }
    foreach ($id in $expectedReservation) {
        if (!$newSeen.ContainsKey($id)) { throw ('Missing Ominous Below type 0x{0:X4} in {1}' -f $id, $Description) }
    }
    return $seen.Count
}

$authoredDefinitions = @(Get-ObjectDefinitions ([System.IO.Path]::GetFullPath($XmlRoot)))
$baseCount = Test-OminousReservation $authoredDefinitions 'authored resources'

if ($IncludeCompiled) {
    $compiledDefinitions = @(Get-ObjectDefinitions ([System.IO.Path]::GetFullPath($CompiledXmlRoot)))
    Test-OminousReservation $compiledDefinitions 'compiled resources' | Out-Null
}

$scope = if ($IncludeCompiled) { 'authored and compiled resources' } else { 'authored resources' }
Write-Host ('PASS: {0} unique base object types; Ominous Below reservation F900-F921 is collision-free in {1}.' -f $baseCount, $scope)
