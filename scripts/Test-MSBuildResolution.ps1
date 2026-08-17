$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MSBuild.psm1') -Force
$dotnetRoot = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'dotnet' } else { $null }

$dotnetOnly = Resolve-MSBuild -IgnoreEnvironmentOverride -SkipVsWhere -SkipPath -DotNetRoot $dotnetRoot
if ($dotnetOnly.Kind -ne 'DotNetSdk') { throw "Expected dotnet-SDK fallback, got $($dotnetOnly.Kind)." }
if (!(Test-Path -LiteralPath (Join-Path $dotnetOnly.NetStandardReferencePath 'netstandard.dll'))) { throw 'dotnet-SDK resolver omitted the net461 netstandard compatibility reference.' }

$previousOverride = $env:ECLIPSE_MSBUILD_PATH
try {
    $env:ECLIPSE_MSBUILD_PATH = $dotnetOnly.MSBuildPath
    $explicit = Resolve-MSBuild -DotNetRoot $dotnetRoot
    if ($explicit.Kind -ne 'Explicit' -or $explicit.MSBuildPath -ne $dotnetOnly.MSBuildPath) { throw 'ECLIPSE_MSBUILD_PATH did not take priority.' }
} finally {
    if ($null -eq $previousOverride) { Remove-Item Env:ECLIPSE_MSBUILD_PATH -ErrorAction SilentlyContinue }
    else { $env:ECLIPSE_MSBUILD_PATH = $previousOverride }
}

$vswhere = if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe' } else { $null }
if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
    $visualStudio = Resolve-MSBuild -IgnoreEnvironmentOverride -VsWherePaths @($vswhere) -SkipPath -SkipDotNet -DotNetRoot $dotnetRoot
    if ($visualStudio.Kind -ne 'VisualStudio') { throw "Expected Visual Studio/Build Tools resolution, got $($visualStudio.Kind)." }
    Write-Host "PASS: vswhere resolved $($visualStudio.MSBuildPath)"
} else {
    Write-Host 'SKIP: vswhere Visual Studio/Build Tools resolution (not installed in this environment).'
}

try {
    Resolve-MSBuild -IgnoreEnvironmentOverride -SkipVsWhere -SkipPath -SkipDotNet | Out-Null
    throw 'Missing-MSBuild fixture unexpectedly resolved a tool.'
} catch {
    foreach ($label in @('vswhere:', 'PATH:', 'dotnet SDK:')) {
        if ($_.Exception.Message -notmatch [regex]::Escape($label)) { throw "Missing-MSBuild error did not list $label search status." }
    }
}
Write-Host "PASS: dotnet-SDK fallback and missing-MSBuild diagnostics verified ($($dotnetOnly.Version))."
