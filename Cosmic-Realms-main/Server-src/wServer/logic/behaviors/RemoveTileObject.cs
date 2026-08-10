using System;
using System.Linq;
using wServer.realm;
using wServer.realm.entities;

namespace wServer.logic.behaviors
{
    class RemoveTileObject : Behavior
    {
        private readonly ushort _objType;
        private readonly int _range;

        public RemoveTileObject(ushort objType, int range)
        {
            _objType = objType;
            _range = range;
        }

        protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
        {
            var objType = _objType;

            var map = host.Owner.Map;

            var w = map.Width;
            var h = map.Height;

            var removed = 0;
            for (var y = 0; y < h; y++)
                for (var x = 0; x < w; x++)
                {
                    var tile = map[x, y];

                    if (tile.ObjType != objType)
                        continue;

                    var dx = Math.Abs(x - (int)host.X);
                    var dy = Math.Abs(y - (int)host.Y);

                    if (dx > _range || dy > _range)
                        continue;

                    if (tile.ObjDesc?.BlocksSight == true)
                    {
                        if (host.Owner.Blocking == 3)
                            Sight.UpdateRegion(map, x, y);

                        foreach (var plr in host.Owner.Players.Values
                            .Where(p => MathsUtils.DistSqr(p.X, p.Y, x, y) < Player.RadiusSqr))
                            plr.Sight.UpdateCount++;
                    }

                    tile.ObjType = 0;
                    tile.UpdateCount++;
                    map[x, y] = tile;
                    removed++;
                }

            if (host.ObjectDesc?.ObjectId == "Lab Open Wall")
                log4net.LogManager.GetLogger(typeof(RemoveTileObject)).InfoFormat(
                    "[MAD_LAB_GATE] controller={0} opened second-boss gate by removing {1} tile object(s) type=0x{2:X4} within range={3}.",
                    host.Id, removed, _objType, _range);
        }

        protected override void TickCore(Entity host, RealmTime time, ref object state) { }
    }
}
