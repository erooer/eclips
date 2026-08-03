using common;
using log4net;
using wServer.networking.packets;
using wServer.networking.packets.incoming;
using wServer.networking.packets.outgoing;
using wServer.realm;

namespace wServer.networking.handlers
{
    class HelloHandler : PacketHandlerBase<Hello>
    {
        private static readonly ILog Log = LogManager.GetLogger(typeof(HelloHandler));

        public override PacketId ID => PacketId.HELLO;

        protected override void HandlePacket(Client client, Hello packet)
        {
            //client.Manager.Logic.AddPendingAction(t => Handle(client, packet));
            Handle(client, packet);
        }

        private void Handle(Client client, Hello packet)
        {
            Log.InfoFormat("[TRACE {0:O}] HELLO enter guid={1} build={2} gameId={3} state={4}",
                System.DateTime.UtcNow, packet.GUID, packet.BuildVersion, packet.GameId, client.State);
            // A RECONNECT creates a new TCP client, whose state is Connected rather
            // than Reconnecting.  The key carried by HELLO is the authoritative
            // reconnect marker and is validated by ConnectManager before use.
            var reconnecting = packet.Key != null && packet.Key.Length > 0;
            Log.InfoFormat("[TRACE {0:O}] HELLO connection kind={1} keyBytes={2}",
                System.DateTime.UtcNow, reconnecting ? "reconnect" : "initial", packet.Key?.Length ?? 0);
            if (!reconnecting)
            {
                // get acc info
                client.Manager.Database.Verify(packet.GUID, packet.Password, out var acc);
                if (acc == null)
                {
                    Log.WarnFormat("[TRACE {0:O}] HELLO authentication failed guid={1}", System.DateTime.UtcNow, packet.GUID);
                    return;
                }
              //  client.Manager.Database.LogAccountByIp(client.IP, acc.AccountId);
              //  if (client.IP != acc.IP && !(System.String.IsNullOrEmpty(client.IP) || System.String.IsNullOrEmpty(acc.IP)))
              //      wServer.networking.webhooks.Webhooks.SendToDiscordAsLoginLog("New IP", "", $"{acc.Name} logged from new ip.\nnew IP: **{client.IP}**\nold IP: **{acc.IP}**\nall accounts associated to old IP:\n**{client.Manager.Database.GetAccountsByIP(acc.IP)}**\nall accounts associated to new IP:\n**{client.Manager.Database.GetAccountsByIP(client.IP)}**");

                
                acc.IP = client.IP;
                acc.FlushAsync();
                client.Account = acc;
                Log.InfoFormat("[TRACE {0:O}] HELLO authenticated account={1} id={2}", System.DateTime.UtcNow, acc.Name, acc.AccountId);
            }

            if (!VerifyConnection(client, packet, client.Account))
            {
                Log.WarnFormat("[TRACE {0:O}] HELLO verification failed account={1}", System.DateTime.UtcNow, client.Account?.AccountId);
                return;
            }

            Log.InfoFormat("[TRACE {0:O}] HELLO verified; queueing connection", System.DateTime.UtcNow);
            client.Manager.ConMan.Add(new ConInfo(client, packet, reconnecting));
        }

        private bool VerifyConnection(Client client, Hello packet, DbAccount acc)
        {
            var version = client.Manager.Config.serverSettings.version;
            if (!version.Equals(packet.BuildVersion))
            {
                Log.WarnFormat("[TRACE {0:O}] HELLO build mismatch server={1} client={2}", System.DateTime.UtcNow, version, packet.BuildVersion);
                client.SendFailure(version, Failure.ClientUpdateNeeded);
                return false;
            }

            if (acc.Banned)
            {
                client.SendFailure("Account banned.", Failure.MessageWithDisconnect);
                Log.InfoFormat("{0} ({1}) tried to log in. Account Banned.",
                    acc.Name, client.IP);
                return false;
            }

            if (client.Manager.Database.IsIpBanned(client.IP))
            {
                client.SendFailure("IP banned.", Failure.MessageWithDisconnect);
                Log.InfoFormat("{0} ({1}) tried to log in. IP Banned.",
                    acc.Name, client.IP);
                return false;
            }

            if (!acc.Admin && client.Manager.Config.serverInfo.adminOnly)
            {
                client.SendFailureDialog("Admin Only Server", $"Only admins can play on {client.Manager.Config.serverInfo.name}.");
                return false;
            }

            var minRank = client.Manager.Config.serverInfo.minRank;
            if (acc.Rank < minRank)
            {
                client.SendFailureDialog("Rank Required Server", $"You need a minimum server rank of {minRank} to play on {client.Manager.Config.serverInfo.name}.");
                return false;
            }

            return true;
        }
    }
}
