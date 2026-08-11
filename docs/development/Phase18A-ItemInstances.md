# Phase 18A — Item Instance Foundation

`RInventory` now maintains an additive `Field.instances` server-side ledger alongside the unchanged `ushort[]` object-type array. Each non-empty legacy slot is lazily assigned a GUID, object type, and extensible metadata string. Client packets still receive only object type.

The reconciler retains a matching unused record during slot swaps inside one persistent inventory owner and rejects duplicate IDs. New unmatched items receive new GUIDs. This is a safe compatibility foundation, but cross-owner vault/trade/drop transfers still need explicit atomic instance-ledger moves before Imprints may be enabled; no Imprint functionality is exposed by this phase.

Phase 18B adds `RInventory.TransferInstance`, an authoritative locked cross-owner primitive for persistent inventories. Existing live Vault/trade/container handlers still serialize only legacy object types and require handler-by-handler adoption before enabled Imprints are safe.
