$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$server = Join-Path $root 'Cosmic-Realms-main\Server-src'
$xml = Get-Content (Join-Path $server 'common\resources\xmls\EmbeddedData_EclipseCitadelCXML.dat') -Raw
$world = Get-Content (Join-Path $server 'wServer\realm\worlds\logic\EclipseCitadel.cs') -Raw
$behavior = Get-Content (Join-Path $server 'wServer\logic\db\BehaviorDb.EclipseCitadel.cs') -Raw
$access = Get-Content (Join-Path $server 'wServer\realm\EclipseCitadelAccess.cs') -Raw
$codex = Get-Content (Join-Path $server 'wServer\realm\DungeonCodex.cs') -Raw
$map = Get-Content (Join-Path $server 'common\resources\worlds\EclipseCitadel.jm') -Raw | ConvertFrom-Json

if ($map.width -ne 31 -or $map.height -ne 31 -or [string]::IsNullOrWhiteSpace($map.data)) { throw 'Citadel map is not a populated bespoke 31x31 resource.' }
foreach ($type in 0xF960..0xF96F) { if ($xml -notmatch ('type="0x{0:X}"' -f $type)) { throw ('Missing Citadel type 0x{0:X4}' -f $type) } }
foreach ($name in 'The Hollow Regent','The Zenith Warden','The Umbra Enginekeeper','The Crowned Eclipse','Citadel Mark','Crownrender','Eclipse Aegis','Zenithal Ring','Lightless Staff') { if ($xml -notmatch [regex]::Escape($name)) { throw "Missing Citadel XML object: $name" } }
foreach ($state in 'Lightless Court','Broken Zenith','Umbra Engine','Crown Ascendant','Eclipse Guard','Light and Umbra','Broken Crown') { if (($world + $behavior) -notmatch [regex]::Escape($state)) { throw "Missing Citadel progression/phase: $state" } }
if ($world -notmatch 'The Crowned Eclipse' -or $world -notmatch '0xF96E' -or $world -notmatch '0xF96F' -or $world -notmatch 'Rand.NextDouble\(\) < 0.12') { throw 'Final spawn, bounded completion chest reward, or exit is not runtime-wired.' }
if ($xml -notmatch '<Activate>LegendaryMarks</Activate>' -or $xml -match 'Forge|imprint_shard') { throw 'Citadel Mark is not isolated consumable LegendaryMarks progress.' }
if ($access -notmatch 'WorldInstanceSet' -or $access -notmatch 'TrySpend\(account, "citadel_fragment"' -or $access -notmatch 'Pending.TryAdd') { throw 'Citadel fragment access is not readiness-gated and idempotent.' }
if ($codex -notmatch '"EclipseCitadel"' -or $codex -notmatch 'EclipseCitadel') { throw 'Citadel Codex and timing integration missing.' }
if ((Get-Content (Join-Path $server 'wServer\realm\EclipseImprints.cs') -Raw) -notmatch '0xF96B') { throw 'At least one Citadel item is not explicitly Imprint-eligible.' }
'PASS: Eclipse Citadel map, portal access, three wings, Crowned Eclipse phases, mark/chest/reward wiring, Codex timing, and Imprint eligibility are present.'
