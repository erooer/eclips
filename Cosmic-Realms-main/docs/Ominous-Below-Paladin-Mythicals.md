# Ominous One Paladin Mythicals

The Ominous One's three related Mythical rewards are ordinary independent items. They do not use set equipment, set counters, set bonuses, or equipment-combination logic.

## Item definitions

| Item | Object type | Slot | Mythical bonus fields | Other effects |
| --- | --- | --- | --- | --- |
| Judgement | `0xF921` | Sword (`1`) | `CriticalHit` (`114`) +10; `Luck` (`102`) +10 | One projectile, 700-900 damage, `RateOfFire` 0.35 |
| Eye of the Ominous | `0xF91F` | Seal (`12`) | `CriticalHit` (`114`) +10; `Luck` (`102`) +10 | Existing 75 MP, 500 base area damage and Wisdom scaling remain unchanged; +5 DEX and +5 WIS remain unchanged |
| Mantle of the Below | `0xF920` | Heavy Armor (`7`) | `CriticalHit` (`114`) +10; `Luck` (`102`) +10 | +25 WIS, +10 VIT, -5 DEF; no active or proc |

`<ST/>` is the project's canonical Mythical rarity marker. It controls the existing client rarity treatment, but does not add stats automatically. The standard bonuses are therefore declared exactly once with the normal `ActivateOnEquip` fields, following existing Mythical XML such as Omnipotence Ring and Disarray.

## Judgement visual and rate reference

Judgement reuses the existing `Gargoyle Pulse` projectile (`lofiObj11`, index `0x4c`) temporarily. It is already the projectile for the ordinary Sword-slot heavy weapon **Gargoyle Crusher**, which supplies the verified `RateOfFire` 0.35 reference. Judgement's current inventory placeholder is `Moon:0x80`; Mantle's current inventory placeholder is `lofiObj5:0xfe`. No new art or texture coordinate was added.

`RateOfFire` is a rate multiplier in this project, not a 35% cooldown reduction. Both client and server calculate the attack period as `1 / attackFrequency / RateOfFire`. Thus `0.35` is 35% of the standard weapon fire rate.

## Balance calculation

Judgement's average base damage is `(700 + 900) / 2 = 800` per shot. At a max-Dexterity Paladin's unbuffed base attack frequency (50 DEX: `0.0058333`), `RateOfFire` 0.35 produces about `2.042` shots per second, or about `1,633` average base DPS before Attack scaling, critical effects, enemy defense, and temporary buffs. At the Paladin's natural 50 Attack cap, the normal 1.5 attack multiplier makes that about `2,450` pre-defense average DPS before critical effects.

Comparable existing Sword-slot entries are:

| Weapon | Damage | Rate of fire | Max-Dex unbuffed base DPS |
| --- | --- | --- | --- |
| Judgement | 700-900 | 0.35 | ~1,633 |
| Heavy Moon Gem Sword | 800-1100 | 0.35 | ~1,940 |
| Gargoyle Crusher | 1100-1600 | 0.35 | ~2,756 |
| Shattered Scythe | 900-1200 | 0.30 | ~1,531 |

The source contains no normal Sword definition with a native 3,000-damage projectile range. The closest special reference found is **Admin Sword** (2,000 fixed projectile damage at 1.5 rate of fire), so it is not a comparable ordinary high-end reward. Optimized damage can exceed listed base values through the normal Attack, critical, and temporary status multipliers; no such multipliers were added or changed here.

Mantle's net normal-stat impact is +25 WIS, +10 VIT, and -5 DEF, plus the two explicit Mythical bonuses. The negative Defense uses the ordinary `Defense` stat field and therefore updates the effective player stat and client tooltip through the standard equipment-stat path. Relative to conventional high-end heavy armors, it trades direct survivability for unusually high Wisdom and Vitality.

Eye computes its agreed area damage server-side as `500 + (500 * effective Wisdom / 20)`. Mantle increases the final effective Wisdom by 25, so it adds `625` damage to a single Eye activation. Eye's own +5 WIS is included once in effective Wisdom and adds `125`; the combined equipment contribution is `750` damage. For example, at 50 base Wisdom, Eye alone yields `1,875` damage (`500 + 500 * 55 / 20`); Eye plus Mantle yields `2,500` (`500 + 500 * 80 / 20`). No item bonus is counted twice.

## Drop source

The Ominous One's existing threshold loot table gives Judgement, Eye of the Ominous, and Mantle of the Below one independent `0.006` (0.6%) entry each. Judgement uses the pre-existing Eye/Mantle rate as its direct reference. All are BagType 10, matching the project's existing Mythical-bag convention. Marks, potions, and Ominous Below Key entries are unchanged.

## Manual verification checklist

1. Spawn and equip Judgement on a Paladin; confirm Sword slot, 700-900 projectile roll, 35% rate, one shot, `Gargoyle Pulse` visual, exact description, and +10 Critical Chance/+10 Loot Chance.
2. Equip Eye; confirm Seal slot, 75 MP, +5 DEX, +5 WIS, the two Mythical bonuses, existing custom icon, ordinary Seal effects, and the 500-base Wisdom-scaled blast.
3. Equip Mantle on a Paladin; confirm Heavy Armor slot, +25 WIS, +10 VIT, -5 DEF, and the two Mythical bonuses. Attempting to equip it on a robe-only class should fail through the existing slot rules.
4. With Eye equipped, record an area-damage result at a known Wisdom value; equip Mantle and confirm the expected +625 increase from its +25 WIS.
5. Defeat the Ominous One repeatedly or inspect its loot table; confirm exactly one `0.006` entry for each of the three rewards and unchanged mark/potion/key entries.

No Redis data or schema is involved in these definitions. Existing saved `0xF920` copies resolve to Heavy Armor after clients and servers reload resources; users should fully restart the client to discard cached XML/item-category state.
