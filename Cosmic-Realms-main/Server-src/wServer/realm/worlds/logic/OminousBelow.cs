using common.resources;
using wServer.networking;
using wServer.logic;
using wServer.realm.entities;
using System.Linq;
using log4net;

namespace wServer.realm.worlds.logic
{
    // The name deliberately matches OminousBelow.jw for DynamicWorld.TryGetWorld.
    class OminousBelow : World
    {
        private static readonly ILog Log = LogManager.GetLogger(typeof(OminousBelow));
        private bool _ferrymanDefeated;
        private bool _veyraDefeated;
        private bool _completed;
        private int _lanternsDestroyed;
        private int _gaolersDefeated;
        private int _sealsDestroyed;
        private int _bargeAnchors;
        private int _chainAnchors;
        private int _ritualPillars;
        private Enemy _ferryman;
        private Enemy _veyra;
        private Enemy _ominousOne;

        public OminousBelow(ProtoWorld proto, Client client = null) : base(proto) { }

        public override int EnterWorld(Entity entity)
        {
            var id = base.EnterWorld(entity);
            var player = entity as Player;
            if (player != null)
                SendObjectiveSummary(player);
            var enemy = entity as Enemy;
            if (enemy != null)
            {
                enemy.OnDeath += OnEnemyDeath;
                if (enemy.ObjectDesc.ObjectId == "Veyra, Warden of Chains")
                {
                    _veyra = enemy;
                    _veyra.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                }
                if (enemy.ObjectDesc.ObjectId == "The Ominous One")
                {
                    _ominousOne = enemy;
                    _ominousOne.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                }
                if (enemy.ObjectDesc.ObjectId == "The Faceless Ferryman")
                {
                    _ferryman = enemy;
                    // The arena is closed until all three instance-local lanterns are gone.
                    // Stasis stops behavior ticking; Invincible prevents any damage race.
                    _ferryman.ApplyConditionEffect(ConditionEffectIndex.Stasis);
                    _ferryman.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                    Log.Info("OminousBelow: Ferryman dormant; waiting for 3 lanterns.");
                }
                if (enemy.ObjectDesc.ObjectId == "Soul Barge Anchor")
                {
                    _bargeAnchors++;
                    if (_ferryman != null) _ferryman.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                    Log.InfoFormat("OminousBelow: barge anchor registered; count={0}.", _bargeAnchors);
                }
                if (enemy.ObjectDesc.ObjectId == "Chain Anchor")
                {
                    _chainAnchors++;
                    if (_veyra != null) _veyra.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                }
                if (enemy.ObjectDesc.ObjectId == "Ritual Pillar")
                {
                    _ritualPillars++;
                    if (_ominousOne != null) _ominousOne.ApplyConditionEffect(ConditionEffectIndex.Invincible);
                }
            }
            return id;
        }

