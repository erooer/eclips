using System;
using System.Collections.Generic;
using System.Linq;
using common;
using Newtonsoft.Json;
using wServer.realm.entities;
using wServer.realm.worlds;

namespace wServer.realm
{
    // Static dungeon facts are intentionally separate from persisted player progress.
    // A future client Codex can serialize these definitions without changing save data.
    public sealed class DungeonCodexDefinition
    {
        public string Key;
        public string WorldName;
        public string DisplayName;
        public int Difficulty;
        public string RecommendedProgression;
        public string[] Bosses;
        public string[] PotionDrops;
        public string[] KnownUniques;
        public string MarkType;
        public string QuestChest;
        public string PortalSource;
    }

    public sealed class DungeonCodexEntry
    {
        public bool Discovered;
        public int Completions;
        public int Deaths;
        public long BestSoloClearMs;
        // Reserved for Phase 13 parties. Kept in the initial schema so no migration
        // is necessary when party membership becomes authoritative.
        public long BestPartyClearMs;
    }

    public sealed class DungeonCodexState
    {
        public Dictionary<string, DungeonCodexEntry> Entries = new Dictionary<string, DungeonCodexEntry>();
    }

    public static class DungeonCodexService
    {
        private static readonly Dictionary<string, DungeonCodexDefinition> Definitions =
            new Dictionary<string, DungeonCodexDefinition>(StringComparer.OrdinalIgnoreCase)
            {
                { "Pirate Cave", Def("Pirate Cave", "Pirate Cave", 1, "Early game", new[] { "Dreadstump the Pirate King" }, new[] { "Potion of Attack" }, new[] { "Pirate King's Cutlass" }, "Common Mark", "Standard Chest", "Realm pirate encounters and keys") },
                { "Snake Pit", Def("Snake Pit", "Snake Pit", 2, "Early game", new[] { "Stheno the Snake Queen" }, new[] { "Potion of Speed" }, new[] { "Stheno's Staff" }, "Common Mark", "Standard Chest", "Realm Medusa and Snake Pit portals") },
                { "Spider Den", Def("Spider Den", "Spider Den", 2, "Early game", new[] { "Arachna the Spider Queen" }, new[] { "Potion of Dexterity" }, new[] { "Arachna's Fang" }, "Common Mark", "Standard Chest", "Realm spider encounters and Spider Den portals") },
                { "Undead Lair", Def("Undead Lair", "Undead Lair", 3, "Early game", new[] { "Septavius the Ghost God" }, new[] { "Potion of Wisdom" }, new[] { "Septavius's Tome" }, "Rare Mark", "Mighty Chest", "Realm ghost-god encounters and Undead Lair portals") },
                { "Abyss of Demons", Def("Abyss of Demons", "Abyss of Demons", 4, "Mid game", new[] { "Archdemon Malphas" }, new[] { "Potion of Vitality" }, new[] { "Demon Blade" }, "Rare Mark", "Mighty Chest", "Realm demon encounters and Abyss portals") },
                { "Sprite World", Def("Sprite World", "Sprite World", 3, "Early game", new[] { "Limon the Sprite God" }, new[] { "Potion of Dexterity" }, new[] { "Staff of the Cosmic Whole" }, "Rare Mark", "Mighty Chest", "Realm Sprite God encounters and Sprite World portals") },
                { "Forbidden Jungle", Def("Forbidden Jungle", "Forbidden Jungle", 3, "Early game", new[] { "Mixcoatl the Masked God" }, new[] { "Potion of Defense" }, new[] { "Leaf Bow" }, "Rare Mark", "Mighty Chest", "Realm jungle encounters and Forbidden Jungle portals") },
                { "Manor of the Immortals", Def("Manor of the Immortals", "Manor of the Immortals", 4, "Mid game", new[] { "Lord Ruthven" }, new[] { "Potion of Attack" }, new[] { "Ruthven's Wand" }, "Epic Mark", "Grand Master Chest", "Realm ghost encounters and Manor portals") },
                { "Ocean Trench", Def("Ocean Trench", "Ocean Trench", 5, "Mid game", new[] { "Thessal the Mermaid Goddess" }, new[] { "Potion of Wisdom" }, new[] { "Coral Bow" }, "Epic Mark", "Grand Master Chest", "Realm sea encounters and Ocean Trench portals") },
                { "Mad Lab", Def("Mad Lab", "Mad Lab", 5, "Mid game", new[] { "Dr. Terrible" }, new[] { "Potion of Wisdom", "Potion of Vitality" }, new[] { "Conducting Wand" }, "Epic Mark", "Grand Master Chest", "Realm robot encounters and Mad Lab portals") },
                { "OminousBelow", Def("OminousBelow", "The Ominous Below", 8, "Advanced / endgame", new[] { "The Faceless Ferryman", "Veyra, Warden of Chains", "The Ominous One" }, new[] { "Potion of Attack", "Potion of Defense" }, new[] { "Eye of the Ominous", "Mantle of the Below", "Judgement" }, "Ominous Below Mark (Legendary)", "Grand Champion Chest", "Haunted Omen — Guaranteed Portal") }
            };

        private static DungeonCodexDefinition Def(string key, string worldName, int difficulty, string progression,
            string[] bosses, string[] potions, string[] uniques, string mark, string chest, string source)
        {
            return new DungeonCodexDefinition
            {
                Key = key,
                WorldName = worldName,
                DisplayName = worldName,
                Difficulty = difficulty,
                RecommendedProgression = progression,
                Bosses = bosses,
                PotionDrops = potions,
                KnownUniques = uniques,
                MarkType = mark,
                QuestChest = chest,
                PortalSource = source
            };
        }

