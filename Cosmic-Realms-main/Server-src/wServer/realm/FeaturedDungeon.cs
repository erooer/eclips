using System;
using System.Collections.Generic;
using System.Linq;
using common;
using Newtonsoft.Json;

namespace wServer.realm
{
    public sealed class FeaturedDungeonState { public string LastRewardDate = ""; public string LastRewardDungeon = ""; }
    public static class FeaturedDungeonService
    {
        public const double XpMultiplier = 1.20;
        public const double RareDropMultiplier = 1.15;
        public const int EchoDustBonusPercent = 25;
        public static DungeonCodexDefinition Current { get { var pool = DungeonCodexService.All.ToArray(); var day = (int)(DateTime.UtcNow.Date - new DateTime(2024, 1, 1)).TotalDays; return pool[Math.Abs(day) % pool.Length]; } }
        public static string Describe() { return "[Featured] " + Current.DisplayName + " | +20% XP | +15% relative direct rare chance | +25% Echo Dust | first clear: 1 sigil_fragment."; }
        public static void RecordCompletion(DbAccount account, DungeonCodexDefinition definition)
        {
            if (account == null || definition.Key != Current.Key) return;
            lock (account)
            {
                var state = Load(account); var day = DateTime.UtcNow.ToString("yyyyMMdd");
                if (state.LastRewardDate == day && state.LastRewardDungeon == definition.Key) return;
                var op = "featured:" + account.AccountId + ":" + day + ":" + definition.Key;
                var reward = MaterialVaultService.TryDeposit(account, "sigil_fragment", 1, op);
                if (!reward.Success) return;
                state.LastRewardDate = day; state.LastRewardDungeon = definition.Key; Save(account, state);
            }
        }
        private static FeaturedDungeonState Load(DbAccount a) { try { return JsonConvert.DeserializeObject<FeaturedDungeonState>(a.FeaturedDungeonState) ?? new FeaturedDungeonState(); } catch { return new FeaturedDungeonState(); } }
        private static void Save(DbAccount a, FeaturedDungeonState s) { a.FeaturedDungeonState = JsonConvert.SerializeObject(s); a.FlushAsync().Wait(); }
    }
}
