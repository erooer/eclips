$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'build\air\CosmicRealms-Desktop\CosmicRealms.exe'
if (!(Test-Path $exe)) { & "$PSScriptRoot\Package-WindowsAirClient.ps1" }
$launcher = Join-Path $PSScriptRoot 'Launch-Client.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$shell = New-Object -ComObject WScript.Shell
$shortcutPaths = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cosmic Realms.lnk'),
    (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Cosmic Realms.lnk')
)
$legacyShortcut = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Eclipse Closed Alpha.lnk'
if (Test-Path -LiteralPath $legacyShortcut) { $shortcutPaths += $legacyShortcut }

foreach ($shortcutPath in $shortcutPaths) {
    New-Item -ItemType Directory -Force -Path (Split-Path $shortcutPath) | Out-Null
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
    $shortcut.WorkingDirectory = $root
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Description = 'Launch the verified current Cosmic Realms AIR client'
    $shortcut.Save()
    Write-Host "Canonical client shortcut: $shortcutPath -> $launcher"
}
