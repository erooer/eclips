# Phase 6 — Dungeon Codex

The first Codex presentation is command-backed to keep it compatible with the current
client: `/codex` lists supported entries, and `/codex <dungeon>` displays the selected
page. This is a server-side V1; `DungeonCodexDefinition` is deliberately separated from
the persisted data so a future client panel can consume the same facts.

Each page includes difficulty, recommended progression, boss list, potion drops, known
uniques, consumable mark tier, associated quest chest, and portal source. The Ominous
Below page explicitly identifies its source as **Haunted Omen — Guaranteed Portal**.

## Tracking

`DbAccount.DungeonCodexState` is an additive JSON field (`dungeonCodexState`) containing
per-dungeon discovery, completion count, death count, solo best-clear milliseconds, and a
reserved party-best-clear field. Existing accounts have no field and deserialize safely to
an empty Codex.

Discovery happens when a player enters a supported dungeon. Completion is not inferred
from a portal: the destination world registers only its configured terminal boss, and the
instance-level latch records a clear once for players present when that boss legitimately
dies. The clear time starts when the player enters the instance. A solo time is eligible
only if one account participated in that instance. Party time remains schema-ready and is
not populated until Phase 13 has authoritative party state.

Permanent player deaths call the same server-side Codex service after the established
death checks have accepted the death. Nexus, arena, resurrection, and non-permadeath
paths therefore do not inflate dungeon death totals.

The Codex does not create portals, teleport players, change mark consumption, award quest
chests, touch Potion Storage, or alter reconnect/session ownership.
