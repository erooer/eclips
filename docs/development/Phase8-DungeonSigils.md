# Phase 8 — Dungeon Sigils

Dungeon Sigils are a veteran convenience system, not a replacement for natural dungeon
access. They use only `sigil_fragment` from the Material Vault. Marks remain consumable
quest-chest items and are never used as Sigil currency.

`/sigils buy <1-20>` purchases fragments for 100 Fame each. `/sigils open <dungeon>` works
only in Nexus after the account meets the Codex completion threshold: 3 clears for early,
5 for midgame, 8 for advanced, and 12 for endgame entries. Portal fragment costs follow
the same 3/5/8/12 progression.

The server creates the normal temporary portal first and charges fragments only when its
destination has registered. A failed or timed-out construction removes the pending request
without spending fragments. Account-persisted pending operations, Material Vault operation
IDs, and a 30-second open rate limit prevent duplicate portals and duplicate spends.

Codex entries now display locked/unlocked status, clears required, fragment cost, and the
natural source. Ominous Below continues to display **Haunted Omen — Guaranteed Portal**;
Sigils are only an additional unlocked access path.
