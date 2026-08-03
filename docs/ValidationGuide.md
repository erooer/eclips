# Validation guide

Use `scripts/Validate-All.ps1` for the complete static report. Focused commands are `Validate-Maps.ps1`, `Validate-Resources.ps1`, `Validate-TypeIds.ps1`, `Validate-Behaviors.ps1`, `Validate-Portals.ps1`, and `Validate-Projectiles.ps1`.

`Validate-Preflight.ps1` is the build gate: it fails for Ominous Below reference/map/type defects and regenerates the broad report. Older source bundles may retain report-only findings (for example historical aliases and non-JM terrain maps); those are documented output, not silently ignored failures.

Reports are deterministic from the checked-out resource files. They do not exercise server networking, persistence, portals at runtime, or gameplay behavior.
