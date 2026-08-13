using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using common;
using Newtonsoft.Json;
using wServer.networking;
using wServer.realm.entities;
using wServer.realm.worlds;

namespace wServer.realm
{
    // The roster is persisted on every member.  That deliberately avoids a Redis
    // key scan after restart and makes recovery possible when the original leader
    // is offline.  All writes update the complete roster under the party lock.
    public sealed class Party { public string Id; public int Leader; public HashSet<int> Members = new HashSet<int>(); }
    internal sealed class PartyInvite { public string PartyId; public int LeaderId; public long ExpiresUtcTicks; }

    public static class PartyService
    {
        const int Max = 10;
        const int InviteMinutes = 10;
        static readonly ConcurrentDictionary<string, Party> Parties = new ConcurrentDictionary<string, Party>();

        static string Serialize(Party party) { return JsonConvert.SerializeObject(new { party.Id, party.Leader, Members = party.Members.OrderBy(x => x).ToArray() }); }
        static Party Deserialize(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return null;
            try
            {
                dynamic raw = JsonConvert.DeserializeObject(value);
                var id = (string)raw.Id;
                if (string.IsNullOrWhiteSpace(id)) return null;
                var members = ((IEnumerable<dynamic>)raw.Members).Select(x => (int)x).Where(x => x > 0).Distinct().ToArray();
                if (members.Length == 0 || members.Length > Max) return null;
                return new Party { Id = id, Leader = (int)raw.Leader, Members = new HashSet<int>(members) };
            }
            catch { return null; }
        }

        static void Flush(DbAccount account) { account.FlushAsync().GetAwaiter().GetResult(); }
        static void Persist(Party party, Database db)
        {
            var payload = Serialize(party);
            foreach (var memberId in party.Members.ToArray())
            {
                var member = db.GetAccount(memberId);
                if (member == null || member.PartyState != party.Id) continue;
                member.PartyRosterState = payload;
                Flush(member);
            }
        }

        static Party Resolve(DbAccount account, Database db)
        {
            if (account == null || string.IsNullOrWhiteSpace(account.PartyState)) return null;
            Party party;
            if (Parties.TryGetValue(account.PartyState, out party)) return party;
            party = Deserialize(account.PartyRosterState);
            if (party == null || party.Id != account.PartyState || !party.Members.Contains(account.AccountId))
            {
                // A pre-Phase-13 in-memory party cannot be reconstructed safely.
                // Clear only the orphaned identity, never an inventory or account lock.
                account.PartyState = "";
                account.PartyRosterState = "";
                Flush(account);
                return null;
            }
            return Parties.GetOrAdd(party.Id, party);
        }

        public static void Reconstruct(DbAccount account, Database db)
        {
            var party = Resolve(account, db);
            if (party == null) { CleanupInvite(account); return; }
            lock (party)
            {
                foreach (var memberId in party.Members.ToArray())
                {
                    var member = db.GetAccount(memberId);
                    if (member == null || member.PartyState != party.Id)
                        party.Members.Remove(memberId);
                }
                if (party.Members.Count == 0) { Party ignored; Parties.TryRemove(party.Id, out ignored); return; }
                if (!party.Members.Contains(party.Leader)) party.Leader = party.Members.Min();
                Persist(party, db);
            }
            CleanupInvite(account);
        }

        static void CleanupInvite(DbAccount account)
        {
            if (account == null || string.IsNullOrWhiteSpace(account.PartyInviteState)) return;
            try
            {
                var invite = JsonConvert.DeserializeObject<PartyInvite>(account.PartyInviteState);
                if (invite == null || invite.ExpiresUtcTicks <= DateTime.UtcNow.Ticks)
                { account.PartyInviteState = ""; Flush(account); }
            }
            catch { account.PartyInviteState = ""; Flush(account); }
        }

        public static string Create(DbAccount account, Database db)
        {
            Reconstruct(account, db);
            if (!string.IsNullOrEmpty(account.PartyState)) return "Already in a party.";
            var party = new Party { Id = Guid.NewGuid().ToString("N"), Leader = account.AccountId };
            party.Members.Add(account.AccountId);
            account.PartyState = party.Id;
            Parties[party.Id] = party;
            Persist(party, db);
            return "Party created.";
        }

        public static string Invite(DbAccount leader, DbAccount target, Database db)
        {
            var party = Resolve(leader, db);
            if (party == null || party.Leader != leader.AccountId) return "Only the leader may invite.";
            lock (party)
            {
                if (party.Members.Count >= Max) return "Party is full.";
                Reconstruct(target, db);
                if (!string.IsNullOrEmpty(target.PartyState)) return "Player is already in a party.";
                target.PartyInviteState = JsonConvert.SerializeObject(new PartyInvite { PartyId = party.Id, LeaderId = party.Leader, ExpiresUtcTicks = DateTime.UtcNow.AddMinutes(InviteMinutes).Ticks });
                Flush(target);
                return "Invitation sent.";
            }
        }