        public static IEnumerable<DungeonCodexDefinition> All { get { return Definitions.Values.OrderBy(d => d.Difficulty).ThenBy(d => d.DisplayName); } }

        public static bool TryGet(World world, out DungeonCodexDefinition definition)
        {
            definition = null;
            return world != null && Definitions.TryGetValue(world.Name, out definition);
        }

        public static bool IsCompletionBoss(World world, string objectId)
        {
            DungeonCodexDefinition definition;
            return TryGet(world, out definition) && definition.Bosses.Last().Equals(objectId, StringComparison.OrdinalIgnoreCase);
        }

        public static void RecordDiscovery(DbAccount account, World world)
        {
            DungeonCodexDefinition definition;
            if (account == null || !TryGet(world, out definition)) return;
            lock (account)
            {
                var state = Load(account);
                var entry = GetEntry(state, definition.Key);
                // A revisit must not put a synchronous persistence write on the
                // normal world-entry path. First discovery is the only mutation.
                if (!entry.Discovered)
                {
                    entry.Discovered = true;
                    Save(account, state);
                }
            }
        }

        public static void RecordDeath(DbAccount account, World world)
        {
            DungeonCodexDefinition definition;
            if (account == null || !TryGet(world, out definition)) return;
            lock (account)
            {
                var state = Load(account);
                var entry = GetEntry(state, definition.Key);
                entry.Discovered = true;
                entry.Deaths++;
                Save(account, state);
            }
        }

        // World invokes this only from a registered terminal-boss death callback.
        // The World instance guards the callback, so an enemy death can credit a
        // player at most once even if behavior code or packets are replayed.
        public static void RecordCompletion(DbAccount account, World world, long elapsedMs, bool solo)
        {
            DungeonCodexDefinition definition;
            if (account == null || !TryGet(world, out definition)) return;
            lock (account)
            {
                var state = Load(account);
                var entry = GetEntry(state, definition.Key);
                entry.Discovered = true;
                entry.Completions++;
                FeaturedDungeonService.RecordCompletion(account, definition);
                if (solo && elapsedMs > 0 && (entry.BestSoloClearMs == 0 || elapsedMs < entry.BestSoloClearMs))
                    entry.BestSoloClearMs = elapsedMs;
                Save(account, state);
            }
        }

        public static string Describe(DbAccount account, string requestedDungeon)
        {
            DungeonCodexDefinition definition;
            if (!TryResolve(requestedDungeon, out definition))
                return "Codex entries: " + string.Join(", ", All.Select(d => d.DisplayName).ToArray()) + ". Use /codex <dungeon>.";

            DungeonCodexEntry entry;
            lock (account)
            {
                entry = GetEntry(Load(account), definition.Key);
            }
            var solo = entry.BestSoloClearMs == 0 ? "—" : FormatTime(entry.BestSoloClearMs);
            var party = entry.BestPartyClearMs == 0 ? "—" : FormatTime(entry.BestPartyClearMs);
            return string.Format("[Codex] {0} | {1} | Difficulty {2} | Bosses: {3} | Potions: {4} | Uniques: {5} | Mark: {6} -> {7} | Source: {8} | Discovered: {9} | Clears: {10} | Deaths: {11} | Best solo: {12} | Best party: {13}",
                definition.DisplayName, definition.RecommendedProgression, definition.Difficulty,
                string.Join(", ", definition.Bosses), string.Join(", ", definition.PotionDrops), string.Join(", ", definition.KnownUniques),
                definition.MarkType, definition.QuestChest, definition.PortalSource, entry.Discovered ? "yes" : "no",
                entry.Completions, entry.Deaths, solo, party) + " | " + DungeonSigilService.DescribeAccess(account, definition);
        }

        public static int GetCompletionCount(DbAccount account, string dungeonKey)
        {
            if (account == null) return 0;
            lock (account) return GetEntry(Load(account), dungeonKey).Completions;
        }

        public static bool TryResolveDefinition(string value, out DungeonCodexDefinition definition)
        {
            return TryResolve(value, out definition);
        }

        private static bool TryResolve(string value, out DungeonCodexDefinition definition)
        {
            definition = null;
            if (string.IsNullOrWhiteSpace(value)) return false;
            var normalized = value.Trim();
            return Definitions.TryGetValue(normalized, out definition) ||
                   (definition = Definitions.Values.FirstOrDefault(d => d.DisplayName.Equals(normalized, StringComparison.OrdinalIgnoreCase))) != null;
        }

        private static DungeonCodexEntry GetEntry(DungeonCodexState state, string key)
        {
            DungeonCodexEntry entry;
            if (!state.Entries.TryGetValue(key, out entry))
            {
                entry = new DungeonCodexEntry();
                state.Entries[key] = entry;
            }
            return entry;
        }

        private static DungeonCodexState Load(DbAccount account)
        {
            try { return JsonConvert.DeserializeObject<DungeonCodexState>(account.DungeonCodexState) ?? new DungeonCodexState(); }
            catch { return new DungeonCodexState(); }
        }

        private static void Save(DbAccount account, DungeonCodexState state)
        {
            account.DungeonCodexState = JsonConvert.SerializeObject(state);
            account.FlushAsync().Wait();
        }

        private static string FormatTime(long milliseconds)
        {
            return TimeSpan.FromMilliseconds(milliseconds).ToString(@"m\:ss\.fff");
        }
    }
}
