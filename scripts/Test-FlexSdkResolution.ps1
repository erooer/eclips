$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'FlexSdk.psm1'
Import-Module $module -Force
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "eclipse-flex-resolution-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $missingRoot = Join-Path $testRoot 'missing-repository'
    New-Item -ItemType Directory -Path $missingRoot | Out-Null
    try {
        Resolve-FlexSdk -RepositoryRoot $missingRoot -SkipJavaValidation | Out-Null
        throw 'Missing toolchain resolution unexpectedly succeeded.'
    } catch {
        if ($_.Exception.Message -notmatch 'Provision-FlexSdk\.ps1') { throw }
    }

    $repository = Join-Path $testRoot 'portable-repository'
    $sdk = Join-Path $repository 'tools\flex-sdk-4.9.1'
    foreach ($directory in @('bin', 'lib', 'frameworks', 'frameworks\libs\player\15.0')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $sdk $directory) | Out-Null
    }
    $fixtures = [ordered]@{
        'NOTICE' = 'Apache Flex fixture'
        'bin\mxmlc.bat' = '@echo fixture'
        'lib\mxmlc.jar' = 'fixture jar'
        'frameworks\flex-config.xml' = '<flex-config />'
        'frameworks\libs\player\15.0\playerglobal.swc' = 'fixture playerglobal'
    }
    foreach ($entry in $fixtures.GetEnumerator()) {
        [System.IO.File]::WriteAllText((Join-Path $sdk $entry.Key), $entry.Value, [Text.UTF8Encoding]::new($false))
    }
    $mxmlcHash = (Get-FileHash -LiteralPath (Join-Path $sdk 'bin\mxmlc.bat') -Algorithm SHA256).Hash
    $playerHash = (Get-FileHash -LiteralPath (Join-Path $sdk 'frameworks\libs\player\15.0\playerglobal.swc') -Algorithm SHA256).Hash
    $resolved = Resolve-FlexSdk -RepositoryRoot $repository -SkipJavaValidation -ExpectedMxmlcSha256 $mxmlcHash -ExpectedPlayerGlobalSha256 $playerHash
    if ($resolved.Root -ne [System.IO.Path]::GetFullPath($sdk)) { throw "Portable repository resolution returned the wrong SDK root: $($resolved.Root)" }
    if ($resolved.Mxmlc -ne (Join-Path ([System.IO.Path]::GetFullPath($sdk)) 'bin\mxmlc.bat')) { throw 'Portable mxmlc resolution returned the wrong launcher.' }
    Write-Host 'PASS: missing Flex toolchain fails clearly and a repo-relative compiler resolves successfully.'
} finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (!$resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing unsafe test cleanup path: $resolvedTestRoot" }
    if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
