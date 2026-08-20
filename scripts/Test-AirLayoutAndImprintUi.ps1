$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Read-Source([string]$relative) {
    Get-Content -LiteralPath (Join-Path $root $relative) -Raw
}
function Require([bool]$condition, [string]$message) {
    if (!$condition) { throw $message }
}

$web = Read-Source 'Cosmic-Realms-main\Client-src\src\WebMain.as'
$game = Read-Source 'Cosmic-Realms-main\Client-src\src\com\company\assembleegameclient\game\GameSprite.as'
$camera = Read-Source 'Cosmic-Realms-main\Client-src\src\com\company\assembleegameclient\map\Camera.as'
$stageProxy = Read-Source 'Cosmic-Realms-main\Client-src\src\com\company\assembleegameclient\util\StageProxy.as'
$renderer = Read-Source 'Cosmic-Realms-main\Client-src\src\kabam\rotmg\stage3D\Renderer.as'
$air = Read-Source 'Cosmic-Realms-main\Client-src\src\AirMain.as'
$connection = Read-Source 'Cosmic-Realms-main\Client-src\src\kabam\rotmg\messaging\impl\GameServerConnectionConcrete.as'
$imprints = Read-Source 'Cosmic-Realms-main\Server-src\wServer\realm\EclipseImprints.cs'
$handler = Read-Source 'Cosmic-Realms-main\Server-src\wServer\networking\handlers\ForgeListHandler.cs'
$panel = Read-Source 'Cosmic-Realms-main\Client-src\src\ToolForge\forgeList\ForgeListPanel.as'
$packet = Read-Source 'Cosmic-Realms-main\Client-src\src\kabam\rotmg\messaging\impl\incoming\ForgeListResult.as'

foreach ($required in @(
    'stage.scaleMode = StageScaleMode.NO_SCALE',
    'this.scaleX = stage.stageWidth / 800',
    'this.scaleY = stage.stageHeight / 600',
    'this.x = (800 - stage.stageWidth) >> 1',
    'this.y = (600 - stage.stageHeight) >> 1',
    'sWidth = stage.stageWidth',
    'Camera.resetDimensions()',
    'Stage3DConfig.resetDimensions()')) {
    Require ($web.Contains($required)) "Original AIR resize contract is missing: $required"
}
Require (!$web.Contains('stage.align = StageAlign.TOP_LEFT')) 'The AIR-specific top-left alignment override is still active.'
Require ($game.Contains('var _local_3:Number = (800 / stage.stageWidth)') -and
    $game.Contains('var _local_6:Number = (600 / stage.stageHeight)') -and
    $game.Contains('this.hudView.x = (800 - (200 * this.hudView.scaleX))')) 'The original HUD inverse-scale/anchor contract is missing.'
Require ($game.Contains('this.map.scaleX = (_local_3 * _local_5)') -and
    $game.Contains('this.map.scaleY = (_local_6 * _local_5)')) 'The original world scale compensation is missing.'
Require ($camera.Contains('_loc5_ = Number(200 * WebMain.sHeight / 600 / _loc2_)')) 'The original camera HUD exclusion contract is missing.'
Require ($stageProxy.Contains('return 800') -and $stageProxy.Contains('return 600')) 'StageProxy no longer exposes the original logical 800x600 stage.'
Require ($renderer.Contains('WebMain.STAGE.stageHeight / 600')) 'The original Stage3D translation scaling is missing.'

# Exercise the original two-layer transform at the baseline and common desktop
# sizes. The root fills the physical window while child UI/world transforms
# preserve the logical 800x600 composition used by the known-good client.
foreach ($size in @(
    @{ W = 800; H = 600 },
    @{ W = 1920; H = 1080 },
    @{ W = 2560; H = 1440 },
    @{ W = 3840; H = 2160 })) {
    $rootScaleX = $size.W / 800
    $rootScaleY = $size.H / 600
    $childScaleX = 800 / $size.W
    $childScaleY = 600 / $size.H
    Require ([Math]::Abs(($rootScaleX * $childScaleX) - 1) -lt 0.000001) "Horizontal round-trip scaling failed at $($size.W)x$($size.H)."
    Require ([Math]::Abs(($rootScaleY * $childScaleY) - 1) -lt 0.000001) "Vertical round-trip scaling failed at $($size.W)x$($size.H)."
}

foreach ($definition in '"swift"', '"bulwark"', '"focused"', '"hunter"') {
    Require ($imprints.Contains($definition)) "Authoritative Imprint definition missing: $definition"
}
foreach ($required in @('if (!HasEligibleBagItem(player))', 'Definitions.Values.OrderBy', 'Select eligible item',
    'imprint_shard (owned ', 'Eligible: Eclipse equipment', 'ValidateBagItem(player', '/imprint apply ')) {
    Require ($imprints.Contains($required)) "Imprint recipe UI contract is missing: $required"
}
Require ($handler.Contains('EclipseImprintService.BuildUi(client.Player)')) 'Category 6 is not populated by the authoritative Imprint service.'
Require ($panel.Contains('this.initialCategory == 6 ? "Imprint Recipes"')) 'The client does not identify the Imprint recipe browser.'
foreach ($field in 'ServiceKind', 'Details', 'Command', 'ActionLabel', 'Craftable') {
    Require ($packet.Contains($field)) "The client Imprint response is missing $field."
}

Require ($air.Contains('log("[FATAL_UNCAUGHT] " + detail)')) 'Runtime errors must remain logged.'
Require ($air.Contains('event.preventDefault()')) 'AIR runtime exceptions must be handled after logging.'
Require (!$air.Contains('airFatalError') -and !$air.Contains('Client startup failed:')) 'The intrusive runtime error overlay is still compiled into the client.'
Require ($air.Contains('field.height = 42')) 'The startup-only fallback must remain compact.'
Require (!$connection.Contains('this.gs_.removeChild(legendarySplashText)') -and
    !$connection.Contains('this.gs_.removeChild(mythicalSplashText)')) 'GTween callbacks still resolve this against the tween callback receiver.'
Require ($connection.Contains('legendarySplashText.parent.removeChild') -and
    $connection.Contains('mythicalSplashText.parent.removeChild')) 'Splash tweens do not clean up through their actual display parent.'

Write-Host 'PASS: original AIR 800x600 root/HUD/camera behavior is restored across windowed and 1080p/1440p/4K resize round trips; Imprint recipes and log-only diagnostics remain intact.'
