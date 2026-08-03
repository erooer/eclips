using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using common;
using common.resources;
using wServer.realm.worlds;

namespace wServer.realm.entities
{
    public enum PortalReadiness
    {
        Closed,
        Preparing,
        Ready,
        Failed
    }

    public class Portal : StaticObject
    {
        public Portal(RealmManager manager, ushort objType, int? life)
            : base(manager, ValidatePortal(manager, objType), life, false, true, false)
        {
            _usable = new SV<bool>(this, StatsType.PortalUsable, true);
            Locked = manager.Resources.GameData.Portals[ObjectType].Locked;
            Opener = "";
        }
        
        private readonly SV<bool> _usable;
        public bool PlayerOpened { get; set; }
        public string Opener { get; set; }

        public bool Usable
        {
            get { return _usable.GetValue(); }
            set { _usable.SetValue(value);}
        }

        public bool Locked { get; private set; }

        public readonly object CreateWorldLock = new object();
        public Task CreateWorldTask { get; set; }
        public DateTime? CreateWorldStartedUtc { get; set; }
        public int CreatingPlayerId { get; set; }
        public World WorldInstance { get; set; }
        public event EventHandler<World> WorldInstanceSet;
        public PortalReadiness Readiness { get; private set; } = PortalReadiness.Ready;

        public override void Init(World owner)
        {
            base.Init(owner);

            // Map-spawned nested portals (including Cyberious) must prepare their
            // destination before a player can use them.  Static destinations are
            // linked here as well, so USEPORTAL has no factory work to perform.
            var proto = FindDestination();
            if (!proto.HasValue)
                return;
            if (proto.Value.id < 0)
            {
                WorldInstance = owner.Manager.GetWorld(proto.Value.id);
                Readiness = WorldInstance == null ? PortalReadiness.Failed : PortalReadiness.Ready;
                return;
            }

            if (Readiness == PortalReadiness.Ready && WorldInstance != null)
                return;

            // Nexus/static worlds are built before RealmManager.Run creates the
            // logic queue.  Leave them untouched until Run schedules the warmup.
            if (owner.Manager.Logic != null)
                PrepareSpawnedDestination();
        }

        public void PrepareSpawnedDestination()
        {
            if (Owner == null || Owner.Manager.Logic == null)
                return;
            var proto = FindDestination();
            if (!proto.HasValue || proto.Value.id < 0)
                return;
            Usable = false;
            BeginDestinationPreparation(Owner.Manager, null, "spawn");
        }

        private static ushort ValidatePortal(RealmManager manager, ushort objType)
        {
            var portals = manager.Resources.GameData.Portals;
            if (!portals.ContainsKey(objType))
            {
                Log.Warn($"Portal {objType.To4Hex()} does not exist. Using Portal of Cowardice.");
                objType = 0x0703; // default to Portal of Cowardice
            }

            return objType;
        }

        protected override void ImportStats(StatsType stats, object val)
        {
            if (stats == StatsType.PortalUsable) Usable = (int)val != 0;
            base.ImportStats(stats, val);
        }

        protected override void ExportStats(IDictionary<StatsType, object> stats)
        {
            stats[StatsType.PortalUsable] = Usable ? 1 : 0;
            base.ExportStats(stats);
        }

        public override bool HitByProjectile(Projectile projectile, RealmTime time)
        {
            return false;
        }

        public bool BeginDestinationPreparation(RealmManager manager, networking.Client client, string reason)
        {
            lock (CreateWorldLock)
            {
                if (Readiness == PortalReadiness.Ready && WorldInstance != null)
                    return true;
                if (Readiness == PortalReadiness.Preparing)
                    return false;

                var proto = FindDestination();
                if (!proto.HasValue)
                {
                    Transition(PortalReadiness.Failed, "no destination mapping");
                    return false;
                }
                if (proto.Value.id < 0)
                {
                    WorldInstance = manager.GetWorld(proto.Value.id);
                    Transition(WorldInstance == null ? PortalReadiness.Failed : PortalReadiness.Ready, "static destination");
                    return WorldInstance != null;
                }

                Usable = false;
                CreateWorldStartedUtc = DateTime.UtcNow;
                CreatingPlayerId = client?.Player?.Id ?? 0;
                Transition(PortalReadiness.Preparing, reason + "; destination=" + proto.Value.name);
                CreateWorldTask = Task.Factory.StartNew(() =>
                {
                    var queueMs = (DateTime.UtcNow - CreateWorldStartedUtc.Value).TotalMilliseconds;
                    Log.InfoFormat("[DYNAMIC_PORTAL_TRACE] worker started portal={0} type=0x{1:x4} queueMs={2:0}.", Id, ObjectType, queueMs);
                    World candidate;
                    var factoryStart = DateTime.UtcNow;
                    DynamicWorld.TryGetWorld(proto.Value, client, out candidate);
                    Log.InfoFormat("[DYNAMIC_PORTAL_TRACE] factory lookup portal={0} elapsedMs={1:0}.", Id, (DateTime.UtcNow - factoryStart).TotalMilliseconds);
                    candidate = candidate ?? new World(proto.Value);

                    // Only registration/initialization mutates live world state, and it
                    // is deliberately returned to the single logic thread.
                    manager.Logic.AddPendingAction(_ => CompletePreparation(manager, candidate));
                }, System.Threading.CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
                CreateWorldTask.ContinueWith(t =>
                {
                    if (!t.IsFaulted && !t.IsCanceled) return;
                    var detail = t.IsFaulted ? t.Exception.Flatten().ToString() : "worker canceled";
                    manager.Logic.AddPendingAction(_ => FailPreparation(detail));
                }, TaskScheduler.Default);
                return false;
            }
        }

        private ProtoWorld? FindDestination()
        {
            foreach (var proto in Program.Resources.Worlds.Data.Values)
                if (proto.portals != null && proto.portals.Contains(ObjectType))
                    return proto;
            return null;
        }

        private void CompletePreparation(RealmManager manager, World candidate)
        {
            try
            {
                var registerStart = DateTime.UtcNow;
                var world = manager.AddWorld(candidate);
                if (PlayerOpened)
                {
                    world.PlayerDungeon = true;
                    world.Opener = Opener;
                    world.Invites = new HashSet<string>();
                    world.Invited = new HashSet<string>();
                }
                lock (CreateWorldLock)
                {
                    WorldInstance = world;
                    Usable = true;
                    Transition(PortalReadiness.Ready, "registered=" + world.Id + "; registerMs=" + (DateTime.UtcNow - registerStart).TotalMilliseconds.ToString("0"));
                }
                WorldInstanceSet?.Invoke(this, world);
            }
            catch (Exception ex)
            {
                FailPreparation(ex.ToString());
            }
        }

        private void FailPreparation(string detail)
        {
            lock (CreateWorldLock)
            {
                WorldInstance = null;
                Usable = false;
                Transition(PortalReadiness.Failed, detail);
            }
        }

        private void Transition(PortalReadiness state, string detail)
        {
            Readiness = state;
            var elapsed = CreateWorldStartedUtc.HasValue ? (DateTime.UtcNow - CreateWorldStartedUtc.Value).TotalMilliseconds : 0;
            Log.InfoFormat("[DYNAMIC_PORTAL_TRACE] state portal={0} type=0x{1:x4} state={2} elapsedMs={3:0} detail={4}", Id, ObjectType, state, elapsed, detail);
        }
    }
}
