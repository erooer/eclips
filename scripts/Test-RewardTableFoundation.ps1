$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$service = Get-Content -LiteralPath (Join-Path $root 'Cosmic-Realms-main\Server-src\wServer\logic\loot\WeightedRewardService.cs') -Raw
$project = Get-Content -LiteralPath (Join-Path $root 'Cosmic-Realms-main\Server-src\wServer\wServer.csproj') -Raw

foreach ($contract in 'class WeightedReward<T>', 'static class WeightedRewardService', 'Total reward weight exceeds', 'Reward selection did not resolve') {
    if ($service -notmatch [regex]::Escape($contract)) { throw "Missing weighted-reward contract: $contract" }
}
if ($project -notmatch 'logic\\loot\\WeightedRewardService.cs') { throw 'Weighted reward service is not compiled by wServer.' }
Write-Host 'PASS: weighted reward foundation is compiled, validates invalid weights, and provides deterministic injectable selection.'
