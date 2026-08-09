using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;
using common;
using wServer.networking.packets;
using wServer.networking.server;
using wServer.realm;
using wServer.realm.entities;
using log4net;
using Newtonsoft.Json;
using wServer.networking.packets.incoming;
using wServer.networking.packets.outgoing;
using wServer.realm.worlds.logic;
using System.Diagnostics;
using System.Threading;

namespace wServer.networking
{
    public enum ProtocolState
    {
        Disconnected,
        Connected,
        Handshaked,
        Queued,
        Ready,
        Reconnecting
    }

    public partial class Client
    {
        static readonly ILog Log = LogManager.GetLogger(typeof(Client));

        public RealmManager Manager { get; private set; }
        static readonly byte[] ServerKey = new byte[] { 0x61, 0x2a, 0x80, 0x6c, 0xac, 0x78, 0x11, 0x4b, 0xa5, 0x01, 0x3c, 0xb5, 0x31 };
        static byte[] _clientKey = new byte[] { 0x81, 0x1f, 0x50, 0x39, 0x1f, 0xb4, 0x55, 0x89, 0x9c, 0xa9, 0xd7, 0x4b, 0x72 };

        public RC4 ReceiveKey { get; private set; }
        public RC4 SendKey { get; private set; }

        private readonly Server _server;
        private readonly CommHandler _handler;
        private readonly Queue<Tuple<Packet, PacketPriority>> _deferredTextPackets = new Queue<Tuple<Packet, PacketPriority>>();
        private int _initialWorldUpdateObserved;
        private int _initialUpdateChunkSynchronizationActive;
        private int _initialUpdateAcksOutstanding;
        private int _initialUpdateAcksExpected;
        private int _initialUpdateRegistered;
        private DateTime _initialUpdateSynchronizationStartedUtc;

        private volatile ProtocolState _state;
        public ProtocolState State
        {
            get { return _state; }
            internal set { _state = value; }
        }

        public int Id { get; internal set; }
        public DbAccount Account { get; internal set; }
        public DbChar Character { get; internal set; }
        public Player Player { get; internal set; }

        public wRandom Random { get; internal set; }

        //Temporary connection state
        internal int TargetWorld = -1;

        public Socket Skt { get; private set; }
        public string IP { get; private set; }
        public bool IsLagging { get; private set; }

        internal readonly object DcLock = new object();

        public Client(Server server, RealmManager manager, 
            SocketAsyncEventArgs send, SocketAsyncEventArgs receive,
            byte[] clientKey)
        {
            _server = server;
            Manager = manager;
            _clientKey = clientKey;

            ReceiveKey = new RC4(_clientKey);
            SendKey = new RC4(ServerKey);
            
            _handler = new CommHandler(this, send, receive);
        }

        public void Reset()
        {
            ReceiveKey = new RC4(_clientKey);
            SendKey = new RC4(ServerKey);

            Id = 0; // needed so that inbound packets that are currently queued are discarded.
            Account = null;
            Character = null;
            Player = null;
            _initialWorldUpdateObserved = 0;
            _initialUpdateChunkSynchronizationActive = 0;
            _initialUpdateAcksOutstanding = 0;
            _initialUpdateAcksExpected = 0;
            _initialUpdateRegistered = 0;
            _initialUpdateSynchronizationStartedUtc = default(DateTime);
            lock (_deferredTextPackets)
                _deferredTextPackets.Clear();

            // reset client ping/pong values
            _pingTime = -1;
            _pongTime = -1;

            _handler.Reset();
        }

        public void BeginHandling(Socket skt)
        {
            Skt = skt;

            try
            {
                IP = ((IPEndPoint)skt.RemoteEndPoint).Address.ToString();
            }
            catch
            {
                IP = "";
            }

            Log.InfoFormat("Received client @ {0}.", IP);
            _handler.BeginHandling(Skt);
        }

        public void SendPacket(Packet pkt, PacketPriority priority = PacketPriority.Normal)
        {
            if (pkt is Text && Volatile.Read(ref _initialUpdateChunkSynchronizationActive) != 0 &&
                (State == ProtocolState.Handshaked || State == ProtocolState.Ready))
            {
                lock (_deferredTextPackets)
                    _deferredTextPackets.Enqueue(Tuple.Create(pkt, priority));

                var earlyText = (Text)pkt;
                Log.InfoFormat("[TEXT_TRACE] deferred until initial UPDATE chunks are acknowledged account={0} state={1} objectId={2} name={3} bubble={4} text={5}",
                    Account?.Name ?? "<none>", State, earlyText.ObjectId, earlyText.Name, earlyText.BubbleTime, earlyText.Txt);
                return;
            }
            using (TimedLock.Lock(DcLock))
            {
                if (State != ProtocolState.Disconnected)
                {
                    var text = pkt as Text;
                    if (text != null)
                        Log.InfoFormat("[TEXT_TRACE] outbound account={0} state={1} objectId={2} name={3} bubble={4} text={5}",
                            Account?.Name ?? "<none>", State, text.ObjectId, text.Name, text.BubbleTime, text.Txt);
                    _handler.SendPacket(pkt, priority);
                }
            }
        }

