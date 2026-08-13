using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using common;
using common.resources;
using wServer.networking;
using wServer.networking.packets.outgoing;
using wServer.realm.entities;
using wServer.realm.entities.vendors;
using wServer.realm.terrain;

namespace wServer.realm.worlds.logic
{
    public class Vault : World
    {
        public int AccountId { get; private set; }
        public DateTime InitializedUtc { get; private set; }

        private readonly Client _client;

        private LinkedList<Container> vaults;

        public Vault(ProtoWorld proto, Client client = null) : base(proto)
        {
            if (client != null)
            {
                _client = client;
                AccountId = _client.Account.AccountId;
                ExtraXML = ExtraXML.Concat(new[]
                {
                    @"	<Objects>
		                    <Object type=""0x0504"" id=""Vault Chest"">
			                    <Class>Container</Class>
			                    <Container/>
			                    <CanPutNormalObjects/>
			                    <CanPutSoulboundObjects/>
			                    <ShowName/>
			                    <Texture><File>lofiObj2</File><Index>0x0e</Index></Texture>
			                    <SlotTypes>0, 0, 0, 0, 0, 0, 0, 0</SlotTypes>
		                    </Object>
	                    </Objects>"
                }).ToArray();
                vaults = new LinkedList<Container>();
            }
        }

        public override bool AllowedAccess(Client client)
        {
            return base.AllowedAccess(client) && AccountId == client.Account.AccountId;
        }

        protected override void Init()
        {
            if (IsLimbo)
                return;

            FromWorldMap(new MemoryStream(Manager.Resources.Worlds[Name].wmap[0]));
            InitVault();
        }

