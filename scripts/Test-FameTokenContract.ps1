param(
    [string]$ClientSwfPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\client-unchanged.swf'),
    [string]$ServerResourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Cosmic-Realms-main\Server-src\bin\resources\xmls\EmbeddedData_CustomObjectsCXML.dat')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $root 'Cosmic-Realms-main'

function Require([bool]$condition, [string]$message) {
    if (!$condition) { throw $message }
}

function Get-CompiledXmlPayloads([string]$swfPath) {
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $swfPath).Path)
    Require ($bytes.Length -gt 12) 'Compiled client SWF is truncated.'
    $signature = [Text.Encoding]::ASCII.GetString($bytes, 0, 3)
    if ($signature -eq 'FWS') {
        $body = New-Object byte[] ($bytes.Length - 8)
        [Array]::Copy($bytes, 8, $body, 0, $body.Length)
    } elseif ($signature -eq 'CWS') {
        $compressed = New-Object IO.MemoryStream
        $compressed.Write($bytes, 8, $bytes.Length - 8)
        $compressed.Position = 2 # skip the zlib header; DeflateStream consumes raw DEFLATE
        $inflater = New-Object IO.Compression.DeflateStream($compressed, [IO.Compression.CompressionMode]::Decompress, $true)
        $expanded = New-Object IO.MemoryStream
        try { $inflater.CopyTo($expanded); $body = $expanded.ToArray() }
        finally { $inflater.Dispose(); $expanded.Dispose(); $compressed.Dispose() }
    } else {
        throw "Unsupported compiled client SWF signature: $signature"
    }

    $nbits = $body[0] -shr 3
    $position = [int][Math]::Ceiling((5 + 4 * $nbits) / 8.0) + 4 # RECT + frame rate/count
    $payloads = New-Object 'System.Collections.Generic.List[string]'
    while ($position + 2 -le $body.Length) {
        # Cast before shifting: Windows PowerShell otherwise keeps the byte
        # operand narrow and discards the high-order tag-header byte.
        $header = [int]$body[$position] -bor ([int]$body[$position + 1] -shl 8)
        $position += 2
        $tag = $header -shr 6
        $length = $header -band 0x3F
        if ($length -eq 0x3F) {
            Require ($position + 4 -le $body.Length) 'Compiled client SWF has a truncated long tag header.'
            $length = [BitConverter]::ToUInt32($body, $position)
            $position += 4
        }
        Require ($position + $length -le $body.Length) 'Compiled client SWF has a truncated tag payload.'
        if ($tag -eq 87 -and $length -gt 6) { # DefineBinaryData: UI16 id + UI32 reserved + bytes
            $text = [Text.Encoding]::UTF8.GetString($body, $position + 6, $length - 6).Trim([char]0)
            if ($text -match '<Objects|<GroundTypes') { $payloads.Add($text) }
        }
        $position += $length
        if ($tag -eq 0) { break }
    }
    return $payloads
}

function Assert-FameToken([xml]$xml, [string]$origin) {
    $tokens = @($xml.Objects.Object | Where-Object id -eq '100K Fame Token')
    Require ($tokens.Count -eq 1) "$origin must contain exactly one 100K Fame Token definition."
    $token = $tokens[0]
    Require ([string]$token.type -match '^(?i:0x0*F971)$') "$origin Fame Token must use type 0xF971."
    Require ($token.Class -eq 'Equipment' -and $token.Item -ne $null -and [int]$token.SlotType -eq 10) "$origin Fame Token is not standard slot-10 Equipment."
    Require ($token.Consumable -ne $null -and $token.Potion -ne $null -and $token.Sound -eq 'use_potion') "$origin Fame Token is not a usable Potion consumable."
    Require ($token.Texture.File -eq 'lofiObj3' -and [int]$token.Texture.Index -eq 0xE0) "$origin Fame Token does not use the known-good compiled-server 5000 Fame consumable/Fame UI texture."
    Require ($token.Activate.'#text' -eq 'Fame' -and [int]$token.Activate.amount -eq 100000) "$origin Fame Token does not grant exactly 100,000 Fame."
    return $token
}

$payloads = Get-CompiledXmlPayloads $ClientSwfPath
$tokenPayloads = @($payloads | Where-Object { [string]$_ -match '100K Fame Token' })
Write-Host "Compiled XML payloads=$(@($payloads).Count), Fame-token payloads=$($tokenPayloads.Count)."
Require ($tokenPayloads.Count -eq 1) 'Compiled client SWF must contain exactly one XML payload defining 100K Fame Token.'
[xml]$compiledClientXml = $tokenPayloads[0]
$clientToken = Assert-FameToken $compiledClientXml 'Compiled client SWF'

