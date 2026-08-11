# Phase 17 — Custom Stat Audit

| Stat | Index | Class data | Persistence / packets | Status |
|---|---:|---|---|---|
| Luck | 10 | All player XML classes: base 0, cap 50 | `Player.Stats[10]`, `StatsType.Luck`, potion storage and Luck potions | **PARTIAL** — server recognizes and persists it, but client HUD/maxing parity requires a dedicated review. |
| Critical Damage | 11 | Not defined in standard player class XML | item/potion references and server combat extensions | **PARTIAL** — sources exist; no audited class-cap/UI contract. |
| Critical Hit / Critical Chance | 12 | Not defined in standard player class XML | item/potion references and server combat extensions | **PARTIAL** — sources exist; no audited class-cap/UI contract. |
| Lunar | no player stat index proven | `PotionStorageLunar*` account fields | storage-only / `Lunar Ascension` paths | **LEGACY/UNUSED as a player stat** — not suitable for Ascension. |

Normal eight stats remain authoritative through the established character model. Luck has explicit XML caps and server serialization. Crit stats are used by custom items and drops but lack a complete end-to-end class-cap/client presentation contract. Lunar is a content tag/storage concept, not a safe ninth stat.

Recommendation: do **not** build Ascension on these paths yet. Phase 18 Imprints can proceed independently using non-stat materials/account state. No Potion Storage behavior was changed.

References: `common/resources/XmlDescriptors.cs` (`Luck` name/index), `wServer/realm/entities/player/Player.cs` (Luck serialization), `Player.UseItem.cs` (custom potion names/storage), `EmbeddedData_PlayersCXML.dat` (Luck cap), and `DbModels.cs` (Lunar storage fields).
