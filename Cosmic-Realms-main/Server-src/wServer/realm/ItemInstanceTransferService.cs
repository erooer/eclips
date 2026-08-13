using System;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using common;
using Newtonsoft.Json;
using StackExchange.Redis;
using wServer.realm.entities;

namespace wServer.realm
{
    // Connects the legacy object-type inventory protocol to server-side records.
    // Persistent endpoints flush their ledger; bags retain the moved identity for
    // their in-world lifetime and never mint a second copy on pickup.
    internal static class ItemInstanceTransferService
    {
        static RInventory.ItemInstanceRecord[] Records(IContainer container)
        {
            if (container.DbLink != null) return container.DbLink.ItemInstances;
            var bag = container as Container;
            if (bag == null) return null;
            if (bag.RuntimeItemInstances == null || bag.RuntimeItemInstances.Length != bag.Inventory.Length)
                bag.RuntimeItemInstances = Enumerable.Range(0, bag.Inventory.Length).Select(i => bag.Inventory[i] == null ? null : new RInventory.ItemInstanceRecord { Id = Guid.NewGuid().ToString("N"), ObjectType = bag.Inventory[i].ObjectType, Metadata = "" }).ToArray();
            return bag.RuntimeItemInstances;
        }

        public static bool Swap(IContainer first, int firstSlot, IContainer second, int secondSlot)
        {
            if (first == null || second == null || firstSlot < 0 || secondSlot < 0 || firstSlot >= first.Inventory.Length || secondSlot >= second.Inventory.Length) return false;
            var aRecords = Records(first); var bRecords = first == second ? aRecords : Records(second);
            if (aRecords == null || bRecords == null) return false;
            var a = aRecords[firstSlot]; var b = bRecords[secondSlot];
            if (a == null && first.Inventory[firstSlot] != null) a = aRecords[firstSlot] = New(first.Inventory[firstSlot]);
            if (b == null && second.Inventory[secondSlot] != null) b = bRecords[secondSlot] = New(second.Inventory[secondSlot]);
            aRecords[firstSlot] = b; bRecords[secondSlot] = a;
            var ids = (first == second ? aRecords : aRecords.Concat(bRecords)).Where(x => x != null).Select(x => x.Id).ToArray();
            if (ids.Any(string.IsNullOrWhiteSpace) || ids.Distinct().Count() != ids.Length) { aRecords[firstSlot] = a; bRecords[secondSlot] = b; return false; }
            try
            {
                Save(first, aRecords);
                if (first != second) Save(second, bRecords);
                return true;
            }
            catch { aRecords[firstSlot] = a; bRecords[secondSlot] = b; return false; }
        }

