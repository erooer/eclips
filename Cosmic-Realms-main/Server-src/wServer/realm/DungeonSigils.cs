using System;
using System.Collections.Generic;
using System.Linq;
using common;
using wServer.realm.entities;
using wServer.realm.worlds;

namespace wServer.realm
{
    public sealed class DungeonSigilState
    {
        public long LastPortalOpenUtcTicks;
        public Dictionary<string, string> PendingOpenOperations = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    public static class DungeonSigilService
    {
        private const int OpenRateLimitSeconds = 30;
        private const int PortalLifetimeMs = 60000;

        public static int UnlockThreshold(DungeonCodexDefinition definition)
        {
            if (definition.Difficulty <= 3) return 3;
            if (definition.Difficulty <= 5) return 5;
            if (definition.Difficulty <= 7) return 8;
            return 12;
        }

        public static int FragmentCost(DungeonCodexDefinition definition)
        {
            if (definition.Difficulty <= 3) return 3;
            if (definition.Difficulty <= 5) return 5;
            if (definition.Difficulty <= 7) return 8;
            return 12;
        }

        public static string DescribeAccess(DbAccount account, DungeonCodexDefinition definition)
        {
            var clears = DungeonCodexService.GetCompletionCount(account, definition.Key);
            var threshold = UnlockThreshold(definition);
            return clears < threshold
                ? string.Format("Sigils: locked ({0}/{1} clears). Natural source: {2}", clears, threshold, definition.PortalSource)
                : string.Format("Sigils: unlocked ({0}/{1} clears); cost {2} sigil_fragment. Natural source: {3}", clears, threshold, FragmentCost(definition), definition.PortalSource);
        }

        public static string BuyFragments(Player player, int amount)
        {
            if (player == null || amount <= 0 || amount > 20) return "Buy between 1 and 20 Sigil Fragments.";
            var cost = amount * 100;
            var account = player.Client.Account;
            lock (account)
            {
                if (account.Fame < cost) return "You need " + cost + " fame.";
                var operation = "sigil-buy:" + account.AccountId + ":" + DateTime.UtcNow.Ticks;
                var result = MaterialVaultService.TryDeposit(account, "sigil_fragment", amount, operation);
                if (!result.Success) return result.Error;
                account.Fame -= cost;
                account.FlushAsync().Wait();
                return "Purchased " + amount + " Sigil Fragment(s) for " + cost + " fame.";
            }
        }

        public static string Open(Player player, string requestedDungeon)
        {
            if (player == null || player.Owner == null || player.Owner.Id != World.Nexus)
                return "Dungeon Sigils can only open portals in Nexus.";

            DungeonCodexDefinition definition;
            if (!DungeonCodexService.TryResolveDefinition(requestedDungeon, out definition))
                return "Unknown Codex dungeon. Use /codex to view available entries.";

            var account = player.Client.Account;
            var clears = DungeonCodexService.GetCompletionCount(account, definition.Key);
            var threshold = UnlockThreshold(definition);
            if (clears < threshold) return "Dungeon is locked: " + clears + "/" + threshold + " Codex clears required.";

            var proto = player.Manager.Resources.Worlds.Data[definition.Key];
            if (proto.portals == null || proto.portals.Length == 0) return "Dungeon portal mapping is unavailable.";

            var now = DateTime.UtcNow;
            string operation;
            lock (account)
            {
                var state = Load(account);
                if (state.PendingOpenOperations.ContainsKey(definition.Key)) return "A Sigil portal for this dungeon is already forming.";
                if (state.LastPortalOpenUtcTicks > 0 && now - new DateTime(state.LastPortalOpenUtcTicks, DateTimeKind.Utc) < TimeSpan.FromSeconds(OpenRateLimitSeconds))
                    return "Wait before opening another Sigil portal.";
                operation = "sigil-open:" + account.AccountId + ":" + definition.Key + ":" + now.Ticks;
                state.PendingOpenOperations[definition.Key] = operation;
                Save(account, state);
            }

            try
            {
                var portal = new Portal(player.Manager, (ushort)proto.portals[0], PortalLifetimeMs)
                {
                    PlayerOpened = true,
                    Opener = player.Name
                };
                portal.WorldInstanceSet += (sender, destination) => FinalizeOpen(player.Owner, portal, account, definition, operation);
                portal.Move(player.X + 2, player.Y);
                player.Owner.EnterWorld(portal);
                PartyService.AnnounceSigilPortal(player, portal, definition.DisplayName, false);
                // Dynamic portals report readiness asynchronously. No fragment is
                // consumed until the destination has registered successfully.
                player.Owner.Timers.Add(new WorldTimer(30000, (world, time) =>
                {
                    if (portal.Readiness == PortalReadiness.Failed || portal.Readiness == PortalReadiness.Preparing)
                    {
                        if (portal.Owner == world) world.LeaveWorld(portal);
                        ClearPending(account, definition.Key, operation, false);
                    }
                }));
                return "Sigil portal is forming. Fragments are charged only when it is ready.";
            }
            catch (Exception ex)
            {
                ClearPending(account, definition.Key, operation, false);
                return "Sigil portal creation failed; no fragments were consumed. " + ex.Message;
            }
        }

        private static void FinalizeOpen(World sourceWorld, Portal portal, DbAccount account, DungeonCodexDefinition definition, string operation)
        {
            var spend = MaterialVaultService.TrySpend(account, "sigil_fragment", FragmentCost(definition), operation);
            if (!spend.Success)
            {
                if (portal.Owner == sourceWorld) sourceWorld.LeaveWorld(portal);
                ClearPending(account, definition.Key, operation, false);
                return;
            }
            ClearPending(account, definition.Key, operation, true);
            var opener = sourceWorld.Players.Values.FirstOrDefault(p => p.Client != null && p.Client.Account != null && p.Client.Account.AccountId == account.AccountId);
            if (opener != null) PartyService.AnnounceSigilPortal(opener, portal, definition.DisplayName, true);
        }

        private static void ClearPending(DbAccount account, string dungeonKey, string operation, bool opened)
        {
            lock (account)
            {
                var state = Load(account);
                string existing;
                if (state.PendingOpenOperations.TryGetValue(dungeonKey, out existing) && existing == operation)
                    state.PendingOpenOperations.Remove(dungeonKey);
                if (opened) state.LastPortalOpenUtcTicks = DateTime.UtcNow.Ticks;
                Save(account, state);
            }
        }

        private static DungeonSigilState Load(DbAccount account)
        {
            try { return Newtonsoft.Json.JsonConvert.DeserializeObject<DungeonSigilState>(account.DungeonSigilState) ?? new DungeonSigilState(); }
            catch { return new DungeonSigilState(); }
        }

        private static void Save(DbAccount account, DungeonSigilState state)
        {
            account.DungeonSigilState = Newtonsoft.Json.JsonConvert.SerializeObject(state);
            account.FlushAsync().Wait();
        }
    }
}
