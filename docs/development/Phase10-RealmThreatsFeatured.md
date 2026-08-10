# Phase 10 — Realm Threats and Featured Dungeon

Each Realm owns a 0–100 Threat meter. Normal kills add 1 and God kills add 5. Thresholds
20/40/60/80/100 trigger once per Realm lifecycle; the first two encounters use Cube God and
Grand Sphinx, scaling HP by 50% per engaged player after the first. Completing an encounter
awards one `threat_fragment` to current participants. Resetting a closed empty Realm clears
the meter, threshold latches, and active encounter state.

Featured Dungeon rotates deterministically by UTC date across Codex entries. It advertises
+20% XP, +15% relative rare-drop chance, +25% Echo Dust, and one first-daily-clear
`sigil_fragment`. First-clear is persisted and idempotent. It does not change marks or quest
chests. `/featured` displays the current entry.
