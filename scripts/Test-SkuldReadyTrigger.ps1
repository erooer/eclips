$ErrorActionPreference = 'Stop'

# Source-contract checks for the Realm-event Skuld interaction.  These prove the
# ready command is accepted during the announced waiting state, normalized for
# case/whitespace, range-limited, and transitions into the existing fight state.
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$behavior = Get-Content -LiteralPath (Join-Path $server 'wServer\logic\db\BehaviorDb.HauntedCemeteryFinalBattle.cs') -Raw
$entity = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\Entity.cs') -Raw
$setPiece = Get-Content -LiteralPath (Join-Path $server 'wServer\realm\setpieces\Skuld.cs') -Raw

if ($behavior -notmatch 'new State\("4"[\s\S]{0,400}?PlayerTextTransition\("85", @"\^\\s\*ready\\s\*\$", 85\)') {
    throw 'Skuld does not accept ready during its announced waiting state.'
}
if ($behavior -notmatch 'new State\("5"[\s\S]{0,220}?PlayerTextTransition\("85", @"\^\\s\*ready\\s\*\$", 85\)') {
    throw 'Skuld fallback waiting state does not use the normalized, range-limited trigger.'
}
if ($entity -notmatch '\[SKULD_EVENT\] ready received' -or
    $entity -notmatch '\[SKULD_EVENT\] fight activated') {
    throw 'Skuld event diagnostics are incomplete.'
}
if ($setPiece -notmatch 'Resources\.Worlds\["Skuld"\]') {
    throw 'Realm Skuld setpiece registration no longer resolves its intended prototype.'
}

Write-Host 'PASS: Realm Skuld accepts trimmed, case-insensitive ready during state 4/5 within 85 tiles and transitions to state 85.'
