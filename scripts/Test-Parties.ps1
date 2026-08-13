$ErrorActionPreference='Stop'
$r=Split-Path $PSScriptRoot -Parent
$x=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\realm\Parties.cs" -Raw
$s=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\realm\DungeonSigils.cs" -Raw
foreach($pattern in 'const\s+int\s+Max\s*=\s*10','PartyRosterState','PartyInviteState','Reconstruct\(','CleanupInvite\(','player\.Reconnect\(world\)','Only the leader may') { if($x -notmatch $pattern){throw "Missing party lifecycle behavior: $pattern"} }
foreach($pattern in 'AnnounceSigilPortal','PlayerOpened\s*=\s*true','PartyService\.AnnounceSigilPortal','TrySpend\(account, "sigil_fragment"') { if($x+$s -notmatch $pattern){throw "Missing party Sigil behavior: $pattern"} }
if($x -match 'MaterialVaultService|ForgeV1Service|PotionStorage'){throw 'Forbidden party-system coupling'}
'PASS: persisted roster/invite reconstruction, reconnect-backed joining, and single-portal party Sigil markers are wired.'
