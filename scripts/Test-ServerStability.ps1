param(
    [ValidateRange(1, 1440)][int]$Minutes = 10,
    [switch]$ActiveClientMode,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $base 'runtime'
$logs = Join-Path $runtime 'logs'
$reportDir = Join-Path $base 'docs\reports'
$report = Join-Path $reportDir 'ServerStabilityBaseline.md'
$startedHere = $false
New-Item -ItemType Directory -Force $reportDir | Out-Null

function Get-WorldProcess { Get-Process -Name wServer -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not (Get-WorldProcess)) {
    & "$PSScriptRoot\Start-All-Stable.ps1"
    $startedHere = $true
}
& "$PSScriptRoot\Health-Check.ps1"

$world = Get-WorldProcess
$start = Get-Date
$startCpu = $world.CPU
$startLog = if (Test-Path "$logs\runtime.log") { (Get-Item "$logs\runtime.log").Length } else { 0 }
$startStalls = if (Test-Path "$logs\stall-events.log") { (Get-Content "$logs\stall-events.log").Count } else { 0 }
if ($ActiveClientMode) { Write-Host 'Active-client mode: connect and play manually; no account actions are automated.' }
Start-Sleep -Seconds ($Minutes * 60)

$world = Get-WorldProcess
$end = Get-Date
$events = if (Test-Path "$logs\stall-events.log") { Get-Content "$logs\stall-events.log" | Select-Object -Skip $startStalls | ForEach-Object { $_ | ConvertFrom-Json } } else { @() }
$lateness = @($events | ForEach-Object { [double]$_.wakeLatenessMs } | Sort-Object)
function Percentile([double[]]$values, [double]$p) { if ($values.Count -eq 0) { return 0 }; return $values[[Math]::Min($values.Count - 1, [Math]::Floor(($values.Count - 1) * $p))] }
$runtimeGrowth = if (Test-Path "$logs\runtime.log") { (Get-Item "$logs\runtime.log").Length - $startLog } else { 0 }
$over100 = @($lateness | Where-Object { $_ -ge 100 }).Count
$over300 = @($lateness | Where-Object { $_ -ge 300 }).Count
$summary = @"
# Server Stability Test

- Started: $($start.ToString('O'))
- Ended: $($end.ToString('O'))
- Duration: $Minutes minute(s)
- Mode: $(if($ActiveClientMode){'manual active-client'}else{'idle'})
- Stall events: $($events.Count) ($over100 over 100 ms; $over300 over 300 ms)
- Wake lateness: average $(if($lateness.Count){'{0:N2}' -f (($lateness | Measure-Object -Average).Average)}else{'0'}) ms; p95 $(Percentile $lateness 0.95) ms; p99 $(Percentile $lateness 0.99) ms; max $(if($lateness.Count){$lateness[-1]}else{0}) ms
- Process CPU delta: $(if($world){'{0:N2}' -f ($world.CPU - $startCpu)}else{'n/a'}) s
- Working set: $(if($world){$world.WorkingSet64}else{'n/a'}) bytes
- Private memory: $(if($world){$world.PrivateMemorySize64}else{'n/a'}) bytes
- Thread count: $(if($world){$world.Threads.Count}else{'n/a'})
- Runtime log growth: $runtimeGrowth bytes

Records are sourced from runtime/logs/stall-events.log; no player account or Redis data was created or modified by this test.
"@
Set-Content -LiteralPath $report -Value $summary -Encoding UTF8
Write-Host "Report: $report"
if ($startedHere -and -not $KeepRunning) { & "$PSScriptRoot\Stop-All.ps1" }
