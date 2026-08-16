function Get-NodeExecutable {
    $command = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        $command = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue
    }

    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source) -and (Test-Path -LiteralPath $command.Source)) {
        return $command.Source
    }

    # Windows' official installer uses this location. It is intentionally a
    # machine-wide fallback, never a user-specific or Codex runtime path.
    $programFilesNode = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'nodejs\node.exe' } else { $null }
    if ($programFilesNode -and (Test-Path -LiteralPath $programFilesNode)) {
        return $programFilesNode
    }

    throw 'Node.js is required but was not found on PATH or in the standard Program Files installation. Install Node.js and ensure the node executable is available before running this script.'
}
