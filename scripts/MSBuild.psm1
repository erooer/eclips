Set-StrictMode -Version Latest

function Get-InstalledDotNetSdks {
    param([string]$DotNetRoot)
    if (!$DotNetRoot) {
        $dotnetCommand = Get-Command dotnet.exe -CommandType Application -ErrorAction SilentlyContinue
        if (!$dotnetCommand) { $dotnetCommand = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue }
        if ($dotnetCommand) { $DotNetRoot = Split-Path -Parent $dotnetCommand.Source }
        elseif ($env:ProgramFiles) { $DotNetRoot = Join-Path $env:ProgramFiles 'dotnet' }
    }
    if (!$DotNetRoot) { return @() }
    $resolvedRoot = [System.IO.Path]::GetFullPath($DotNetRoot)
    $dotnet = Join-Path $resolvedRoot 'dotnet.exe'
    $sdkRoot = Join-Path $resolvedRoot 'sdk'
    if (!(Test-Path -LiteralPath $dotnet -PathType Leaf) -or !(Test-Path -LiteralPath $sdkRoot -PathType Container)) { return @() }
    $sdks = foreach ($directory in Get-ChildItem -LiteralPath $sdkRoot -Directory) {
        $match = [regex]::Match($directory.Name, '^([0-9]+\.[0-9]+\.[0-9]+)')
        if (!$match.Success) { continue }
        [PSCustomObject]@{ Version = [version]$match.Groups[1].Value; Root = $directory.FullName; DotNet = $dotnet }
    }
    return @($sdks | Sort-Object Version -Descending)
}

function Get-NetStandardReferencePath {
    param([string]$PreferredSdkRoot, [string]$DotNetRoot)
    $sdkCandidates = @()
    if ($PreferredSdkRoot) { $sdkCandidates += $PreferredSdkRoot }
    $sdkCandidates += @(Get-InstalledDotNetSdks -DotNetRoot $DotNetRoot | ForEach-Object Root)
    foreach ($sdkRoot in $sdkCandidates | Select-Object -Unique) {
        $candidate = Join-Path $sdkRoot 'Microsoft\Microsoft.NET.Build.Extensions\net461\lib'
        if (Test-Path -LiteralPath (Join-Path $candidate 'netstandard.dll') -PathType Leaf) { return $candidate }
    }
    $gacRoot = Join-Path $env:windir 'Microsoft.NET\assembly\GAC_MSIL\netstandard'
    if (Test-Path -LiteralPath $gacRoot -PathType Container) {
        $gacDll = Get-ChildItem -LiteralPath $gacRoot -Filter netstandard.dll -File -Recurse | Select-Object -First 1
        if ($gacDll) { return $gacDll.DirectoryName }
    }
    return $null
}

function Assert-FrameworkBuildPrerequisites {
    param([string]$PreferredSdkRoot, [string]$DotNetRoot)
    $frameworkRoot = if (${env:ProgramFiles(x86)}) {
        Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework'
    } else {
        Join-Path $env:ProgramFiles 'Reference Assemblies\Microsoft\Framework\.NETFramework'
    }
    foreach ($version in @('v4.6', 'v4.7.2')) {
        $mscorlib = Join-Path $frameworkRoot "$version\mscorlib.dll"
        if (!(Test-Path -LiteralPath $mscorlib -PathType Leaf)) { throw ".NET Framework $version targeting pack was not found at $frameworkRoot." }
    }
    $netStandardPath = Get-NetStandardReferencePath -PreferredSdkRoot $PreferredSdkRoot -DotNetRoot $DotNetRoot
    if (!$netStandardPath) {
        throw 'netstandard compatibility reference was not found in Microsoft.NET.Build.Extensions\net461\lib or the Windows assembly cache.'
    }
    return $netStandardPath
}

function Test-MSBuildCandidate {
    param(
        [string]$Kind,
        [string]$MSBuildPath,
        [string]$DotNetPath,
        [string]$SdkRoot,
        [string]$DotNetRoot
    )
    if (!(Test-Path -LiteralPath $MSBuildPath -PathType Leaf)) { throw "file not found: $MSBuildPath" }
    $csharpTargets = Join-Path (Split-Path -Parent $MSBuildPath) 'Microsoft.CSharp.targets'
    if (!(Test-Path -LiteralPath $csharpTargets -PathType Leaf)) { throw "legacy C# build targets not found beside MSBuild: $csharpTargets" }
    if ($MSBuildPath.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase)) {
        if (!(Test-Path -LiteralPath $DotNetPath -PathType Leaf)) { throw "dotnet host not found: $DotNetPath" }
        $executable = $DotNetPath
        $prefix = @($MSBuildPath)
    } else {
        $executable = $MSBuildPath
        $prefix = @()
    }
    $versionOutput = @(& $executable @prefix -version -nologo 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($versionOutput -join "`n") -notmatch '\d+\.\d+') {
        throw "version probe failed for $MSBuildPath (exit code $LASTEXITCODE)."
    }
    $netStandardPath = Assert-FrameworkBuildPrerequisites -PreferredSdkRoot $SdkRoot -DotNetRoot $DotNetRoot
    return [PSCustomObject]@{
        Kind = $Kind
        Executable = [System.IO.Path]::GetFullPath($executable)
        ArgumentPrefix = @($prefix)
        MSBuildPath = [System.IO.Path]::GetFullPath($MSBuildPath)
        NetStandardReferencePath = $netStandardPath
        Version = (($versionOutput | Where-Object { $_ -match '^\s*\d+\.\d+' } | Select-Object -First 1) -as [string]).Trim()
    }
}

