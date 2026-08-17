Set-StrictMode -Version Latest

$script:FlexSdkVersion = '4.9.1'
$script:FlexSdkArchiveName = 'apache-flex-sdk-4.9.1-bin.zip'
$script:FlexSdkArchiveUri = 'https://archive.apache.org/dist/flex/4.9.1/binaries/apache-flex-sdk-4.9.1-bin.zip'
$script:FlexSdkArchiveSha256 = 'B7EB342D73089A5DD644498CF4CC24B2BC2C55A9E1D436E8B228D9A75D84B262'
$script:MxmlcBatSha256 = '75DDB4235B58D1A340970F7D87B724752D4DFCEE413858C4170140F0F9ED2C6C'
$script:PlayerGlobalVersion = '15.0'
# Adobe's retired download endpoint is no longer consistently reachable. This
# MPL-licensed mirror is pinned to a commit and the exact bytes used by the
# existing project toolchain; it is never resolved from a moving branch/tag.
$script:PlayerGlobalUri = 'https://raw.githubusercontent.com/nexussays/playerglobal/fef560243029214656d83fc673be0267a1ea0816/15.0/playerglobal.swc'
$script:PlayerGlobalSha256 = 'FF7BC30D882CF88678020FFDAD16E13C686C788978E82CD73AB7392ADA869373'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-ExpectedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description,
        [string]$ExpectedSha256
    )
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Invalid Flex SDK: missing $Description at $Path"
    }
    if ($ExpectedSha256) {
        $actual = Get-Sha256 $Path
        if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
            throw "Invalid Flex SDK: $Description checksum mismatch at $Path (expected $ExpectedSha256, got $actual)."
        }
    }
}

function Test-JavaRuntime {
    $java = $null
    if ($env:JAVA_HOME) {
        $javaHomeCandidate = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path -LiteralPath $javaHomeCandidate -PathType Leaf) { $java = $javaHomeCandidate }
    }
    if (!$java) {
        $command = Get-Command java.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $java = $command.Source }
    }
    if (!$java) {
        throw 'Java is required by Apache Flex mxmlc but java.exe was not found via JAVA_HOME or PATH.'
    }
    & $java -version 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Java validation failed for $java (exit code $LASTEXITCODE)." }
    return $java
}

function Test-FlexSdk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SdkRoot,
        [string]$ExpectedMxmlcSha256 = $script:MxmlcBatSha256,
        [string]$ExpectedPlayerGlobalSha256 = $script:PlayerGlobalSha256,
        [switch]$SkipJavaValidation
    )
    $resolvedRoot = [System.IO.Path]::GetFullPath($SdkRoot)
    if (!(Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "Flex SDK directory does not exist: $resolvedRoot"
    }
    Assert-ExpectedFile (Join-Path $resolvedRoot 'NOTICE') 'Apache NOTICE file'
    Assert-ExpectedFile (Join-Path $resolvedRoot 'bin\mxmlc.bat') 'mxmlc launcher' $ExpectedMxmlcSha256
    Assert-ExpectedFile (Join-Path $resolvedRoot 'lib\mxmlc.jar') 'mxmlc compiler JAR'
    Assert-ExpectedFile (Join-Path $resolvedRoot 'frameworks\flex-config.xml') 'Flex compiler configuration'
    Assert-ExpectedFile (Join-Path $resolvedRoot "frameworks\libs\player\$script:PlayerGlobalVersion\playerglobal.swc") 'Flash Player 15 playerglobal.swc' $ExpectedPlayerGlobalSha256
    $java = if ($SkipJavaValidation) { $null } else { Test-JavaRuntime }
    return [PSCustomObject]@{
        Root = $resolvedRoot
        Mxmlc = Join-Path $resolvedRoot 'bin\mxmlc.bat'
        PlayerGlobalHome = Join-Path $resolvedRoot 'frameworks\libs\player'
        Java = $java
        Version = $script:FlexSdkVersion
    }
}

