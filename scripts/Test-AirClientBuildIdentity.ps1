[CmdletBinding()]
param(
    [string]$AirSwfPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\air\CosmicRealmsAir.swf'),
    [string]$DesktopSwfPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\air\CosmicRealms-Desktop\CosmicRealmsAir.swf'),
    [string]$ExpectedSourceCommit
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) {
    $ExpectedSourceCommit = (& git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve expected AIR client source commit.' }
}
& (Join-Path $PSScriptRoot 'Test-ClientBuildIdentity.ps1') -ClientSwfPath $AirSwfPath -ExpectedSourceCommit $ExpectedSourceCommit

$airHash = (Get-FileHash -LiteralPath $AirSwfPath -Algorithm SHA256).Hash
$desktopHash = (Get-FileHash -LiteralPath $DesktopSwfPath -Algorithm SHA256).Hash
if ($airHash -ne $desktopHash) { throw 'Packaged AIR desktop client contains a stale SWF.' }

$airMain = Get-Content -LiteralPath (Join-Path $root 'Cosmic-Realms-main\Client-src\src\AirMain.as') -Raw
foreach ($required in @('stage.nativeWindow.title="Cosmic Realms - "+ClientBuildInfo.SHORT_SOURCE', '[ECLIPSE_CLIENT_BUILD]', 'AIR window title=')) {
    if (!$airMain.Contains($required)) { throw "AIR startup does not expose its compiled build identity: $required" }
}

$short = $ExpectedSourceCommit.Substring(0, 12).ToLowerInvariant()
Write-Host "PASS: AIR and packaged desktop SWFs are byte-identical ($airHash) and set the native title to 'Cosmic Realms - $short'."
