# Ominous Paladin Items Validation

Generated: 2026-07-30 23:09:44 -06:00

## Result

- PASS: Judgement resolves uniquely by canonical and lowercase name through the same generic item lookup.
- PASS: Mantle is Heavy Armor (SlotType 7); Warrior, Knight, and Paladin have SlotType 7, while Priest does not.
- PASS: source/client SWF/AIR resource embedding contains Judgement, Mantle, and Eye.
- Runtime parity: source XML, SWF, and world executable hashes match the deployed runtime.

## Final definitions

| Item | Type | Slot | Key fields |
| --- | --- | --- | --- |
| Judgement | 0xF921 | Sword (1) | 700-900, RoF 0.35, one Gargoyle Pulse (55 speed / 565 ms), ST, +10 Critical / +10 Loot |
| Mantle of the Below | 0xF920 | Heavy Armor (7) | +25 WIS, +10 VIT, -5 DEF, no Activate, ST, +10 Critical / +10 Loot |
| Eye of the Ominous | 0xF91F | Seal (12) | 75 MP, 500 base OminousSealBlast, +5 DEX / +5 WIS, ST |

## Root causes and correction

- Judgement was absent from the runtime XML because the rebuilt resource set had not been deployed; source XML and compiled clients already contained it.
- Mantle was Priest-only because the runtime still had the legacy SlotType 4, which is Priest ability. The source definition is SlotType 7 with its final stat fields.
- Mantle stats and Mythical rarity were absent for the same stale-runtime reason: the old runtime XML had no ST marker or ActivateOnEquip entries.
- `/give` was exact-case only. The generic lookup now performs a case-insensitive fallback for all item IDs/display names.

## References

- Slow Sword: Gargoyle Crusher (SlotType 1, RateOfFire 0.35, Gargoyle Pulse).
- Heavy Armor: Gargoyle Stoneplate (SlotType 7).
- Mythical items: Omnipotence Ring and Disarray (`<ST/>` plus explicit bonuses).
- Stat format: standard signed `ActivateOnEquip stat="..." amount="..."` values; Mantle uses -5 Defense.

## Equip compatibility

| Class | Judgement | Mantle |
| --- | --- | --- |
| Warrior | yes | yes |
| Knight | yes | yes |
| Paladin | yes | yes |
| Priest | no | no |

## Drops

- Ominous One has exactly one independent 0.006 entry for each of Judgement, Mantle of the Below, and Eye of the Ominous.

## Manual checks remaining

1. `/give judgement`, equip on Warrior/Knight/Paladin, and fire once.
2. `/give mantle of the below`, equip on Warrior/Knight/Paladin, and verify Priest rejects it.
3. Confirm the displayed stats and Mythical tooltip after a full client restart.
