$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$xmlRoot = Join-Path $root 'Cosmic-Realms-main\Server-src\common\resources\xmls'
$missing = @()

Get-ChildItem -LiteralPath $xmlRoot -Filter '*.dat' -File | ForEach-Object {
    $file = $_
    try {
        [xml]$document = Get-Content -LiteralPath $file.FullName -Raw
    }
    catch {
        throw "Invalid XML resource '$($file.FullName)': $($_.Exception.Message)"
    }

    # This directory also contains GroundTypes, EquipmentSets, Regions, and
    # Tutorial roots. DOM inspection is strict-mode safe and keeps the check on
    # direct Object/Class and Object/Description children used by XmlData.
    $documentRoot = $document.DocumentElement
    if ($null -ne $documentRoot -and $documentRoot.LocalName -eq 'Objects') {
        foreach ($object in $documentRoot.ChildNodes) {
            if ($object.NodeType -eq [System.Xml.XmlNodeType]::Element -and $object.LocalName -eq 'Object') {
                $classNode = @($object.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.LocalName -eq 'Class' } | Select-Object -First 1)
                if ($classNode.Count -eq 1 -and $classNode[0].InnerText -in @('Equipment', 'Dye')) {
                    $description = @($object.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.LocalName -eq 'Description' } | Select-Object -First 1)
                    if ($description.Count -eq 0) {
                        $missing += "$($file.Name): type $($object.GetAttribute('type')), id '$($object.GetAttribute('id'))'"
                    }
                }
            }
        }
    }
}

if ($missing.Count -gt 0) {
    throw "Item XML definitions require <Description> for the current Item parser:`n$($missing -join "`n")"
}

Write-Output 'PASS: every authored Equipment/Dye XML object has a Description.'
