$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$xmlRoot = Join-Path $root 'Cosmic-Realms-main\Server-src\common\resources\xmls'
$missing = @()

Get-ChildItem -LiteralPath $xmlRoot -Filter '*.dat' -File | ForEach-Object {
    try {
        [xml]$document = Get-Content -LiteralPath $_.FullName -Raw
    }
    catch {
        throw "Invalid XML resource '$($_.FullName)': $($_.Exception.Message)"
    }

    # XmlData.AddObjects creates Item only for an Object whose direct Class is
    # Equipment or Dye. Nested <Equipment> slot arrays are not item definitions.
    foreach ($object in @($document.Objects.Object)) {
        if ([string]$object.Class -in @('Equipment', 'Dye')) {
            if ($null -eq $object.Description) {
                $missing += "$($_.Name): type $($object.type), id '$($object.id)'"
            }
        }
    }
}

if ($missing.Count -gt 0) {
    throw "Item XML definitions require <Description> for the current Item parser:`n$($missing -join "`n")"
}

Write-Output 'PASS: every authored Equipment/Dye XML object has a Description.'
