[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Position = 1)]
    [ValidateRange(0, 999)]
    [int]$Rank = 60
)

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$redisCli = Join-Path $base 'Cosmic-Realms-main\Server-src\Redis-x64-3.2.100\redis-cli.exe'
$backupScript = Join-Path $PSScriptRoot 'Backup-Redis.ps1'
$db = 15

if (-not (Test-Path -LiteralPath $redisCli)) { throw "Redis CLI was not found: $redisCli" }
if ((& $redisCli -h 127.0.0.1 -p 6379 -n $db PING) -ne 'PONG') { throw 'Redis is not reachable on 127.0.0.1:6379 (database 15).' }

Write-Host 'Source-defined rank reference:'
Write-Host '  0   none / Normal Player'
Write-Host ' 10   donor / Patron T2'
Write-Host ' 20   Patron T3'
Write-Host ' 60   Administrator threshold (sets admin=true)'
Write-Host ' 70   Former Staff'
Write-Host ' 80   GM'
Write-Host ' 90   Dev'
Write-Host '100   Owner'
Write-Host 'The rebuilt source has no Supporter or Moderator role constants; other numeric ranks are accepted by its /rank command.'

$selector = $Account.Trim()
$id = $null

# Email/UUID lookup: the login JSON is read only to obtain AccountId and is never emitted.
$login = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET logins $selector.ToUpperInvariant()
if ($login -match '"AccountId"\s*:\s*(\d+)') { $id = [int]$matches[1] }

# Character-name lookup uses the source-maintained names hash.
if ($null -eq $id) {
    $nameId = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET names $selector.ToUpperInvariant()
    if ($nameId -match '^\d+$') { $id = [int]$nameId }
}

# Guest and unchosen-name accounts are not necessarily in the names hash; match only non-sensitive account fields.
if ($null -eq $id) {
    $candidates = @()
    foreach ($key in @(& $redisCli -h 127.0.0.1 -p 6379 -n $db --scan --pattern 'account.*')) {
        $uuid = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET $key uuid
        $name = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET $key name
        if ($uuid -ieq $selector -or $name -ieq $selector) { $candidates += $key.Substring('account.'.Length) }
    }
    if ($candidates.Count -gt 1) { throw "The selector '$Account' matches multiple accounts. Use the login email/UUID." }
    if ($candidates.Count -eq 1) { $id = [int]$candidates[0] }
}

if ($null -eq $id) { throw "No account matched '$Account' in Redis database 15. No data was changed." }
$key = "account.$id"
if ((& $redisCli -h 127.0.0.1 -p 6379 -n $db EXISTS $key) -ne '1') { throw "Resolved account $id has no account hash. No data was changed." }

$uuid = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET $key uuid
$name = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET $key name
$beforeRank = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET $key rank
$beforeAdminByte = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw EVAL "local v=redis.call('HGET',KEYS[1],'admin'); return v and string.byte(v,1) or -1" 1 $key
$charCount = @(& $redisCli -h 127.0.0.1 -p 6379 -n $db --scan --pattern "char.$id.*").Count
$vaultExists = & $redisCli -h 127.0.0.1 -p 6379 -n $db EXISTS "vault.$id"

Write-Host "Resolved account: id=$id, uuid=$uuid, name=$name"
Write-Host "Current rank=$beforeRank; adminByte=$beforeAdminByte; characters=$charCount; vaultExists=$vaultExists"
Write-Host "Requested rank=$Rank; resulting admin=$($Rank -ge 60)"

if (-not $PSCmdlet.ShouldProcess("$key (account '$uuid')", "set rank to $Rank and admin to $($Rank -ge 60)")) { return }

# This backup is a Redis SAVE plus a copy of the RDB/AOF/configuration. It preserves the complete account entry without displaying credentials or serialized fields.
& $backupScript | Out-Host

# Match RedisObject.SetValue exactly: rank is UTF-8 decimal text; admin is one binary byte (0x01 or 0x00).
$adminByte = if ($Rank -ge 60) { 1 } else { 0 }
$lua = "redis.call('HSET', KEYS[1], 'rank', ARGV[1]); redis.call('HSET', KEYS[1], 'admin', string.char(tonumber(ARGV[2]))); return 1"
$write = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw EVAL $lua 1 $key $Rank $adminByte
if ($write -ne '1') { throw 'Redis did not acknowledge the rank update.' }
& $redisCli -h 127.0.0.1 -p 6379 -n $db SAVE | Out-Null

$afterRank = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw HGET $key rank
$afterAdminByte = & $redisCli -h 127.0.0.1 -p 6379 -n $db --raw EVAL "local v=redis.call('HGET',KEYS[1],'admin'); return v and string.byte(v,1) or -1" 1 $key
$afterCharCount = @(& $redisCli -h 127.0.0.1 -p 6379 -n $db --scan --pattern "char.$id.*").Count
$afterVaultExists = & $redisCli -h 127.0.0.1 -p 6379 -n $db EXISTS "vault.$id"

if ($afterRank -ne "$Rank" -or $afterAdminByte -ne "$adminByte") { throw 'Post-write verification failed.' }
if ($charCount -ne $afterCharCount -or $vaultExists -ne $afterVaultExists) { throw 'Character or vault key inventory changed; investigate before logging in.' }
Write-Host "Success: account.$id now has rank=$afterRank and adminByte=$afterAdminByte. Character/vault key inventory is unchanged."