function Resolve-MSBuild {
    [CmdletBinding()]
    param(
        [string]$ExplicitPath,
        [string[]]$VsWherePaths,
        [string]$DotNetRoot,
        [switch]$IgnoreEnvironmentOverride,
        [switch]$SkipVsWhere,
        [switch]$SkipPath,
        [switch]$SkipDotNet
    )
    $searched = [System.Collections.Generic.List[string]]::new()
    $failures = [System.Collections.Generic.List[string]]::new()
    if (!$ExplicitPath -and !$IgnoreEnvironmentOverride) { $ExplicitPath = $env:ECLIPSE_MSBUILD_PATH }
    if ($ExplicitPath) {
        $searched.Add("ECLIPSE_MSBUILD_PATH/explicit: $ExplicitPath")
        try {
            $resolvedExplicit = [System.IO.Path]::GetFullPath($ExplicitPath)
            if ($resolvedExplicit.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase)) {
                $sdkRoot = Split-Path -Parent $resolvedExplicit
                $dotnetRootForExplicit = Split-Path -Parent (Split-Path -Parent $sdkRoot)
                return Test-MSBuildCandidate -Kind 'Explicit' -MSBuildPath $resolvedExplicit -DotNetPath (Join-Path $dotnetRootForExplicit 'dotnet.exe') -SdkRoot $sdkRoot -DotNetRoot $dotnetRootForExplicit
            }
            return Test-MSBuildCandidate -Kind 'Explicit' -MSBuildPath $resolvedExplicit -DotNetRoot $DotNetRoot
        } catch { throw "Explicit MSBuild override is unusable: $($_.Exception.Message)" }
    }

    if (!$SkipVsWhere) {
        if (!$VsWherePaths) {
            $VsWherePaths = @()
            if (${env:ProgramFiles(x86)}) { $VsWherePaths += Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe' }
            if ($env:ProgramFiles) { $VsWherePaths += Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe' }
        }
        foreach ($vswhere in $VsWherePaths | Select-Object -Unique) {
            $searched.Add("vswhere: $vswhere")
            if (!(Test-Path -LiteralPath $vswhere -PathType Leaf)) { continue }
            try {
                $installation = (& $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath).Trim()
                if (!$installation) { throw 'no matching Visual Studio/Build Tools installation returned.' }
                $candidate = Join-Path $installation 'MSBuild\Current\Bin\MSBuild.exe'
                return Test-MSBuildCandidate -Kind 'VisualStudio' -MSBuildPath $candidate -DotNetRoot $DotNetRoot
            } catch { $failures.Add("vswhere candidate failed: $($_.Exception.Message)") }
        }
    } else { $searched.Add('vswhere: skipped by caller') }

    if (!$SkipPath) {
        $searched.Add('PATH: msbuild.exe/msbuild')
        $command = Get-Command msbuild.exe -CommandType Application -ErrorAction SilentlyContinue
        if (!$command) { $command = Get-Command msbuild -CommandType Application -ErrorAction SilentlyContinue }
        if ($command) {
            try { return Test-MSBuildCandidate -Kind 'Path' -MSBuildPath $command.Source -DotNetRoot $DotNetRoot }
            catch { $failures.Add("PATH candidate failed: $($_.Exception.Message)") }
        }
    } else { $searched.Add('PATH: skipped by caller') }

    if (!$SkipDotNet) {
        $sdks = @(Get-InstalledDotNetSdks -DotNetRoot $DotNetRoot)
        if ($sdks.Count -eq 0) { $searched.Add('dotnet SDK: none found') }
        foreach ($sdk in $sdks) {
            foreach ($name in @('MSBuild.exe', 'MSBuild.dll')) {
                $candidate = Join-Path $sdk.Root $name
                $searched.Add("dotnet SDK $($sdk.Version): $candidate")
                if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
                try { return Test-MSBuildCandidate -Kind 'DotNetSdk' -MSBuildPath $candidate -DotNetPath $sdk.DotNet -SdkRoot $sdk.Root -DotNetRoot (Split-Path -Parent $sdk.DotNet) }
                catch { $failures.Add("dotnet SDK $($sdk.Version) candidate failed: $($_.Exception.Message)") }
            }
        }
    } else { $searched.Add('dotnet SDK: skipped by caller') }

    $detail = (($searched | ForEach-Object { "- $_" }) + ($failures | ForEach-Object { "- failure: $_" })) -join "`n"
    throw "No usable MSBuild installation was found. Searched:`n$detail"
}

Export-ModuleMember -Function Resolve-MSBuild
