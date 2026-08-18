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

After pulling, the deployment script validates the checked-in production
artifact bundle. It does not compile code and does not require Java, Flex,
PlayerGlobal, MSBuild, Visual Studio, or .NET targeting packs on the VPS.
Manifest identity, the complete artifact inventory, SHA-256 hashes, protocol
compatibility, and compiled Type ID resources are checked before backup or
service stop. Any failure therefore leaves the live services untouched.
Before those checks, the deployer materializes the manifest and every artifact
from the selected commit's Git blobs into an isolated temporary staging tree.
Raw blob streams are written without PowerShell text decoding or Git checkout
conversion, then SHA-256 verified. All server/client deployment copies use this
staging tree, so `core.autocrlf`, stale or manually altered working files,
assume-unchanged state, and old generated output cannot change deployed bytes.
Source files and live configuration are not staged or touched by this step.

`Start-All.ps1` uses `Cosmic-Realms-main\Server-src\bin` as its input. The deployment script therefore copies only the verified current-HEAD bundle's `Cosmic-Realms-main\Server-src\bin` executables, DLLs/PDBs, and resources into the live `Server-src\bin` before restarting. It also copies that bundle's `build\client-unchanged.swf` and refreshes the live runtime web root from the same verified resource set.

`runtime` is deliberately not used as a deployment source: it is a generated execution directory which `Start-All.ps1` refreshes from `Server-src\bin` each time the stack starts.

Every deployable server DLL/PDB and compiled resource, plus `server.exe`,
`wServer.exe`, and the client SWF, is tracked and SHA-256 checked. The manifest's
source commit must be the exact parent of current HEAD, current HEAD may contain
only the manifest and allowlisted artifacts, and the build/server web SWFs must
match. This prevents partial or stale server, world, client, and resource sets.

The complete workflow is:

```text
PC:  commit source -> Build-Everything.ps1 -> validate -> commit artifact bundle -> push
VPS: git pull -> Deploy-VPS.ps1
```

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
