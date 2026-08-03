param(
    [ValidateSet('all','maps','resources','behaviors','portals','types','performance','dungeons')]
    [string]$Scope = 'all',
    [string]$Report,
    [switch]$ReportOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$candidates = @(@(
    (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    'C:\Users\erooe\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
) | Where-Object { $_ -and (Test-Path $_) })
if (!$candidates) { throw 'Node.js is required for static validation but was not found.' }
$arguments = @((Join-Path $root 'tools\DungeonValidator\index.js'), '--scope', $Scope)
if ($Report) { $arguments += @('--report', $Report) }
if ($ReportOnly) { $arguments += '--report-only' }
& $candidates[0] @arguments
if ($LASTEXITCODE -ne 0) { throw "Static validation failed for scope '$Scope'." }
