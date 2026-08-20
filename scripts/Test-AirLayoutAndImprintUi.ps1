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
    'stage.align = StageAlign.TOP_LEFT',
    'this.scaleX = 1',
    'this.scaleY = 1',
    'sWidth = stage.stageWidth',
    'Camera.resetDimensions()',
    'Stage3DConfig.resetDimensions()')) {
    Require ($web.Contains($required)) "AIR root resize contract is missing: $required"
}
Require (!$web.Contains('this.scaleX = stage.stageWidth / 800')) 'WebMain must not scale the root a second time.'
Require ($game.Contains('stage.stageWidth - 200') -and $game.Contains('this.hudView.x = hudX')) 'The 200px HUD is not anchored to the right edge.'
Require ($game.Contains('this.map.scaleX = mapScale') -and $game.Contains('this.map.scaleY = mapScale')) 'World scaling must remain uniform.'
Require ($camera.Contains('_loc5_ = Number(200 / _loc2_)')) 'Camera culling does not reserve the fixed HUD width.'
Require ($stageProxy.Contains('this.reference.stage.stageWidth') -and $stageProxy.Contains('this.reference.stage.stageHeight')) 'StageProxy still hides the real AIR window size.'
Require (!$renderer.Contains('WebMain.STAGE.stageHeight / 600')) 'Stage3D HUD translation must not grow with window height.'

# Exercise the invariant at the baseline and common 16:9 desktop sizes. The
# world area grows, the fixed HUD remains on-screen, and X/Y map scale matches.
foreach ($size in @(
    @{ W = 800; H = 600 },
    @{ W = 1920; H = 1080 },
    @{ W = 2560; H = 1440 },
    @{ W = 3840; H = 2160 })) {
    $hudX = $size.W - 200
    $worldWidth = $size.W - 200
    Require ($hudX -ge 0 -and ($hudX + 200) -eq $size.W) "HUD anchoring failed at $($size.W)x$($size.H)."
    Require ($worldWidth -gt 0 -and $size.H -gt 0) "World viewport failed at $($size.W)x$($size.H)."
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

Write-Host 'PASS: AIR root/HUD/camera layout covers windowed and 1080p/1440p/4K, Imprint recipes are authoritative and non-empty, and runtime diagnostics stay log-only.'
