param(
    [ValidateSet('all','maps','resources','behaviors','portals','types','performance','dungeons')]
    [string]$Scope = 'all',
    [string]$Report,
    [switch]$ReportOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Resolve-Node.ps1')
$node = Get-NodeExecutable
$arguments = @((Join-Path $root 'tools\DungeonValidator\index.js'), '--scope', $Scope)
if ($Report) { $arguments += @('--report', $Report) }
if ($ReportOnly) { $arguments += '--report-only' }
& $node @arguments
if ($LASTEXITCODE -ne 0) { throw "Static validation failed for scope '$Scope'." }
