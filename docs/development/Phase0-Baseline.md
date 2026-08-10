# Eclipse Content + QoL Bible — Phase 0 Baseline

Recorded: 2026-08-10 12:18 America/Edmonton  
Source revision: `01bdaa9` on `main`

## Scope

This is a source and artifact baseline for the revised Eclipse Content + QoL
Bible. It records the systems that later phases must preserve. No gameplay
behavior was changed in Phase 0.

## Preserved systems

- Dungeon marks are physical consumables. `Player.UseItem.cs` routes the four
  existing mark activation effects to persisted account counters and gift-chest
  rewards. Marks are not a material wallet or Forge input.
- Potion Storage is a separate Vault system (`Vault.cs` and its existing
  command/UI path). It was not changed or redesigned.
- Reconnect safety uses a single-use reconnect record and token-owned Redis
  account-lock handoff. The static reconnect test confirms authorized
  Nexus/Vault, Nexus/Realm, and dungeon/Nexus handoffs while keeping ordinary
  duplicate logins rejected.
- The current Ominous Below world/map/resources and portal definition exist.
  The audit found that `The Haunted Omen` has no Ominous Below
  portal-on-death behavior yet; Phase 1 will add the required exactly-once
  server-authoritative route.

## Build and validation

The untouched server source rebuilt successfully with 0 compiler errors.

Static checks passed:

- `scripts/Test-ReconnectHandoff.ps1`
- `scripts/Test-TypeIdCollisions.ps1` — 6,657 unique object types; the
  Ominous reservation `0xF900`–`0xF921` is collision-free.
- `scripts/Test-OminousBelow.ps1` — map/objective/resource/return-portal
  checks passed (115 × 61 map, 7,015 assigned tiles, 23 behavior definitions).
- `scripts/Build-Server.ps1` — static validator reports 0 errors. The
  pre-existing validator warning inventory contains 1,555 legacy findings.

No services were started, no VPS was contacted, and no gameplay test was run.

## Artifact hashes after the Phase 0 rebuild

| Artifact | Source SHA-256 | Runtime SHA-256 |
|---|---|---|
| `server.exe` | `8A743675277820E9711B6F0B7A3417B602895A99D149223A5727C1BFFF1741A0` | `8A743675277820E9711B6F0B7A3417B602895A99D149223A5727C1BFFF1741A0` |
| `wServer.exe` | `2D4387BEE8288C5BEDB9C60DE8B3202E63F4D29EE93A246B7CE7822EF7AA06C1` | `2D4387BEE8288C5BEDB9C60DE8B3202E63F4D29EE93A246B7CE7822EF7AA06C1` |
| `common.dll` | `0D9CFD42673F8E28B2EE8BE4E57A86203A7C4B349DD827A69ACBB1FAA12DA9BA` | `0D9CFD42673F8E28B2EE8BE4E57A86203A7C4B349DD827A69ACBB1FAA12DA9BA` |

Client payload:

`build/client-unchanged.swf` — SHA-256
`92D5C6B1FFDB2DB09E7AB6EE8F3FE394043B0BD8BDA660EE5239C6B960CF39C5`

## Redis persistence audit

`runtime/redis.conf` remains loopback-only (`bind 127.0.0.1`, port 6379) and
uses `runtime/redis-data` with AOF enabled (`appendonly yes`,
`appendfsync everysec`) plus RDB snapshot rules (`save 900 1`, `save 300 10`,
`save 60 10000`).

The protected persistence directory exists and contains both expected formats:

- `appendonly.aof` — 7,103,032 bytes; last written 2026-08-07T02:49:21Z.
- `matching-rebuild.rdb` — 6,716 bytes; last written 2026-08-07T02:41:21Z.

No Redis key, schema, or persistence data was opened, changed, copied, or
restarted during this phase.
