using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using common.resources;
using wServer.realm.worlds;

namespace wServer.realm
{
    public sealed class DungeonAnomaly { public int Grade; public string[] Modifiers; public double RewardMultiplier; }
    // Instance-bound only: no account state, marks, or persistent currency is involved.
    public static class DungeonAnomalyService
    {
        private static readonly ConcurrentDictionary<int, DungeonAnomaly> Active = new ConcurrentDictionary<int, DungeonAnomaly>();
        public static DungeonAnomaly Roll(DungeonCodexDefinition d, Random rng)
        {
            if (d == null || rng == null) return null;
            var chance = d.Difficulty <= 3 ? .05 : d.Difficulty <= 5 ? .08 : d.Difficulty <= 7 ? .10 : .12;
            if (rng.NextDouble() >= chance) return null;
            var grade = rng.Next(1, 4); var mods = grade == 1 ? new[] { "Boss HP +20%", "Extra potion roll" } : grade == 2 ? new[] { "Boss HP +20%", "Minion HP +25%", "Bonus material" } : new[] { "Boss HP +20%", "Minion speed +15%", "Elite guard", "Sigil Fragment chance" };
            return new DungeonAnomaly { Grade = grade, Modifiers = mods, RewardMultiplier = Math.Min(1.5, 1 + grade * .15) };
        }
        public static void Attach(World world, DungeonAnomaly anomaly) { if (world != null && anomaly != null) Active[world.Id] = anomaly; }
        public static bool TryGet(World world, out DungeonAnomaly anomaly) { anomaly = null; return world != null && Active.TryGetValue(world.Id, out anomaly); }
        public static void Cleanup(World world) { if (world != null) { DungeonAnomaly ignored; Active.TryRemove(world.Id, out ignored); } }
        public static string Describe(World world) { DungeonAnomaly a; return TryGet(world, out a) ? "[Anomaly " + a.Grade + "] " + string.Join(", ", a.Modifiers) : "No active dungeon anomaly."; }
    }
}
