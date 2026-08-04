using common.resources;
using wServer.realm;
using wServer.realm.entities;

namespace wServer.logic.behaviors
{
    // Spawns a finite, server-authoritative lifetime total for one boss form.
    // The counter is deliberately separate from behavior state so re-entering
    // the state cannot reset it. A transform creates a new host Entity and
    // therefore legitimately receives a fresh counter.
    class LifetimeSpawn : Behavior
    {
        private readonly ushort _childType;
        private readonly int _maxTotal;
        private readonly bool _givesNoXp;
        private readonly object _lifetimeCounterKey = new object();

        public LifetimeSpawn(string child, int maxTotal = 5, bool givesNoXp = true)
        {
            _childType = GetObjType(child);
            _maxTotal = maxTotal;
            _givesNoXp = givesNoXp;
        }

        protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
        {
            var spawned = host.StateStorage.ContainsKey(_lifetimeCounterKey)
                ? (int)host.StateStorage[_lifetimeCounterKey]
                : 0;

            while (spawned < _maxTotal)
            {
                var child = Entity.Resolve(host.Manager, _childType);
                child.Move(host.X, host.Y);
                child.GivesNoXp = _givesNoXp;

                var parentEnemy = host as Enemy;
                var childEnemy = child as Enemy;
                if (parentEnemy != null && childEnemy != null)
                {
                    if (!child.GivesNoXp)
                        child.GivesNoXp = parentEnemy.GivesNoXp;

                    childEnemy.ParentEntity = parentEnemy;
                    childEnemy.Terrain = parentEnemy.Terrain;
                    if (parentEnemy.Spawned)
                    {
                        childEnemy.Spawned = true;
                        childEnemy.ApplyConditionEffect(new ConditionEffect
                        {
                            Effect = ConditionEffectIndex.Invisible,
                            DurationMS = -1
                        });
                    }
                }

                host.Owner.EnterWorld(child);
                spawned++;
                host.StateStorage[_lifetimeCounterKey] = spawned;
            }
        }

        protected override void TickCore(Entity host, RealmTime time, ref object state)
        {
            // All permitted spawns are performed on state entry. Deaths never
            // free capacity, so the lifetime total cannot be replenished.
        }
    }
}
