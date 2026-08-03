$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root 'tools\flex-air-32.0'
$build = Join-Path $root 'build\air'
$descriptor = Join-Path $root 'Cosmic-Realms-main\Client-src\air\application.xml'
$private = Join-Path $root 'runtime\air\private'
$certificate = Join-Path $private 'cosmic-realms-dev.pfx'
$passwordFile = Join-Path $private 'cosmic-realms-dev.password.dpapi'
if (!(Test-Path "$build\CosmicRealmsAir.swf")) { & "$PSScriptRoot\Build-AirClient.ps1" }
if (!(Test-Path "$sdk\bin\adt.bat")) { throw 'AIR SDK 32.0 is not installed.' }
New-Item -ItemType Directory -Force -Path $private | Out-Null
if (!(Test-Path $certificate)) {
    $plain = [Guid]::NewGuid().ToString('N')
    ConvertTo-SecureString $plain -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath $passwordFile -NoNewline
    & "$sdk\bin\adt.bat" -certificate -cn 'Cosmic Realms Development' -o 'Cosmic Realms Local' -c CA -validityPeriod 5 2048-RSA $certificate $plain
    if ($LASTEXITCODE -ne 0) { throw 'Could not create local AIR development certificate.' }
}
$secure = Get-Content -LiteralPath $passwordFile -Raw | ConvertTo-SecureString
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
& "$sdk\bin\adt.bat" -package -storetype pkcs12 -keystore $certificate -storepass $plain -tsa none -target air (Join-Path $build 'CosmicRealms.air') $descriptor -C $build CosmicRealmsAir.swf client.json
if ($LASTEXITCODE -ne 0) { throw "ADT package failed with exit code $LASTEXITCODE" }
Write-Host "Packaged $build\CosmicRealms.air"
