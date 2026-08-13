using System;
using System.Linq;
using common.resources;
using wServer.realm.entities;

namespace wServer.realm.worlds.logic
{
    // Runtime-owned progression keeps the three wings and final gate instance-local.
    // Nothing is persisted on the world: a new Citadel is always a clean encounter.
    class EclipseCitadel : World
    {
        private Enemy _regent, _enginekeeper, _crowned;
        private bool _populated, _courtComplete, _zenithComplete, _engineComplete, _crownSpawned, _completed;
        private int _courtGuards, _engineNodes;

        public EclipseCitadel(ProtoWorld proto, wServer.networking.Client client = null) : base(proto)
        {
            DungeonAnomalyService.Attach(this, DungeonAnomalyService.Roll(
                DungeonCodexService.All.FirstOrDefault(d => d.Key == "EclipseCitadel"), new Random(Id)));
        }

        public override int EnterWorld(Entity entity)
        {
            var id = base.EnterWorld(entity);
            if (entity is Player)
            {
                if (!_populated) Populate();
                SendProgress(entity as Player);
                return id;
            }

            var enemy = entity as Enemy;
            if (enemy == null) return id;
            DungeonAnomalyService.Apply(this, enemy);
            enemy.OnDeath += (sender, args) => OnEnemyDeath(enemy);
            switch (enemy.ObjectDesc.ObjectId)
            {
                case "The Hollow Regent":
                    _regent = enemy;
                    _regent.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                    break;
                case "The Umbra Enginekeeper":
                    _enginekeeper = enemy;
                    _enginekeeper.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                    break;
                case "The Crowned Eclipse":
                    _crowned = enemy;
                    break;
                case "Lightless Court Guard":
                    _courtGuards++;
                    break;
                case "Umbra Engine Node":
                    _engineNodes++;
                    break;
            }
            return id;
        }

        private void Populate()
        {
            _populated = true;
            // Lightless Court (west), Broken Zenith (east), Umbra Engine (north).
            Spawn("Lightless Court Guard", 3, 5); Spawn("Lightless Court Guard", 5, 7); Spawn("Lightless Court Guard", 7, 5); Spawn("The Hollow Regent", 5, 4);
            Spawn("Zenith Astralist", 21, 5); Spawn("Zenith Astralist", 23, 7); Spawn("Zenith Astralist", 25, 5); Spawn("The Zenith Warden", 23, 4);
            Spawn("Umbra Engine Node", 12, 14); Spawn("Umbra Engine Node", 15, 12); Spawn("Umbra Engine Node", 18, 14); Spawn("The Umbra Enginekeeper", 15, 16);
            Announce("[Citadel] Complete the Lightless Court, Broken Zenith, and Umbra Engine.");
        }

        private void Spawn(string objectId, float x, float y)
        {
            var entity = Entity.Resolve(Manager, objectId);
            if (entity == null) throw new InvalidOperationException("Missing Citadel entity: " + objectId);
            entity.Move(x, y);
            EnterWorld(entity);
        }

        private void OnEnemyDeath(Enemy enemy)
        {
            switch (enemy.ObjectDesc.ObjectId)
            {
                case "Lightless Court Guard":
                    _courtGuards = Math.Max(0, _courtGuards - 1);
                    if (_courtGuards == 0 && _regent != null)
                    {
                        _regent.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        Announce("[Citadel] The Hollow Regent's guard has fallen.");
                    }
                    break;
                case "Umbra Engine Node":
                    _engineNodes = Math.Max(0, _engineNodes - 1);
                    if (_engineNodes == 0 && _enginekeeper != null)
                    {
                        _enginekeeper.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        Announce("[Citadel] The Umbra Engine is exposed.");
                    }
                    break;
                case "The Hollow Regent": _courtComplete = true; CompleteWing("Lightless Court"); break;
                case "The Zenith Warden": _zenithComplete = true; CompleteWing("Broken Zenith"); break;
                case "The Umbra Enginekeeper": _engineComplete = true; CompleteWing("Umbra Engine"); break;
                case "Crown Shadow":
                    if (_crowned != null && !Enemies.Values.Any(e => e.ObjectDesc.ObjectId == "Crown Shadow"))
                    {
                        _crowned.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        Announce("[Citadel] The Eclipse Guard is broken. The Crowned Eclipse is vulnerable.");
                    }
                    break;
                case "The Crowned Eclipse": CompleteCitadel(); break;
            }
        }

        private void CompleteWing(string wing)
        {
            Announce("[Citadel] " + wing + ": Complete.");
            if (_courtComplete && _zenithComplete && _engineComplete && !_crownSpawned)
            {
                _crownSpawned = true;
                Spawn("The Crowned Eclipse", 15, 24);
                Announce("[Citadel] All wings complete. The Crowned Eclipse descends.");
            }
            BroadcastProgress();
        }

        private void CompleteCitadel()
        {
            if (_completed) return;
            _completed = true;
            DungeonAnomalyService.Cleanup(this);
            foreach (var player in Players.Values.ToArray())
            {
                var account = player.Client.Account;
                MaterialVaultService.TryDeposit(account, "imprint_shard", 2, "citadel:" + Id + ":shards:" + account.AccountId);
                MaterialVaultService.TryDeposit(account, "echo_dust", 25, "citadel:" + Id + ":echo:" + account.AccountId);
                AccountProgressionService.Award(account, "clear:EclipseCitadel");
            }
            var chest = new Container(Manager, 0xF96E, 90000, true);
            chest.Move(15.5f, 23.5f);
            chest.Inventory[0] = Manager.Resources.GameData.Items[0xF96A]; // Citadel Mark
            chest.Inventory[1] = Manager.Resources.GameData.Items[0x0A1F]; // Attack potion
            chest.Inventory[2] = Manager.Resources.GameData.Items[0x0A20]; // Defense potion
            // A chest is always useful, but its Citadel unique is deliberately a bounded bonus.
            if (Rand.NextDouble() < 0.12)
            {
                var uniqueTypes = new ushort[] { 0xF96B, 0xF96C, 0xF96D, 0xF970 };
                chest.Inventory[3] = Manager.Resources.GameData.Items[uniqueTypes[Rand.Next(uniqueTypes.Length)]];
            }
            EnterWorld(chest);
            var exit = Entity.Resolve(Manager, (ushort)0xF96F);
            exit.Move(18.5f, 23.5f);
            EnterWorld(exit);
            Timers.Add(new WorldTimer(90000, (world, time) => { if (exit.Owner == world) world.LeaveWorld(exit); }));
            Announce("[Citadel] The Crowned Eclipse has fallen. Claim the completion chest; the Nexus exit remains for 90 seconds.");
        }

        private void BroadcastProgress() { foreach (var player in Players.Values) SendProgress(player); }
        private void SendProgress(Player player)
        {
            if (player == null || _completed) return;
            player.SendInfo("[Citadel] Lightless Court: " + (_courtComplete ? "Complete" : "Active") +
                            " | Broken Zenith: " + (_zenithComplete ? "Complete" : "Active") +
                            " | Umbra Engine: " + (_engineComplete ? "Complete" : "Active") +
                            (_crownSpawned ? " | Crowned Eclipse: Active" : ""));
            var anomaly = DungeonAnomalyService.Describe(this);
            if (anomaly != "No active dungeon anomaly.") player.SendInfo(anomaly);
        }
        private void Announce(string message) { foreach (var player in Players.Values) player.SendInfo(message); }
    }
}
