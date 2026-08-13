# Phase 18 — Eclipse Imprints V1

Eclipse Imprints are deterministic, per-item sidegrades stored in the existing server-side item-instance `Metadata` field. The client continues to receive only legacy `ushort` object types; no packet format, item XML, or base item definition changes are made.

## Eligible item allowlist

- Eye of the Ominous (`0xF91F`)
- Mantle of the Below (`0xF920`)
- Judgement (`0xF921`)
- Nacre Talisman (`0xF938`)
- Sunforged Plate (`0xF947`)
- Parallax Bulwark (`0xF956`)

Only unequipped bag slots may be Imprinted. There is no per-item lock feature in this source; if one is added later, the command must reject locked records before applying metadata.

## Imprints and cost

Each Imprint costs 25 `imprint_shard` from the Material Vault.

- **Swift:** +3 SPD, -25 HP
- **Bulwark:** +4 DEF, -2 DEX
- **Focused:** +3 WIS, -20 HP
- **Hunter:** +2 ATT, +2 DEX, -2 VIT

Only standard, fully supported stats are used. Marks, Luck, Critical Hit, Critical Damage, Lunar, and other partial/legacy custom stats are excluded.

## Commands

- `/imprint`
- `/imprint inspect <bag-slot>`
- `/imprint preview <bag-slot> <imprint>`
- `/imprint apply <bag-slot> <imprint>`

## Persistence and safety

Metadata uses an extensible semicolon-delimited format, currently `imprint=<id>`. Existing unrelated metadata fields are retained. Application atomically compares and writes the account Material Vault state and the target character’s `.instances` ledger in one Redis transaction. The operation ID is derived from account and immutable item-instance GUID, so retries cannot double-spend or apply a second Imprint.

The existing instance-transfer records carry metadata through inventory movement, Vault, trade, ground bags/pickup, Gift Chest withdrawal/drop, reconnect, and restart. A base item with no `imprint` metadata gets no additional boost.

## V1 limitations

This is command-backed and does not add item tooltip rendering for server-only metadata. The gameplay boost is server-authoritative whenever the corresponding instance is equipped. No Imprints are enabled for items outside the explicit allowlist.
