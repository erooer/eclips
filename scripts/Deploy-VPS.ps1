[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$SkipPull,
    [switch]$NoRestart,
    # Optional only for isolated dry-run validation. Production defaults are fixed below.
    [string]$GitRootPath = 'C:\Eclipse-Git\eclips',
    [string]$LiveRootPath = 'C:\Eclipse\rebuild-original\rebuild-original',
    [string]$DeploymentLogRoot = 'C:\Eclipse\deployment-logs'
)

# Eclipse VPS deployment. Run this script on the VPS from an elevated PowerShell.
# It deliberately updates the live Server-src\bin source used by Start-All.ps1;
# editing runtime alone would be overwritten on the next startup.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GitRoot = $GitRootPath
$LiveRoot = $LiveRootPath
$LiveProject = Join-Path $LiveRoot 'Cosmic-Realms-main'
$GitProject = Join-Path $GitRoot 'Cosmic-Realms-main'
$LiveRuntime = Join-Path $LiveRoot 'runtime'
$LiveClientSwf = Join-Path $LiveRoot 'build\client-unchanged.swf'
$LiveServerBin = Join-Path $LiveProject 'Server-src\bin'
$DeploymentLogs = $DeploymentLogRoot
$RedisHelpers = Join-Path $PSScriptRoot 'Redis-Helpers.ps1'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupRoot = Join-Path $LiveRoot "deployment-backups\$Timestamp"
$CopiedFiles = [System.Collections.Generic.List[string]]::new()
$BackupCreated = $false
$ServicesStopped = $false
$TranscriptStarted = $false
$DeploymentPhase = 'initialization'
$ArtifactRoot = $GitRoot
$SourceClientSwf = $null
$SourceServerBin = $null
$GeneratedCheckoutChanges = @()
$DeploymentArtifactPaths = @()
Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step([string]$Message) {
    Write-Host "[$(Get-Date -Format 's')] $Message"
}

