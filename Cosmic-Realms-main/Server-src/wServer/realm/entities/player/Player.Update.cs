using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using wServer.networking.packets.outgoing;
using wServer.networking.server;
using wServer.realm.terrain;

namespace wServer.realm.entities
{
    public class UpdatedSet : HashSet<Entity>
    {
        private readonly Player _player;
        private readonly object _changeLock = new object();

        public UpdatedSet(Player player)
        {
            _player = player;
        }

        public new bool Add(Entity e)
        {
            using (TimedLock.Lock(_changeLock))
            {
                var added = base.Add(e);
                if (added)
                    e.StatChanged += _player.HandleStatChanges;

                return added;
            }
        }

        public new bool Remove(Entity e)
        {
            using (TimedLock.Lock(_changeLock))
            {
                e.StatChanged -= _player.HandleStatChanges;
                return base.Remove(e);
            }
        }

        public new void RemoveWhere(Predicate<Entity> match)
        {
            using (TimedLock.Lock(_changeLock))
            {
                foreach (var e in this.Where(match.Invoke))
                    e.StatChanged -= _player.HandleStatChanges;

                base.RemoveWhere(match);
            }
        }

        public void Dispose()
        {
            RemoveWhere(e => true);
        }
    }

    public partial class Player
    {
        public HashSet<Entity> clientEntities => _clientEntities;

        public readonly ConcurrentQueue<Entity> ClientKilledEntity = new ConcurrentQueue<Entity>();

        public const int Radius = 20;
        public const int RadiusSqr = Radius * Radius;
        private const int StaticBoundingBox = Radius * 2;
        private const int AppoxAreaOfSight = (int)(Math.PI * Radius * Radius + 1);
        // Keep every UPDATE frame comfortably below the 128 KiB socket buffer.
        // UPDATE sections are independent, so chunking preserves protocol order.
        private const int MaxTilesPerUpdatePacket = 8192;
        private const int MaxObjectsPerUpdatePacket = 256;
        private const int MaxDropsPerUpdatePacket = 8192;

        private readonly HashSet<IntPoint> _clientStatic = new HashSet<IntPoint>();
        private readonly UpdatedSet _clientEntities;
        private ObjectStats[] _updateStatuses;
        private Update.TileData[] _tiles;
        private ObjectDef[] _newObjects;
        private int[] _removedObjects;

        private readonly object _statUpdateLock = new object();
        private readonly Dictionary<Entity, Dictionary<StatsType, object>> _statUpdates =
            new Dictionary<Entity, Dictionary<StatsType, object>>();

        public Sight Sight { get; private set; }

        public int TickId;

        // This is intentionally called on every Player world entry, even though a
        // newly constructed Player normally starts empty. It is the invariant that
        // protects a reused connection from suppressing destination-world objects.
        private void ResetWorldVisibilityState()
        {
            var staleEntities = _clientEntities.Count;
            var staleStatics = _clientStatic.Count;
            var staleKilled = ClientKilledEntity.Count;
            _clientEntities.RemoveWhere(e => true);
            _clientStatic.Clear();
            Entity ignored;
            while (ClientKilledEntity.TryDequeue(out ignored)) { }
            using (TimedLock.Lock(_statUpdateLock))
                _statUpdates.Clear();

            Log.InfoFormat("[WORLD_SYNC] visibility-reset trace={0} account={1} char={2} staleEntities={3} staleStatics={4} staleKilled={5} afterEntities={6} afterStatics={7}.",
                Client.PortalTransitionTraceId ?? "<none>", AccountId, Client.Character?.CharId ?? 0,
                staleEntities, staleStatics, staleKilled, _clientEntities.Count, _clientStatic.Count);
        }

        public void HandleStatChanges(object entity, StatChangedEventArgs statChange)
        {
            var e = entity as Entity;
            if (e == null || e != this && statChange.UpdateSelfOnly)
                return;
            using (TimedLock.Lock(_statUpdateLock))
            {
                if (e == this && statChange.Stat == StatsType.None)
                    return;

                if (!_statUpdates.ContainsKey(e))
                    _statUpdates[e] = new Dictionary<StatsType, object>();

                if (statChange.Stat != StatsType.None)
                    _statUpdates[e][statChange.Stat] = statChange.Value;

            }
        }

