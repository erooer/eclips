using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using log4net;
using wServer.networking;
using wServer.networking.packets.outgoing;
using wServer.realm.worlds;
using wServer.realm.worlds.logic;
using File = System.IO.File;

namespace wServer.realm
{
    public class ReconInfo
    {
        public readonly int Destination;
        public readonly byte[] Key;
        public readonly string TraceId;
        public readonly int SourceWorldId;
        public readonly int CharacterId;
        public DateTime Timeout;

        public ReconInfo(int dest, byte[] key, DateTime timeout, string traceId, int sourceWorldId, int characterId)
        {
            Destination = dest;
            Key = key;
            Timeout = timeout;
            TraceId = traceId;
            SourceWorldId = sourceWorldId;
            CharacterId = characterId;
        }
    }

    public class ConnectManager
    {
        private static readonly ILog Log = LogManager.GetLogger(typeof(ConnectManager));

        private const int ReconTTL = 90; // in seconds
        private const int ConnectingTTL = 15; // in seconds

        private readonly RealmManager _manager;
        private readonly int _maxPlayerCount;
        private readonly int _maxPlayerCountWithPriority;
        private readonly ConnectionQueue _queue;
        private readonly ConcurrentDictionary<int, ReconInfo> _recon;
        private readonly ConcurrentDictionary<Client, DateTime> _connecting;
        private long _lastTick;

        public ConnectManager(RealmManager manager, int maxPlayerCount, int maxPlayerCountWithPriority)
        {
            _manager = manager;
            _maxPlayerCount = maxPlayerCount;
            _maxPlayerCountWithPriority = maxPlayerCountWithPriority;
            _recon = new ConcurrentDictionary<int, ReconInfo>();
            _queue = new ConnectionQueue();
            _connecting = new ConcurrentDictionary<Client, DateTime>();
        }

        public void Add(ConInfo conInfo)
        {
            Log.InfoFormat("[TRACE {0:O}] CONNECT add account={1} gameId={2}", DateTime.UtcNow, conInfo.Account?.AccountId, conInfo.GameId);
            // instantly connect reconnecting clients
            if (conInfo.Reconnecting)
            {
                Connect(conInfo);
                return;
            }

            // don't use queue for ranked players
            if (conInfo.Account.Rank > 0)
            {
                if (GetPlayerCount() < _maxPlayerCountWithPriority)
                {
                    Connect(conInfo);
                    return;
                }

                conInfo.Client.SendFailure("Server at max capacity.");
                return;
            }

            if (!_queue.Add(conInfo))
            {
                conInfo.Client.SendFailure("Account already in queue.",
                    Failure.MessageWithDisconnect);
                return;
            }

            conInfo.Client.State = ProtocolState.Queued;

            var position = _queue.Position(conInfo);
            if (_maxPlayerCount - GetPlayerCount() >= position)
            {
                return;
            }

            // send server full
            conInfo.Client.SendPacket(new ServerFull()
            {
                Position = position,
                Count = _queue.Count
            });
        }

        public void AddReconnect(int accountId, Reconnect rcp, string traceId, int sourceWorldId, int characterId)
        {
            if (rcp == null)
                return;

            var rInfo = new ReconInfo(rcp.GameId, rcp.Key, DateTime.Now.AddSeconds(ReconTTL), traceId, sourceWorldId, characterId);
            if (!_recon.TryAdd(accountId, rInfo))
                Log.WarnFormat("[RECONNECT_TRACE] retained existing reconnect key for account={0}; duplicate destination={1} ignored.",
                    accountId, rcp.GameId);
            else
                Log.InfoFormat("[RECONNECT_TRACE] registered account={0} destination={1} expires={2:O}.",
                    accountId, rcp.GameId, rInfo.Timeout);
        }

        // A reconnect uses a fresh TCP Client. HELLO arrives before Connect()
        // consumes the single-use key, so resolve its account from the pending
        // random key first; consumption and destination validation remain in
        // Connect().
        public bool TryPrepareReconnect(Client client, int destination, byte[] key)
        {
            if (client == null || key == null || key.Length == 0)
                return false;

            foreach (var entry in _recon)
            {
                var info = entry.Value;
                if (info.Destination != destination || !key.SequenceEqual(info.Key))
                    continue;

                var account = _manager.Database.GetAccount(entry.Key);
                if (account == null)
                    return false;

                client.Account = account;
                client.PortalTransitionTraceId = info.TraceId;
                client.PortalTransitionSourceWorldId = info.SourceWorldId;
                Log.InfoFormat("[WORLD_TRANSITION {0}] reconnect HELLO prepared account={1} sourceWorld={2} destinationWorld={3}.",
                    info.TraceId, account.AccountId, info.SourceWorldId, destination);
                return true;
            }
            return false;
        }