function Assert-Path([string]$Path, [string]$Description) {
    if (!(Test-Path -LiteralPath $Path)) {
        throw "Missing ${Description}: $Path"
    }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Copy-VerifiedFile([string]$Source, [string]$Destination) {
    Assert-Path $Source 'deployment source file'
    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    $sourceHash = Get-Sha256 $Source
    $destinationHash = Get-Sha256 $Destination
    if ($sourceHash -ne $destinationHash) {
        throw "Hash mismatch after copy: $Source -> $Destination"
    }
    $script:CopiedFiles.Add($Destination)
    Write-Step "COPIED $Source -> $Destination [$sourceHash]"
}

function Copy-VerifiedDirectory([string]$SourceDirectory, [string]$DestinationDirectory) {
    Assert-Path $SourceDirectory 'deployment source directory'
    Get-ChildItem -LiteralPath $SourceDirectory -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($SourceDirectory.Length).TrimStart('\')
        Copy-VerifiedFile $_.FullName (Join-Path $DestinationDirectory $relative)
    }
}

function Test-CheckedInArtifacts([string]$ExpectedHead) {
    $verified = Test-DeploymentManifest -RepositoryRoot $GitRoot -ExpectedHead $ExpectedHead -RequireArtifactBundleCommit
    $script:DeploymentArtifactPaths = @($verified.ArtifactPaths)
    $script:SourceClientSwf = Join-Path $GitRoot 'build\client-unchanged.swf'
    $script:SourceServerBin = Join-Path $GitRoot 'Cosmic-Realms-main\Server-src\bin'
    & (Join-Path $GitRoot 'scripts\Test-ClientHandshakeProtocol.ps1') -WorldServerPath (Join-Path $script:SourceServerBin 'wServer.exe')
    & (Join-Path $GitRoot 'scripts\Test-TypeIdCollisions.ps1') -IncludeCompiled -CompiledXmlRoot (Join-Path $script:SourceServerBin 'resources\xmls')
    Write-Step "VERIFIED artifact bundle HEAD=$ExpectedHead sourceCommit=$($verified.SourceCommit) artifacts=$($verified.ArtifactPaths.Count)."
}

function Sync-ManifestServerArtifacts {
    $binPrefix = 'Cosmic-Realms-main/Server-src/bin/'
    $binArtifacts = @($script:DeploymentArtifactPaths | Where-Object { $_.StartsWith($binPrefix, [StringComparison]::OrdinalIgnoreCase) })
    $desired = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $binArtifacts) {
        $destinationRelative = $relative.Substring($binPrefix.Length).Replace('/', '\')
        [void]$desired.Add([System.IO.Path]::GetFullPath((Join-Path $LiveServerBin $destinationRelative)))
    }

    $managedExisting = @()
    if (Test-Path -LiteralPath $LiveServerBin) {
        $managedExisting += @(Get-ChildItem -LiteralPath $LiveServerBin -File | Where-Object { $_.Name -in @('server.exe', 'wServer.exe') -or $_.Extension -in @('.dll', '.pdb') })
        $liveResources = Join-Path $LiveServerBin 'resources'
        if (Test-Path -LiteralPath $liveResources) { $managedExisting += @(Get-ChildItem -LiteralPath $liveResources -File -Recurse) }
    }
    foreach ($file in $managedExisting) {
        if (!$desired.Contains([System.IO.Path]::GetFullPath($file.FullName))) {
            Remove-Item -LiteralPath $file.FullName -Force
            Write-Step "REMOVED stale deployment artifact $($file.FullName)"
        }
    }

    foreach ($relative in $binArtifacts) {
        $destinationRelative = $relative.Substring($binPrefix.Length).Replace('/', '\')
        Copy-VerifiedFile (Join-Path $GitRoot $relative.Replace('/', '\')) (Join-Path $LiveServerBin $destinationRelative)
    }

    $desiredRuntimeNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $binArtifacts | Where-Object { $_ -notmatch '/resources/' }) {
        [void]$desiredRuntimeNames.Add((Split-Path -Leaf $relative))
    }
    Get-ChildItem -LiteralPath $LiveRuntime -File | Where-Object {
        ($_.Name -in @('server.exe', 'wServer.exe') -or $_.Extension -in @('.dll', '.pdb')) -and !$desiredRuntimeNames.Contains($_.Name)
    } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
        Write-Step "REMOVED stale runtime artifact $($_.FullName)"
    }
}

function Get-GeneratedCheckoutChanges([string[]]$StatusLines) {
    $generated = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $StatusLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -lt 4) { throw "Unrecognized Git status entry: $line" }
        $state = $line.Substring(0, 2)
        $path = $line.Substring(3).Trim('"').Replace('\', '/')
        # Never discard staged changes or untracked files, even under a generated
        # directory. Only old build output modifications are migration-safe.
        if ($state[0] -ne ' ' -or $state -eq '??') { throw "Refusing to deploy with staged/untracked change: $line" }
        $isGenerated =
            $path.StartsWith('Cosmic-Realms-main/Server-src/bin/', [StringComparison]::OrdinalIgnoreCase) -or
            $path.StartsWith('docs/reports/', [StringComparison]::OrdinalIgnoreCase) -or
            $path.StartsWith('runtime/resources/', [StringComparison]::OrdinalIgnoreCase) -or
            $path -match '^runtime/(server|wServer)\.exe$' -or
            $path -match '^runtime/[^/]+\.(dll|pdb)$' -or
            $path -eq 'build/client-unchanged.swf'
        if (!$isGenerated) { throw "Refusing to deploy with non-generated local change: $line" }
        $generated.Add($path)
    }
    return @($generated | Select-Object -Unique)
}

function Clear-GeneratedCheckoutChanges {
    if ($script:GeneratedCheckoutChanges.Count -eq 0) { return }
    Write-Step "Removing $($script:GeneratedCheckoutChanges.Count) tracked generated-output changes left by the legacy in-place build."
    & git -C $GitRoot restore --worktree -- $script:GeneratedCheckoutChanges
    if ($LASTEXITCODE -ne 0) { throw "git restore of generated outputs failed with exit code $LASTEXITCODE" }
    if (& git -C $GitRoot status --porcelain) { throw 'Git checkout is still dirty after generated-output cleanup.' }
}

function Get-EclipseProcesses {
    $names = @('server.exe', 'wServer.exe', 'redis-server.exe')
    Get-CimInstance Win32_Process | Where-Object {
        $names -contains $_.Name -and $_.ExecutablePath -and $_.ExecutablePath.StartsWith($LiveRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Stop-EclipseServices {
    Write-Step 'Stopping the live Eclipse stack.'
    & (Join-Path $LiveRoot 'scripts\Stop-All.ps1')
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $remaining = @(Get-EclipseProcesses)
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    $remaining = @(Get-EclipseProcesses)
    foreach ($process in $remaining) {
        # ExecutablePath was checked against $LiveRoot above. Never kill same-named processes elsewhere.
        Write-Step "Stopping remaining Eclipse process PID=$($process.ProcessId) path=$($process.ExecutablePath)"
        Stop-Process -Id $process.ProcessId -Force
    }
    Start-Sleep -Seconds 2
    $remaining = @(Get-EclipseProcesses)
    if ($remaining.Count -ne 0) {
        throw "Eclipse processes remained after stop: $($remaining | ForEach-Object { $_.ExecutablePath } | Join-String -Separator '; ')"
    }
    $script:ServicesStopped = $true
}

function Backup-Path([string]$Source, [string]$RelativeDestination) {
    if (Test-Path -LiteralPath $Source) {
        $destination = Join-Path $BackupRoot $RelativeDestination
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $destination -Recurse -Force
        Write-Step "BACKUP $Source -> $destination"
    }
}

function New-DeploymentBackup {
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    Backup-Path $LiveServerBin 'source-bin'
    Backup-Path $LiveClientSwf 'build\client-unchanged.swf'

    # Runtime artifacts only. Redis data, logs, and backups are intentionally excluded.
    foreach ($name in @('server.exe', 'wServer.exe', 'common.dll')) {
        Backup-Path (Join-Path $LiveRuntime $name) (Join-Path 'runtime-artifacts' $name)
    }
    Get-ChildItem -LiteralPath $LiveRuntime -File | Where-Object { $_.Extension -in @('.dll', '.pdb') } | ForEach-Object {
        Backup-Path $_.FullName (Join-Path 'runtime-artifacts' $_.Name)
    }
    Backup-Path (Join-Path $LiveRuntime 'resources') 'runtime-artifacts\resources'

    # Record and preserve VPS-only configuration; deployment never copies over these paths.
    foreach ($relative in @('runtime\redis.conf', 'runtime\server.json', 'runtime\wServer.json', 'runtime\air\client.json', 'runtime\processes.json')) {
        Backup-Path (Join-Path $LiveRoot $relative) (Join-Path 'vps-config' $relative)
    }
    # Redis persistence is protected live data. AOF/RDB files may be locked while
    # Redis is running, so inventory metadata only—never hash, copy, or open them.
    $persistence = @()
    foreach ($directory in @((Join-Path $LiveRuntime 'redis-data'), (Join-Path $LiveRuntime 'redis-backups'))) {
        Assert-Path $directory 'protected Redis persistence directory'
        Write-Step "PRESERVED REDIS DIRECTORY $directory"
        Get-ChildItem -LiteralPath $directory -File -Recurse | ForEach-Object {
            $persistence += [PSCustomObject]@{ Path = $_.FullName; Bytes = $_.Length; LastWriteTimeUtc = $_.LastWriteTimeUtc }
            Write-Step "PRESERVED REDIS FILE path=$($_.FullName) bytes=$($_.Length) modifiedUtc=$($_.LastWriteTimeUtc.ToString('o'))"
        }
    }
    $persistence | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $BackupRoot 'redis-persistence-inventory.json') -Encoding UTF8
    $script:BackupCreated = $true
    Write-Step "Backup created at $BackupRoot. Redis database files were inventoried but not copied."
}

function Restore-DeploymentBackup {
    if (!$script:BackupCreated) { return }
    Write-Step "ROLLBACK restoring $BackupRoot"
    $backupBin = Join-Path $BackupRoot 'source-bin'
    if (Test-Path -LiteralPath $backupBin) { Copy-Item -LiteralPath "$backupBin\*" -Destination $LiveServerBin -Recurse -Force }
    $backupSwf = Join-Path $BackupRoot 'build\client-unchanged.swf'
    if (Test-Path -LiteralPath $backupSwf) { Copy-Item -LiteralPath $backupSwf -Destination $LiveClientSwf -Force }
    $backupRuntime = Join-Path $BackupRoot 'runtime-artifacts'
    if (Test-Path -LiteralPath $backupRuntime) { Copy-Item -LiteralPath "$backupRuntime\*" -Destination $LiveRuntime -Recurse -Force }

    # These were never overwritten by deployment, but restore the backed-up VPS
    # configuration explicitly before bringing the previous version back online.
    $backupConfig = Join-Path $BackupRoot 'vps-config'
    foreach ($relative in @('runtime\redis.conf', 'runtime\server.json', 'runtime\wServer.json', 'runtime\air\client.json')) {
        $source = Join-Path $backupConfig $relative
        if (Test-Path -LiteralPath $source) {
            $destination = Join-Path $LiveRoot $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }

    # Delete only files introduced by this failed deployment that had no backed-up counterpart.
    foreach ($destination in $script:CopiedFiles) {
        if (!$destination.StartsWith($LiveServerBin, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $relative = $destination.Substring($LiveServerBin.Length).TrimStart('\')
        $backupEquivalent = Join-Path $backupBin $relative
        if (!(Test-Path -LiteralPath $backupEquivalent) -and (Test-Path -LiteralPath $destination)) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
}

function Test-Http([string]$Uri, [string]$Method = 'GET') {
    $response = Invoke-WebRequest -Uri $Uri -Method $Method -UseBasicParsing -TimeoutSec 15
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) { throw "HTTP $Method $Uri returned $($response.StatusCode)" }
    Write-Step "HEALTH HTTP $Method $Uri = $($response.StatusCode)"
}

function Start-AndVerify {
    Write-Step 'Starting the deployed Eclipse stack.'
    & (Join-Path $LiveRoot 'scripts\Start-All.ps1')
    Start-Sleep -Seconds 5

    $redisCli = Join-Path $LiveProject 'Server-src\Redis-x64-3.2.100\redis-cli.exe'
    if (!(Wait-ForRedisPong -RedisCli $redisCli -TimeoutSeconds 30)) {
        throw 'Redis did not return PONG on 127.0.0.1:6379 within 30 seconds.'
    }
    Write-Step 'HEALTH Redis PING = PONG'
    foreach ($port in @(80, 2050, 843)) {
        if (!(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)) { throw "Port $port is not listening." }
    }
    $runtimeProcesses = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($LiveRuntime, [System.StringComparison]::OrdinalIgnoreCase) -and $_.Name -in @('server.exe', 'wServer.exe')
    })
    foreach ($name in @('server.exe', 'wServer.exe')) {
        if (!($runtimeProcesses | Where-Object Name -eq $name)) { throw "$name is not running from $LiveRuntime." }
    }
    Test-Http 'http://127.0.0.1/crossdomain.xml'
    Test-Http 'http://127.0.0.1/app/init' 'POST'
    Test-Http 'http://127.0.0.1/rotmg.swf'
    $health = Join-Path $LiveRoot 'scripts\Health-Check.ps1'
    if (Test-Path -LiteralPath $health) { & $health; Write-Step 'Health-Check.ps1 passed.' }
}

try {
    $DeploymentPhase = 'preflight'
    Assert-Path $RedisHelpers 'Redis helper script'
    . $RedisHelpers
    if (!(Test-Administrator)) {
        # -WhatIf performs no service, file, Git, or deployment mutations and may be
        # used by an operator to validate the plan before opening an elevated shell.
        if ($WhatIfPreference) { Write-Warning 'Running read-only -WhatIf preflight without Administrator privileges.' }
        else { throw 'Administrator privileges are required.' }
    }
    foreach ($entry in @(
        @($GitRoot, 'Git root'), @($GitProject, 'Git source project'), @($LiveRoot, 'live root'),
        @((Join-Path $GitRoot 'scripts\DeploymentArtifacts.psm1'), 'deployment artifact validator'),
        @((Join-Path $LiveRoot 'scripts\Start-All.ps1'), 'live Start-All.ps1'), @((Join-Path $LiveRoot 'scripts\Stop-All.ps1'), 'live Stop-All.ps1'),
        @($LiveServerBin, 'live Server-src bin'), @($LiveClientSwf, 'live client SWF'),
        @((Join-Path $LiveRuntime 'redis-data'), 'live protected Redis data directory'), @((Join-Path $LiveRuntime 'redis-backups'), 'live protected Redis backup directory')
    )) { Assert-Path $entry[0] $entry[1] }

    Push-Location $GitRoot
    $branch = (& git branch --show-current).Trim()
    if ($branch -ne 'main') { throw "Refusing to deploy from branch '$branch'; expected 'main'." }
    $checkoutStatus = @(& git status --porcelain)
    $script:GeneratedCheckoutChanges = @(Get-GeneratedCheckoutChanges $checkoutStatus)
    $oldCommit = (& git rev-parse HEAD).Trim()
    Pop-Location

    if ($WhatIfPreference) {
        Write-Step "WHATIF: commit=$oldCommit; would clear only $($GeneratedCheckoutChanges.Count) tracked generated-output changes, pull, verify the checked-in artifact bundle and manifest, then create backup $BackupRoot, stop only Eclipse-owned processes, copy verified artifacts, and restart unless -NoRestart."
        return
    }

    New-Item -ItemType Directory -Force -Path $DeploymentLogs | Out-Null
    $log = Join-Path $DeploymentLogs "deploy-$Timestamp.log"
    Start-Transcript -LiteralPath $log -Append | Out-Null
    $TranscriptStarted = $true
    Write-Step "Git commit before deployment: $oldCommit"

    Clear-GeneratedCheckoutChanges
    Push-Location $GitRoot
    if (!$SkipPull) {
        & git fetch --prune
        & git pull --ff-only
    }
    $newCommit = (& git rev-parse HEAD).Trim()
    Pop-Location
    Write-Step "Git commit after deployment: $newCommit"
    if ($oldCommit -eq $newCommit -and !$SkipPull) {
        $answer = Read-Host 'No new commits. Redeploy the current version? (Y/N)'
        if ($answer -notmatch '^(Y|y|Yes|yes)$') { Write-Step 'Deployment cancelled: no new commits.'; return }
    }

    # Checked-in artifact and compatibility validation happens before backup/stop.
    # The VPS intentionally needs no compiler, Flex SDK, Java, or MSBuild.
    $DeploymentPhase = 'validate checked-in artifacts'
    # A pull that first introduces .gitattributes does not rewrite unchanged
    # files left in an older checkout. Rehydrate manifest artifacts from Git's
    # index so legacy CRLF copies cannot disagree with the committed blob.
    Restore-DeploymentArtifactsFromIndex -RepositoryRoot $GitRoot
    Test-CheckedInArtifacts $newCommit

    $DeploymentPhase = 'backup'
    New-DeploymentBackup
    # Stop-All.ps1 is used before the main artifact-copy phase. Refresh only the
    # Redis helper and stop script first so a stale live copy cannot fail on an
    # expected connection refusal during a reboot deployment.
    $DeploymentPhase = 'stop infrastructure update'
    foreach ($scriptName in @('Redis-Helpers.ps1', 'Stop-All.ps1')) {
        Copy-VerifiedFile (Join-Path $ArtifactRoot "scripts\$scriptName") (Join-Path $LiveRoot "scripts\$scriptName")
    }
    $DeploymentPhase = 'stop'
    if (!$NoRestart) { Stop-EclipseServices }

    $DeploymentPhase = 'copy'
    # The manifest is authoritative: copy only listed server artifacts and
    # remove stale managed files that survived older ignored-bin workflows.
    Sync-ManifestServerArtifacts
    Copy-VerifiedFile $SourceClientSwf $LiveClientSwf
    # Start-All runs from runtime, so refresh its hosted web root from the same
    # compiled Server-src\\bin resource set. Runtime is never a deployment source.
    Copy-VerifiedFile $SourceClientSwf (Join-Path $LiveRuntime 'resources\web\rotmg.swf')

    # These scripts are deployment infrastructure, not VPS configuration. No server JSON,
    # Redis configuration, Redis data, logs, or air client configuration is copied from Git.
    foreach ($scriptName in @('Redis-Helpers.ps1', 'Start-All.ps1', 'Stop-All.ps1', 'Health-Check.ps1')) {
        $source = Join-Path $ArtifactRoot "scripts\$scriptName"
        if (Test-Path -LiteralPath $source) { Copy-VerifiedFile $source (Join-Path $LiveRoot "scripts\$scriptName") }
    }

    $DeploymentPhase = 'hash verification'
    foreach ($pair in @(
        @((Join-Path $SourceServerBin 'wServer.exe'), (Join-Path $LiveServerBin 'wServer.exe')),
        @((Join-Path $SourceServerBin 'server.exe'), (Join-Path $LiveServerBin 'server.exe')),
        @((Join-Path $SourceServerBin 'common.dll'), (Join-Path $LiveServerBin 'common.dll')),
        @($SourceClientSwf, $LiveClientSwf),
        @((Join-Path $SourceServerBin 'resources\xmls\EmbeddedData_EquipCXML.dat'), (Join-Path $LiveServerBin 'resources\xmls\EmbeddedData_EquipCXML.dat'))
    )) {
        if ((Get-Sha256 $pair[0]) -ne (Get-Sha256 $pair[1])) { throw "Required deployment hash verification failed: $($pair[0])" }
        Write-Step "VERIFIED $($pair[1])"
    }

    Set-Content -LiteralPath (Join-Path $LiveRuntime 'deployed-version.txt') -Value $newCommit -Encoding ASCII
    $DeploymentPhase = 'start and health verification'
    if ($NoRestart) {
        Write-Step "Deployment copied $($CopiedFiles.Count) files without restarting services (-NoRestart)."
    } else {
        Start-AndVerify
        Write-Step "DEPLOYMENT SUCCESS commit=$newCommit backup=$BackupRoot copied=$($CopiedFiles.Count) log=$log"
    }
}
catch {
    $failure = $_
    $line = $failure.InvocationInfo.ScriptLineNumber
    $source = if ($failure.InvocationInfo.ScriptName) { $failure.InvocationInfo.ScriptName } else { $MyInvocation.MyCommand.Path }
    Write-Error "Deployment failed during phase '$DeploymentPhase' at ${source}:${line}: $($failure.Exception.Message)"
    if (!$WhatIfPreference -and $BackupCreated) {
        try {
            if (!$NoRestart) { Stop-EclipseServices }
            Restore-DeploymentBackup
            if (!$NoRestart) { Start-AndVerify }
            Write-Error "Rollback succeeded. Previous version restored from $BackupRoot."
        } catch {
            Write-Error "ROLLBACK FAILED: $($_.Exception.Message)"
        }
    }
    exit 1
}
finally {
    if (Get-Location | ForEach-Object { $_.Path -eq $GitRoot }) { Pop-Location }
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
}
