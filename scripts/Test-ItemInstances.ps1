$ErrorActionPreference='Stop'
$r=Split-Path $PSScriptRoot -Parent
$db=Get-Content "$r\Cosmic-Realms-main\Server-src\common\DbModels.cs" -Raw
$swap=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\networking\handlers\InvSwapHandler.cs" -Raw
$drop=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\networking\handlers\InvDropHandler.cs" -Raw
$trade=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\networking\handlers\AcceptTradeHandler.cs" -Raw
$service=Get-Content "$r\Cosmic-Realms-main\Server-src\wServer\realm\ItemInstanceTransferService.cs" -Raw
foreach($pattern in 'ItemInstanceRecord','ReconcileInstances','Duplicate item instance ID rejected','SetItemInstances','ushort\[\] Items'){if($db -notmatch $pattern){throw "Missing ledger behavior: $pattern"}}
foreach($pair in @(@($swap,'ItemInstanceTransferService\.Swap'),@($drop,'ItemInstanceTransferService\.Swap'),@($trade,'ItemInstanceTransferService\.ApplyTransactions'),@($service,'RuntimeItemInstances'),@($service,'Distinct\(\).*Count'))){if($pair[0] -notmatch $pair[1]){throw "Missing handler adoption: $($pair[1])"}}
'PASS: legacy migration plus swap, drop/pickup, and trade instance-transfer hooks are present.'
