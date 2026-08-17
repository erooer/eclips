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
    Invoke-Git @('add', 'source.txt')
    Invoke-Git @('commit', '--quiet', '-m', 'source')
    $sourceCommit = (& git -C $testRoot rev-parse HEAD).Trim()

    Set-FixtureFile 'build\client-unchanged.swf' 'client'
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\common.dll' 'common'
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\common.pdb' 'common symbols'
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\server.exe' 'server'
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\wServer.exe' 'world'
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\resources\web\rotmg.swf' 'client'
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\resources\xmls\EmbeddedData_EquipCXML.dat' '<Objects />'
    Set-FixtureFile 'Cosmic-Realms-main\Server-src\bin\resources\xmls\Extra.dat' '<Objects />'
    New-DeploymentManifest -RepositoryRoot $testRoot -SourceCommit $sourceCommit | Out-Null
    Invoke-Git @('add', 'build', 'Cosmic-Realms-main/Server-src/bin')
    Invoke-Git @('commit', '--quiet', '-m', 'deployment artifacts')
    $head = (& git -C $testRoot rev-parse HEAD).Trim()

    $verified = Test-DeploymentManifest -RepositoryRoot $testRoot -ExpectedHead $head -RequireArtifactBundleCommit
    $copyRoot = Join-Path $testRoot 'copy-simulation'
    foreach ($relative in $verified.ArtifactPaths) {
        $source = Join-Path $testRoot $relative.Replace('/', '\')
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

    Write-Host "PASS: valid artifact bundle accepted; stale server, world, SWF, resource, missing file, wrong commit, hashes, and copy integrity verified."
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
