using wServer.realm.entities;
using wServer.networking.packets;
using wServer.networking.packets.incoming;
using wServer.networking.packets.outgoing;
using wServer.realm;
using wServer.realm.worlds.logic;
using log4net;

namespace wServer.networking.handlers
{
    class LoadHandler : PacketHandlerBase<Load>
    {
        private static readonly ILog Log = LogManager.GetLogger(typeof(LoadHandler));
        public override PacketId ID => PacketId.LOAD;

        protected override void HandlePacket(Client client, Load packet)
        {
            //client.Manager.Logic.AddPendingAction(t => Handle(client, packet));
            Handle(client, packet);
        }

        private void Handle(Client client, Load packet)
        {
            if (client.State != ProtocolState.Handshaked)
                return;

            client.Character = client.Manager.Database.LoadCharacter(client.Account, packet.CharId);

            if (client.Character == null)
            {
                client.SendFailure("Failed to load your character!", Failure.MessageWithDisconnect);
                return;
            }

            if (client.Character.Dead)
            {
                client.SendFailure("Your chracter is dead!", Failure.MessageWithDisconnect);
                return;
            }

            PartyService.Reconstruct(client.Account, client.Manager.Database);

            var target = client.Manager.GetWorld(client.TargetWorld);
            if (target == null || target.Deleted)
            {
                client.SendFailure("Destination world is unavailable.", Failure.MessageWithDisconnect);
                return;
            }

            client.BeginWorldSynchronization(target.Id, client.Character.CharId);
            client.Player = target is Test ? new Player(client, false) : new Player(client);
            Log.InfoFormat("[WORLD_TRANSITION {0}] LOAD accepted account={1} char={2} destinationWorld={3}.",
                client.PortalTransitionTraceId ?? "initial", client.Account.AccountId, client.Character.CharId, target.Id);

            client.SendPacket(new CreateSuccess()
            {
                CharId = client.Character.CharId,
                ObjectId = target.EnterWorld(client.Player)
            }, PacketPriority.High);

            client.State = ProtocolState.Ready;
            client.Manager.ConMan.ClientConnected(client);

        }
    }
}
