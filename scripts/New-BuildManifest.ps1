[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\deployment-manifest.json')
)
$ErrorActionPreference = 'Stop'
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
$commit = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw 'Unable to determine the source commit for the build manifest.' }
$paths = @(
    'build\client-unchanged.swf',
    'runtime\resources\web\rotmg.swf',
    'Cosmic-Realms-main\Server-src\bin\resources\web\rotmg.swf',
    'Cosmic-Realms-main\Server-src\bin\server.exe',
    'Cosmic-Realms-main\Server-src\bin\wServer.exe',
    'Cosmic-Realms-main\Server-src\bin\common.dll',
    'Cosmic-Realms-main\Server-src\bin\resources\xmls\EmbeddedData_EquipCXML.dat'
)
$artifacts = [ordered]@{}
foreach ($relative in $paths) {
    $absolute = Join-Path $RepositoryRoot $relative
    if (!(Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Cannot create build manifest; missing artifact: $relative" }
    $artifacts[$relative.Replace('\', '/')] = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash
}
$manifest = [ordered]@{
    schemaVersion = 1
    sourceCommit = $commit
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    artifacts = $artifacts
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Build manifest: $OutputPath (source $commit)"
