using System;
using common.resources;
using wServer.realm;
using wServer.realm.worlds.logic;

namespace wServer.logic.behaviors
{
    // Deliberately separate from DropPortalOnDeath: flagship encounter access
    // must not be probabilistic and must never duplicate if death propagation is
    // invoked again for the same entity.
    class GuaranteedPortalOnDeath : Behavior
    {
        private readonly ushort _target;
        private readonly int? _timeout;
        private readonly object _spawnedKey = new object();

        public GuaranteedPortalOnDeath(string target, int? timeout = null)
        {
            _target = GetObjType(target);
            _timeout = timeout;
        }

        protected internal override void Resolve(State parent)
        {
            parent.Death += (sender, e) =>
            {
                var host = e.Host;
                var owner = host.Owner;

                // Admin-created entities are not a legitimate Realm-event
                // completion and therefore must not create progression access.
                if (host.PlayerSpawned)
                    return;

                if (!host.CurrentState.Is(parent))
                    return;

                // StateStorage is per entity, unlike behavior instances, so this
                // protects a single encounter without suppressing future Omens.
                if (host.StateStorage.ContainsKey(_spawnedKey))
                {
                    Log.WarnFormat("[HAUNTED_OMEN_PORTAL] duplicate death callback ignored boss={0} world={1}", host.Id, owner?.Id);
                    return;
                }
                host.StateStorage[_spawnedKey] = true;

                try
                {
                    if (owner == null)
                        throw new InvalidOperationException("Haunted Omen has no owning world during portal creation.");

                    PortalDesc portalDesc;
                    if (!host.Manager.Resources.GameData.Portals.TryGetValue(_target, out portalDesc))
                        throw new InvalidOperationException("Ominous Below portal descriptor is unavailable.");

                    var portal = Entity.Resolve(host.Manager, _target);
                    if (portal == null)
                        throw new InvalidOperationException("Ominous Below portal entity could not be resolved.");

                    portal.Move(host.X, host.Y);
                    owner.EnterWorld(portal);

                    var timeoutSeconds = _timeout ?? portalDesc.Timeout;
                    if (timeoutSeconds != 0)
                    {
                        owner.Timers.Add(new WorldTimer(timeoutSeconds * 1000, (world, time) =>
                        {
                            if (portal.Owner == world)
                                world.LeaveWorld(portal);
                        }));
                    }

                    Log.InfoFormat("[HAUNTED_OMEN_PORTAL] spawned exactly one portal boss={0} world={1} portal={2} timeoutSeconds={3}", host.Id, owner.Id, portal.Id, timeoutSeconds);
                }
                catch (Exception ex)
                {
                    Log.ErrorFormat("[HAUNTED_OMEN_PORTAL] FAILED boss={0} world={1} destination=OminousBelow reason={2}", host.Id, owner?.Id, ex);
                }
            };
        }

        protected override void TickCore(Entity host, RealmTime time, ref object state)
        {
        }
    }
}