        public void Tick(RealmTime time)
        {
            _queue.KeepAlive(time);

            // connect player if possible
            if (GetPlayerCount() < _maxPlayerCount && _queue.Count > 0)
                Connect(_queue.Remove());

            if (time.TotalElapsedMs - _lastTick > 5000)
            {
                _lastTick = time.TotalElapsedMs;
                var dateTime = DateTime.Now;

                // process reconnect timeouts
                foreach (var r in _recon
                    .Where(r => DateTime.Compare(r.Value.Timeout, dateTime) < 0))
                {
                    ReconInfo ignored;
                    _recon.TryRemove(r.Key, out ignored);
                }

                // process connecting timeouts 
                // for those that go through the connection process but never send a Create or Load packet
                foreach (var c in _connecting
                    .Where(c => DateTime.Compare(c.Value, dateTime) < 0))
                {
                    DateTime ignored;
                    _connecting.TryRemove(c.Key, out ignored);
                }
            }
        }

        public int GetPlayerCount()
        {
            return _manager.Clients.Count + _recon.Count;
        }

        private void Connect(ConInfo conInfo)
        {
            var client = conInfo.Client;
            var acc = conInfo.Account;

            // configure override
            if (acc.Admin && acc.AccountIdOverride != 0)
            {
                var accOverride = client.Manager.Database.GetAccount(acc.AccountIdOverride);
                if (accOverride == null)
                {
                    client.SendPacket(new Text()
                    {
                        BubbleTime = 0,
                        NumStars = -1,
                        Name = "*Error*",
                        Txt = "Account does not exist."
                    });
                }
                else
                {
                    accOverride.AccountIdOverrider = acc.AccountId;
                    acc = accOverride;
                }
            }

            var gameId = conInfo.GameId;
            if (conInfo.Reconnecting)
            {
                ReconInfo rInfo;
                if (!_recon.TryRemove(acc.AccountId, out rInfo))
                {
                    client.SendFailure("Invalid reconnect.",
                        Failure.MessageWithDisconnect);
                    return;
                }

                if (!gameId.Equals(rInfo.Destination))
                {
                    client.SendFailure("Invalid reconnect destination.",
                        Failure.MessageWithDisconnect);
                    return;
                }

                if (!conInfo.Key.SequenceEqual(rInfo.Key))
                {
                    client.SendFailure("Invalid reconnect key.",
                        Failure.MessageWithDisconnect);
                    return;
                }

                client.PortalTransitionTraceId = rInfo.TraceId;
                client.PortalTransitionSourceWorldId = rInfo.SourceWorldId;
                Log.InfoFormat("[WORLD_TRANSITION {0}] reconnect key consumed account={1} sourceWorld={2} destinationWorld={3}.",
                    rInfo.TraceId, acc.AccountId, rInfo.SourceWorldId, gameId);

                // A valid reconnect key authorizes replacement of only its own
                // source session.  Detach that source first (which releases its
                // database lock), then acquire the lock for this new socket.
                // Ordinary duplicate logins never enter this branch.
                client.Manager.HandoffReconnectSource(client, rInfo.SourceWorldId, rInfo.CharacterId, rInfo.TraceId);
                if (!client.Manager.Database.AcquireLock(acc))
                {
                    Log.ErrorFormat("[RECONNECT_HANDOFF {0}] failed to acquire destination account lock account={1} after source handoff.",
                        rInfo.TraceId, acc.AccountId);
                    client.SendFailure("Account in Use (reconnect handoff failed).", Failure.MessageWithDisconnect);
                    return;
                }
                Log.InfoFormat("[RECONNECT_HANDOFF {0}] destination account lock acquired account={1} destinationSocket={2}.",
                    rInfo.TraceId, acc.AccountId, client.IP);
            }
            else
            {
                if (gameId != World.Test)
                    gameId = World.Nexus;
            }

            if (!conInfo.Reconnecting && !client.Manager.Database.AcquireLock(acc))
            {
                // disconnect current connected client (if any)
                var otherClients = client.Manager.Clients.Keys
                    .Where(c => c == client || c.Account != null && c.State != ProtocolState.Reconnecting && (c.Account.AccountId == acc.AccountId || c.Account.DiscordId != null && c.Account.DiscordId == acc.DiscordId));
                foreach (var otherClient in otherClients)
                    otherClient.Disconnect();

                // try again...
                if (!client.Manager.Database.AcquireLock(acc))
                {
                    client.SendFailure("Account in Use (" +
                        client.Manager.Database.GetLockTime(acc)?.ToString("%s") + " seconds until timeout)");
                    return;
                }
            }

            acc.Reload(); // make sure we have the latest data
            client.Account = acc;

            // connect client to realm manager
            if (!client.Manager.TryConnect(client))
            {
                client.SendFailure("Failed to connect");
                return;
            }

            var world = client.Manager.GetWorld(gameId);
            if (world == null || world.Deleted)
            {
                client.SendPacket(new Text()
                {
                    BubbleTime = 0,
                    NumStars = -1,
                    Name = "*Error*",
                    Txt = "World does not exist."
                });
                world = client.Manager.GetWorld(World.Nexus);
            }

            if (world is Test &&
                !(world as Test).JsonLoaded &&
                acc.Rank < client.Manager.Resources.Settings.EditorMinRank)
            {
                client.SendFailure("Only players with a rank of 50 and above can make test maps.",
                    Failure.MessageWithDisconnect);
                return;
            }

            if (world.IsLimbo)
                world = world.GetInstance(client);

            if (!world.AllowedAccess(client))
            {
                if (!world.Persist && world.TotalConnects <= 0)
                    client.Manager.RemoveWorld(world);

                client.SendPacket(new Text()
                {
                    BubbleTime = 0,
                    NumStars = -1,
                    Name = "*Error*",
                    Txt = "Access denied"
                });

                if (!(world is Nexus))
                    world = client.Manager.GetWorld(World.Nexus);
                else
                {
                    client.Disconnect();
                    return;
                }
            }

            if (world is Test && !(world as Test).JsonLoaded)
            {
                // save map
                var mapFolder = $"{_manager.Config.serverSettings.logFolder}/maps";
                if (!Directory.Exists(mapFolder))
                    Directory.CreateDirectory(mapFolder);
                File.WriteAllText($"{mapFolder}/{acc.Name}_{DateTime.Now.Ticks}.jm", conInfo.MapInfo);

                (world as Test).LoadJson(conInfo.MapInfo);

                var dreamName = client.Account.Name.ToLower().EndsWith("s") ? client.Account.Name + "' Dream World" : client.Account.Name + "'s Dream World";

                world.SBName = dreamName;
                world.Name = dreamName;
                //client.Manager.Monitor.AddPortal(world.Id);
            }

            var seed = (uint)((long)Environment.TickCount * conInfo.GUID.GetHashCode()) % uint.MaxValue;
            client.Random = new wRandom(seed);
            client.TargetWorld = world.Id;
            Log.InfoFormat("[WORLD_TRANSITION {0}] MAPINFO queued account={1} client={2} sourceWorld={3} destinationWorld={4} destinationName={5}.",
                client.PortalTransitionTraceId ?? "initial", acc.AccountId, client.Id,
                client.PortalTransitionSourceWorldId, world.Id, world.Name);

            var now = (Int32)(DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1))).TotalSeconds;

