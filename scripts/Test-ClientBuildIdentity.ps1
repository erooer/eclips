[CmdletBinding()]
param(
    [string]$ClientSwfPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\client-unchanged.swf'),
    [string]$ExpectedSourceCommit
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) {
    $ExpectedSourceCommit = (& git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve expected client source commit.' }
}
if ($ExpectedSourceCommit -notmatch '^[0-9a-fA-F]{40}$') { throw "Invalid expected client source commit: $ExpectedSourceCommit" }
if (!(Test-Path -LiteralPath $ClientSwfPath -PathType Leaf)) { throw "Missing compiled client SWF: $ClientSwfPath" }

$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ClientSwfPath).Path)
$signature = [Text.Encoding]::ASCII.GetString($bytes, 0, 3)
if ($signature -eq 'FWS') {
    $body = New-Object byte[] ($bytes.Length - 8)
    [Array]::Copy($bytes, 8, $body, 0, $body.Length)
} elseif ($signature -eq 'CWS') {
    $input = New-Object IO.MemoryStream
    $input.Write($bytes, 8, $bytes.Length - 8)
    $input.Position = 2
    $inflater = New-Object IO.Compression.DeflateStream($input, [IO.Compression.CompressionMode]::Decompress, $true)
    $expanded = New-Object IO.MemoryStream
    try { $inflater.CopyTo($expanded); $body = $expanded.ToArray() }
    finally { $inflater.Dispose(); $expanded.Dispose(); $input.Dispose() }
} else { throw "Unsupported SWF signature: $signature" }

$compiledText = [Text.Encoding]::UTF8.GetString($body)
$expected = $ExpectedSourceCommit.ToLowerInvariant()
$short = $expected.Substring(0, 12)
if (!$compiledText.Contains($expected)) { throw "Compiled SWF does not contain its expected source commit $expected." }
if (!$compiledText.Contains("Eclipse client $short")) { throw "Compiled SWF does not expose the expected runtime build label Eclipse client $short." }

$webMain = Get-Content -LiteralPath (Join-Path $root 'Cosmic-Realms-main\Client-src\src\WebMain.as') -Raw
foreach ($required in @('ECLIPSE_CLIENT_BUILD', 'ContextMenuItem(ClientBuildInfo.LABEL', 'publishClientBuildIdentity')) {
    if (!$webMain.Contains($required)) { throw "Production client build identity is not observable at runtime: $required" }
}

$hash = (Get-FileHash -LiteralPath $ClientSwfPath -Algorithm SHA256).Hash
Write-Host "PASS: exact compiled SWF $hash exposes runtime label 'Eclipse client $short' bound to source $expected."
