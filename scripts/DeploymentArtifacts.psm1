Set-StrictMode -Version Latest

$script:ManifestRelativePath = 'build/deployment-manifest.json'

function ConvertTo-ArtifactPath([string]$RepositoryRoot, [string]$AbsolutePath) {
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\') + '\'
    $path = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (!$path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact path escapes repository root: $path"
    }
    return $path.Substring($root.Length).Replace('\', '/')
}

function Get-DeploymentArtifactPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $serverBin = Join-Path $root 'Cosmic-Realms-main\Server-src\bin'
    $required = @(
        'build\client-unchanged.swf',
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
        [string]$SourceCommit
    )
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (!$OutputPath) { $OutputPath = Join-Path $root $script:ManifestRelativePath.Replace('/', '\') }
    if (!$SourceCommit) {
        $SourceCommit = (& git -C $root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Unable to determine the source commit for the deployment manifest.' }
    }
    if ($SourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Unable to determine the source commit for the deployment manifest.' }

    $artifacts = [ordered]@{}
    foreach ($relative in Get-DeploymentArtifactPaths -RepositoryRoot $root) {
        $absolute = Join-Path $root $relative.Replace('/', '\')
        $artifacts[$relative] = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash
    }
    $manifest = [ordered]@{
        schemaVersion = 2
        sourceCommit = $SourceCommit
        builtAtUtc = [DateTime]::UtcNow.ToString('o')
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
        [string]$ExpectedHead,
        [switch]$RequireArtifactBundleCommit,
        [switch]$CheckForUnlistedArtifacts
    )
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $manifestPath = Join-Path $root $script:ManifestRelativePath.Replace('/', '\')
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing deployment manifest: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 2) { throw "Unsupported deployment manifest schema: $($manifest.schemaVersion)" }
    if ($manifest.sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Deployment manifest contains an invalid source commit.' }

    $manifestPaths = @($manifest.artifacts.PSObject.Properties.Name | Sort-Object -Unique)
    $requiredPaths = @(
        'build/client-unchanged.swf',
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
        $absolute = [System.IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/', '\')))
        if (!$absolute.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe artifact path in deployment manifest: $relative" }
        if (!(Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Missing deployment artifact: $relative" }
        $actual = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash
        $expected = [string]$manifest.artifacts.PSObject.Properties[$relative].Value
        if ($actual -ne $expected) { throw "Deployment artifact hash mismatch: $relative" }
    }

    if ($CheckForUnlistedArtifacts) {
        $discoveredPaths = @(Get-DeploymentArtifactPaths -RepositoryRoot $root)
        foreach ($relative in $discoveredPaths) {
            if ($relative -notin $manifestPaths) { throw "Deployable build output is omitted from the manifest: $relative" }
        }
        foreach ($relative in $manifestPaths) {
            if ($relative -notin $discoveredPaths) { throw "Deployment manifest contains a file outside the build artifact set: $relative" }
        }
    }

    $clientHash = (Get-FileHash -LiteralPath (Join-Path $root 'build\client-unchanged.swf') -Algorithm SHA256).Hash
    $webHash = (Get-FileHash -LiteralPath (Join-Path $root 'Cosmic-Realms-main\Server-src\bin\resources\web\rotmg.swf') -Algorithm SHA256).Hash
    if ($clientHash -ne $webHash) { throw 'Stale SWF copy: build client and deployable server web client differ.' }

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
            $tracked = @(& git -C $root ls-files -- $relative)
            if ($LASTEXITCODE -ne 0 -or $relative -notin $tracked) { throw "Deployment artifact is not tracked by Git: $relative" }
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
        $tracked = @(& git -C $root ls-files -- $relative)
        if ($LASTEXITCODE -ne 0 -or $relative -notin $tracked) { throw "Manifest artifact is absent from the Git index: $relative" }
        & git -C $root diff --quiet -- $relative
        if ($LASTEXITCODE -ne 0) { throw "Manifest artifact has unstaged bytes that differ from the Git index: $relative" }
    }
    $verified = Test-DeploymentManifest -RepositoryRoot $root -CheckForUnlistedArtifacts
    $staged = @(& git -C $root diff --cached --name-only | ForEach-Object { $_.Replace('\', '/') })
    foreach ($relative in $staged) {
        if ($relative -notin $paths) { throw "Non-artifact path is staged for the artifact bundle: $relative" }
    }
    if ($script:ManifestRelativePath -notin $staged) { throw 'Deployment manifest is not staged for the artifact bundle commit.' }
    return $verified
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

Export-ModuleMember -Function Get-DeploymentArtifactPaths, New-DeploymentManifest, Test-DeploymentManifest, Test-DeploymentArtifactIndex, Add-DeploymentArtifactsToIndex
