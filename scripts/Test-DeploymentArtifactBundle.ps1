$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "eclipse-artifact-bundle-$([guid]::NewGuid().ToString('N'))"

function Invoke-Git([string[]]$Arguments) {
    & git -C $testRoot @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed: git $($Arguments -join ' ')" }
}

function Set-FixtureFile([string]$Relative, [string]$Value) {
    $path = Join-Path $testRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    Set-Content -LiteralPath $path -Value $Value -Encoding ASCII
}

function Set-FixtureBytes([string]$Relative, [byte[]]$Value) {
    $path = Join-Path $testRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllBytes($path, $Value)
}

function Assert-Rejected([string]$Expected, [scriptblock]$Action) {
    try { & $Action; throw "Invalid artifact fixture unexpectedly passed: $Expected" }
    catch { if ($_.Exception.Message -notmatch [regex]::Escape($Expected)) { throw } }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Invoke-Git @('init', '--quiet')
    Invoke-Git @('config', 'user.email', 'artifact-test@example.invalid')
    Invoke-Git @('config', 'user.name', 'Artifact Test')
    Set-FixtureFile 'source.txt' 'source revision'
    Set-FixtureFile '.gitignore' 'Cosmic-Realms-main/Server-src/bin/'
    Set-FixtureFile '.gitattributes' "build/client-unchanged.swf -text`nCosmic-Realms-main/Server-src/bin/** -text"
    Invoke-Git @('add', 'source.txt', '.gitignore', '.gitattributes')
    Invoke-Git @('commit', '--quiet', '-m', 'source')
    $sourceCommit = (& git -C $testRoot rev-parse HEAD).Trim()

    $clientBytes = [byte[]](0, 13, 10, 255, 83, 87, 70)
    Set-FixtureBytes 'build\client-unchanged.swf' $clientBytes
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\common.dll' ([byte[]](0, 68, 76, 76, 255))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\common.pdb' ([byte[]](0, 80, 68, 66, 255))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\server.exe' ([byte[]](0, 69, 88, 69, 255))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\wServer.exe' ([byte[]](0, 87, 79, 82, 76, 68, 255))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\resources\web\rotmg.swf' $clientBytes
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\resources\xmls\EmbeddedData_EquipCXML.dat' ([Text.Encoding]::ASCII.GetBytes("<Objects />`n"))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\resources\xmls\Extra.dat' ([Text.Encoding]::ASCII.GetBytes("<Objects />`n"))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\resources\data\template.txt' ([Text.Encoding]::ASCII.GetBytes("first`nsecond`n"))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\resources\data\settings.xml' ([Text.Encoding]::ASCII.GetBytes("<root>`n</root>`n"))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\resources\data\settings.json' ([Text.Encoding]::ASCII.GetBytes("{`n  `"ok`": true`n}`n"))
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\resources\data\server.config' ([Text.Encoding]::ASCII.GetBytes("key=value`nnext=value`n"))
    New-DeploymentManifest -RepositoryRoot $testRoot -SourceCommit $sourceCommit | Out-Null

    Assert-Rejected 'absent from the Git index' { Test-DeploymentArtifactIndex -RepositoryRoot $testRoot | Out-Null }
    Set-FixtureFile '.gitattributes' '* text=auto'
    Assert-Rejected 'normalization changed' { Add-DeploymentArtifactsToIndex -RepositoryRoot $testRoot | Out-Null }
    Invoke-Git @('reset', '--quiet', 'HEAD', '--', '.')
    Invoke-Git @('restore', '--', '.gitattributes')
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\Unlisted.dll' 'unlisted'
    Assert-Rejected 'omitted from the manifest' { Add-DeploymentArtifactsToIndex -RepositoryRoot $testRoot | Out-Null }
    Remove-Item -LiteralPath (Join-Path $testRoot 'Cosmic-Realms-main\Server-src\bin\Unlisted.dll') -Force

    Add-DeploymentArtifactsToIndex -RepositoryRoot $testRoot | Out-Null
    Test-DeploymentArtifactIndex -RepositoryRoot $testRoot | Out-Null
    Add-Content -LiteralPath (Join-Path $testRoot 'Cosmic-Realms-main\Server-src\bin\common.pdb') -Value 'unstaged'
    Assert-Rejected 'unstaged bytes' { Test-DeploymentArtifactIndex -RepositoryRoot $testRoot | Out-Null }
    Invoke-Git @('restore', '--', 'Cosmic-Realms-main/Server-src/bin/common.pdb')
    & git -C $testRoot rm --cached --quiet -- 'Cosmic-Realms-main/Server-src/bin/common.pdb'
    if ($LASTEXITCODE -ne 0) { throw 'Fixture failed to remove the PDB from the Git index.' }
    Assert-Rejected 'absent from the Git index' { Test-DeploymentArtifactIndex -RepositoryRoot $testRoot | Out-Null }
    & git -C $testRoot add -f -- 'Cosmic-Realms-main/Server-src/bin/common.pdb'
    if ($LASTEXITCODE -ne 0) { throw 'Fixture failed to restore the PDB to the Git index.' }
    Test-DeploymentArtifactIndex -RepositoryRoot $testRoot | Out-Null
    Invoke-Git @('commit', '--quiet', '-m', 'deployment artifacts')
    $head = (& git -C $testRoot rev-parse HEAD).Trim()

    $verified = Test-DeploymentManifest -RepositoryRoot $testRoot -ExpectedHead $head -RequireArtifactBundleCommit
    $textArtifact = Join-Path $testRoot 'Cosmic-Realms-main\Server-src\bin\resources\data\template.txt'
    [IO.File]::WriteAllText($textArtifact, "first`r`nsecond`r`n", [Text.Encoding]::ASCII)
    Assert-Rejected 'hash mismatch' { Test-DeploymentManifest -RepositoryRoot $testRoot | Out-Null }
    Set-FixtureBytes 'Cosmic-Realms-main\Server-src\bin\common.dll' ([byte[]](255, 0, 1, 2, 3))
    $materialized = New-DeploymentArtifactStageFromGit -RepositoryRoot $testRoot -Commit $head -DestinationRoot (Join-Path $testRoot 'blob-stage-altered-worktree')
    if ($materialized.ArtifactPaths.Count -ne $verified.ArtifactPaths.Count) { throw 'Blob staging lost manifest artifacts.' }
    $stagedText = Join-Path $materialized.ArtifactRoot 'Cosmic-Realms-main\Server-src\bin\resources\data\template.txt'
    $manifestTextHash = [string]$materialized.Manifest.artifacts.PSObject.Properties['Cosmic-Realms-main/Server-src/bin/resources/data/template.txt'].Value
    if ((Get-FileHash -LiteralPath $stagedText -Algorithm SHA256).Hash -ne $manifestTextHash) { throw 'Blob-staged TXT does not match its manifest hash.' }
    Invoke-Git @('restore', '--', 'Cosmic-Realms-main/Server-src/bin/resources/data/template.txt', 'Cosmic-Realms-main/Server-src/bin/common.dll')
    Test-DeploymentManifest -RepositoryRoot $testRoot | Out-Null
    foreach ($autocrlf in @('true', 'false')) {
        $checkout = Join-Path $testRoot "checkout-$autocrlf"
        & git -c "core.autocrlf=$autocrlf" clone --quiet --no-hardlinks $testRoot $checkout
        if ($LASTEXITCODE -ne 0) { throw "Fixture clone failed with core.autocrlf=$autocrlf." }
        $checkoutHead = (& git -C $checkout rev-parse HEAD).Trim()
        $checkoutVerified = Test-DeploymentManifest -RepositoryRoot $checkout -ExpectedHead $checkoutHead -RequireArtifactBundleCommit
        if ($checkoutVerified.ArtifactPaths.Count -ne $verified.ArtifactPaths.Count) { throw "Artifact count changed with core.autocrlf=$autocrlf." }
        $checkoutStage = New-DeploymentArtifactStageFromGit -RepositoryRoot $checkout -Commit $checkoutHead -DestinationRoot (Join-Path $checkout 'blob-stage')
        if ($checkoutStage.ArtifactPaths.Count -ne $verified.ArtifactPaths.Count) { throw "Blob artifact count changed with core.autocrlf=$autocrlf." }
    }
    $copyRoot = Join-Path $testRoot 'copy-simulation'
    foreach ($relative in $verified.ArtifactPaths) {
        $source = Join-Path $materialized.ArtifactRoot $relative.Replace('/', '\')
        $destination = Join-Path $copyRoot $relative.Replace('/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
            throw "Deployment copy simulation hash mismatch: $relative"
        }
    }

    foreach ($fixture in @(
        @{ Path = 'Cosmic-Realms-main\Server-src\bin\server.exe'; Error = 'server.exe' },
        @{ Path = 'Cosmic-Realms-main\Server-src\bin\wServer.exe'; Error = 'wServer.exe' },
        @{ Path = 'Cosmic-Realms-main\Server-src\bin\common.pdb'; Error = 'common.pdb' },
        @{ Path = 'build\client-unchanged.swf'; Error = 'client-unchanged.swf' },
        @{ Path = 'Cosmic-Realms-main\Server-src\bin\resources\xmls\Extra.dat'; Error = 'Extra.dat' }
    )) {
        Add-Content -LiteralPath (Join-Path $testRoot $fixture.Path) -Value 'stale'
        Assert-Rejected $fixture.Error { Test-DeploymentManifest -RepositoryRoot $testRoot -ExpectedHead $head -RequireArtifactBundleCommit | Out-Null }
        Invoke-Git @('restore', '--', $fixture.Path.Replace('\', '/'))
    }

    $missing = 'Cosmic-Realms-main\Server-src\bin\common.dll'
    Move-Item -LiteralPath (Join-Path $testRoot $missing) -Destination (Join-Path $testRoot 'common.dll.missing')
    Assert-Rejected 'common.dll' { Test-DeploymentManifest -RepositoryRoot $testRoot -ExpectedHead $head -RequireArtifactBundleCommit | Out-Null }
    Move-Item -LiteralPath (Join-Path $testRoot 'common.dll.missing') -Destination (Join-Path $testRoot $missing)

    $manifestPath = Join-Path $testRoot 'build\deployment-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.sourceCommit = '0000000000000000000000000000000000000000'
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'Stale deployment bundle' { Test-DeploymentManifest -RepositoryRoot $testRoot -ExpectedHead $head -RequireArtifactBundleCommit | Out-Null }
    Invoke-Git @('restore', '--', 'build/deployment-manifest.json')

    Write-Host "PASS: publisher verifies Git blobs; CRLF-sensitive TXT/XML/JSON/CONFIG/DAT and binary DLL/PDB/SWF materialize identically with core.autocrlf=true/false."
    Write-Host "PASS: altered working-tree text/binary bytes are ignored; deployment copy simulation uses only the blob-exact staging tree."
    Write-Host "PASS: index omissions, unstaged bytes, stale DLL/PDB/server/world/SWF/resource, missing file, wrong commit, hashes, and copy integrity verified."
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
