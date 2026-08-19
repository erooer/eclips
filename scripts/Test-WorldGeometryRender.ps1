param(
    [string]$ClientSwfPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\client-unchanged.swf')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root 'Cosmic-Realms-main\Client-src'
$sdk = Join-Path $root 'tools\flex-sdk-4.9.1'
$compiler = Join-Path $sdk 'bin\mxmlc.bat'
$playerGlobalHome = Join-Path $sdk 'frameworks\libs\player'
$projector = Join-Path $root 'tools\flashplayer_32_sa_debug.exe'
$probeSource = Join-Path $PSScriptRoot 'probes\WorldGeometryRenderProbe.as'
$buildInfo = & (Join-Path $PSScriptRoot 'New-ClientBuildInfo.ps1') -RepositoryRoot $root
$probeSwf = Join-Path ([IO.Path]::GetTempPath()) "WorldGeometryRenderProbe-$([guid]::NewGuid().ToString('N')).swf"
$flashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'

foreach ($required in @($compiler, $projector, $probeSource, $ClientSwfPath)) {
    if (!(Test-Path -LiteralPath $required)) { throw "World geometry render probe prerequisite is missing: $required" }
}

$squareSource = Get-Content -LiteralPath (Join-Path $project 'src\com\company\assembleegameclient\map\Square.as') -Raw
if ($squareSource -match 'lastVisible_\s*=\s*0') { throw 'Square face clipping can still clear anchored-object visibility.' }
$faceSource = Get-Content -LiteralPath (Join-Path $project 'src\com\company\assembleegameclient\engine3d\Face3D.as') -Raw
foreach ($edge in @('entirelyLeft', 'entirelyRight', 'entirelyAbove', 'entirelyBelow')) {
    if ($faceSource -notmatch $edge) { throw "Face3D is missing polygon/viewport edge rejection state: $edge" }
}

try {
    $env:PLAYERGLOBAL_HOME = $playerGlobalHome
    $savedErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $compilerOutput = & $compiler '-static-link-runtime-shared-libraries=true' "-source-path+=$($project)\src" "-source-path+=$($buildInfo.SourceRoot)" "-library-path+=$($project)\libs" "-output=$probeSwf" '-default-size=800,600' '-swf-version=15' '-target-player=15.0' $probeSource 2>&1
        $compilerExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorPreference
    }
    if ($compilerExitCode -ne 0 -or !(Test-Path -LiteralPath $probeSwf)) {
        $compilerOutput | Out-Host
        throw 'The real client software-render probe did not compile.'
    }
    $process = Start-Process -FilePath $projector -ArgumentList $probeSwf -PassThru -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $trace = ''
    do {
        Start-Sleep -Milliseconds 100
        if (Test-Path -LiteralPath $flashLog) {
            $stream = [IO.File]::Open($flashLog, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $reader = New-Object IO.StreamReader($stream)
                $trace = $reader.ReadToEnd()
            } finally { $stream.Dispose() }
        }
    } while ($trace -notmatch 'WORLD_GEOMETRY_RENDER_PROBE (?:PASS|FAIL)' -and
        !$process.HasExited -and [DateTime]::UtcNow -lt $deadline)
    if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
    if (!(Test-Path -LiteralPath $flashLog)) { throw 'Flash debug trace log was not produced by the render probe.' }
    if ($trace -notmatch 'WORLD_GEOMETRY_RENDER_PROBE (?:PASS|FAIL)') { throw 'The real client software-render probe timed out.' }
    if ($trace -notmatch 'WORLD_GEOMETRY_RENDER_PROBE PASS') { throw "The real software renderer did not complete all authored geometry cases.`n$trace" }
    foreach ($expected in @('Vault Wood Panel Wall 0x01e4 @ 52,60', 'Vault Wood Fence 0x193c @ 56,56', 'Nexus Guild Board 0x01e7 @ 86,170')) {
        if ($trace -notmatch [regex]::Escape($expected)) { throw "Render trace omitted authored object: $expected" }
    }
    Write-Host $trace.Trim()
    Write-Host "PASS: authored Vault/Nexus geometry reached the real Face3D software draw call and produced visible 800x600 pixels; production SWF SHA-256=$((Get-FileHash -LiteralPath $ClientSwfPath -Algorithm SHA256).Hash)"
} finally {
    if (Test-Path -LiteralPath $probeSwf) {
        # The standalone projector can retain its mapped SWF briefly after the
        # process exits. Cleanup is best-effort and must not hide the probe's real
        # assertion result.
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            try {
                Remove-Item -LiteralPath $probeSwf -Force -ErrorAction Stop
                break
            } catch {
                if ($attempt -eq 9) {
                    Write-Warning "Could not remove render-probe SWF after projector exit: $($_.Exception.Message)"
                } else {
                    Start-Sleep -Milliseconds (100 * ($attempt + 1))
                }
            }
        }
    }
}
