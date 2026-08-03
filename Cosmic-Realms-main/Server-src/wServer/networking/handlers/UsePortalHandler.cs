using System.Linq;
using System.Threading.Tasks;
using wServer.realm.entities;
using wServer.networking.packets;
using wServer.networking.packets.incoming;
using wServer.realm.worlds.logic;

namespace wServer.networking.handlers
{
    class UsePortalHandler : PacketHandlerBase<UsePortal>
    {
        private readonly int[] _realmPortals = new int[] { 0x0704, 0x070e, 0x071c, 0x703, 0x070d, 0x0d40 };
        
        public override PacketId ID => PacketId.USEPORTAL;

        protected override void HandlePacket(Client client, UsePortal packet)
        {
            Log.InfoFormat("[USEPORTAL_TRACE] received account={0} player={1} state={2} objectId={3}",
                client.Account?.Name ?? "<none>", client.Player?.Id.ToString() ?? "<none>", client.State, packet.ObjectId);
            if (client.State == ProtocolState.Reconnecting || client.State == ProtocolState.Disconnected)
            {
                Log.WarnFormat("[USEPORTAL_TRACE] rejected account={0}: client state is {1}.",
                    client.Account?.Name ?? "<none>", client.State);
                return;
            }
            client.Manager.Logic.AddPendingAction(t => Handle(client, packet));
            //Handle(client, packet);
        }

        private void Handle(Client client, UsePortal packet)
        {
            if (client.State == ProtocolState.Reconnecting || client.State == ProtocolState.Disconnected)
            {
                Log.WarnFormat("[USEPORTAL_TRACE] rejected queued request account={0}: client state is {1}.",
                    client.Account?.Name ?? "<none>", client.State);
                return;
            }

            var player = client.Player;
            if (player?.Owner == null)
            {
                Log.Warn("[USEPORTAL_TRACE] rejected: player or world is unavailable.");
                return;
            }
            if (IsTest(client))
            {
                Log.Warn("[USEPORTAL_TRACE] rejected: portal use is disabled in Test worlds.");
                return;
            }

            var entity = player.Owner.GetEntity(packet.ObjectId);
            if (entity == null)
            {
                Log.WarnFormat("[USEPORTAL_TRACE] rejected player={0}: object {1} was not found in world {2}.", player.Id, packet.ObjectId, player.Owner.Name);
                return;
            }

            Log.InfoFormat("[USEPORTAL_TRACE] resolved player={0} world={1} entity={2} type=0x{3:x4} distance={4:0.00}",
                player.Id, player.Owner.Name, entity.GetType().Name, entity.ObjectType, player.Dist(entity));

            if (entity is GuildHallPortal)
            {
                HandleGuildPortal(player, entity as GuildHallPortal);
                return;
            }

            HandlePortal(player, entity as Portal);
        }

        private void HandleGuildPortal(Player player, GuildHallPortal portal)
        {
            if (string.IsNullOrEmpty(player.Guild))
            {
                player.SendError("You are not in a guild.");
                return;
            }

            if (portal.ObjectType == 0x072f)
            {
                var proto = player.Manager.Resources.Worlds["GuildHall"];
                var world = player.Manager.GetWorld(proto.id);
                player.Reconnect(world);
                return;
            }

            player.SendInfo("Portal not implemented.");
        }

        private void HandlePortal(Player player, Portal portal)
        {
            if (portal == null)
            {
                Log.WarnFormat("[USEPORTAL_TRACE] rejected player={0}: entity is {1}, usable={2}.", player.Id, portal?.GetType().Name ?? "not a Portal", portal?.Usable.ToString() ?? "n/a");
                return;
            }

            using (TimedLock.Lock(portal.CreateWorldLock))
            {
                var world = portal.WorldInstance;
                Log.InfoFormat("[USEPORTAL_TRACE] portal object={0} type=0x{1:x4} usable={2} locked={3} opened={4} cooldown=none createTask={5} destination={6}",
                    portal.Id, portal.ObjectType, portal.Usable, portal.Locked, portal.PlayerOpened,
                    portal.CreateWorldTask == null ? "none" : portal.CreateWorldTask.Status.ToString(),
                    world == null ? "<dynamic>" : $"{world.Name} ({world.Id})");

                if (portal.Readiness != PortalReadiness.Ready || !portal.Usable)
                {
                    Log.InfoFormat("[USEPORTAL_TRACE] portal={0} is {1}; no destination construction will start from USEPORTAL.", portal.Id, portal.Readiness);
                    if (portal.Readiness == PortalReadiness.Failed)
                        player.SendError("This portal failed to form.");
                    else
                        player.SendInfo("This portal is still forming.");
                    return;
                }

                // special portal case lookup
                if (world == null && _realmPortals.Contains(portal.ObjectType))
                {
                    world = player.Manager.GetRandomGameWorld();
                    if (world == null)
                    {
                        Log.WarnFormat("[USEPORTAL_TRACE] rejected player={0}: no active Realm destination for portal 0x{1:x4}.", player.Id, portal.ObjectType);
                        return;
                    }
                }

                if (world is Realm && !player.Manager.Resources.GameData.ObjectTypeToId[portal.ObjectDesc.ObjectType].Contains("Cowardice"))
                {
                    
                    player.FameCounter.CompleteDungeon(player.Owner.Name);
                }

                if (world != null)
                {
                    Log.InfoFormat("[USEPORTAL_TRACE] reconnecting player={0} distance={1:0.00} to world={2} id={3}.",
                        player.Id, player.Dist(portal), world.Name, world.Id);
                    player.Reconnect(world);

                    if (portal.WorldInstance?.Invites != null)
                    {
                        portal.WorldInstance.Invites.Remove(player.Name.ToLower());
                    }
                    if (portal.WorldInstance?.Invited != null)
                    {
                        portal.WorldInstance.Invited.Add(player.Name.ToLower());
                    }
                    return;
                }

                Log.WarnFormat("[USEPORTAL_TRACE] portal={0} was Ready but had no registered destination.", portal.Id);
            }
        }
    }
}
