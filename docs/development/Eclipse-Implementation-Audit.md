# Eclipse Implementation-Depth Audit

Audited against `main` on 2026-08-11. Status describes runtime code, not prior reports.

## Phase 0–4

| Phase / commit | Runtime entry points and persistence | Tests | Status / gaps |
|---|---|---|---|
| 0 `6c4f563` | Documentation baseline only. | None. | **STATIC/FOUNDATION ONLY**. |
| 1–3 `47a255f`, `0b3d88d`, `170aa0a`, `143344f` | Haunted Omen has `GuaranteedPortalOnDeath`; Ominous mark XML uses `LegendaryMarks`; Ominous world callbacks are in `OminousBelow.cs`. | Existing Ominous scripts are source-text checks plus build validation. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION**. Manual test: portal, mark consumption, all gates. |
| 4 `143344f` | Ominous-specific polish only. | Static map/behavior script. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION**. |

## Phase 5–10

| Phase / commit | Runtime entry points and persistence | Tests truly verify | Status / gaps |
|---|---|---|---|
| 5 `69e3524` Contracts | `/contracts`; `ContractState`; mark call in `Player.UseItem`. | Text presence, not request replay/persistence. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION**. |
| 6 `9d71976` Codex | `/codex`; `DungeonCodexState`; `World` completion/death hooks. | Text presence. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION**; completion depends on actual world terminal callback. |
| 7 `7e1a7d5` Materials | `/materials`; `MaterialVaultState`; service has idempotency ledger. | Text/static checks. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION**. |
| 8 `ceed000` Sigils | `/sigils`; `DungeonSigilState`; Nexus portal create. | Text/static checks. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION**; manual portal/reconnect validation needed. |
| 9 `2652edc` Forge | `/forge`; `ForgeState`; Material Vault spend. | Text/static checks. | **FUNCTIONAL V1 / MINIMAL IMPLEMENTATION**; no per-item lock/instance semantics. |
| 10 `5adb885` Threats/Featured | Realm calls `AddActivity`; `/featured`; `FeaturedDungeonState`. | Text checks only. | **INCOMPLETE**: threat encounters are generic existing enemies; Featured XP/rare/Echo values are readout constants, not connected to XP/loot/salvage. |

## Phase 11–15 dungeons

| Phase / commit | Runtime entry points and persistence | Tests truly verify | Status / gaps |
|---|---|---|---|
| 11 `9d09391` Sunken Reliquary | `.jw`, XML portal, world class, BehaviorDb, Codex. | Names/tags exist. | **DEAD/UNREACHABLE**: `.jw` has `maps: []`; no map places Guardian/Custodian/Pearls/Warden. Natural drop source absent. Boss/loot/mark cannot occur naturally. Placeholder `chars16x16dEncounters2`/`lofiObj5`. |
| 12 `6fa24ef` Anomalies | Only `SunkenReliquary` attaches in constructor; in-memory dictionary. | Text checks. | **STATIC/FOUNDATION ONLY**: no natural portal roll interception, no modifier application to enemy stats/loot, no portal/readout command. |
| 13 `9a7071f`, `93c9a30` Parties | `/party`, `/p`; `PartyState`; in-memory party dictionary. | Text checks. | **INCOMPLETE**: parties do not reconstruct membership after restart, no disconnect cleanup, no join-world implementation, no Sigil sharing/markers. |
| 14 `4439497` Ashen Foundry | `.jw`, XML, world class, BehaviorDb, Codex. | Names/tags exist. | **DEAD/UNREACHABLE**: empty map and no spawn/natural portal source. Placeholder textures. |
| 15 `12e79d8` Starfall Observatory | `.jw`, XML, world class, BehaviorDb, Codex. | Names/tags exist. | **DEAD/UNREACHABLE**: empty map and no wing seals/boss spawn; selected wings are not used to alter Parallax behavior. Placeholder textures. |

## Phase 16–18B

| Phase / commit | Runtime entry points and persistence | Tests truly verify | Status / gaps |
|---|---|---|---|
| 16 `a50c7f8` History/Mastery/Guild/Boards | `/mastery`, `/history`, `/leaderboard`; `EclipseProgressState`; Codex calls Mastery/boards. | Text checks. | **INCOMPLETE**: death recording has no permanent-death hook; guild progression absent; leaderboards are in-memory, not weekly/persistent; rewards do not provide titles/frames. |
| 17 `7e5cf81` Audit | Documentation/script only. | Text checks. | **STATIC/FOUNDATION ONLY**. Correctly identifies partial custom stats; no fixes. |
| 18A `c2c9151` | `RInventory.Field.instances` additive record ledger. | Text checks. | **STATIC/FOUNDATION ONLY**: legacy migration exists, but only type-matching reconciliation is ambiguous for duplicate types and no handlers use records. |
| 18B `6f329d1` | `RInventory.TransferInstance` primitive. | Text checks. | **INCOMPLETE**: Vault, InvSwap, trade, drop/pickup, and Gift Chest handlers do not call it; no atomic Redis transaction/rollback implementation. Imprints remain unsafe. |

## Persistence and reachability conclusions

All added account fields use `DbAccount` getters/setters and are additive, so they can serialize when explicitly flushed. That does **not** prove every producer/consumer is runtime-wired. All Phase 11/14/15 dungeon `.jw` files have empty map arrays, proving their claimed room structures, enemies, bosses, drops, marks, and completion callbacks are unreachable without additional world population/spawn logic.

The phase test scripts are predominantly single-line source-string assertions. They prove declarations exist, not packet flow, Redis transactions, map population, behavior execution, or reconnect persistence. They should not be treated as runtime/integration tests.

## Explicit placeholders

Sunken Reliquary, Ashen Foundry, and Starfall Observatory use `lofiObj5` and `chars16x16dEncounters2`; their maps are empty. No final assets/maps were added.

## Required manual/runtime validation after corrective work

Portal accessibility and world spawning; each boss gate and reward; mark consumption/chest grant; transfer identity across all containers; reconnect persistence; party lifecycle; Contracts/Codex/Sigil/Forge request replay; Threat/Featured reward math; and permanent-death recaps/leaderboard reset behavior.
