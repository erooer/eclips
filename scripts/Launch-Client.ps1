[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$ProbeOnly,
    [ValidateRange(5, 60)][int]$StartupTimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root 'build\deployment-manifest.json'
$bundle = Join-Path $root 'build\air\CosmicRealms-Desktop'
$exe = Join-Path $bundle 'CosmicRealms.exe'
$airSwf = Join-Path $bundle 'CosmicRealmsAir.swf'
$descriptor = Join-Path $bundle 'META-INF\AIR\application.xml'
$configPath = Join-Path $bundle 'client.json'

if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'The production manifest is missing. Run scripts\Build-Everything.ps1 before launching the client.'
}

Import-Module (Join-Path $PSScriptRoot 'DeploymentArtifacts.psm1') -Force
$verified = Test-DeploymentManifest -RepositoryRoot $root
$sourceCommit = [string]$verified.SourceCommit
$shortCommit = $sourceCommit.Substring(0, 12)
$expectedTitle = "Cosmic Realms - $shortCommit"

foreach ($required in @($exe, $airSwf, $descriptor, $configPath)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Canonical AIR bundle is incomplete: $required" }
}

& (Join-Path $PSScriptRoot 'Test-AirClientBuildIdentity.ps1') `
    -AirSwfPath (Join-Path $root 'build\air\CosmicRealmsAir.swf') `
    -DesktopSwfPath $airSwf `
    -ExpectedSourceCommit $sourceCommit

[xml]$application = Get-Content -LiteralPath $descriptor -Raw
$namespace = New-Object Xml.XmlNamespaceManager($application.NameTable)
$namespace.AddNamespace('air', $application.DocumentElement.NamespaceURI)
$content = $application.SelectSingleNode('/air:application/air:initialWindow/air:content', $namespace).InnerText
if ($content -ne 'CosmicRealmsAir.swf') { throw "AIR descriptor launches an unexpected root SWF: $content" }

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$config.accountHost) -or [int]$config.accountPort -lt 1 -or [int]$config.accountPort -gt 65535) {
    throw 'Canonical AIR client contains an invalid account-server configuration.'
}

$swfHash = (Get-FileHash -LiteralPath $airSwf -Algorithm SHA256).Hash
Write-Host "PASS: canonical AIR client is $exe"
Write-Host "PASS: root SWF=$content SHA-256=$swfHash source=$sourceCommit server=$($config.accountHost):$($config.accountPort)"
if ($ValidateOnly) { return }

$logPath = Join-Path $env:APPDATA 'com.cosmicrealms.desktop\Local Store\logs\air-client.log'
$logOffset = if (Test-Path -LiteralPath $logPath) { (Get-Item -LiteralPath $logPath).Length } else { 0L }
$process = Start-Process -FilePath $exe -WorkingDirectory $bundle -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
$newLog = ''
$ready = $false

try {
    while ([DateTime]::UtcNow -lt $deadline -and !$process.HasExited) {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if (Test-Path -LiteralPath $logPath) {
            $stream = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                [void]$stream.Seek([Math]::Min($logOffset, $stream.Length), [IO.SeekOrigin]::Begin)
                $reader = New-Object IO.StreamReader($stream)
                try { $newLog = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
        }
        if ($newLog -match '\[FATAL_UNCAUGHT\]') { throw "AIR client reported a fatal startup error.`n$newLog" }
        if ($process.MainWindowTitle -eq $expectedTitle -and $newLog -match '\[AIR_BOOTSTRAP_READY\]') {
            $ready = $true
            break
        }
    }

    if ($process.HasExited) { throw "AIR client exited during startup with code $($process.ExitCode)." }
    if (!$ready) { throw "AIR client did not reach its bootstrap-ready marker within $StartupTimeoutSeconds seconds. Window title='$($process.MainWindowTitle)'." }
    Write-Host "PASS: launched '$expectedTitle' and reached AIR_BOOTSTRAP_READY (PID=$($process.Id))."
} catch {
    if ($ProbeOnly -and !$process.HasExited) { Stop-Process -Id $process.Id -Force }
    throw
}

if ($ProbeOnly -and !$process.HasExited) {
    Stop-Process -Id $process.Id -Force
    $process.WaitForExit()
}