        // The initial-state marker is consumed exactly once per connection. Normal
        // UPDATEs never activate chunk synchronization or defer gameplay traffic.
        public bool MarkInitialWorldUpdate()
        {
            return Interlocked.CompareExchange(ref _initialWorldUpdateObserved, 1, 0) == 0;
        }

        // A large initial UPDATE can be split into several protocol-valid frames.
        // Only this exceptional path defers startup TEXT until every chunk is acked.
        public bool RegisterInitialUpdatePackets(int packetCount)
        {
            if (packetCount <= 1)
                return false;

            if (Interlocked.CompareExchange(ref _initialUpdateRegistered, 1, 0) != 0)
                return false;

            Interlocked.Exchange(ref _initialUpdateAcksExpected, packetCount);
            Interlocked.Exchange(ref _initialUpdateAcksOutstanding, packetCount);
            _initialUpdateSynchronizationStartedUtc = DateTime.UtcNow;
            Interlocked.Exchange(ref _initialUpdateChunkSynchronizationActive, 1);
            return true;
        }

        public void InitialUpdateAcknowledged()
        {
            if (Volatile.Read(ref _initialUpdateChunkSynchronizationActive) == 0)
                return;

            var outstanding = Interlocked.Decrement(ref _initialUpdateAcksOutstanding);
            if (outstanding > 0)
                return;

            if (outstanding < 0 || Interlocked.CompareExchange(ref _initialUpdateChunkSynchronizationActive, 0, 1) != 1)
                return;

            Queue<Tuple<Packet, PacketPriority>> pending;
            lock (_deferredTextPackets)
            {
                pending = new Queue<Tuple<Packet, PacketPriority>>(_deferredTextPackets);
                _deferredTextPackets.Clear();
            }

            var world = Player?.Owner;
            var elapsedMs = _initialUpdateSynchronizationStartedUtc == default(DateTime)
                ? -1
                : (long)(DateTime.UtcNow - _initialUpdateSynchronizationStartedUtc).TotalMilliseconds;
            Log.InfoFormat("[INITIAL_SYNC] released worldType={0} world={1} account={2} elapsedMs={3} acknowledgements={4}/{5} deferredPackets={6}",
                world == null ? "<none>" : world.GetType().Name, world == null ? -1 : world.Id,
                Account?.AccountId ?? 0, elapsedMs,
                Volatile.Read(ref _initialUpdateAcksExpected) - Math.Max(outstanding, 0),
                Volatile.Read(ref _initialUpdateAcksExpected), pending.Count);
            while (pending.Count > 0)
            {
                var entry = pending.Dequeue();
                SendPacket(entry.Item1, entry.Item2);
            }
        }

        public void SendPackets(IEnumerable<Packet> pkts, PacketPriority priority = PacketPriority.Normal)
        {
            using (TimedLock.Lock(DcLock))
            {
                if (State != ProtocolState.Disconnected)
                    _handler.SendPackets(pkts, priority);
            }
        }

        public bool IsReady()
        {
            if (State == ProtocolState.Disconnected)
                return false;

            if (State == ProtocolState.Ready && Player?.Owner == null)
                return false;

            return true;
        }

        public bool CheckForLag()
        {
            IsLagging = _handler.IsLagging();
            return IsLagging;
        }

        internal void ProcessPacket(Packet pkt)
        {
            using (TimedLock.Lock(DcLock))
            {
                if (State == ProtocolState.Disconnected)
                    return;

                try
                {
                    Log.Logger.Log(typeof(Client), log4net.Core.Level.Verbose,
                        $"Handling packet '{pkt.ID}'...", null);

                    IPacketHandler handler;
                    if (!PacketHandlers.Handlers.TryGetValue(pkt.ID, out handler))
                        Log.WarnFormat("Unhandled packet '{0}'.", pkt.ID);
                    else
                        handler.Handle(this, (IncomingMessage)pkt);
                }
                catch (Exception e)
                {
                    Log.Error($"Error when handling packet '{pkt.ToString()}'...", e);
                    Disconnect("Packet handling error.");
                }
            }
        }

