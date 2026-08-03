using wServer.realm;
using wServer.realm.entities;
using wServer.networking.packets;
using wServer.networking.packets.incoming;

namespace wServer.networking.handlers
{
    class UseItemHandler : PacketHandlerBase<UseItem>
    {
        public override PacketId ID => PacketId.USEITEM;

        protected override void HandlePacket(Client client, UseItem packet)
        {
            Log.InfoFormat("[USEITEM_TRACE] received account={0} player={1} state={2} time={3} objectId={4} slot={5} objectType=0x{6:x4} pos=({7:0.00},{8:0.00}) useType={9}",
                client.Account?.Name ?? "<none>", client.Player?.Id.ToString() ?? "<none>", client.State,
                packet.Time, packet.SlotObject.ObjectId, packet.SlotObject.SlotId, packet.SlotObject.ObjectType,
                packet.ItemUsePos.X, packet.ItemUsePos.Y, packet.UseType);
            client.Manager.Logic.AddPendingAction(t => Handle(client.Player, t, packet));
        }

        void Handle(Player player, RealmTime time, UseItem packet)
        {
            if (player?.Owner == null)
            {
                Log.WarnFormat("[USEITEM_TRACE] rejected before use: player or owner is unavailable.");
                return;
            }

            Log.InfoFormat("[USEITEM_TRACE] dispatch player={0} world={1}", player.Id, player.Owner.Name);
            player.UseItem(time, packet.SlotObject.ObjectId, packet.SlotObject.SlotId,
                packet.SlotObject.ObjectType, packet.ItemUsePos, packet.UseType);
        }
    }
}
