# Resource pipeline

`EmbeddedData_*.dat` files are XML bundles read by the rebuilt server and embedded by the rebuilt client. Object IDs, ground IDs, portal classes, textures, and projectile definitions originate here.

Run `scripts/Validate-Resources.ps1` after changing a bundle. The validator reports duplicate names/types, malformed XML envelopes, blank or unresolved XML object references, duplicate projectile indexes, and texture embeds that cannot be located by filename.

Do not delete an active asset based only on a report. Generated validation reports live in `docs/reports` and can be safely regenerated.
