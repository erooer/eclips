using System;

namespace wServer.networking.handlers
{
    // Kept independent of a packet/client so the exact consumption math is shared by
    // the server handler and its regression tests.
    public struct PotionStorageConsumptionResult
    {
        public bool AlreadyMaxed;
        public int PotionsNeeded;
        public int PotionsConsumed;
        public int StatPointsApplied;
    }

    public static class PotionStorageConsumption
    {
        public static PotionStorageConsumptionResult Resolve(int current, int cap, int available, int pointsPerPotion, bool consumeMaximum)
        {
            if (current >= cap)
                return new PotionStorageConsumptionResult { AlreadyMaxed = true };

            var pointsNeeded = cap - current;
            var potionsNeeded = (pointsNeeded + pointsPerPotion - 1) / pointsPerPotion;
            var potionsConsumed = consumeMaximum
                ? Math.Min(potionsNeeded, Math.Max(0, available))
                : Math.Min(1, Math.Max(0, available));

            return new PotionStorageConsumptionResult
            {
                PotionsNeeded = potionsNeeded,
                PotionsConsumed = potionsConsumed,
                StatPointsApplied = Math.Min(pointsNeeded, potionsConsumed * pointsPerPotion)
            };
        }
    }
}
