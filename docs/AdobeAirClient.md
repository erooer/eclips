# Cosmic Realms Adobe AIR client

The desktop target is compiled directly from shared `Client-src`; it is not an HTML wrapper. The existing projector/browser SWF remains `build/client-unchanged.swf`.

## Toolchain

AIR SDK 15 was attempted first, but Adobe's retired URL returned HTML rather than an SDK archive. The selected isolated toolchain is Adobe AIR SDK **32.0** overlaid on a copied Apache Flex **4.9.1** installation at `tools/flex-air-32.0`. Java 8 remains the compiler runtime. The original Flex SDK is untouched.

## Commands

```powershell
./scripts/Build-AirClient.ps1
./scripts/Launch-AirClient.ps1
./scripts/Package-AirClient.ps1
./scripts/Build-All-Clients.ps1
./scripts/Start-All-Air.ps1
```

`Build-AirClient.ps1` produces `build/air/CosmicRealmsAir.swf`. `Package-AirClient.ps1` produces the signed local-development package `build/air/CosmicRealms.air`. The private development certificate and its DPAPI-protected password are under `runtime/air/private` and are not source-controlled.

## Configuration and logs

Edit `runtime/air/client.json` before building. It contains only host/port/environment settings; never store credentials there. The build copies it beside the AIR SWF. AIR startup writes to `runtime/air/logs/air-client.log` when that configured path is writable, otherwise its AIR application-storage fallback is `%APPDATA%/com.cosmicrealms.desktop/Local Store/logs/air-client.log`.

AIR uses the same HTTP account service, world socket, Flash policy service, resource inventory, packet map, and Redis-backed accounts as the SWF. Redis data/schema are not changed.

## Restore and troubleshooting

The pre-AIR snapshot is in `backups/before-adobe-air-20260729-172352`; the Git baseline tag is `baseline-before-adobe-air-20260729-172304`. To roll back source, switch to that tag or restore the snapshot, then use `scripts/Build-Client.ps1` and `Launch-Client.ps1` as before.

If AIR does not start, rebuild the AIR target, verify `client.json`, run `Health-Check.ps1`, and inspect the AIR log. Close it normally to let the normal socket timeout release server-side state. Manual validation remains required for login, character selection, Nexus, movement, combat, consumables, portals, dungeon transition, reconnect, and close/relaunch.
