# Eclipse VPS deployment

Run the deployment script **on the VPS** in an elevated PowerShell window. It deploys from `C:\Eclipse-Git\eclips` to `C:\Eclipse\rebuild-original\rebuild-original`.

## Commands

Normal deployment:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& 'C:\Eclipse-Git\eclips\scripts\Deploy-VPS.ps1'
```

Dry run (preflight and plan only; does not pull, stop, copy, or restart):

```powershell
& 'C:\Eclipse-Git\eclips\scripts\Deploy-VPS.ps1' -WhatIf
```

Redeploy the current checkout without fetching/pulling:

```powershell
& 'C:\Eclipse-Git\eclips\scripts\Deploy-VPS.ps1' -SkipPull
```

Copy and verify files without stopping or restarting the live stack:

```powershell
& 'C:\Eclipse-Git\eclips\scripts\Deploy-VPS.ps1' -NoRestart
```

## What is deployed

After pulling, the deployment script creates a disposable detached Git worktree
at the exact new `HEAD`, runs `Build-Everything.ps1` there, and validates the
resulting commit-bound SHA-256 manifest. This entire build happens before the
live stack is stopped. A missing compiler, failed validation, failed server or
client build, mismatched SWF copy, or stale manifest therefore leaves the live
services untouched.

The checksum-verified Flex SDK is cached outside the disposable worktree at
`C:\Eclipse-Git\eclips\tools\flex-sdk-4.9.1`. It is ignored by Git and can be
pre-provisioned with `scripts\Provision-FlexSdk.ps1`.

`Start-All.ps1` uses `Cosmic-Realms-main\Server-src\bin` as its input. The deployment script therefore copies only the isolated current-HEAD build's `Cosmic-Realms-main\Server-src\bin` executables, DLLs/PDBs, and resources into the live `Server-src\bin` before restarting. It also copies that build's `build\client-unchanged.swf` and refreshes the live runtime web root from the same freshly built resource set.

`runtime` is deliberately not used as a deployment source: it is a generated execution directory which `Start-All.ps1` refreshes from `Server-src\bin` each time the stack starts.

Every copied file is SHA-256 checked. The server executable, world executable, `common.dll`, all three client SWF copies, and `EmbeddedData_EquipCXML.dat` are bound to current `HEAD` in the manifest and explicitly verified before restart. Building in a disposable worktree also prevents tracked generated artifacts from dirtying the primary VPS checkout and blocking the next pull.

For compatibility with a checkout dirtied by the old in-place build, the
deployer may restore tracked changes only under its explicit generated-output
allowlist before the first pull. It refuses staged changes, untracked files,
source changes, and runtime configuration changes; those are never discarded.

## Preserved VPS data and configuration

The script does not copy, delete, or restore these live paths from Git:

- `runtime\redis-data`
- `runtime\redis-backups`
- `runtime\logs`
- `runtime\redis.conf`
- `runtime\server.json`
- `runtime\wServer.json`
- `runtime\air\client.json`
- `runtime\processes.json`

Redis persistence files are inventoried with size and SHA-256 before deployment, but are not backed up or copied as part of this release operation.

## Rollback

Before changing files, a timestamped backup is created below:

`C:\Eclipse\rebuild-original\rebuild-original\deployment-backups\<timestamp>`

It includes the live server-bin input, client SWF, runtime binaries/resources, and a copy of VPS configuration files. If copying, verification, startup, or health checks fail, the script stops Eclipse-owned processes, restores that backup, restarts the previous version, and checks Redis/ports/HTTP again. It never stops same-named processes outside the live Eclipse paths.

## Logs and deployed version

Each deployment writes a transcript to:

`C:\Eclipse\deployment-logs\deploy-<timestamp>.log`

The deployed commit is written to:

`C:\Eclipse\rebuild-original\rebuild-original\runtime\deployed-version.txt`

Verify it with:

```powershell
Get-Content 'C:\Eclipse\rebuild-original\rebuild-original\runtime\deployed-version.txt'
```
