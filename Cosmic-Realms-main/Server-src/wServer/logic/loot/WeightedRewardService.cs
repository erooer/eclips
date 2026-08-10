using System;
using System.Collections.Generic;

namespace wServer.logic.loot
{
    // Data-driven weighted selection for new reward tables. Existing legacy
    // ItemLoot tables deliberately remain untouched until individually audited.
    public sealed class WeightedReward<T>
    {
        public readonly T Value;
        public readonly int Weight;

        public WeightedReward(T value, int weight)
        {
            if (weight <= 0) throw new ArgumentOutOfRangeException(nameof(weight));
            Value = value;
            Weight = weight;
        }
    }

    public static class WeightedRewardService
    {
        public static T Select<T>(IList<WeightedReward<T>> entries, Random random)
        {
            if (entries == null || entries.Count == 0) throw new ArgumentException("A reward table requires at least one entry.", nameof(entries));
            if (random == null) throw new ArgumentNullException(nameof(random));

            long total = 0;
            foreach (var entry in entries)
            {
                if (entry == null) throw new ArgumentException("Reward table contains a null entry.", nameof(entries));
                total += entry.Weight;
            }
            if (total > int.MaxValue) throw new ArgumentOutOfRangeException(nameof(entries), "Total reward weight exceeds the supported range.");

            var roll = random.Next((int)total);
            foreach (var entry in entries)
            {
                if (roll < entry.Weight) return entry.Value;
                roll -= entry.Weight;
            }
            throw new InvalidOperationException("Reward selection did not resolve an entry.");
        }
    }
}
