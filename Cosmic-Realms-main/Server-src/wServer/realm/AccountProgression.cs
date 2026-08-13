using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using common;
using Newtonsoft.Json;
using StackExchange.Redis;

namespace wServer.realm
{
    public sealed class DeathRecap { public string Class; public int Level; public int Maxed; public int Fame; public string World; public string Killer; public string Equipment; public long Utc; }
    public sealed class EclipseProgress
    {
        public int Mastery;
        public HashSet<string> Awards = new HashSet<string>();
        public List<DeathRecap> Deaths = new List<DeathRecap>();
        // Bounded idempotency ledger for server-side score/event mutations.
        public HashSet<string> LeaderboardEvents = new HashSet<string>();
    }
    public sealed class GuildProgress
    {
        public Dictionary<string, int> Trophies = new Dictionary<string, int>();
        public string Week = "";
        public int WeeklyDungeonClears;
        public HashSet<string> Events = new HashSet<string>();
    }

    public static class AccountProgressionService
    {
        const int MaxDeaths = 20;
        const int MaxEvents = 512;
        public static EclipseProgress Load(DbAccount a) { try { return JsonConvert.DeserializeObject<EclipseProgress>(a.EclipseProgressState) ?? new EclipseProgress(); } catch { return new EclipseProgress(); } }
        static void Save(DbAccount a, EclipseProgress s) { a.EclipseProgressState = JsonConvert.SerializeObject(s); a.FlushAsync().Wait(); }
        internal static bool TryUseLeaderboardEvent(DbAccount account, string eventKey)
        {
            lock (account)
            {
                var state = Load(account);
                if (!state.LeaderboardEvents.Add(eventKey)) return false;
                if (state.LeaderboardEvents.Count > MaxEvents)
                    state.LeaderboardEvents = new HashSet<string>(state.LeaderboardEvents.OrderByDescending(x => x).Take(MaxEvents));
                Save(account, state);
                return true;
            }
        }
        public static void Award(DbAccount a, string key, int mastery = 1) { lock (a) { var s = Load(a); if (!s.Awards.Add(key)) return; s.Mastery += mastery; if (s.Mastery % 10 == 0) MaterialVaultService.TryDeposit(a, "sigil_fragment", 1, "mastery:" + key); Save(a, s); } }
        public static void RecordDeath(DbAccount a, DeathRecap d)
        {
            if (a == null || d == null) return;
            lock (a) { var s = Load(a); s.Deaths.Insert(0, d); if (s.Deaths.Count > MaxDeaths) s.Deaths.RemoveRange(MaxDeaths, s.Deaths.Count - MaxDeaths); Save(a, s); }
            EclipseLeaderboards.Record(a, "recent-death-fame", d.Fame, "death:" + d.Utc, false);
        }
        public static string Describe(DbAccount a) { var s = Load(a); return "Mastery " + s.Mastery + " | titles unlocked: " + s.Awards.Count + " | recent deaths: " + s.Deaths.Count; }
        public static string Deaths(DbAccount a) { var s = Load(a); return s.Deaths.Count == 0 ? "No recorded permanent deaths." : string.Join(" | ", s.Deaths.Take(5).Select(x => x.Class + " L" + x.Level + " fame " + x.Fame + " in " + x.World)); }
    }

    public static class EclipseLeaderboards
    {
        const int MaxEntries = 100;
        static string Week(DateTime utc)
        {
            var day = CultureInfo.InvariantCulture.Calendar.GetDayOfWeek(utc);
            if (day >= DayOfWeek.Monday && day <= DayOfWeek.Wednesday) utc = utc.AddDays(3);
            return utc.Year + "-W" + CultureInfo.InvariantCulture.Calendar.GetWeekOfYear(utc, CalendarWeekRule.FirstFourDayWeek, DayOfWeek.Monday).ToString("00");
        }
        static string Key(string category) { return "eclipse:leaderboard:" + Week(DateTime.UtcNow) + ":" + category; }
        // All scores are stored so that higher is better. Times are negated; this
        // keeps Redis rank ordering and the top-100 trim identical for each category.
        public static void Record(DbAccount account, string category, long score, string eventKey, bool lowerIsBetter = false)
        {
            if (account == null || string.IsNullOrWhiteSpace(category) || string.IsNullOrWhiteSpace(eventKey)) return;
            var week = Week(DateTime.UtcNow);
            if (!AccountProgressionService.TryUseLeaderboardEvent(account, "board:" + week + ":" + category + ":" + eventKey)) return;
            var key = Key(category);
            if (category == "weekly-clears")
                account.Database.SortedSetIncrement(key, account.AccountId, 1);
            else
                account.Database.SortedSetAdd(key, account.AccountId, lowerIsBetter ? -score : score);
            var count = account.Database.SortedSetLength(key);
            if (count > MaxEntries) account.Database.SortedSetRemoveRangeByRank(key, 0, count - MaxEntries - 1);
        }
        public static string Describe(DbAccount account, string category)
        {
            if (account == null) return "No entries.";
            var entries = account.Database.SortedSetRangeByRankWithScores(Key(category), 0, 9, Order.Descending);
            return entries.Length == 0 ? "No entries for " + Week(DateTime.UtcNow) + "." : string.Join(", ", entries.Select(x => x.Element + ":" + (x.Score < 0 ? (-x.Score).ToString(CultureInfo.InvariantCulture) + "ms" : x.Score.ToString(CultureInfo.InvariantCulture))));
        }
    }

    public static class GuildProgressionService
    {
        const int MaxEvents = 512;
        static GuildProgress Load(DbGuild guild) { try { return JsonConvert.DeserializeObject<GuildProgress>(guild.EclipseProgressState) ?? new GuildProgress(); } catch { return new GuildProgress(); } }
        static void Save(DbGuild guild, GuildProgress state) { guild.EclipseProgressState = JsonConvert.SerializeObject(state); guild.FlushAsync().Wait(); }
        public static void RecordDungeonCompletion(DbAccount account, string dungeon, string eventKey)
        {
            if (account == null || account.GuildId <= 0) return;
            var guild = new DbGuild(account);
            lock (guild)
            {
                var state = Load(guild); var week = DateTime.UtcNow.Year + "-W" + CultureInfo.InvariantCulture.Calendar.GetWeekOfYear(DateTime.UtcNow, CalendarWeekRule.FirstFourDayWeek, DayOfWeek.Monday).ToString("00");
                if (state.Week != week) { state.Week = week; state.WeeklyDungeonClears = 0; state.Events.Clear(); }
                if (!state.Events.Add(eventKey)) return;
                state.Trophies[dungeon] = state.Trophies.ContainsKey(dungeon) ? state.Trophies[dungeon] + 1 : 1;
                state.WeeklyDungeonClears++;
                if (state.Events.Count > MaxEvents) state.Events = new HashSet<string>(state.Events.OrderByDescending(x => x).Take(MaxEvents));
                Save(guild, state);
            }
        }
        public static string Describe(DbAccount account)
        {
            if (account == null || account.GuildId <= 0) return "You are not in a guild.";
            var state = Load(new DbGuild(account));
            var trophies = state.Trophies.OrderByDescending(x => x.Value).Take(5).Select(x => x.Key + " x" + x.Value);
            return "Guild weekly dungeon challenge: " + state.WeeklyDungeonClears + " clears | trophies: " + (trophies.Any() ? string.Join(", ", trophies) : "none");
        }
    }
}
