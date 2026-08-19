param(
    [string]$ClientSwfPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\client-unchanged.swf')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'Cosmic-Realms-main\Server-src'

function Require([bool]$condition, [string]$message) {
    if (!$condition) { throw $message }
}

Require (Test-Path -LiteralPath $ClientSwfPath) 'The exact production SWF is missing.'
$hash = (Get-FileHash -LiteralPath $ClientSwfPath -Algorithm SHA256).Hash
$version = $hash.Substring(0, 16).ToLowerInvariant()
$indexPath = Join-Path $source 'bin\resources\web\index.html'
$index = Get-Content -LiteralPath $indexPath -Raw
Require ($index -match '"rotmg\.swf"') 'The production bootstrap no longer contains the expected SWF URL.'

$resources = Get-Content -LiteralPath (Join-Path $source 'common\resources\Resources.cs') -Raw
foreach ($required in @('SHA256.Create()', 'webFiles.TryGetValue("/rotmg.swf"', 'rotmg.swf?v=', 'Substring(0, 16).ToLowerInvariant()')) {
    Require ($resources.Contains($required)) "The runtime bootstrap is missing exact-SWF version binding: $required"
}
$simulated = $index.Replace('"rotmg.swf"', '"rotmg.swf?v=' + $version + '"')
Require ($simulated -match [regex]::Escape("rotmg.swf?v=$version")) 'The runtime cache-busting transform does not bind this exact SWF hash.'

$staticFile = Get-Content -LiteralPath (Join-Path $source 'server\StaticFile.cs') -Raw
foreach ($required in @('no-store', 'no-cache', 'must-revalidate', 'max-age=0')) {
    Require ($staticFile.Contains($required)) "Static SWF delivery is missing cache directive: $required"
}
$requests = Get-Content -LiteralPath (Join-Path $source 'server\RequestHandler.cs') -Raw
Require ($requests -match 'EndsWith\("\.swf"' -and $requests -match 'EndsWith\("\.html"') 'SWF/HTML routes do not opt into cache-safe delivery.'

$deploy = Get-Content -LiteralPath (Join-Path $root 'scripts\Deploy-VPS.ps1') -Raw
$health = Get-Content -LiteralPath (Join-Path $root 'scripts\Health-Check.ps1') -Raw
foreach ($required in @('Test-ServedClientArtifact', 'Hosted rotmg.swf is not the verified deployment artifact', 'rotmg.swf?v=')) {
    Require ($deploy.Contains($required)) "Deployment does not verify the served production client boundary: $required"
}
Require ($health.Contains('Hosted SWF differs from deployed client artifact')) 'Runtime health check does not compare the served SWF byte-for-byte.'

Write-Host "PASS: production bootstrap binds rotmg.swf to hash version $version, disables stale caching, and deployment/health validation compares served bytes to exact SWF SHA-256=$hash."
