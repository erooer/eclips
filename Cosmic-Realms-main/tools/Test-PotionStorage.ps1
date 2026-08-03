param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'Server-src\wServer\networking\handlers\PotionStorageConsumption.cs'
Add-Type -TypeDefinition (Get-Content -Raw -LiteralPath $source) -Language CSharp

function Assert-Equal([string]$name, $actual, $expected) {
    if ($actual -ne $expected) { throw "${name}: expected $expected, got $actual" }
}

function Assert-Scenario([string]$name, [int]$current, [int]$cap, [int]$available, [int]$perPotion, [bool]$max, [int]$expectedConsumed, [int]$expectedPoints, [bool]$expectedMaxed = $false) {
    $result = [wServer.networking.handlers.PotionStorageConsumption]::Resolve($current, $cap, $available, $perPotion, $max)
    Assert-Equal "$name consumed" $result.PotionsConsumed $expectedConsumed
    Assert-Equal "$name points" $result.StatPointsApplied $expectedPoints
    Assert-Equal "$name already-maxed" $result.AlreadyMaxed $expectedMaxed
}

# Full, partial, empty, already-maxed, multi-point, excess-storage, and repeated-request cases.
Assert-Scenario 'full max'       35  70 40 1 $true  35 35
Assert-Scenario 'partial max'    35  70 20 1 $true  20 20
Assert-Scenario 'zero storage'   35  70  0 1 $true   0  0
Assert-Scenario 'already maxed'  70  70 20 1 $true   0  0 $true
Assert-Scenario 'life five point' 95 120 9 5 $true   5 25
Assert-Scenario 'life overflow' 118 120 9 5 $true   1  2
Assert-Scenario 'excess storage' 35  70 99 1 $true  35 35

# The second rapid request sees the persisted first result: it cannot consume again.
$first = [wServer.networking.handlers.PotionStorageConsumption]::Resolve(35, 70, 35, 1, $true)
$second = [wServer.networking.handlers.PotionStorageConsumption]::Resolve(35 + $first.StatPointsApplied, 70, 35 - $first.PotionsConsumed, 1, $true)
Assert-Equal 'rapid first consumed' $first.PotionsConsumed 35
Assert-Equal 'rapid second consumed' $second.PotionsConsumed 0

Write-Output 'Potion Storage consumption regression tests passed (8 scenarios).'