        private void OnEnemyDeath(object sender, BehaviorEventArgs args)
        {
            var enemy = sender as Enemy;
            if (enemy == null) return;
            switch (enemy.ObjectDesc.ObjectId)
            {
                case "Ominous Soul Lantern":
                    if (_lanternsDestroyed >= 3) break;
                    _lanternsDestroyed++;
                    Log.InfoFormat("OminousBelow: lantern destroyed; count={0}/3.", _lanternsDestroyed);
                    Announce(_lanternsDestroyed == 1 ? "The first lantern has gone dark." : _lanternsDestroyed == 2 ? "Two lanterns have gone dark." : "The final lantern has gone dark. The Ferryman awaits.");
                    if (_lanternsDestroyed == 3)
                    {
                        OpenFerrymanRoom();
                        if (_ferryman != null)
                        {
                            _ferryman.ApplyConditionEffect(ConditionEffectIndex.Stasis, 0);
                            _ferryman.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        }
                        Log.Info("OminousBelow: Ferryman arena opened and encounter activated.");
                        Announce("The Ferryman arena gate opens.");
                    }
                    BroadcastObjectiveSummary();
                    break;
                case "The Faceless Ferryman":
                    if (!_ferrymanDefeated) { _ferrymanDefeated = true; ClearDivider(47); Log.Info("OminousBelow: Ferryman defeated; complete prison divider removed."); Announce("The Ferryman's passage opens into the prison."); }
                    break;
                case "Soul Barge Anchor":
                    if (--_bargeAnchors <= 0 && _ferryman != null)
                    {
                        _bargeAnchors = 0;
                        _ferryman.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        Log.Info("OminousBelow: all barge anchors destroyed; Ferryman vulnerable.");
                        Announce("The Soul Barges are destroyed. The Ferryman can be harmed.");
                    }
                    else Log.InfoFormat("OminousBelow: barge anchor destroyed; remaining={0}.", _bargeAnchors);
                    break;
                case "The First Gaoler":
                case "The Last Gaoler":
                    _gaolersDefeated++;
                    Announce("A Gaoler falls (" + _gaolersDefeated + "/2).");
                    if (_gaolersDefeated == 2 && _veyra != null)
                    {
                        _veyra.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        Announce("The prison wards fail. Veyra is vulnerable.");
                    }
                    BroadcastObjectiveSummary();
                    break;
                case "Ominous Seal":
                    _sealsDestroyed++;
                    Announce("An abyssal seal breaks (" + _sealsDestroyed + "/4).");
                    if (_sealsDestroyed == 4 && _ominousOne != null)
                    {
                        _ominousOne.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        Announce("The Ominous One awakens.");
                    }
                    BroadcastObjectiveSummary();
                    break;
                case "Chain Anchor":
                    if (--_chainAnchors <= 0 && _veyra != null)
                    {
                        _chainAnchors = 0;
                        _veyra.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        Announce("The final chain breaks. Veyra can be harmed.");
                    }
                    break;
                case "Ritual Pillar":
                    if (--_ritualPillars <= 0 && _ominousOne != null)
                    {
                        _ritualPillars = 0;
                        _ominousOne.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
                        // Do not depend on a radius-based "no entities" behavior
                        // transition here. Removed anchors can remain in a spatial
                        // query for the rest of a tick, leaving the boss stuck in
                        // its stagger. The instance owns this completion event.
                        SwitchOminousState("World Below Barrage");
                        Announce("The ritual is interrupted. The Ominous One is exposed.");
                    }
                    break;
                case "Veyra, Warden of Chains":
                    if (!_veyraDefeated)
                    {
                        _veyraDefeated = true;
                        // This is a full prison divider, like the Ferryman exit. A
                        // narrow opening leaves the rest of the wall's backing map
                        // collision in place and makes the transition look blocked.
                        ClearDivider(81);
                        Log.Info("OminousBelow: Veyra defeated; complete abyss divider removed.");
                        Announce("Veyra's chains break. The descent into the abyss opens.");
                    }
                    break;
                case "The Ominous One":
                    Complete();
                    break;
            }
        }

        private void ClearGate(int x)
        {
            // LeaveWorld removes the entity/collision map only. Clear the backing map
            // tile too, otherwise IsPassable still sees a fully occupied invisible wall.
            for (var y = 28; y <= 32; y++)
            {
                // Remove any static object on a gate tile. The map itself is the
                // authority for these coordinates, so this does not depend on a
                // particular wall subclass or ObjectId being used at runtime.
                foreach (var gate in StaticObjects.Values.Where(e => (int)e.X == x && (int)e.Y == y).ToArray())
                    LeaveWorld(gate);

                var tile = Map[x, y];
                tile.ObjId = 0;
                tile.ObjType = 0;
                tile.ObjDesc = null;
                tile.ObjCfg = null;
                tile.UpdateCount++;
            }
            Log.InfoFormat("OminousBelow: cleared physical gate at x={0}, y=28..32; centerPassable={1}.", x, IsPassable(x + .5, 30.5));
        }