        void InitVault()
        {
            var vaultChestPosition = new List<IntPoint>();
            var giftChestPosition = new List<IntPoint>();
            var spawn = new IntPoint(0, 0);

            var w = Map.Width;
            var h = Map.Height;

            for (var y = 0; y < h; y++)
                for (var x = 0; x < w; x++)
                {
                    var tile = Map[x, y];
                    switch (tile.Region)
                    {
                        case TileRegion.Spawn:
                            spawn = new IntPoint(x, y);
                            break;
                        case TileRegion.Vault:
                            vaultChestPosition.Add(new IntPoint(x, y));
                            break;
                        case TileRegion.Gifting_Chest:
                            giftChestPosition.Add(new IntPoint(x, y));
                            break;
                    }
                }

            vaultChestPosition.Sort((x, y) => Comparer<int>.Default.Compare(
                (x.X - spawn.X) * (x.X - spawn.X) + (x.Y - spawn.Y) * (x.Y - spawn.Y),
                (y.X - spawn.X) * (y.X - spawn.X) + (y.Y - spawn.Y) * (y.Y - spawn.Y)));

            giftChestPosition.Sort((x, y) => Comparer<int>.Default.Compare(
                (x.X - spawn.X) * (x.X - spawn.X) + (x.Y - spawn.Y) * (x.Y - spawn.Y),
                (y.X - spawn.X) * (y.X - spawn.X) + (y.Y - spawn.Y) * (y.Y - spawn.Y)));

            for (var i = 0; i < _client.Account.VaultCount && vaultChestPosition.Count > 0; i++)
            {
                var vaultChest = new DbVaultSingle(_client.Account, i);
                var con = new Container(_client.Manager, 0x0504, null, false, vaultChest);
                con.BagOwners = new int[] { _client.Account.AccountId };
                con.Inventory.SetItems(vaultChest.Items);
                con.Inventory.InventoryChanged += (sender, e) => SaveChest(((Inventory) sender).Parent);
                con.Move(vaultChestPosition[0].X + 0.5f, vaultChestPosition[0].Y + 0.5f);
                EnterWorld(con);
                vaultChestPosition.RemoveAt(0);
                vaults.AddFirst(con);
            }
            foreach (var i in vaultChestPosition)
            {
                var x = new ClosedVaultChest(_client.Manager, 0x0505);
                x.Move(i.X + 0.5f, i.Y + 0.5f);
                EnterWorld(x);
            }

            // The storage UI already uses the account's PotionStoragePotions fields.
            // Add one local access point beside the existing Daily Login/Tinkerer hub;
            // it is a view only, not another inventory or persistence system.
            ushort dailyLoginType;
            ushort tinkererType;
            Manager.Resources.GameData.IdToObjectType.TryGetValue("Daily Login Rewards", out dailyLoginType);
            Manager.Resources.GameData.IdToObjectType.TryGetValue("Quest Rewards", out tinkererType);
            var seer = StaticObjects.Values.FirstOrDefault(e =>
                e.ObjectType == dailyLoginType || e.ObjectType == tinkererType);
            if (seer != null)
            {
                var storage = Entity.Resolve(Manager, "Potion Storage");
                if (storage != null)
                {
                    var placed = false;
                    for (var radius = 2; radius <= 5 && !placed; radius++)
                        for (var dx = -radius; dx <= radius && !placed; dx++)
                            for (var dy = -radius; dy <= radius; dy++)
                            {
                                if (Math.Abs(dx) != radius && Math.Abs(dy) != radius)
                                    continue;
                                var x = (int)seer.X + dx + .5f;
                                var y = (int)seer.Y + dy + .5f;
                                if (!IsPassable(x, y, true))
                                    continue;
                                // Static objects export their server-side Size stat.  Set it
                                // here so it cannot override the XML's 25% display size.
                                storage.SetDefaultSize(25);
                                storage.Move(x, y);
                                EnterWorld(storage);
                                placed = true;
                                break;
                            }
                }
            }

            var gifts = _client.Account.Gifts.ToList();
            var giftRecords = _client.Manager.Database.EnsureGiftInstances(_client.Account).ToList();
            gifts = _client.Account.Gifts.ToList();
            var giftOffset = 0;
            while (gifts.Count > 0 && giftChestPosition.Count > 0)
            {
                var c = Math.Min(8, gifts.Count);
                var items = gifts.GetRange(0, c);
                var records = giftRecords.GetRange(0, c);
                var indexes = Enumerable.Range(giftOffset, c).ToArray();
                gifts.RemoveRange(0, c);
                giftRecords.RemoveRange(0, c);
                giftOffset += c;
                if (c < 8)
                {
                    items.AddRange(Enumerable.Repeat(ushort.MaxValue, 8 - c));
                    records.AddRange(Enumerable.Repeat<RInventory.ItemInstanceRecord>(null, 8 - c));
                }

                var con = new GiftChest(_client.Manager, 0x0744, null, false);
                con.BagOwners = new int[] { _client.Account.AccountId };
                con.Inventory.SetItems(items);
                con.RuntimeItemInstances = records.ToArray();
                con.GiftIndexes = indexes;
                con.Move(giftChestPosition[0].X + 0.5f, giftChestPosition[0].Y + 0.5f);
                EnterWorld(con);
                giftChestPosition.RemoveAt(0);
            }
            foreach (var i in giftChestPosition)
            {
                var x = new StaticObject(_client.Manager, 0x0743, null, true, false, false);
                x.Move(i.X + 0.5f, i.Y + 0.5f);
                EnterWorld(x);
            }

            // devon roach
            if (_client.Account.Name.Equals("Devon"))
            {
                var e = new Enemy(Manager, 0x12C);
                e.Move(38, 68);
                EnterWorld(e);
            }

            InitializedUtc = DateTime.UtcNow;
        }

        public override void Tick(RealmTime time)
        {
            base.Tick(time);
        }

        public void AddChest(Entity original)
        {
            var vaultChest = new DbVaultSingle(_client.Account, _client.Account.VaultCount - 1);
            var con = new Container(_client.Manager, 0x0504, null, false, vaultChest);
            con.BagOwners = new int[] { _client.Account.AccountId };
            con.Inventory.SetItems(vaultChest.Items);
            con.Inventory.InventoryChanged += (sender, e) => SaveChest(((Inventory) sender).Parent);
            con.Move(original.X, original.Y);
            LeaveWorld(original);
            EnterWorld(con);
            con.InvokeStatChange(StatsType.NameChosen, true);
            vaults.AddFirst(con);
        }

        private void SaveChest(IContainer chest)
        {
            var dbLink = chest?.DbLink;
            if (dbLink == null)
                return;

            dbLink.Items = chest.Inventory.GetItemTypes();
            dbLink.FlushAsync();
        }

        public override void LeaveWorld(Entity entity)
        {
            base.LeaveWorld(entity);

            if (entity.ObjectType != 0x0744)
                return;

            var x = new StaticObject(_client.Manager, 0x0743, null, true, false, false);
            x.Move(entity.X, entity.Y);
            EnterWorld(x);

            if (_client.Account.Gifts.Length <= 0)
                _client.SendPacket(new GlobalNotification
                {
                    Text = "giftChestEmpty"
                });
        }
    }
}
