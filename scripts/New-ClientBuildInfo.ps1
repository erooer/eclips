[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$SourceCommit,
    [string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\generated-client')
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
    $SourceCommit = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the source commit for the client build identity.' }
}
if ($SourceCommit -notmatch '^[0-9a-fA-F]{40}$') { throw "Invalid client source commit: $SourceCommit" }

$sourceCommitLower = $SourceCommit.ToLowerInvariant()
$shortCommit = $sourceCommitLower.Substring(0, 12)
$targetDirectory = Join-Path $OutputRoot 'eclipse'
$target = Join-Path $targetDirectory 'ClientBuildInfo.as'
New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
$content = @"
package eclipse {
public final class ClientBuildInfo {
    public static const SOURCE_COMMIT:String = "$sourceCommitLower";
    public static const SHORT_SOURCE:String = "$shortCommit";
    public static const LABEL:String = "Eclipse client $shortCommit";
}
}
"@
[IO.File]::WriteAllText($target, $content, (New-Object Text.UTF8Encoding($false)))
Write-Output ([pscustomobject]@{
    SourceCommit = $sourceCommitLower
    ShortCommit = $shortCommit
    SourceRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
    SourceFile = (Resolve-Path -LiteralPath $target).Path
})
