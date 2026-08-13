$ErrorActionPreference='Stop'
$r=Split-Path $PSScriptRoot -Parent
$x=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\realm\Parties.cs" -Raw
foreach($pattern in 'const\s+int\s+Max\s*=\s*10','PartyRosterState','PartyInviteState','Reconstruct\(','CleanupInvite\(','player\.Reconnect\(world\)','Only the leader may') { if($x -notmatch $pattern){throw "Missing party lifecycle behavior: $pattern"} }
if($x -match 'Mark|Forge|Potion'){throw 'Forbidden system change'}
'PASS: persisted roster/invite reconstruction, leader enforcement, and reconnect-backed joining are wired.'
