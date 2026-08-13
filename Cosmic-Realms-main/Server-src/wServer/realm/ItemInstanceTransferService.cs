using System;
using System.Linq;
using common;
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
            try { foreach (var c in contexts) Save(c.T.Parent, c.Next); return true; }
            catch { return false; }
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