        private void SendNewTick(RealmTime time)
        {
            using (TimedLock.Lock(_statUpdateLock))
            {
                _updateStatuses = _statUpdates.Select(_ => new ObjectStats()
                {
                    DamageDealt = GetDamageDealt(_.Key),
                    Id = _.Key.Id,
                    Position = new Position() { X = _.Key.RealX, Y = _.Key.RealY },
                    Stats = _.Value.ToArray()
                }).ToArray();
                _statUpdates.Clear();
            }

            _client.SendPacket(new NewTick
            {
                TickId = ++TickId,
                // The client uses this duration for movement interpolation.  The world
                // already supplies the accumulated tick duration, so multiplying it
                // makes a local 200 ms tick appear as 600 ms of network latency.
                TickTime = time.ElaspedMsDelta,
                Statuses = _updateStatuses,
                DateTime = Manager.CurrentDatetime
            });
            AwaitMove(TickId);
        }

        private int GetDamageDealt(Entity en)
        {
            if (!(en is Enemy))
                return 0;
            if (en as Enemy == null || (en as Enemy).DamageCounter == null)
                return 0;
            var hitters = (en as Enemy).DamageCounter.hitters;
            if (!hitters.ContainsKey(this))
                return 0;
            return hitters[this];
        }

        private void SendUpdate(RealmTime time)
        {
            // init sight circle
            var sCircle = Sight.GetSightCircle(Owner.Blocking);

            // get list of tiles for update
            var tilesUpdate = new List<Update.TileData>(AppoxAreaOfSight);
            foreach (var point in sCircle)
            {
                var x = point.X;
                var y = point.Y;
                var tile = Owner.Map[x, y];

                if (tile.TileId == 255 ||
                    tiles[x, y] >= tile.UpdateCount)
                    continue;

                tilesUpdate.Add(new Update.TileData()
                {
                    X = (short)x,
                    Y = (short)y,
                    Tile = (Tile)tile.TileId
                });
                tiles[x, y] = tile.UpdateCount;
            }
            FameCounter.TileSent(tilesUpdate.Count);

            // get list of new static objects to add
            var expectedStaticObjects = sCircle.Count(point =>
            {
                var tile = Owner.Map[point.X, point.Y];
                return tile.ObjId != 0 && tile.ObjType != 0;
            });
            var knownStaticsBefore = _clientStatic.Count;
            var knownEntitiesBefore = _clientEntities.Count;
            var staticsUpdate = GetNewStatics(sCircle).ToArray();

            // get dropped entities list
            var entitiesRemove = new HashSet<int>(GetRemovedEntities(sCircle));

            // removed stale entities
            _clientEntities.RemoveWhere(e => entitiesRemove.Contains(e.Id));

            // get list of added entities
            var entitiesAdd = GetNewEntities(sCircle).ToArray();

            // get dropped statics list
            var staticsRemove = new HashSet<IntPoint>(GetRemovedStatics(sCircle));
            _clientStatic.ExceptWith(staticsRemove);

            if (tilesUpdate.Count > 0 || entitiesRemove.Count > 0 || staticsRemove.Count > 0 ||
                entitiesAdd.Length > 0 || staticsUpdate.Length > 0)
            {
                entitiesRemove.UnionWith(
                    staticsRemove.Select(s => Owner.Map[s.X, s.Y].ObjId));

                _tiles = tilesUpdate.ToArray();
                _newObjects = entitiesAdd.Select(_ => _.ToDefinition()).Concat(staticsUpdate).ToArray();
                _removedObjects = entitiesRemove.ToArray();

                var isInitialWorldUpdate = _client.MarkInitialWorldUpdate();

                var initialUpdate = new Update
                {
                    Tiles = _tiles,
                    NewObjs = _newObjects,
                    Drops = _removedObjects
                };
                var initialFrameLength = -1;
                if (isInitialWorldUpdate)
                {
                    var objectIds = new HashSet<int>();
                    var duplicateObjectIds = _newObjects.Count(obj => !objectIds.Add(obj.Stats.Id));
                    var dropObjectOverlap = _removedObjects.Count(id => objectIds.Contains(id));
                    var filteredAsKnown = expectedStaticObjects - staticsUpdate.Length;
                    Log.InfoFormat("[WORLD_SYNC] initial-enumeration trace={0} world={1} client={2} account={3} knownBeforeEntities={4} knownBeforeStatics={5} expectedStatics={6} filteredAsKnown={7} serializedObjects={8} queuedObjects={8} duplicateObjectIds={9} dropObjectOverlap={10}.",
                        Client.PortalTransitionTraceId ?? "<none>", Owner.Id, Client.Id, AccountId,
                        knownEntitiesBefore, knownStaticsBefore, expectedStaticObjects, filteredAsKnown,
                        _newObjects.Length, duplicateObjectIds, dropObjectOverlap);
                    if (knownStaticsBefore != 0 || knownEntitiesBefore != 0 || filteredAsKnown != 0 ||
                        duplicateObjectIds != 0 || dropObjectOverlap != 0)
                    {
                        Log.ErrorFormat("[WORLD_SYNC] rejected inconsistent initial state trace={0} world={1} account={2}.",
                            Client.PortalTransitionTraceId ?? "<none>", Owner.Id, AccountId);
                        _client.Disconnect("Initial world synchronization invariant failed.");
                        return;
                    }
                    try
                    {
                        initialFrameLength = initialUpdate.GetFrameLength();
                    }
                    catch (Exception e)
                    {
                        Log.Error($"[INITIAL_SYNC] UPDATE serialization failed world={Owner.Id} account={AccountId}.", e);
                        _client.Disconnect("Initial world synchronization serialization failed.");
                        return;
                    }
                }

                // Normal UPDATEs retain the original single-packet fast path. The
                // expensive size check and chunking are reserved for an oversized
                // first synchronization frame only.
                var chunkInitialUpdate = isInitialWorldUpdate && initialFrameLength > Server.BufferSize;
                if (isInitialWorldUpdate)
                {
                    Log.InfoFormat(
                        "[INITIAL_SYNC] begin worldType={0} world={1} account={2} bytes={3} chunked={4} tiles={5} staticObjects={6} entities={7} removed={8}",
                        Owner.GetType().Name, Owner.Id, AccountId, initialFrameLength, chunkInitialUpdate,
                        _tiles.Length, staticsUpdate.Length, _newObjects.Length, _removedObjects.Length);
                }

                if (!chunkInitialUpdate)
                {
                    _client.SendPacket(initialUpdate);
                    AwaitUpdateAck(time.TotalElapsedMs);
                    if (isInitialWorldUpdate)
                        Log.InfoFormat("[INITIAL_SYNC] released worldType={0} world={1} account={2} elapsedMs=0 acknowledgements=0/0 deferredPackets=0",
                            Owner.GetType().Name, Owner.Id, AccountId);
                    return;
                }

                Update[] updates;
                try
                {
                    updates = CreateUpdatePackets(_tiles, _newObjects, _removedObjects).ToArray();
                }
                catch (Exception e)
                {
                    Log.Error($"[VAULT_SYNC] UPDATE chunk creation failed world={Owner.Id} account={AccountId}.", e);
                    _client.Disconnect("Initial world synchronization serialization failed.");
                    return;
                }
                if (!_client.RegisterInitialUpdatePackets(updates.Length))
                {
                    Log.ErrorFormat("[INITIAL_SYNC] could not register oversized initial UPDATE world={0} account={1} chunks={2}.",
                        Owner.Id, AccountId, updates.Length);
                    _client.Disconnect("Initial world synchronization registration failed.");
                    return;
                }

                Log.InfoFormat("[INITIAL_SYNC] chunking worldType={0} world={1} account={2} chunks={3} expectedAcknowledgements={3}",
                    Owner.GetType().Name, Owner.Id, AccountId, updates.Length);

                for (var index = 0; index < updates.Length; index++)
                {
                    var update = updates[index];
                    int frameLength;
                    try
                    {
                        frameLength = update.GetFrameLength();
                    }
                    catch (Exception e)
                    {
                        Log.Error($"[VAULT_SYNC] UPDATE serialization failed world={Owner.Id} account={AccountId} chunk={index + 1}/{updates.Length}.", e);
                        _client.Disconnect("Initial world synchronization serialization failed.");
                        return;
                    }

                    if (frameLength > Server.BufferSize)
                    {
                        Log.ErrorFormat("[VAULT_SYNC] rejected oversized UPDATE world={0} account={1} chunk={2}/{3} bytes={4}.",
                            Owner.Id, AccountId, index + 1, updates.Length, frameLength);
                        _client.Disconnect("Initial world synchronization packet was too large.");
                        return;
                    }

                    Log.InfoFormat("[INITIAL_SYNC] chunk worldType={0} world={1} account={2} index={3}/{4} bytes={5} tiles={6} objects={7} drops={8}",
                            Owner.GetType().Name, Owner.Id, AccountId, index + 1, updates.Length, frameLength,
                            update.Tiles.Length, update.NewObjs.Length, update.Drops.Length);

                    _client.SendPacket(update);
                    AwaitUpdateAck(time.TotalElapsedMs);
                }
            }
        }

