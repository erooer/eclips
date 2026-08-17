$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Test-TypeIdCollisions.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "eclipse-type-collision-$([guid]::NewGuid().ToString('N'))"
$authored = Join-Path $testRoot 'authored'
$compiled = Join-Path $testRoot 'compiled'

function Write-TestResources([string]$Destination, [string]$FirstOminousType = '0xF900') {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Destination 'EmbeddedData_BaseCXML.dat'), '<Objects><Object type="0x1000" id="Existing Object" /></Objects>', [Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $Destination 'EmbeddedData_GroundCXML.dat'), '<GroundTypes><Ground type="0xF900" id="Unrelated Ground" /></GroundTypes>', [Text.UTF8Encoding]::new($false))
    $objects = for ($id = 0xF900; $id -le 0xF921; $id++) {
        $type = if ($id -eq 0xF900) { $FirstOminousType } else { '0x{0:X4}' -f $id }
        '<Object type="{0}" id="Ominous {1:X4}" />' -f $type, $id
    }
    [System.IO.File]::WriteAllText((Join-Path $Destination 'EmbeddedData_OminousBelowCXML.dat'), "<Objects>$($objects -join '')</Objects>", [Text.UTF8Encoding]::new($false))
}

try {
    Write-TestResources $authored
    Write-TestResources $compiled
    & { Set-StrictMode -Version Latest; & $validator -XmlRoot $authored -IncludeCompiled -CompiledXmlRoot $compiled }

    Write-TestResources $authored '0x1000'
    try {
        & { Set-StrictMode -Version Latest; & $validator -XmlRoot $authored }
        throw 'The collision fixture unexpectedly passed.'
    } catch {
        if ($_.Exception.Message -notmatch 'collides with Existing Object') { throw }
    }

    Write-TestResources $authored
    Write-TestResources $compiled '0x1000'
    try {
        & { Set-StrictMode -Version Latest; & $validator -XmlRoot $authored -IncludeCompiled -CompiledXmlRoot $compiled }
        throw 'The compiled collision fixture unexpectedly passed.'
    } catch {
        if ($_.Exception.Message -notmatch 'collides with Existing Object in compiled resources') { throw }
    }
    Write-Host 'PASS: strict-mode XML shapes and authored/compiled Ominous collision validation verified.'
} finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (!$resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing unsafe test cleanup path: $resolvedTestRoot" }
    if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
