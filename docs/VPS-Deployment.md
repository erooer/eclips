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

`Start-All.ps1` uses `Cosmic-Realms-main\Server-src\bin` as its input. The deployment script therefore copies Git `runtime` server executables, DLLs/PDBs, and resources into that directory before restarting. It also copies `build\client-unchanged.swf` and hosted web resources.

Every copied file is SHA-256 checked. The server executable, world executable, `common.dll`, client SWF, and `EmbeddedData_EquipCXML.dat` are explicitly verified before restart.

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
