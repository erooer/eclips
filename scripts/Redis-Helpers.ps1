# Shared Redis command helpers. Native redis-cli failures are captured as data so
# a temporary connection refusal cannot become a terminating PowerShell error.

function Invoke-RedisCli {
    param(
        [Parameter(Mandatory = $true)][string]$RedisCli,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    if (!(Test-Path -LiteralPath $RedisCli -PathType Leaf)) {
        throw "Missing redis-cli.exe: $RedisCli"
    }

    $output = @()
    $exitCode = $null
    try {
        $output = @(& $RedisCli @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    catch {
        # PowerShell 7 can promote non-zero native exit codes when the caller uses
        # $ErrorActionPreference = 'Stop'. The executable path was validated above,
        # so preserve the failure as a non-terminating command result instead.
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            $output = @($_)
        }
        else {
            throw
        }
    }

    [PSCustomObject]@{
        ExitCode = $exitCode
        Output = $output
        Text = ($output -join [Environment]::NewLine).Trim()
    }
}

function Test-RedisPong {
    param([Parameter(Mandatory = $true)][string]$RedisCli)

    $result = Invoke-RedisCli -RedisCli $RedisCli -Arguments @('-h', '127.0.0.1', '-p', '6379', 'PING')
    return $result.ExitCode -eq 0 -and $result.Text -ceq 'PONG'
}

function Wait-ForRedisPong {
    param(
        [Parameter(Mandatory = $true)][string]$RedisCli,
        [int]$TimeoutSeconds = 30,
        [int]$PollMilliseconds = 250
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-RedisPong -RedisCli $RedisCli) {
            return $true
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ((Get-Date) -lt $deadline)

    return $false
}