function Invoke-PinnedDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        if ((Get-Sha256 $Destination) -eq $ExpectedSha256) { return }
        Remove-Item -LiteralPath $Destination -Force
    }
    Write-Host "Downloading pinned toolchain dependency: $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -TimeoutSec 180
    $actual = Get-Sha256 $Destination
    if ($actual -ne $ExpectedSha256) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Downloaded toolchain checksum mismatch for $Uri (expected $ExpectedSha256, got $actual)."
    }
}

function Install-FlexSdk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SdkRoot,
        [string]$DownloadCache
    )
    $resolvedRoot = [System.IO.Path]::GetFullPath($SdkRoot)
    if (Test-Path -LiteralPath $resolvedRoot) {
        return Test-FlexSdk -SdkRoot $resolvedRoot
    }
    $parent = Split-Path -Parent $resolvedRoot
    if (!$DownloadCache) { $DownloadCache = Join-Path $parent '.downloads' }
    $resolvedCache = [System.IO.Path]::GetFullPath($DownloadCache)
    New-Item -ItemType Directory -Force -Path $parent,$resolvedCache | Out-Null

    $archive = Join-Path $resolvedCache $script:FlexSdkArchiveName
    $playerGlobal = Join-Path $resolvedCache 'playerglobal-15.0-fef560243029214656d83fc673be0267a1ea0816.swc'
    Invoke-PinnedDownload $script:FlexSdkArchiveUri $archive $script:FlexSdkArchiveSha256
    Invoke-PinnedDownload $script:PlayerGlobalUri $playerGlobal $script:PlayerGlobalSha256

    $partial = "$resolvedRoot.partial-$([guid]::NewGuid().ToString('N'))"
    try {
        New-Item -ItemType Directory -Path $partial | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $partial
        $playerDirectory = Join-Path $partial "frameworks\libs\player\$script:PlayerGlobalVersion"
        New-Item -ItemType Directory -Force -Path $playerDirectory | Out-Null
        Copy-Item -LiteralPath $playerGlobal -Destination (Join-Path $playerDirectory 'playerglobal.swc') -Force
        Test-FlexSdk -SdkRoot $partial -SkipJavaValidation | Out-Null
        Move-Item -LiteralPath $partial -Destination $resolvedRoot
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Recurse -Force }
    }
    return Test-FlexSdk -SdkRoot $resolvedRoot
}

function Resolve-FlexSdk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$SdkRoot,
        [switch]$ProvisionIfMissing,
        [switch]$SkipJavaValidation,
        [string]$ExpectedMxmlcSha256 = $script:MxmlcBatSha256,
        [string]$ExpectedPlayerGlobalSha256 = $script:PlayerGlobalSha256
    )
    $candidate = if ($SdkRoot) {
        $SdkRoot
    } elseif ($env:ECLIPSE_FLEX_SDK_HOME) {
        $env:ECLIPSE_FLEX_SDK_HOME
    } else {
        Join-Path $RepositoryRoot "tools\flex-sdk-$script:FlexSdkVersion"
    }
    $candidate = [System.IO.Path]::GetFullPath($candidate)
    if (!(Test-Path -LiteralPath $candidate)) {
        if (!$ProvisionIfMissing) {
            throw "Apache Flex SDK $script:FlexSdkVersion was not found at $candidate. Run .\scripts\Provision-FlexSdk.ps1, or set ECLIPSE_FLEX_SDK_HOME to a validated SDK root."
        }
        Install-FlexSdk -SdkRoot $candidate | Out-Null
    }
    return Test-FlexSdk -SdkRoot $candidate -SkipJavaValidation:$SkipJavaValidation -ExpectedMxmlcSha256 $ExpectedMxmlcSha256 -ExpectedPlayerGlobalSha256 $ExpectedPlayerGlobalSha256
}

Export-ModuleMember -Function Resolve-FlexSdk, Install-FlexSdk, Test-FlexSdk
