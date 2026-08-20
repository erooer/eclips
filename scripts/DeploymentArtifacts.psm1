Set-StrictMode -Version Latest

$script:ManifestRelativePath = 'build/deployment-manifest.json'

function Get-GitExecutable {
    $git = @(Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (!$git) { $git = @(Get-Command git -CommandType Application -ErrorAction Stop) | Select-Object -First 1 }
    return $git.Path
}

function ConvertTo-ArtifactPath([string]$RepositoryRoot, [string]$AbsolutePath) {
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\') + '\'
    $path = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (!$path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact path escapes repository root: $path"
    }
    return $path.Substring($root.Length).Replace('\', '/')
}

function Get-GitBlobSha256([string]$RepositoryRoot, [string]$ObjectId) {
    if ($ObjectId -notmatch '^[0-9a-f]{40,64}$') { throw "Invalid Git object ID: $ObjectId" }
    $escapedRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).Replace('"', '\"')
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Get-GitExecutable
    $start.Arguments = "-C `"$escapedRoot`" cat-file blob $ObjectId"
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = $sha.ComputeHash($process.StandardOutput.BaseStream) }
        finally { $sha.Dispose() }
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "git cat-file failed for $ObjectId (exit $($process.ExitCode)): $errorText" }
        return ([BitConverter]::ToString($hash)).Replace('-', '')
    } finally { $process.Dispose() }
}

function Get-GitCommitBlobId([string]$RepositoryRoot, [string]$Commit, [string]$RelativePath) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "Invalid deployment commit: $Commit" }
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)') {
        throw "Unsafe artifact path in deployment manifest: $RelativePath"
    }
    $entry = @(& git -C $RepositoryRoot ls-tree $Commit -- $RelativePath)
    if ($LASTEXITCODE -ne 0 -or $entry.Count -ne 1 -or $entry[0] -notmatch '^100(?:644|755)\s+blob\s+([0-9a-f]+)\t') {
        throw "Deployment artifact is not a regular Git blob at commit ${Commit}: $RelativePath"
    }
    return $Matches[1]
}

function Write-GitBlobToFile([string]$RepositoryRoot, [string]$ObjectId, [string]$Destination) {
    if ($ObjectId -notmatch '^[0-9a-f]{40,64}$') { throw "Invalid Git object ID: $ObjectId" }
    $directory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if (Test-Path -LiteralPath $Destination) { throw "Refusing to overwrite blob staging path: $Destination" }

    $escapedRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).Replace('"', '\"')
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Get-GitExecutable
    $start.Arguments = "-C `"$escapedRoot`" cat-file blob $ObjectId"
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = [IO.File]::Create($Destination)
        try { $process.StandardOutput.BaseStream.CopyTo($output) }
        finally { $output.Dispose() }
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            throw "git cat-file failed for $ObjectId (exit $($process.ExitCode)): $errorText"
        }
    } finally { $process.Dispose() }
}

function Get-DeploymentArtifactPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $serverBin = Join-Path $root 'Cosmic-Realms-main\Server-src\bin'
    $airBuild = Join-Path $root 'build\air'
    $required = @(
        'build\client-unchanged.swf',
        'build\air\CosmicRealmsAir.swf',
        'build\air\CosmicRealms.air',
        'build\air\CosmicRealms-Desktop\CosmicRealms.exe',
        'build\air\CosmicRealms-Desktop\CosmicRealmsAir.swf',
        'Cosmic-Realms-main\Server-src\bin\common.dll',
        'Cosmic-Realms-main\Server-src\bin\server.exe',
        'Cosmic-Realms-main\Server-src\bin\wServer.exe',
        'Cosmic-Realms-main\Server-src\bin\resources\web\rotmg.swf',
        'Cosmic-Realms-main\Server-src\bin\resources\xmls\EmbeddedData_EquipCXML.dat'
    )
    foreach ($relative in $required) {
        if (!(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
            throw "Missing required deployment artifact: $relative"
        }
    }

    $files = [System.Collections.Generic.List[string]]::new()
    $files.Add((Join-Path $root 'build\client-unchanged.swf'))
    Get-ChildItem -LiteralPath $airBuild -File -Recurse | ForEach-Object { $files.Add($_.FullName) }
    foreach ($name in @('server.exe', 'wServer.exe')) { $files.Add((Join-Path $serverBin $name)) }
    Get-ChildItem -LiteralPath $serverBin -File | Where-Object { $_.Extension -in @('.dll', '.pdb') } | ForEach-Object { $files.Add($_.FullName) }
    Get-ChildItem -LiteralPath (Join-Path $serverBin 'resources') -File -Recurse | ForEach-Object { $files.Add($_.FullName) }
    return @($files | ForEach-Object { ConvertTo-ArtifactPath $root $_ } | Sort-Object -Unique)
}

