# Eclipse Implementation-Depth Audit

Audited from the current `main` working tree on 2026-08-13. This document classifies only code paths that have a server runtime entry point; it does not treat XML, a command declaration, or a source-text test as proof of playable behavior.

## Phase 0–4

| Phase / commits | Runtime wiring and persistence | Tests actually run | Status |
|---|---|---|---|
| 0 `6c4f563` | Baseline documentation. | None. | **STATIC/FOUNDATION ONLY** |
| 1–3 `47a255f`, `0b3d88d`, `170aa0a` | Haunted Omen’s death behavior opens the Ominous portal; Ominous mark uses the existing consumable LegendaryMarks flow. | Static validators. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 4 `143344f` | Ominous world/behavior polish. | Static map/behavior validation. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |

## Phase 5–10

| Phase / commits | Runtime wiring and persistence | Remaining limits | Status |
|---|---|---|---|
| 5 `69e3524` Contracts | `/contracts`; account `ContractState`; mark-consumption hook in `Player.UseItem`. | Command/replay behavior has no executable integration test. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 6 `9d71976` Codex | `/codex`; `DungeonCodexState`; completion/death callbacks from `World`; party-time fields are updated by party state. | Requires manual boss-clear verification. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 7 `7e1a7d5` Materials | `/materials`; account `MaterialVaultState`; server idempotency ledger. | No live request test. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 8 `ceed000` Sigils, `10cd948` | `/sigils`; account `DungeonSigilState`; one temporary Nexus portal is created and charged only on readiness; party receives a same-Nexus marker/readout. | Party/Sigil test is source-level; portal/reconnect needs manual testing. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 9 `2652edc` Forge | `/forge`; account `ForgeState`; Material Vault spend. | Uses legacy type inventory; Imprint metadata remains disabled. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 10 `5adb885`, `c3015c9`, `01d4673` | Realm activity/threshold hooks; featured date rotation; XP multiplier in `Player.Leveling`; rare-loot multiplier in `Loots`; first clear awards from `FeaturedDungeonService`. | Threat encounters remain reused/generic and need live validation. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |

## Phase 11–15 dungeon/runtime content

| Phase / commits | Runtime wiring and persistence | Placeholder/minimal pieces | Status |
|---|---|---|---|
| 11 `9d09391`, `5ba192c`, `25bd07f` Sunken Reliquary | Natural portal drop; dynamic world constructor spawns Reliquary entities/pearls/Nacre Warden; Codex completion and mark paths use shared systems; Anomaly attach. | Uses shared `SP_Horde.jm`, scripted spawn positions, and reused textures rather than a bespoke three-cluster map. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 12 `6fa24ef`, `25bd07f` Anomalies | Runtime anomaly state attaches to supported new worlds; HP modifier applies at spawn and state is cleaned at world completion. | No interception of all legacy natural portals; modifier/reward pool remains narrow. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 13 `9a7071f`, `93c9a30`, `485b3f0`, `10cd948` Parties | `/party`, `/p`; persisted `PartyState`, roster, invite expiry; reconstructs on create/load; safe `/party join` invokes normal reconnect; same-Nexus Sigil marker. | Disconnect intentionally preserves party for reconnect; no client party panel. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 14 `4439497`, `5ba192c` Ashen Foundry | Natural portal drop; constructor spawns guards, Overseer, three vents, Iron Sun; shared Codex/mark/reward hooks. | Shared map and scripted locations; no final forge art/room layout. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 15 `12e79d8`, `5ba192c` Starfall Observatory | Natural portal drop; deterministic two-wing selection, wing/seal spawns, Parallax spawn and a small selected-wing HP influence; shared progression hooks. | Shared map; Parallax influence is minimal rather than a rich mechanic set. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |

## Phase 16–18B

| Phase / commits | Runtime wiring and persistence | Remaining limits | Status |
|---|---|---|---|
| 16 `a50c7f8`, `ba54507`, `31f3490` History/Mastery/Guild/Boards | Permanent death calls `RecordDeath`; bounded account recap/Mastery state; weekly Redis sorted-set boards with per-account idempotency; guild `EclipseProgressState` stores trophy and weekly-clear state; `/mastery`, `/history`, `/leaderboard`, `/guildprogress`. | Leaderboard display uses account IDs; cosmetic title/frame presentation is not implemented. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 17 `7e5cf81` Custom Stat Audit | Documentation/static audit only. | No new stat system was enabled, intentionally. | **STATIC/FOUNDATION ONLY** |
| 18A `c2c9151`, `57a9b09` Item records | Additive `RInventory` record ledger, legacy migration, persisted inventory/vault swap hooks. | Duplicate identical object types have deterministic but not client-visible instance selection. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |
| 18B `6f329d1`, `f8ec5cf` Transfers | INVSWAP covers character/vault/ground containers; InvDrop moves identity into a transient bag; pickup returns it; trade maps existing records before snapshots save. Gift Chest has no persistent record array in its native gift schema, so legacy gift entries mint an identity on first withdrawal rather than retaining a pre-existing one. | No distributed Redis transaction across two account hashes; failed second persistent write is logged/rejected but is not a true multi-key atomic rollback. Imprints remain disabled. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION** |

## Tests and validation evidence

The server project builds with **0 errors**. `Test-Parties.ps1`, `Test-AccountProgression.ps1`, and `Test-ItemInstances.ps1` currently validate wiring and invariants by source inspection. The resource validator has **0 errors** and pre-existing legacy warnings. These are static checks, not substitute gameplay tests.

## Explicit manual validation still required

1. Portal accessibility, gates, boss progression, drops, and marks for Sunken Reliquary, Ashen Foundry, and Starfall Observatory.
2. Sigil readiness, party marker visibility, and party join across a real reconnect handoff.
3. Weekly leaderboard rollover and guild trophy persistence after a Redis/server restart.
4. Vault swap, trade, drop/pickup, and Gift Chest withdrawal identity persistence—including forced write failure cases.
5. Contract/Codex/Forge/Material replay behavior and Realm Threat/Featured reward math.

## Phase 19 gate

Phase 19 should not rely on Imprint data until cross-key item-transfer atomicity and persistent Gift Chest identity are implemented and verified. The current code is suitable for further non-Imprint content work, but it is not an honest foundation for enabling per-item Imprints.