        private bool IsPortal(ObjectDef obj)
        {
            common.resources.ObjectDesc desc;
            return Manager.Resources.GameData.ObjectDescs.TryGetValue(obj.ObjectType, out desc) && desc.Class == "Portal";
        }

        private static IEnumerable<Update> CreateUpdatePackets(Update.TileData[] tiles, ObjectDef[] objects, int[] drops)
        {
            var complete = new Update { Tiles = tiles, NewObjs = objects, Drops = drops };
            if (complete.GetFrameLength() <= Server.BufferSize)
            {
                yield return complete;
                yield break;
            }

            foreach (var chunk in Chunk(tiles, MaxTilesPerUpdatePacket))
                yield return new Update { Tiles = chunk, NewObjs = new ObjectDef[0], Drops = new int[0] };

            foreach (var chunk in ChunkObjects(objects))
                yield return new Update { Tiles = new Update.TileData[0], NewObjs = chunk, Drops = new int[0] };

            foreach (var chunk in Chunk(drops, MaxDropsPerUpdatePacket))
                yield return new Update { Tiles = new Update.TileData[0], NewObjs = new ObjectDef[0], Drops = chunk };
        }

        private static IEnumerable<T[]> Chunk<T>(T[] values, int size)
        {
            if (values.Length == 0)
                return new T[0][];

            var chunks = new List<T[]>((values.Length + size - 1) / size);
            for (var offset = 0; offset < values.Length; offset += size)
            {
                var length = Math.Min(size, values.Length - offset);
                var chunk = new T[length];
                Array.Copy(values, offset, chunk, 0, length);
                chunks.Add(chunk);
            }
            return chunks;
        }