        // Trade is the only supported multi-slot cross-owner operation. Map each
        // original durable record to exactly one final slot of the same object type
        // before either character snapshot is persisted.
        public static bool ApplyTransactions(params InventoryTransaction[] transactions)
        {
            if (transactions == null || transactions.Length == 0 || transactions.Any(x => x == null || x.Parent.DbLink == null)) return false;
            var contexts = transactions.Select(t => new { T = t, Records = t.Parent.DbLink.ItemInstances, Next = new RInventory.ItemInstanceRecord[t.Length] }).ToArray();
            if (contexts.Any(c => c.Records.Length != c.T.Length)) return false;
            var available = contexts.SelectMany(c => Enumerable.Range(0, c.T.Length).Where(i => c.T.OriginalItems[i] != null).Select(i => c.Records[i])).ToList();
            if (available.Any(x => x == null || string.IsNullOrWhiteSpace(x.Id))) return false;
            foreach (var c in contexts)
                for (var i = 0; i < c.T.Length; i++)
                    if (c.T.OriginalItems[i] != null && c.T.ChangedItems[i] != null && c.T.OriginalItems[i].ObjectType == c.T.ChangedItems[i].ObjectType)
                    { c.Next[i] = c.Records[i]; available.Remove(c.Records[i]); }
            foreach (var c in contexts)
                for (var i = 0; i < c.T.Length; i++)
                    if (c.T.ChangedItems[i] != null && c.Next[i] == null)
                    {
                        var record = available.FirstOrDefault(x => x.ObjectType == c.T.ChangedItems[i].ObjectType);
                        if (record == null) return false;
                        c.Next[i] = record; available.Remove(record);
                    }
            var ids = contexts.SelectMany(c => c.Next).Where(x => x != null).Select(x => x.Id).ToArray();
            if (ids.Distinct().Count() != ids.Length) return false;
            try
            {
                var database = contexts[0].T.Parent.DbLink.Database;
                if (contexts.Any(c => c.T.Parent.DbLink.Database != database)) return false;
                var transaction = database.CreateTransaction();
                foreach (var c in contexts)
                {
                    var link = c.T.Parent.DbLink;
                    var oldItems = link.Database.HashGet(link.Key, link.Field);
                    var oldRecords = link.Database.HashGet(link.Key, link.Field + ".instances");
                    transaction.AddCondition(Condition.HashEqual(link.Key, link.Field, oldItems));
                    transaction.AddCondition(Condition.HashEqual(link.Key, link.Field + ".instances", oldRecords));
                    transaction.HashSetAsync(link.Key, link.Field, ItemBytes(c.T.ChangedItems));
                    transaction.HashSetAsync(link.Key, link.Field + ".instances", JsonConvert.SerializeObject(c.Next));
                }
                if (!transaction.Execute()) return false;
                foreach (var c in contexts)
                {
                    c.T.Parent.DbLink.Items = c.T.ChangedItems.Select(x => x == null ? (ushort)0xffff : x.ObjectType).ToArray();
                    c.T.Parent.DbLink.SetItemInstances(c.Next);
                }
                return true;
            }
            catch { return false; }
        }

        // Gift chests are account-backed rather than RInventory-backed. This is a
        // single Redis transaction covering the legacy gift types, parallel gift
        // records, destination character types, and destination records. Nothing
        // in the client protocol changes.
        public static bool TryWithdrawGift(Player player, GiftChest chest, int giftSlot, int destinationSlot)
        {
            if (player == null || chest == null || player.DbLink == null || chest.GiftIndexes == null ||
                giftSlot < 0 || giftSlot >= chest.Inventory.Length || destinationSlot < 0 || destinationSlot >= player.Inventory.Length ||
                destinationSlot < 4 || chest.Inventory[giftSlot] == null || player.Inventory[destinationSlot] != null || giftSlot >= chest.GiftIndexes.Length)
                return false;
            var account = player.Client.Account;
            var expected = chest.RuntimeItemInstances == null ? null : chest.RuntimeItemInstances[giftSlot];
            var globalIndex = chest.GiftIndexes[giftSlot];
            try
            {
                var database = account.Database;
                account.Reload("gifts"); account.Reload("giftInstances");
                var gifts = account.Gifts.ToList();
                var giftRecords = account.GiftItemInstances.ToList();
                if (globalIndex < 0 || globalIndex >= gifts.Count || globalIndex >= giftRecords.Count ||
                    gifts[globalIndex] != chest.Inventory[giftSlot].ObjectType || giftRecords[globalIndex] == null ||
                    (expected != null && giftRecords[globalIndex].Id != expected.Id)) return false;
                var record = giftRecords[globalIndex];
                if (record.ObjectType != gifts[globalIndex] || string.IsNullOrWhiteSpace(record.Id)) return false;
                var charTypes = player.Inventory.GetItemTypes();
                var charRecords = player.DbLink.ItemInstances;
                if (charRecords.Length != charTypes.Length || charTypes[destinationSlot] != 0xffff || charRecords[destinationSlot] != null) return false;
                charTypes[destinationSlot] = record.ObjectType; charRecords[destinationSlot] = record;
                gifts.RemoveAt(globalIndex); giftRecords.RemoveAt(globalIndex);
                var all = charRecords.Concat(giftRecords).Where(x => x != null).Select(x => x.Id).ToArray();
                if (all.Distinct().Count() != all.Length) return false;
                var tx = database.CreateTransaction();
                var oldGifts = database.HashGet(account.Key, "gifts");
                var oldGiftRecords = database.HashGet(account.Key, "giftInstances");
                var oldCharTypes = database.HashGet(player.DbLink.Key, player.DbLink.Field);
                var oldCharRecords = database.HashGet(player.DbLink.Key, player.DbLink.Field + ".instances");
                tx.AddCondition(Condition.HashEqual(account.Key, "gifts", oldGifts));
                tx.AddCondition(Condition.HashEqual(account.Key, "giftInstances", oldGiftRecords));
                tx.AddCondition(Condition.HashEqual(player.DbLink.Key, player.DbLink.Field, oldCharTypes));
                tx.AddCondition(Condition.HashEqual(player.DbLink.Key, player.DbLink.Field + ".instances", oldCharRecords));
                tx.HashSetAsync(account.Key, "gifts", GiftBytes(gifts));
                tx.HashSetAsync(account.Key, "giftInstances", JsonConvert.SerializeObject(giftRecords));
                tx.HashSetAsync(player.DbLink.Key, player.DbLink.Field, UshortBytes(charTypes));
                tx.HashSetAsync(player.DbLink.Key, player.DbLink.Field + ".instances", JsonConvert.SerializeObject(charRecords));
                if (!tx.Execute()) return false;
                account.Reload("gifts"); account.Reload("giftInstances");
                player.DbLink.Reload(player.DbLink.Field); player.DbLink.Reload(player.DbLink.Field + ".instances");
                player.Inventory[destinationSlot] = chest.Inventory[giftSlot];
                chest.Inventory[giftSlot] = null; chest.RuntimeItemInstances[giftSlot] = null; chest.GiftIndexes[giftSlot] = -1;
                player.Client.Character.Items = charTypes;
                return true;
            }
            catch { return false; }
        }

