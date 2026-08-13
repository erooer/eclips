# Phase 19 — Eclipse Citadel

## Runtime design

Eclipse Citadel is a difficulty-10, 31×31 bespoke Purple Stone Dark dungeon map. Its runtime world spawns three independently completable wings: Lightless Court (The Hollow Regent), Broken Zenith (The Zenith Warden), and Umbra Engine (The Umbra Enginekeeper). The Crowned Eclipse does not spawn until all three instance-local completion flags are true.

The Crowned Eclipse has four behavior states: Crown Ascendant, Eclipse Guard (visible Crown Shadows provide the invulnerability reason), alternating Light and Umbra, and Broken Crown. The world releases its invulnerability only after the Crown Shadows are gone. Completion is guarded by a single `_completed` flag and creates the Citadel Completion Chest plus a 90-second return portal.

## Access and rewards

- Starfall Observatory: 5% natural Eclipse Citadel portal on The Parallax's death (180 seconds).
- Realm Threat: the completed level-100 encounter opens one public Citadel portal for 180 seconds.
- Nexus: `/citadel open` spends 25 `citadel_fragment` only after the portal's destination world has registered. Pending account operations suppress duplicate requests.
- The Crowned Eclipse drops a consumable Citadel Mark using `LegendaryMarks`; it is neither Forge nor Imprint currency.
- Completion chest: Citadel Mark, Attack Potion, Defense Potion, plus a bounded 12% roll for one Citadel unique. The four uniques are Crownrender, Eclipse Aegis, Zenithal Ring, and Lightless Staff.
- Completion additionally awards 2 `imprint_shard` and 25 `echo_dust` once per account/world operation.

## Integrations

Citadel is a Codex entry, therefore existing server-authoritative completion hooks provide Contracts, Featured Dungeon rotation, Sigil access after its normal threshold, Anomaly attachment, party/solo timing, Mastery, guild trophies, and weekly leaderboards. `Crownrender`, `Eclipse Aegis`, `Zenithal Ring`, and `Lightless Staff` are explicit Eclipse Imprint allowlist entries.

## Placeholder assets

All Citadel enemies use existing `chars16x16dEncounters2` frames and lofi object icons. The bespoke geometry is intentionally functional but needs final court/observatory/engine art and bespoke character sprites in a later art pass.

## Manual validation still required

Test the three wing combat layouts, player-facing readability of the Crowned Eclipse's alternating pattern states, actual portal visibility, party scaling feel, and loot/chest visuals after deployment. No live server, Redis, or gameplay test was performed during implementation.
