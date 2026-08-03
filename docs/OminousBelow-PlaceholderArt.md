# The Ominous Below placeholder art

All new entities use the already embedded `chars16x16dEncounters2:96` ghostly encounter sprite, and static objects use `lofiObj5:fe/ff`.
These are intentionally shared visual coordinates only; every dungeon entity has its own type ID. Future art should replace the river spirits, wardens, seals, pillars, portal, chest, and final abyss entity with dedicated dark-underworld sprites.

## Paladin reward placeholders

No reward artwork was changed in the runtime pass. The exact XML texture fields to replace later are in `Server-src/common/resources/xmls/EmbeddedData_OminousBelowCXML.dat`:

| Item | Current `<Texture><File>` | Current `<Index>` |
| --- | --- | --- |
| Judgement (`0xF921`) | `Moon` | `0x80` |
| Mantle of the Below (`0xF920`) | `lofiObj5` | `0xfe` |

The client already registers `OminousBelowItems` as an 8×8 image set. No asset or XML texture coordinate was changed here.