[xml]$compiledServerXml = Get-Content -LiteralPath $ServerResourcePath -Raw
$serverToken = Assert-FameToken $compiledServerXml 'Compiled server resource'
Require ([string]$clientToken.type -eq [string]$serverToken.type -and [string]$clientToken.id -eq [string]$serverToken.id) 'Compiled client/server Fame Token identity differs.'

$compiledOwners = New-Object 'System.Collections.Generic.List[string]'
$compiledXmlRoot = Split-Path -Parent $ServerResourcePath
foreach ($file in Get-ChildItem -LiteralPath $compiledXmlRoot -Filter '*.dat') {
    try { [xml]$resource = Get-Content -LiteralPath $file.FullName -Raw } catch { continue }
    foreach ($object in @($resource.Objects.Object)) {
        if ([string]$object.type -match '^(?i:0x0*F971)$') { $compiledOwners.Add([string]$object.id) }
    }
}
Require ($compiledOwners.Count -eq 1 -and $compiledOwners[0] -eq '100K Fame Token') 'Type 0xF971 collides in compiled server resources.'

$serverBin = Split-Path (Split-Path (Split-Path $ServerResourcePath -Parent) -Parent) -Parent
$commonAssembly = Join-Path $serverBin 'common.dll'
$logAssembly = Join-Path $serverBin 'log4net.dll'
Require (Test-Path -LiteralPath $commonAssembly) 'Compiled common.dll is required for the /give descriptor integration test.'
if (Test-Path -LiteralPath $logAssembly) { [void][Reflection.Assembly]::LoadFrom($logAssembly) }
[void][Reflection.Assembly]::LoadFrom($commonAssembly)
$gameData = New-Object common.resources.XmlData($compiledXmlRoot)
try {
    $arguments = [object[]]@('100K Fame Token', $null)
    $resolved = $gameData.GetType().GetMethod('TryResolveItem').Invoke($gameData, $arguments)
    Require $resolved 'The compiled GameData resolver used by /give rejected 100K Fame Token.'
    $resolvedItem = $arguments[1]
    Require ($null -ne $resolvedItem) 'The compiled /give resolver returned no Item descriptor.'
    Require ($resolvedItem.ObjectType -eq 0xF971 -and $resolvedItem.ObjectId -eq '100K Fame Token') 'The compiled /give resolver returned the wrong item identity.'
    Require ($resolvedItem.Class -eq 'Equipment' -and $resolvedItem.SlotType -eq 10 -and $resolvedItem.Consumable -and $resolvedItem.Potion) 'The compiled inventory descriptor is not a usable slot-10 consumable potion.'
    $fameEffects = @($resolvedItem.ActivateEffects | Where-Object { $_.Effect.ToString() -eq 'Fame' })
    Require ($fameEffects.Count -eq 1 -and $fameEffects[0].Amount -eq 100000) 'The compiled UseItem descriptor does not resolve exactly one +100,000 Fame activation.'
    $caseArguments = [object[]]@('100k fame token', $null)
    $caseResolved = $gameData.GetType().GetMethod('TryResolveItem').Invoke($gameData, $caseArguments)
    Require ($caseResolved -and $caseArguments[1].ObjectType -eq 0xF971) 'The shared /give resolver regressed case-insensitive item commands.'
} finally {
    if ($null -ne $gameData) { $gameData.Dispose() }
}

$giveSource = Get-Content -LiteralPath (Join-Path $sourceRoot 'Server-src\wServer\realm\commands\RankedCommands.cs') -Raw
Require ($giveSource -match 'gameData\.TryResolveItem\(args,\s*out item\)') '/give does not call the compiled GameData item resolver exercised above.'
$useItemSource = Get-Content -LiteralPath (Join-Path $sourceRoot 'Server-src\wServer\realm\entities\player\Player.UseItem.cs') -Raw
Require ($useItemSource -match 'case\s+ActivateEffects\.Fame:\s*AEAddFame' -and
    $useItemSource -match 'acc\.Fame\s*\+=\s*eff\.Amount' -and
    $useItemSource -match 'acc\.FlushAsync\(\)\.Wait\(\)') 'The real UseItem Fame activation is not synchronously persisted.'

Write-Host "PASS: compiled /give GameData resolution returns unique type 0xF971 and the exact inventory/UseItem descriptor; compiled client/server resources agree on Equipment, Potion, slot 10, Fame 100000, lofiObj3:0xE0, and use_potion. SWF SHA-256=$((Get-FileHash -LiteralPath $ClientSwfPath -Algorithm SHA256).Hash)"
