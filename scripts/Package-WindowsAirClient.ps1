$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root 'tools\flex-air-32.0'
$build = Join-Path $root 'build\air'
$descriptor = Join-Path $root 'Cosmic-Realms-main\Client-src\air\application.xml'
$private = Join-Path $root 'runtime\air\private'
$certificate = Join-Path $private 'cosmic-realms-dev.pfx'
$passwordFile = Join-Path $private 'cosmic-realms-dev.password.dpapi'
$bundle = Join-Path $build 'CosmicRealms-Desktop'
if (!(Test-Path "$build\CosmicRealmsAir.swf")) { & "$PSScriptRoot\Build-AirClient.ps1" }
if (!(Test-Path $certificate)) { & "$PSScriptRoot\Package-AirClient.ps1" }
$secure = Get-Content -LiteralPath $passwordFile -Raw | ConvertTo-SecureString
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
if (Test-Path $bundle) { Remove-Item -LiteralPath $bundle -Recurse -Force }
& "$sdk\bin\adt.bat" -package -storetype pkcs12 -keystore $certificate -storepass $plain -tsa none -target bundle $bundle $descriptor -C $build CosmicRealmsAir.swf client.json
if ($LASTEXITCODE -ne 0) { throw "Windows AIR bundle failed with exit code $LASTEXITCODE" }
Write-Host "Windows app: $bundle\CosmicRealms.exe"
