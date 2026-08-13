using System;
using System.Collections.Concurrent;
using System.Linq;
using common;
using wServer.realm.entities;
using wServer.realm.worlds;

namespace wServer.realm
{
    // The fragment debit happens only after the dynamic portal has a registered
    // destination. A failed preparation therefore cannot consume Citadel access.
    public static class EclipseCitadelAccessService
    {
        public const int FragmentCost = 25;
        private const int PortalLifetimeMs = 90000;
        private static readonly ConcurrentDictionary<int, string> Pending = new ConcurrentDictionary<int, string>();

        public static string Describe(DbAccount account)
        {
            return "[Citadel] Eclipse Citadel (Difficulty 10) | " + FragmentCost + " citadel_fragment | balance " +
                   MaterialVaultService.GetBalance(account, "citadel_fragment") + " | /citadel open";
        }

        public static string Open(Player player)
        {
            if (player == null || player.Owner == null || player.Owner.Id != World.Nexus)
                return "Citadel access can only be opened from Nexus.";
            var account = player.Client.Account;
            var operation = "citadel-open:" + account.AccountId + ":" + DateTime.UtcNow.Ticks;
            if (!Pending.TryAdd(account.AccountId, operation)) return "A Citadel portal is already forming for this account.";
            try
            {
                if (MaterialVaultService.GetBalance(account, "citadel_fragment") < FragmentCost)
                {
                    Pending.TryRemove(account.AccountId, out operation);
                    return "You need " + FragmentCost + " citadel_fragment.";
                }
                var portal = new Portal(player.Manager, 0xF960, PortalLifetimeMs) { PlayerOpened = true, Opener = player.Name };
                portal.WorldInstanceSet += (sender, destination) => Finalize(player.Owner, portal, account, operation);
                portal.Move(player.X + 2, player.Y);
                player.Owner.EnterWorld(portal);
                PartyService.AnnounceSigilPortal(player, portal, "Eclipse Citadel", false);
                player.Owner.Timers.Add(new WorldTimer(30000, (world, time) =>
                {
                    if (portal.Readiness == PortalReadiness.Preparing || portal.Readiness == PortalReadiness.Failed)
                    {
                        if (portal.Owner == world) world.LeaveWorld(portal);
                        string ignored; Pending.TryRemove(account.AccountId, out ignored);
                    }
                }));
                return "Eclipse Citadel portal is forming. Fragments are charged only when it is ready.";
            }
            catch (Exception ex)
            {
                string ignored; Pending.TryRemove(account.AccountId, out ignored);
                return "Citadel portal creation failed; no fragments were consumed. " + ex.Message;
            }
        }

        private static void Finalize(World source, Portal portal, DbAccount account, string operation)
        {
            try
            {
                var debit = MaterialVaultService.TrySpend(account, "citadel_fragment", FragmentCost, operation);
                if (!debit.Success && !debit.Duplicate)
                {
                    if (portal.Owner == source) source.LeaveWorld(portal);
                    return;
                }
                var opener = source.Players.Values.FirstOrDefault(p => p.Client.Account.AccountId == account.AccountId);
                if (opener != null) PartyService.AnnounceSigilPortal(opener, portal, "Eclipse Citadel", true);
            }
            finally
            {
                string ignored; Pending.TryRemove(account.AccountId, out ignored);
            }
        }
    }
}