        private void ClearDivider(int x)
        {
            // A progression objective removes its entire divider, not merely a slit.
            // This makes the completion state visually unambiguous and clears both
            // the server collision map and the static wall entities.
            var removed = 0;
            for (var y = 1; y < Map.Height - 1; y++)
            {
                foreach (var wall in StaticObjects.Values.Where(e => (int)e.X == x && (int)e.Y == y).ToArray())
                {
                    LeaveWorld(wall);
                    removed++;
                }

                var tile = Map[x, y];
                tile.ObjId = 0;
                tile.ObjType = 0;
                tile.ObjDesc = null;
                tile.ObjCfg = null;
                tile.UpdateCount++;
            }
            Log.InfoFormat("OminousBelow: removed complete progression divider at x={0}; staticWalls={1}; centerPassable={2}.", x, removed, IsPassable(x + .5, 30.5));
        }

        private void OpenFerrymanRoom()
        {
            // x=30 is the final maze partition visible in front of the arena;
            // x=32 is the arena divider itself. Both vanish as one transition.
            ClearDivider(30);
            ClearDivider(32);
            Log.Info("OminousBelow: all final maze walls before the Ferryman have been removed.");
        }

        private void SwitchOminousState(string stateName)
        {
            if (_ominousOne == null || _ominousOne.CurrentState == null) return;

            var root = _ominousOne.CurrentState;
            while (root.Parent != null) root = root.Parent;
            var target = root.States.FirstOrDefault(s => s.Name == stateName);
            if (target == null)
            {
                Log.WarnFormat("OminousBelow: unable to find Ominous One state '{0}'.", stateName);
                return;
            }

            _ominousOne.SwitchTo(target);
            Log.InfoFormat("OminousBelow: Ominous One advanced to '{0}' after final ritual pillar.", stateName);
        }

        private void Complete()
        {
            if (_completed) return;
            _completed = true;
            Announce("The Ominous One has fallen. The way home is open.");
            foreach (var enemy in Enemies.Values.Where(e => e != _ominousOne).ToArray()) LeaveWorld(enemy);
            foreach (var projectile in Projectiles.Values.ToArray()) LeaveWorld(projectile);
            var chest = new Container(Manager, 0xF918, 60000, true);
            chest.Move(96.5f, 25.5f);
            chest.Inventory[0] = Manager.Resources.GameData.Items[0xF91C];
            chest.Inventory[1] = Manager.Resources.GameData.Items[0x0A1F]; // Potion of Attack
            chest.Inventory[2] = Manager.Resources.GameData.Items[0x0A20]; // Potion of Defense
            EnterWorld(chest);

            // Completion-only exit: no permanent boss-room portal, but a run
            // can never strand players after the completion chest appears.
            var exit = Entity.Resolve(Manager, 0xF919);
            exit.Move(101.5f, 25.5f);
            EnterWorld(exit);
            Timers.Add(new WorldTimer(60000, (world, time) =>
            {
                if (exit.Owner == world) world.LeaveWorld(exit);
            }));
        }

        private void BroadcastObjectiveSummary()
        {
            foreach (var player in Players.Values) SendObjectiveSummary(player);
        }

        private void SendObjectiveSummary(Player player)
        {
            if (player == null || _completed) return;
            if (_lanternsDestroyed < 3)
                player.SendInfo("[Objective] Soul Lanterns: " + _lanternsDestroyed + "/3");
            else if (!_ferrymanDefeated)
                player.SendInfo("[Objective] Defeat the Faceless Ferryman.");
            else if (_gaolersDefeated < 2)
                player.SendInfo("[Objective] Gaolers: " + _gaolersDefeated + "/2");
            else if (!_veyraDefeated)
                player.SendInfo("[Objective] Defeat Veyra, Warden of Chains.");
            else if (_sealsDestroyed < 4)
                player.SendInfo("[Objective] Ominous Seals: " + _sealsDestroyed + "/4");
            else
                player.SendInfo("[Objective] Defeat the Ominous One.");
        }

        private void Announce(string text)
        {
            foreach (var player in Players.Values) player.SendInfo(text);
        }
    }
}
