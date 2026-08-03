# Type ID registry

Object and ground IDs are declared in `Server-src/common/resources/xmls/EmbeddedData_*.dat`. `scripts/Validate-TypeIds.ps1` reports collisions and `scripts/Generate-TypeIdReport.ps1` writes the current static report.

Reserved authored range: `0xF900–0xF920` — The Ominous Below. Do not allocate inside this range. Before reserving a new range, run the collision check, record the owner and range here, then add the XML in the same change.

Projectile indexes are local to an object definition, not global type IDs. They are checked for duplicate indexes by the resource validator.
