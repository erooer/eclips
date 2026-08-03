$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'build\air\CosmicRealms-Desktop\CosmicRealms.exe'
if (!(Test-Path $exe)) { & "$PSScriptRoot\Package-WindowsAirClient.ps1" }
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cosmic Realms.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = Split-Path $exe
$shortcut.Description = 'Cosmic Realms standalone AIR client'
$shortcut.Save()
Write-Host "Desktop shortcut: $shortcutPath"