        public static string Accept(DbAccount account, Database db)
        {
            CleanupInvite(account);
            PartyInvite invite;
            try { invite = JsonConvert.DeserializeObject<PartyInvite>(account.PartyInviteState); }
            catch { invite = null; }
            if (invite == null || invite.ExpiresUtcTicks <= DateTime.UtcNow.Ticks) return "No pending party invitation.";
            Party party;
            if (!Parties.TryGetValue(invite.PartyId, out party))
            {
                // Load the persisted leader snapshot if the server restarted.
                var leader = invite.LeaderId > 0 ? db.GetAccount(invite.LeaderId) : null;
                party = leader == null ? null : Deserialize(leader.PartyRosterState);
                if (party != null) Parties.TryAdd(party.Id, party);
            }
            if (party == null) return "The party invitation is no longer valid.";
            lock (party)
            {
                if (party.Members.Count >= Max) return "Party is full.";
                if (!string.IsNullOrEmpty(account.PartyState)) return "Already in a party.";
                party.Members.Add(account.AccountId);
                account.PartyState = party.Id;
                account.PartyInviteState = "";
                Persist(party, db);
                return "Joined party.";
            }
        }

        public static string Leave(DbAccount account, Database db)
        {
            var party = Resolve(account, db);
            if (party == null) return "Not in a party.";
            lock (party)
            {
                party.Members.Remove(account.AccountId);
                account.PartyState = ""; account.PartyRosterState = ""; account.PartyInviteState = ""; Flush(account);
                if (party.Members.Count == 0) { Party ignored; Parties.TryRemove(party.Id, out ignored); }
                else { if (party.Leader == account.AccountId) party.Leader = party.Members.Min(); Persist(party, db); }
                return "Left party.";
            }
        }

        public static string Kick(DbAccount leader, DbAccount target, Database db)
        {
            var party = Resolve(leader, db);
            if (party == null || party.Leader != leader.AccountId) return "Only the leader may kick.";
            lock (party)
            {
                if (target.AccountId == leader.AccountId || !party.Members.Remove(target.AccountId)) return "Player is not a removable party member.";
                target.PartyState = ""; target.PartyRosterState = ""; target.PartyInviteState = ""; Flush(target);
                Persist(party, db);
                return "Player removed.";
            }
        }

        public static string Status(DbAccount account, Database db)
        {
            var party = Resolve(account, db);
            return party == null ? "Not in a party." : "Party " + party.Id.Substring(0, 6) + ": " + party.Members.Count + "/10; leader " + party.Leader + "; members " + string.Join(", ", party.Members.OrderBy(x => x));
        }
        public static bool SameParty(DbAccount a, DbAccount b) { return a != null && b != null && !string.IsNullOrEmpty(a.PartyState) && a.PartyState == b.PartyState; }
        public static bool IsParty(DbAccount account) { Party party; return account != null && Parties.TryGetValue(account.PartyState, out party) && party.Members.Count > 1; }
        public static void OnDisconnected(DbAccount account) { /* Membership intentionally survives normal reconnects. */ }

        public static void Chat(Player sender, string text)
        {
            if (sender == null || string.IsNullOrWhiteSpace(text)) return;
            foreach (var client in sender.Manager.Clients.Keys.Where(c => c.Player != null && SameParty(sender.Client.Account, c.Account)).ToArray())
                client.Player.SendInfo("[Party] " + sender.Name + ": " + text);
        }
        public static string Gather(Player leader)
        {
            var party = Resolve(leader.Client.Account, leader.Manager.Database);
            if (party == null || party.Leader != leader.Client.Account.AccountId) return "Only the leader may gather.";
            foreach (var client in leader.Manager.Clients.Keys.Where(c => c.Player != null && SameParty(leader.Client.Account, c.Account)).ToArray())
                client.Player.SendInfo("[Party] Gather at " + leader.Owner.Name + " (" + (int)leader.X + "," + (int)leader.Y + ").");
            return "Gather notice sent.";
        }
        public static string Join(Player player, string name)
        {
            var target = player.Manager.Clients.Keys.FirstOrDefault(c => c.Player != null && c.Account != null && c.Account.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (target == null || !SameParty(player.Client.Account, target.Account)) return "That party member is not online.";
            var world = target.Player.Owner;
            if (world == null || world.Deleted || world.IsLimbo || !world.AllowedAccess(player.Client)) return "That party member's world cannot be joined.";
            if (player.Owner == world) return "You are already in that world.";
            player.Reconnect(world); // Uses the ordinary server-authorized reconnect handoff.
            return "Joining " + target.Account.Name + ".";
        }
    }
}
