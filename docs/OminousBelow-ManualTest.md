# The Ominous Below manual test

Use an administrator account and enter `/give Ominous Below Key` (alias of the rank-60 `/gimme` command) to obtain the key (type `0xF901`). Do not use a production or shipped SWF.

For a construction-only diagnostic, the existing rank-70 command `/quake OminousBelow` creates an instance through `DynamicWorld`. It is not needed for normal testing; test the key portal separately because portal preparation is part of the release path.

1. In Nexus, use the key and wait for `Ominous Below Portal` to become usable.
2. Enter once; verify the map starts at the River of the Forgotten spawn and the first divider is closed.
3. Kill all three Ominous Soul Lanterns and the Faceless Ferryman. Verify the prison gate opens only after both conditions are true.
4. Kill The First Gaoler and The Last Gaoler. Verify Veyra changes from invulnerable to vulnerable.
5. Kill Veyra. Verify the abyss gate opens and the final arena is reachable.
6. Destroy all four Ominous Seals. Verify The Ominous One becomes vulnerable only after the fourth seal.
7. Kill The Ominous One. Verify exactly one completion chest and one return portal spawn; loot the timed chest and return to Nexus.
8. Open a second key dungeon without restarting the server. Repeat steps 2-7 and verify its gates and announcements begin fresh.

Runtime expectations: `worldTickMs` remains 75, no legacy protocol flag is used, and the current client is `rebuild-original\\build\\client-unchanged.swf` served through the runtime web root.
