# Dungeon overview

Each dungeon is registered by a `.jw` world definition under `Server-src/common/resources/worlds` and one or more maps under the same tree. A world names its map files and portal type IDs; map dictionaries reference object IDs from `EmbeddedData_*.dat`.

The Ominous Below uses `OminousBelow.jw`, `OminousBelow.jm`, and `EmbeddedData_OminousBelowCXML.dat`. Its reserved object range is `0xF900–0xF920`. Validate it with `scripts/Test-OminousBelow.ps1` before a build.

New dungeon workflow: allocate IDs, add resource XML, add maps, register the world/portal, then run `Validate-Preflight.ps1` and both builds. The validators are static; they intentionally do not replace gameplay testing.
