using common;

namespace wServer.realm.entities
{
    class GiftChest : OneWayContainer
    {
        // Maps a visible 0..7 chest slot to its stable account gift entry.
        // It is deliberately server-only; the client still receives only types.
        public int[] GiftIndexes { get; set; }
        public GiftChest(RealmManager manager, ushort objType, int? life, bool dying, RInventory dbLink = null) 
            : base(manager, objType, life, dying, dbLink)
        {
        }

        public GiftChest(RealmManager manager, ushort id) 
            : base(manager, id)
        {
        }
    }
}