        private static IEnumerable<ObjectDef[]> ChunkObjects(ObjectDef[] objects)
        {
            var chunk = new List<ObjectDef>(Math.Min(MaxObjectsPerUpdatePacket, objects.Length));
            foreach (var obj in objects)
            {
                chunk.Add(obj);
                var candidate = new Update
                {
                    Tiles = new Update.TileData[0],
                    NewObjs = chunk.ToArray(),
                    Drops = new int[0]
                };

                if (chunk.Count <= MaxObjectsPerUpdatePacket && candidate.GetFrameLength() <= Server.BufferSize)
                    continue;

                chunk.RemoveAt(chunk.Count - 1);
                if (chunk.Count == 0)
                    throw new InvalidOperationException("A single UPDATE object definition exceeds the protocol frame limit.");

                yield return chunk.ToArray();
                chunk.Clear();
                chunk.Add(obj);
                if ((new Update
                {
                    Tiles = new Update.TileData[0],
                    NewObjs = chunk.ToArray(),
                    Drops = new int[0]
                }).GetFrameLength() > Server.BufferSize)
                    throw new InvalidOperationException("A single UPDATE object definition exceeds the protocol frame limit.");
            }

            if (chunk.Count > 0)
                yield return chunk.ToArray();
        }

        private IEnumerable<int> GetRemovedEntities(HashSet<IntPoint> visibleTiles)
        {
            foreach (var e in ClientKilledEntity)
                yield return e.Id;

            foreach (var i in _clientEntities)
            {
                if (i.Owner == null)
                    yield return i.Id;

                if (i != this && !i.CanBeSeenBy(this))
                    yield return i.Id;

                var so = i as StaticObject;
                if (so != null && so.Static)
                {
                    if (Math.Abs(StaticBoundingBox - ((int)X - i.X)) > 0 &&
                        Math.Abs(StaticBoundingBox - ((int)Y - i.Y)) > 0)
                        continue;
                }


                if (i is Player ||
                    i == questEntity || i == SpectateTarget || i == spooky || i == spooky2 || i == spooky3 || i == spooky4 || i == spooky5 || i == spooky6 || visibleTiles.Contains(new IntPoint((int)i.X, (int)i.Y)))
                    continue;

                yield return i.Id;
            }
        }

