using common.resources;
using wServer.realm.entities;
using wServer.networking.packets;
using wServer.networking.packets.incoming;
using wServer.networking.packets.outgoing;
using wServer.realm;
using log4net;

namespace wServer.networking.handlers
{
    class PlayerShootHandler : PacketHandlerBase<PlayerShoot>
    {
        public override PacketId ID => PacketId.PLAYERSHOOT;
        private static readonly ILog CheatLog = LogManager.GetLogger("CheatLog");
        // Diagnostic-only switch. Leave disabled in normal builds to avoid packet-log noise.
        private const bool JudgementTraceEnabled = false;
        private const ushort JudgementType = 0xF921;
        private static readonly ILog JudgementTrace = LogManager.GetLogger("JudgementTrace");

        protected override void HandlePacket(Client client, PlayerShoot packet)
        {
            client.Manager.Logic.AddPendingAction(t => Handle(client.Player, packet, t));
            //Handle(client.Player, packet);
        }

        void Handle(Player player, PlayerShoot packet, RealmTime time)
        {
            var trace = JudgementTraceEnabled && packet.ContainerType == JudgementType;
            if (trace)
                JudgementTrace.Info($"PLAYERSHOOT received: player={player?.Name ?? "<none>"}, container=0x{packet.ContainerType:X4}, bullet={packet.BulletId}.");

            if (player?.Owner == null)
            {
                if (trace)
                    JudgementTrace.Info("PLAYERSHOOT rejected: player or world is unavailable.");
                return;
            }

            Item item;

            if (!player.Manager.Resources.GameData.Items.TryGetValue(packet.ContainerType, out item))
            {
                if (trace)
                    JudgementTrace.Info("PLAYERSHOOT rejected: item type was not found in GameData.");
                return;
            }

            if (trace)
                JudgementTrace.Info($"PLAYERSHOOT resolved: item={item.ObjectId}, slotType={item.SlotType}, projectiles={item.Projectiles.Length}.");

            // if not shooting main weapon do nothing (ability shoot is handled with useItem)
            if (player.Inventory[0] != item)
            {
                if (trace)
                    JudgementTrace.Info($"PLAYERSHOOT rejected: main slot contains {player.Inventory[0]?.ObjectId ?? "<empty>"}.");
                return;
            }

            if (!player.ValidatePlayerShoot(packet.Time, item))
            {
                if (trace)
                    JudgementTrace.Info("PLAYERSHOOT rejected: attack-rate validation failed.");
                player.Client.Disconnect("Attack speed modifaction detected!");
                return;
            }

            if (item.Projectiles.Length == 0)
            {
                if (trace)
                    JudgementTrace.Info("PLAYERSHOOT rejected: weapon has no projectile descriptor.");
                return;
            }

            // create projectile and show other players
            var prjDesc = item.Projectiles[0]; //Assume only one
            Projectile prj = player.PlayerShootProjectile(
                packet.BulletId, prjDesc, item.ObjectType,
                packet.Time, packet.StartingPos, packet.Angle);
            if (trace)
                JudgementTrace.Info($"PLAYERSHOOT accepted: projectile created with descriptor damage={prjDesc.MinDamage}-{prjDesc.MaxDamage}, server damage={prj.Damage}.");
            player.Owner.EnterWorld(prj);
            if (!player.Manager.Resources.Settings.DisableAlly)
                player.Owner.BroadcastPacketNearby(new AllyShoot()
                {
                    OwnerId = player.Id,
                    Angle = packet.Angle,
                    ContainerType = packet.ContainerType,
                    BulletId = packet.BulletId
                }, player, player, PacketPriority.Low);
            player.FameCounter.Shoot(prj);
        }
    }
}
