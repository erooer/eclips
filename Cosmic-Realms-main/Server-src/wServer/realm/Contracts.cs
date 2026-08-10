using System;
using common;
using Newtonsoft.Json;

namespace wServer.realm
{
    public sealed class ContractProgress
    {
        public string DailyKey = "";
        public string WeeklyKey = "";
        public int DailyMarks;
        public int DailyChests;
        public int WeeklyMarks;
        public int WeeklyChests;
        public int DailyMarkTarget = 3;
        public int DailyRerolls;
        public bool DailyMarksClaimed;
        public bool DailyChestsClaimed;
        public bool DailyBonusClaimed;
        public bool WeeklyMarksClaimed;
        public bool WeeklyChestsClaimed;
        public bool WeeklyBonusClaimed;
    }

    // All contract mutation is server-side and persisted as one additive account
    // field. Claim flags are durable, so replaying a command cannot award fame twice.
    public static class ContractService
    {
        private const int RerollCost = 250;
        public static void RecordMark(DbAccount account, bool questChestEarned)
        {
            lock (account)
            {
                var state = Load(account);
                state.DailyMarks++;
                state.WeeklyMarks++;
                if (questChestEarned) { state.DailyChests++; state.WeeklyChests++; }
                Save(account, state);
            }
        }
        public static string Describe(DbAccount account)
        {
            lock (account)
            {
                var s = Load(account);
                return string.Format("Daily: Marks {0}/{1}, Chests {2}/1. Weekly: Marks {3}/12, Chests {4}/3. Use /contracts claim or /contracts reroll.", s.DailyMarks, s.DailyMarkTarget, s.DailyChests, s.WeeklyMarks, s.WeeklyChests);
            }
        }
        public static string Claim(DbAccount account, string scope)
        {
            lock (account)
            {
                var s = Load(account); int award = 0;
                if (scope == "daily-marks" && s.DailyMarks >= s.DailyMarkTarget && !s.DailyMarksClaimed) { s.DailyMarksClaimed = true; award = 125; }
                else if (scope == "daily-chests" && s.DailyChests >= 1 && !s.DailyChestsClaimed) { s.DailyChestsClaimed = true; award = 150; }
                else if (scope == "daily-bonus" && s.DailyMarksClaimed && s.DailyChestsClaimed && !s.DailyBonusClaimed) { s.DailyBonusClaimed = true; award = 250; }
                else if (scope == "weekly-marks" && s.WeeklyMarks >= 12 && !s.WeeklyMarksClaimed) { s.WeeklyMarksClaimed = true; award = 400; }
                else if (scope == "weekly-chests" && s.WeeklyChests >= 3 && !s.WeeklyChestsClaimed) { s.WeeklyChestsClaimed = true; award = 450; }
                else if (scope == "weekly-bonus" && s.WeeklyMarksClaimed && s.WeeklyChestsClaimed && !s.WeeklyBonusClaimed) { s.WeeklyBonusClaimed = true; award = 600; }
                if (award == 0) return "Contract is incomplete or was already claimed.";
                account.Fame += award; Save(account, s); return "Contract reward claimed: +" + award + " fame.";
            }
        }
        public static string Reroll(DbAccount account)
        {
            lock (account)
            {
                var s = Load(account);
                if (s.DailyRerolls >= 1) return "Daily Contracts can only be rerolled once.";
                if (account.Fame < RerollCost) return "You need 250 fame to reroll Daily Contracts.";
                account.Fame -= RerollCost; s.DailyRerolls++; s.DailyMarkTarget = 5; s.DailyMarks = 0; s.DailyMarksClaimed = false; s.DailyBonusClaimed = false;
                Save(account, s); return "Daily mark contract rerolled: consume 5 marks. -250 fame.";
            }
        }
        private static ContractProgress Load(DbAccount account)
        {
            ContractProgress s; try { s = JsonConvert.DeserializeObject<ContractProgress>(account.ContractState) ?? new ContractProgress(); } catch { s = new ContractProgress(); }
            var now = DateTime.UtcNow; var daily = now.ToString("yyyyMMdd"); var monday = now.Date.AddDays(-((7 + (int)now.DayOfWeek - 1) % 7)).ToString("yyyyMMdd");
            if (s.DailyKey != daily) { s.DailyKey = daily; s.DailyMarks = s.DailyChests = s.DailyRerolls = 0; s.DailyMarkTarget = 3; s.DailyMarksClaimed = s.DailyChestsClaimed = s.DailyBonusClaimed = false; }
            if (s.WeeklyKey != monday) { s.WeeklyKey = monday; s.WeeklyMarks = s.WeeklyChests = 0; s.WeeklyMarksClaimed = s.WeeklyChestsClaimed = s.WeeklyBonusClaimed = false; }
            return s;
        }
        private static void Save(DbAccount account, ContractProgress state)
        {
            account.ContractState = JsonConvert.SerializeObject(state);
            // Claim/reroll acknowledgement is not sent until the existing Redis
            // account flush completes, which makes replayed commands observe the
            // durable claim flag rather than a stale in-memory result.
            account.FlushAsync().Wait();
        }
    }
}
