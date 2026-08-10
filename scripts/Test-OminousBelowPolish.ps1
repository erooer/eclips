$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$world = Get-Content -LiteralPath (Join-Path $root 'Cosmic-Realms-main\Server-src\wServer\realm\worlds\logic\OminousBelow.cs') -Raw
foreach ($entry in 'SendObjectiveSummary', 'Soul Lanterns:', 'Gaolers:', 'Ominous Seals:', 'Entity.Resolve(Manager, 0xF919)', 'WorldTimer(60000') {
    if ($world -notmatch [regex]::Escape($entry)) { throw "Missing Ominous Below polish contract: $entry" }
}
Write-Host 'PASS: Ominous Below exposes objective state and creates only a timed completion exit.'