function New-DeploymentManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$OutputPath,
        [string]$SourceCommit,
        [switch]$ProtocolValidationPassed
    )
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (!$OutputPath) { $OutputPath = Join-Path $root $script:ManifestRelativePath.Replace('/', '\') }
    if (!$SourceCommit) {
        $SourceCommit = (& git -C $root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Unable to determine the source commit for the deployment manifest.' }
    }
    if ($SourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Unable to determine the source commit for the deployment manifest.' }
    if (!$ProtocolValidationPassed) {
        throw 'Refusing to create a deployment manifest without successful deep client/server protocol validation.'
    }

    $artifacts = [ordered]@{}
    foreach ($relative in Get-DeploymentArtifactPaths -RepositoryRoot $root) {
        $absolute = Join-Path $root $relative.Replace('/', '\')
        $artifacts[$relative] = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash
    }
    $clientPath = 'build/client-unchanged.swf'
    $airClientPath = 'build/air/CosmicRealmsAir.swf'
    $airPackagePath = 'build/air/CosmicRealms.air'
    $airDesktopClientPath = 'build/air/CosmicRealms-Desktop/CosmicRealmsAir.swf'
    $webClientPath = 'Cosmic-Realms-main/Server-src/bin/resources/web/rotmg.swf'
    $worldServerPath = 'Cosmic-Realms-main/Server-src/bin/wServer.exe'
    $accountServerPath = 'Cosmic-Realms-main/Server-src/bin/server.exe'
    $protocolValidation = [ordered]@{
        schemaVersion = 1
        sourceCommit = $SourceCommit
        validator = 'scripts/Test-ClientHandshakeProtocol.ps1'
        artifacts = [ordered]@{
            clientSwfSha256 = $artifacts[$clientPath]
            airClientSwfSha256 = $artifacts[$airClientPath]
            airPackageSha256 = $artifacts[$airPackagePath]
            airDesktopClientSwfSha256 = $artifacts[$airDesktopClientPath]
            deployedClientSwfSha256 = $artifacts[$webClientPath]
            worldServerSha256 = $artifacts[$worldServerPath]
            accountServerSha256 = $artifacts[$accountServerPath]
        }
        packetIds = [ordered]@{ HELLO = 183; GOTO = 30; BUY = 50; BUYRESULT = 93; MAPINFO = 74; LOAD = 26; CREATE = 12; CREATE_SUCCESS = 81 }
        contracts = [ordered]@{
            compiledClientBytecode = $true
            compiledWorldServerPacketTable = $true
            rc4Keys = $true
            rsaHello = $true
            helloSerialization = $true
            nexusMapInfo = $true
            createLoadReady = $true
            encryptedHandshakeProbe = $true
            runtimeClientBuildIdentity = $true
            airNativeWindowBuildIdentity = $true
        }
        clientBuildIdentity = [ordered]@{
            sourceCommit = $SourceCommit
            label = 'Eclipse client ' + $SourceCommit.Substring(0, 12)
        }
    }
    $manifest = [ordered]@{
        schemaVersion = 3
        sourceCommit = $SourceCommit
        builtAtUtc = [DateTime]::UtcNow.ToString('o')
        protocolValidation = $protocolValidation
        artifacts = $artifacts
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Deployment manifest: $OutputPath ($($artifacts.Count) artifacts built from $SourceCommit)"
    return $manifest
}

function Test-DeploymentManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$ArtifactRoot,
        [string]$ExpectedHead,
        [switch]$RequireArtifactBundleCommit,
        [switch]$CheckForUnlistedArtifacts
    )
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (!$ArtifactRoot) { $ArtifactRoot = $root }
    $artifactRootPath = [System.IO.Path]::GetFullPath($ArtifactRoot)
    $manifestPath = Join-Path $artifactRootPath $script:ManifestRelativePath.Replace('/', '\')
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing deployment manifest: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 3) { throw "Unsupported deployment manifest schema: $($manifest.schemaVersion)" }
    if ($manifest.sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Deployment manifest contains an invalid source commit.' }

    $manifestPaths = @($manifest.artifacts.PSObject.Properties.Name | Sort-Object -Unique)
    $requiredPaths = @(
        'build/client-unchanged.swf',
        'build/air/CosmicRealmsAir.swf',
        'build/air/CosmicRealms.air',
        'build/air/CosmicRealms-Desktop/CosmicRealms.exe',
        'build/air/CosmicRealms-Desktop/CosmicRealmsAir.swf',
        'Cosmic-Realms-main/Server-src/bin/common.dll',
        'Cosmic-Realms-main/Server-src/bin/server.exe',
        'Cosmic-Realms-main/Server-src/bin/wServer.exe',
        'Cosmic-Realms-main/Server-src/bin/resources/web/rotmg.swf',
        'Cosmic-Realms-main/Server-src/bin/resources/xmls/EmbeddedData_EquipCXML.dat'
    )
    foreach ($relative in $requiredPaths) {
        if ($relative -notin $manifestPaths) { throw "Deployment manifest is missing core artifact: $relative" }
    }
    foreach ($relative in $manifestPaths) {
        if ([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)') { throw "Unsafe artifact path in deployment manifest: $relative" }
        $absolute = [System.IO.Path]::GetFullPath((Join-Path $artifactRootPath $relative.Replace('/', '\')))
        if (!$absolute.StartsWith($artifactRootPath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe artifact path in deployment manifest: $relative" }
        if (!(Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Missing deployment artifact: $relative" }
        $actual = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash
        $expected = [string]$manifest.artifacts.PSObject.Properties[$relative].Value
        if ($actual -ne $expected) { throw "Deployment artifact hash mismatch: $relative" }
    }

    $protocol = $manifest.protocolValidation
    if (!$protocol -or $protocol.schemaVersion -ne 1 -or $protocol.sourceCommit -ne $manifest.sourceCommit) {
        throw 'Deployment manifest protocol validation evidence is missing, unsupported, or bound to a different source commit.'
    }
    $protocolArtifactBindings = [ordered]@{
        clientSwfSha256 = 'build/client-unchanged.swf'
        airClientSwfSha256 = 'build/air/CosmicRealmsAir.swf'
        airPackageSha256 = 'build/air/CosmicRealms.air'
        airDesktopClientSwfSha256 = 'build/air/CosmicRealms-Desktop/CosmicRealmsAir.swf'
        deployedClientSwfSha256 = 'Cosmic-Realms-main/Server-src/bin/resources/web/rotmg.swf'
        worldServerSha256 = 'Cosmic-Realms-main/Server-src/bin/wServer.exe'
        accountServerSha256 = 'Cosmic-Realms-main/Server-src/bin/server.exe'
    }
    foreach ($binding in $protocolArtifactBindings.GetEnumerator()) {
        $attested = [string]$protocol.artifacts.PSObject.Properties[$binding.Key].Value
        $manifestHash = [string]$manifest.artifacts.PSObject.Properties[$binding.Value].Value
        if ($attested -ne $manifestHash) { throw "Protocol validation evidence is not bound to the exact artifact: $($binding.Value)" }
    }
    $requiredProtocolIds = [ordered]@{ HELLO = 183; GOTO = 30; BUY = 50; BUYRESULT = 93; MAPINFO = 74; LOAD = 26; CREATE = 12; CREATE_SUCCESS = 81 }
    foreach ($entry in $requiredProtocolIds.GetEnumerator()) {
        if ([int]$protocol.packetIds.PSObject.Properties[$entry.Key].Value -ne $entry.Value) {
            throw "Protocol validation evidence contains an invalid packet mapping for $($entry.Key)."
        }
    }
    foreach ($contract in @('compiledClientBytecode', 'compiledWorldServerPacketTable', 'rc4Keys', 'rsaHello', 'helloSerialization', 'nexusMapInfo', 'createLoadReady', 'encryptedHandshakeProbe', 'runtimeClientBuildIdentity', 'airNativeWindowBuildIdentity')) {
        if ($protocol.contracts.PSObject.Properties[$contract].Value -ne $true) {
            throw "Protocol validation evidence is missing required successful check: $contract"
        }
    }
    $expectedClientLabel = 'Eclipse client ' + $manifest.sourceCommit.Substring(0, 12)
    if ($protocol.clientBuildIdentity.sourceCommit -ne $manifest.sourceCommit -or
        $protocol.clientBuildIdentity.label -ne $expectedClientLabel) {
        throw 'Protocol validation evidence contains an invalid runtime client build identity.'
    }

    if ($CheckForUnlistedArtifacts) {
        $discoveredPaths = @(Get-DeploymentArtifactPaths -RepositoryRoot $artifactRootPath)
        foreach ($relative in $discoveredPaths) {
            if ($relative -notin $manifestPaths) { throw "Deployable build output is omitted from the manifest: $relative" }
        }
        foreach ($relative in $manifestPaths) {
            if ($relative -notin $discoveredPaths) { throw "Deployment manifest contains a file outside the build artifact set: $relative" }
        }
    }

    $clientHash = (Get-FileHash -LiteralPath (Join-Path $artifactRootPath 'build\client-unchanged.swf') -Algorithm SHA256).Hash
    $webHash = (Get-FileHash -LiteralPath (Join-Path $artifactRootPath 'Cosmic-Realms-main\Server-src\bin\resources\web\rotmg.swf') -Algorithm SHA256).Hash
    if ($clientHash -ne $webHash) { throw 'Stale SWF copy: build client and deployable server web client differ.' }
    $airHash = (Get-FileHash -LiteralPath (Join-Path $artifactRootPath 'build\air\CosmicRealmsAir.swf') -Algorithm SHA256).Hash
    $desktopAirHash = (Get-FileHash -LiteralPath (Join-Path $artifactRootPath 'build\air\CosmicRealms-Desktop\CosmicRealmsAir.swf') -Algorithm SHA256).Hash
    if ($airHash -ne $desktopAirHash) { throw 'Stale AIR SWF copy: build client and packaged desktop client differ.' }

    if ($RequireArtifactBundleCommit) {
        if (!$ExpectedHead) { $ExpectedHead = (& git -C $root rev-parse HEAD).Trim() }
        if ($LASTEXITCODE -ne 0 -or $ExpectedHead -notmatch '^[0-9a-f]{40}$') { throw 'Unable to determine current HEAD for artifact-bundle validation.' }
        $parent = (& git -C $root rev-parse "$ExpectedHead^").Trim()
        if ($LASTEXITCODE -ne 0 -or $parent -ne $manifest.sourceCommit) {
            throw "Stale deployment bundle: manifest was built from $($manifest.sourceCommit), but current HEAD $ExpectedHead has parent $parent."
        }
        $changed = @(& git -C $root diff-tree --no-commit-id --name-only -r $ExpectedHead | ForEach-Object { $_.Replace('\', '/') })
        $allowed = @($manifestPaths + $script:ManifestRelativePath)
        foreach ($relative in $changed) {
            if ($relative -notin $allowed) { throw "Artifact bundle commit contains a non-artifact change: $relative" }
        }
        if ($script:ManifestRelativePath -notin $changed) { throw 'Current HEAD is not an artifact bundle commit: deployment manifest was not committed in HEAD.' }
        foreach ($relative in @($script:ManifestRelativePath) + $manifestPaths) {
            [void](Get-GitCommitBlobId -RepositoryRoot $root -Commit $ExpectedHead -RelativePath $relative)
        }
    }
    return [PSCustomObject]@{ Manifest = $manifest; ArtifactPaths = $manifestPaths; SourceCommit = [string]$manifest.sourceCommit }
}

function Test-DeploymentArtifactIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $manifestPath = Join-Path $root $script:ManifestRelativePath.Replace('/', '\')
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing deployment manifest: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $paths = @($script:ManifestRelativePath) + @($manifest.artifacts.PSObject.Properties.Name)
    foreach ($relative in $paths) {
        $indexEntry = @(& git -C $root ls-files --stage -- $relative)
        if ($LASTEXITCODE -ne 0 -or $indexEntry.Count -ne 1 -or $indexEntry[0] -notmatch '^\d+\s+([0-9a-f]+)\s+\d+\s+') {
            throw "Manifest artifact is absent from the Git index: $relative"
        }
        $objectId = $Matches[1]
        & git -C $root diff --quiet -- $relative
        if ($LASTEXITCODE -ne 0) { throw "Manifest artifact has unstaged bytes that differ from the Git index: $relative" }
        if ($relative -ne $script:ManifestRelativePath) {
            $expected = [string]$manifest.artifacts.PSObject.Properties[$relative].Value
            $blobHash = Get-GitBlobSha256 -RepositoryRoot $root -ObjectId $objectId
            if ($blobHash -ne $expected) { throw "Git index normalization changed manifest artifact bytes: $relative" }
        }
    }
    $verified = Test-DeploymentManifest -RepositoryRoot $root -CheckForUnlistedArtifacts
    $staged = @(& git -C $root diff --cached --name-only | ForEach-Object { $_.Replace('\', '/') })
    foreach ($relative in $staged) {
        if ($relative -notin $paths) { throw "Non-artifact path is staged for the artifact bundle: $relative" }
    }
    if ($script:ManifestRelativePath -notin $staged) { throw 'Deployment manifest is not staged for the artifact bundle commit.' }
    return $verified
}

function New-DeploymentArtifactStageFromGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$DestinationRoot
    )
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $resolvedCommit = @(& git -C $root rev-parse --verify "$Commit`^{commit}")
    if ($LASTEXITCODE -ne 0 -or $resolvedCommit.Count -ne 1 -or $resolvedCommit[0] -ne $Commit) {
        throw "Unable to resolve exact deployment commit: $Commit"
    }
    $stage = [System.IO.Path]::GetFullPath($DestinationRoot)
    if (Test-Path -LiteralPath $stage) { throw "Deployment artifact staging directory already exists: $stage" }
    New-Item -ItemType Directory -Path $stage | Out-Null

    $manifestObject = Get-GitCommitBlobId -RepositoryRoot $root -Commit $Commit -RelativePath $script:ManifestRelativePath
    $manifestPath = Join-Path $stage $script:ManifestRelativePath.Replace('/', '\')
    Write-GitBlobToFile -RepositoryRoot $root -ObjectId $manifestObject -Destination $manifestPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 3) { throw "Unsupported deployment manifest schema: $($manifest.schemaVersion)" }
    $paths = @($manifest.artifacts.PSObject.Properties.Name)
    foreach ($relative in $paths) {
        if ([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)') { throw "Unsafe artifact path in deployment manifest: $relative" }
        $objectId = Get-GitCommitBlobId -RepositoryRoot $root -Commit $Commit -RelativePath $relative
        $destination = [System.IO.Path]::GetFullPath((Join-Path $stage $relative.Replace('/', '\')))
        if (!$destination.StartsWith($stage.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe artifact path in deployment manifest: $relative" }
        Write-GitBlobToFile -RepositoryRoot $root -ObjectId $objectId -Destination $destination
        $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        $expected = [string]$manifest.artifacts.PSObject.Properties[$relative].Value
        if ($actual -ne $expected) { throw "Materialized Git blob hash mismatch: $relative" }
    }
    $verified = Test-DeploymentManifest -RepositoryRoot $root -ArtifactRoot $stage -ExpectedHead $Commit -RequireArtifactBundleCommit
    Write-Host "PASS: materialized and verified all $($verified.ArtifactPaths.Count) deployment artifacts from exact Git blobs at $Commit."
    return [PSCustomObject]@{
        Manifest = $verified.Manifest
        ArtifactPaths = $verified.ArtifactPaths
        SourceCommit = $verified.SourceCommit
        ArtifactRoot = $stage
    }
}

function Add-DeploymentArtifactsToIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $verified = Test-DeploymentManifest -RepositoryRoot $root -CheckForUnlistedArtifacts
    $head = (& git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -ne $verified.SourceCommit) {
        throw "Artifact publishing must run at manifest source commit $($verified.SourceCommit); current HEAD is $head."
    }
    $alreadyStaged = @(& git -C $root diff --cached --name-only)
    if ($alreadyStaged.Count -ne 0) { throw "Refusing artifact publishing with pre-existing staged changes: $($alreadyStaged -join ', ')" }

    $paths = @($script:ManifestRelativePath) + @($verified.ArtifactPaths)
    for ($offset = 0; $offset -lt $paths.Count; $offset += 60) {
        $last = [Math]::Min($offset + 59, $paths.Count - 1)
        $batch = @($paths[$offset..$last])
        & git -C $root add -f -- @batch
        if ($LASTEXITCODE -ne 0) { throw "Failed to stage deployment artifact batch beginning at index $offset." }
    }
    $indexed = Test-DeploymentArtifactIndex -RepositoryRoot $root
    Write-Host "PASS: staged and index-verified all $($indexed.ArtifactPaths.Count) manifest artifacts."
    return $indexed
}

Export-ModuleMember -Function Get-DeploymentArtifactPaths, New-DeploymentManifest, Test-DeploymentManifest, Test-DeploymentArtifactIndex, Add-DeploymentArtifactsToIndex, New-DeploymentArtifactStageFromGit