        // A Gift Chest is intentionally withdrawal-only. Consumable use and
        // stacking destroy (or transform) the exact visible gift entry rather
        // than removing the first matching object type from the account list.
        public static bool TryConsumeGift(Player player, GiftChest chest, int giftSlot, common.resources.Item original, common.resources.Item successor)
        {
            if (player == null || chest == null || original == null || chest.GiftIndexes == null ||
                giftSlot < 0 || giftSlot >= chest.GiftIndexes.Length || chest.RuntimeItemInstances == null ||
                giftSlot >= chest.RuntimeItemInstances.Length)
                return false;
            var account = player.Client.Account;
            var expected = chest.RuntimeItemInstances[giftSlot];
            var globalIndex = chest.GiftIndexes[giftSlot];
            try
            {
                var database = account.Database;
                account.Reload("gifts"); account.Reload("giftInstances");
                var gifts = account.Gifts.ToList();
                var records = account.GiftItemInstances.ToList();
                if (globalIndex < 0 || globalIndex >= gifts.Count || globalIndex >= records.Count ||
                    gifts[globalIndex] != original.ObjectType || records[globalIndex] == null ||
                    records[globalIndex].ObjectType != original.ObjectType || string.IsNullOrWhiteSpace(records[globalIndex].Id) ||
                    (expected != null && records[globalIndex].Id != expected.Id))
                    return false;

                if (successor == null)
                {
                    gifts.RemoveAt(globalIndex);
                    records.RemoveAt(globalIndex);
                }
                else
                {
                    gifts[globalIndex] = successor.ObjectType;
                    records[globalIndex].ObjectType = successor.ObjectType;
                }
                var ids = records.Where(x => x != null).Select(x => x.Id).ToArray();
                if (ids.Distinct().Count() != ids.Length) return false;

                var tx = database.CreateTransaction();
                var oldGifts = database.HashGet(account.Key, "gifts");
                var oldRecords = database.HashGet(account.Key, "giftInstances");
                tx.AddCondition(Condition.HashEqual(account.Key, "gifts", oldGifts));
                tx.AddCondition(Condition.HashEqual(account.Key, "giftInstances", oldRecords));
                tx.HashSetAsync(account.Key, "gifts", GiftBytes(gifts));
                tx.HashSetAsync(account.Key, "giftInstances", JsonConvert.SerializeObject(records));
                if (!tx.Execute()) return false;

                account.Reload("gifts"); account.Reload("giftInstances");
                chest.RuntimeItemInstances[giftSlot] = successor == null ? null : records[globalIndex];
                if (successor == null) chest.GiftIndexes[giftSlot] = -1;
                return true;
            }
            catch { return false; }
        }

