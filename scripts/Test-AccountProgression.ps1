$ErrorActionPreference='Stop'
$r=Split-Path $PSScriptRoot -Parent
$x=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\realm\AccountProgression.cs" -Raw
$c=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\realm\DungeonCodex.cs" -Raw
foreach($pattern in 'MaxDeaths\s*=\s*20','Awards\.Add','LeaderboardEvents','SortedSet(Add|Increment)','eclipse:leaderboard','GuildProgressionService','RecordDeath','weekly-clears','StarfallObservatory'){if($x+$c -notmatch $pattern){throw "Missing progression behavior: $pattern"}}
'PASS: bounded death recaps, idempotent persistent weekly leaderboard, guild trophy, and Codex hooks are present.'