            if (acc.GuildId > 0 && now - acc.LastSeen > 1800)
            {
                client.Manager.Chat.GuildAnnounce(acc, acc.Name + " has joined the game");
            }

            if (!acc.Hidden && acc.AccountIdOverrider == 0)
            {
                acc.RefreshLastSeen();
                acc.FlushAsync();
            }

            // send out map info
            var mapSize = Math.Max(world.Map.Width, world.Map.Height);
            client.SendPacket(new MapInfo()
            {
                Width = mapSize,
                Height = mapSize,
                Name = world.Name,
                DisplayName = world.SBName,
                Seed = seed,
                Background = world.Background,
                Difficulty = world.Difficulty,
                AllowPlayerTeleport = world.AllowTeleport,
                ShowDisplays = world.ShowDisplays,
                Weather = world.Weather,
                CurrentDateTime = client.Manager.CurrentDatetime,

                Music2 = world.Music.Length != 0 ? world.Music2 :
                new string[1] { client.Manager.CurrentDatetime >= 48000 ? "night" : "day" },

                ClientXML = Empty<string>.Array,//client.Manager.Resources.GameData.AdditionXml,
                ExtraXML = world.ExtraXML
            });

            // send out account lock/ignore list
            client.SendPacket(new AccountList()
            {
                AccountListId = 0, // locked list
                AccountIds = client.Account.LockList
                    .Select(i => i.ToString())
                    .ToArray(),
                LockAction = 1
            });
            client.SendPacket(new AccountList()
            {
                AccountListId = 1, // ignore list
                AccountIds = client.Account.IgnoreList
                    .Select(i => i.ToString())
                    .ToArray()
            });

            client.State = ProtocolState.Handshaked;
            _connecting.TryAdd(client, DateTime.Now.AddSeconds(ConnectingTTL));
        }

        public void ClientConnected(Client client)
        {
            DateTime to;
            _connecting.TryRemove(client, out to);

            // update PlayerInfo with world data
            var plrInfo = client.Manager.Clients[client];
            plrInfo.WorldInstance = client.Player.Owner.Id;
            plrInfo.WorldName = client.Player.Owner.Name;
        }

        public int QueueLength()
        {
            return _queue.Count;
        }
    }
}
