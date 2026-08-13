using System;
using System.Collections.Generic;
using System.Linq;
using wServer.logic;
using wServer.realm.entities;
using wServer.realm.worlds.logic;

namespace wServer.realm
{
    // Per-Realm, non-persistent controller. It is reset when the Realm map resets.
    public sealed class RealmThreatController
    {
        public int Threat { get; private set; }
        private readonly HashSet<int> Triggered = new HashSet<int>();
        private readonly HashSet<int> ActiveThreatEntities = new HashSet<int>();
        public void AddActivity(Realm realm, Enemy enemy)
        {
            if (realm == null || realm.Closed || enemy == null) return;
            Threat = Math.Min(100, Threat + (enemy.ObjectDesc.God ? 5 : 1));
            foreach (var threshold in new[] { 20, 40, 60, 80, 100 }) if (Threat >= threshold && Triggered.Add(threshold)) Spawn(realm, threshold);
        }
        private void Spawn(Realm realm, int threshold)
        {
            var type = threshold == 20 ? "Cube God" : threshold == 40 ? "Grand Sphinx" : "Cube God";
            var enemy = Entity.Resolve(realm.Manager, type) as Enemy;
            if (enemy == null) return;
            var engaged = Math.Max(1, realm.Players.Count);
            enemy.HP = (int)(enemy.HP * (1.0 + .50 * (engaged - 1)));
            enemy.Move(realm.Players.Values.FirstOrDefault()?.X ?? 50, realm.Players.Values.FirstOrDefault()?.Y ?? 50);
            enemy.OnDeath += (sender, args) => Complete(realm, enemy);
            realm.EnterWorld(enemy); ActiveThreatEntities.Add(enemy.Id);
            foreach (var p in realm.Players.Values) p.SendInfo("[Threat] Level " + threshold + " encounter: " + type + ".");
        }
        private void Complete(Realm realm, Enemy enemy)
        {
            if (!ActiveThreatEntities.Remove(enemy.Id)) return;
            foreach (var p in realm.Players.Values)
            {
                var op = "threat:" + realm.Id + ":" + enemy.Id + ":" + p.Client.Account.AccountId;
                MaterialVaultService.TryDeposit(p.Client.Account, "threat_fragment", 1, op);
            }
            // The final per-Realm threat completion is an additional public
            // Citadel access path. It is instance-local and uses the normal
            // Portal/reconnect path, not a direct world transfer.
            if (Threat >= 100 && Triggered.Contains(100))
            {
                var portal = Entity.Resolve(realm.Manager, "Eclipse Citadel Portal");
                if (portal != null)
                {
                    portal.Move(enemy.X, enemy.Y);
                    realm.EnterWorld(portal);
                    realm.Timers.Add(new WorldTimer(180000, (world, time) =>
                    {
                        if (portal.Owner == world) world.LeaveWorld(portal);
                    }));
                    foreach (var p in realm.Players.Values) p.SendInfo("[Threat] The Eclipse Citadel portal has opened for 3 minutes.");
                }
            }
        }
        public void Reset() { Threat = 0; Triggered.Clear(); ActiveThreatEntities.Clear(); }
    }
}