        public void Reconnect(Reconnect pkt)
        {
            if (Account == null)
            {
                Disconnect("Tried to reconnect an client with a null account...");
                return;
            }

            if (State == ProtocolState.Reconnecting)
            {
                Log.WarnFormat("[RECONNECT_TRACE] ignored duplicate reconnect account={0} destination={1} gameId={2}.",
                    Account.Name, pkt.Name, pkt.GameId);
                return;
            }

            Log.InfoFormat("[RECONNECT_TRACE] issuing account={0} ip={1} state={2} destination={3} gameId={4}.",
                Account.Name, IP, State, pkt.Name, pkt.GameId);

            State = ProtocolState.Reconnecting;
            // A reconnect immediately creates a new Player from Redis.  Do not allow
            // that load to race the character write that contains the belt stacks.
            Log.InfoFormat("[POTION_PERSIST] reconnect-save begin account={0} char={1} hp={2} mp={3} destination={4}.",
                Account.Name, Character?.CharId ?? 0, Player?.HealthPots?.Count ?? 0,
                Player?.MagicPots?.Count ?? 0, pkt.GameId);
            if (!Save(false, true))
            {
                State = ProtocolState.Ready;
                Log.ErrorFormat("[POTION_PERSIST] reconnect-save failed account={0} char={1}; reconnect cancelled.",
                    Account.Name, Character?.CharId ?? 0);
                SendFailure("Could not save your character before reconnecting.", Failure.MessageWithDisconnect);
                return;
            }

            Manager.ConMan.AddReconnect(Account.AccountId, pkt);
            SendPacket(pkt);
        }

        public async void SendFailure(string text, int errorId = 0)
        {
            SendPacket(new Failure()
            {
                ErrorId = errorId,
                ErrorDescription = text
            });

            var t = Task.Delay(1000);
            await t;

            Disconnect();
        }

        public async void SendFailureDialog(string title, string description)
        {
            // Note: Client is programmed to check the build parameter
            // of the json object. If it doesn't match what the client
            // has, the error dialog will be an update client dialog
            // instead.

            var jsonMsg = new FailureJsonDialogMessage()
            {
                build = Manager.Config.serverSettings.version,
                title = title,
                description = description
            };
            SendPacket(new Failure()
            {
                ErrorId = Failure.JsonDialogDisconnect,
                ErrorDescription = JsonConvert.SerializeObject(jsonMsg)
            });

            var t = Task.Delay(1000);
            await t;

            Disconnect();
        }

        public void Disconnect(string reason = "")
        {
            using (TimedLock.Lock(DcLock))
            {
                if (State == ProtocolState.Disconnected)
                    return;

                State = ProtocolState.Disconnected;

                if (!string.IsNullOrEmpty(reason))
                    Log.InfoFormat("Disconnecting client ({0}) @ {1}... {2}",
                        Account?.Name ?? " ", IP, reason);

                if (Account != null)
                    try
                    {
                        Save(true);
                    }
                    catch (Exception e)
                    {
                        var msg = $"{e.Message}\n{e.StackTrace}";
                        Log.Error(msg);
                    }

                _handler.Disconnect();
                Manager.Disconnect(this);
                _server.Disconnect(this);
            }
        }

        private bool Save(bool unlock, bool waitForCharacterCommit = false)
        {
            var acc = Account;

            if (Character == null || Player == null || Player.Owner is Test)
            {
                if (unlock)
                    Manager.Database.ReleaseLock(acc);
                return true;
            }
            
            Player.SaveToCharacter();
            if (!acc.Hidden && acc.AccountIdOverrider == 0)
                acc.RefreshLastSeen();
            acc.FlushAsync();
            if (unlock)
                Manager.Database.ReleaseLock(acc);
            var saveTask = Manager.Database.SaveCharacter(acc, Character, Player.FameCounter.ClassStats, !unlock);
            if (!waitForCharacterCommit)
                return true;

            var saved = saveTask.GetAwaiter().GetResult();
            Log.InfoFormat("[POTION_PERSIST] reconnect-save committed account={0} char={1} hp={2} mp={3} saved={4}.",
                acc.Name, Character.CharId, Character.HealthStackCount, Character.MagicStackCount, saved);
            return saved;
        }

        public void Dispose()
        {
            Manager = null;
            ReceiveKey = null;
            SendKey = null;
            Account = null;
            Character = null;
            Player?.Dispose();
            Player = null;
            Random = null;
            Skt = null;
            GC.Collect();
        }
    }
}