        // Transfers a gift directly to a temporary ground container while
        // retaining its record. The target is a fresh, empty bag, so the Redis
        // transaction only needs to remove the account-owned source first.
        public static bool TryDropGift(Player player, GiftChest chest, int giftSlot, Container bag)
        {
            if (player == null || chest == null || bag == null || bag.Inventory[0] == null || chest.GiftIndexes == null ||
                giftSlot < 0 || giftSlot >= chest.Inventory.Length || giftSlot >= chest.GiftIndexes.Length || chest.Inventory[giftSlot] == null)
                return false;
            var expected = chest.RuntimeItemInstances == null ? null : chest.RuntimeItemInstances[giftSlot];
            var account = player.Client.Account;
            var globalIndex = chest.GiftIndexes[giftSlot];
            try
            {
                var database = account.Database;
                account.Reload("gifts"); account.Reload("giftInstances");
                var gifts = account.Gifts.ToList(); var records = account.GiftItemInstances.ToList();
                if (globalIndex < 0 || globalIndex >= gifts.Count || globalIndex >= records.Count || records[globalIndex] == null ||
                    gifts[globalIndex] != chest.Inventory[giftSlot].ObjectType || records[globalIndex].ObjectType != gifts[globalIndex] ||
                    (expected != null && records[globalIndex].Id != expected.Id)) return false;
                var record = records[globalIndex];
                gifts.RemoveAt(globalIndex); records.RemoveAt(globalIndex);
                var ids = records.Where(x => x != null).Select(x => x.Id).ToArray();
                if (ids.Distinct().Count() != ids.Length) return false;
                var tx = database.CreateTransaction();
                var oldGifts = database.HashGet(account.Key, "gifts"); var oldRecords = database.HashGet(account.Key, "giftInstances");
                tx.AddCondition(Condition.HashEqual(account.Key, "gifts", oldGifts));
                tx.AddCondition(Condition.HashEqual(account.Key, "giftInstances", oldRecords));
                tx.HashSetAsync(account.Key, "gifts", GiftBytes(gifts));
                tx.HashSetAsync(account.Key, "giftInstances", JsonConvert.SerializeObject(records));
                if (!tx.Execute()) return false;
                account.Reload("gifts"); account.Reload("giftInstances");
                bag.RuntimeItemInstances[0] = record;
                chest.Inventory[giftSlot] = null; chest.RuntimeItemInstances[giftSlot] = null; chest.GiftIndexes[giftSlot] = -1;
                return true;
            }
            catch { return false; }
        }

        static byte[] ItemBytes(common.resources.Item[] items)
        {
            var types = items.Select(x => x == null ? (ushort)0xffff : x.ObjectType).ToArray();
            var bytes = new byte[types.Length * 2]; Buffer.BlockCopy(types, 0, bytes, 0, bytes.Length); return bytes;
        }

        static byte[] UshortBytes(IEnumerable<ushort> types)
        {
            var array = types.ToArray(); var bytes = new byte[array.Length * 2]; Buffer.BlockCopy(array, 0, bytes, 0, bytes.Length); return bytes;
        }

        static byte[] GiftBytes(IEnumerable<ushort> types)
        {
            var values = types.ToArray();
            return values.Length == 0 ? null : UshortBytes(values);
        }

        static RInventory.ItemInstanceRecord New(common.resources.Item item) { return new RInventory.ItemInstanceRecord { Id = Guid.NewGuid().ToString("N"), ObjectType = item.ObjectType, Metadata = "" }; }
        static void Save(IContainer container, RInventory.ItemInstanceRecord[] records)
        {
            if (container.DbLink == null) { ((Container)container).RuntimeItemInstances = records; return; }
            container.DbLink.SetItemInstances(records);
            container.DbLink.FlushAsync().GetAwaiter().GetResult();
        }
    }
}
