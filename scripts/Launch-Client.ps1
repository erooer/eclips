$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$projector = Join-Path $base 'tools\flashplayer_32_sa_debug.exe'
$buildSwf = Join-Path $base 'build\client-unchanged.swf'
$swf = Join-Path $base 'runtime\resources\web\rotmg.swf'
if (!(Test-Path $projector)) { throw "Missing Flash debug projector: $projector" }
if (!(Test-Path $buildSwf)) { throw "Missing rebuilt client SWF: $buildSwf. Run Build-Client.ps1 first." }
New-Item -ItemType Directory -Force (Split-Path -Parent $swf) | Out-Null
Copy-Item -LiteralPath $buildSwf -Destination $swf -Force
$buildHash = (Get-FileHash -LiteralPath $buildSwf -Algorithm SHA256).Hash
$servedHash = (Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash
if ($buildHash -ne $servedHash) { throw "SWF deployment verification failed: $swf does not match $buildSwf" }
$buildId = (Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash.Substring(0, 12)
$url = "http://127.0.0.1/rotmg.swf?Host=127.0.0.1&env=production&deployment=Production&build=$buildId"
Start-Process -FilePath $projector -ArgumentList $url -WorkingDirectory (Join-Path $base 'runtime')
"Launched rebuilt SWF: $swf ($buildId)"
"Source build SWF: $buildSwf"
"URL: $url"