        private IEnumerable<Entity> GetNewEntities(HashSet<IntPoint> visibleTiles)
        {
            Entity entity;
            while (ClientKilledEntity.TryDequeue(out entity))
                _clientEntities.Remove(entity);

            foreach (var i in Owner.Players)
                if ((i.Value == this || (i.Value.Client.Account != null && i.Value.Client.Player.CanBeSeenBy(this))) && _clientEntities.Add(i.Value))
                    yield return i.Value;

            foreach (var i in Owner.PlayersCollision.HitTest(X, Y, Radius))
                if ((i is Decoy || i is Pet) && _clientEntities.Add(i))
                    yield return i;

            var p = new IntPoint(0, 0);
            foreach (var i in Owner.EnemiesCollision.HitTest(X, Y, Radius))
            {
                if (i is Container)
                {
                    int[] owners = (i as Container).BagOwners;
                    if (owners.Length > 0 && Array.IndexOf(owners, AccountId) == -1)
                        continue;
                }

                p.X = (int)i.X;
                p.Y = (int)i.Y;
                if (visibleTiles.Contains(p) && _clientEntities.Add(i))
                    yield return i;
            }

            if (spooky2?.Owner != null && _clientEntities.Add(spooky2))
                yield return spooky2;

            if (spooky3?.Owner != null && _clientEntities.Add(spooky3))
                yield return spooky3;

            if (spooky4?.Owner != null && _clientEntities.Add(spooky4))
                yield return spooky4;

            if (spooky5?.Owner != null && _clientEntities.Add(spooky5))
                yield return spooky5;

            if (spooky6?.Owner != null && _clientEntities.Add(spooky6))
                yield return spooky6;

            if (questEntity?.Owner != null && _clientEntities.Add(questEntity))
                yield return questEntity;

            if (spooky?.Owner != null && _clientEntities.Add(spooky))
                yield return spooky;

            if (SpectateTarget?.Owner != null && _clientEntities.Add(SpectateTarget))
                yield return SpectateTarget;
        }

        private IEnumerable<IntPoint> GetRemovedStatics(HashSet<IntPoint> visibleTiles)
        {
            foreach (var i in _clientStatic)
            {
                var tile = Owner.Map[i.X, i.Y];

                if (/*visibleTiles.Contains(i)*/
                    StaticBoundingBox - ((int)X - i.X) > 0 &&
                    StaticBoundingBox - ((int)Y - i.Y) > 0 &&
                    tile.ObjType != 0 &&
                    tile.ObjId != 0)
                    continue;

                yield return i;
            }
        }

        private readonly List<ObjectDef> _newStatics = new List<ObjectDef>(AppoxAreaOfSight);
        private IEnumerable<ObjectDef> GetNewStatics(HashSet<IntPoint> visibleTiles)
        {
            _newStatics.Clear();

            foreach (var i in visibleTiles)
            {
                var x = i.X;
                var y = i.Y;
                var tile = Owner.Map[x, y];

                if (tile.ObjId != 0 && tile.ObjType != 0 && _clientStatic.Add(i))
                    _newStatics.Add(tile.ToDef(x, y));
            }

            return _newStatics;
        }
    }
}
