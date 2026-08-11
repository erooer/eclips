using System.Linq;
using common.resources;
using wServer.realm.entities;
namespace wServer.realm.worlds.logic
{
    // Three compact clusters and the optional chamber are represented by the
    // spawn progression; final art/map is intentionally a functional placeholder.
    class SunkenReliquary : World
    {
        private Enemy _warden; private bool _complete, _populated;
        public SunkenReliquary(ProtoWorld proto, wServer.networking.Client client = null) : base(proto) { DungeonAnomalyService.Attach(this, DungeonAnomalyService.Roll(DungeonCodexService.All.FirstOrDefault(d => d.Key == "SunkenReliquary"), new System.Random(Id))); }
        public override int EnterWorld(Entity entity)
        {
            var id = base.EnterWorld(entity); var player = entity as Player;
            if (player != null && !_populated) { _populated = true; Spawn("Pearlbound Sentinel",2,2); Spawn("Tideglass Oracle",7,2); Spawn("Reliquary Custodian",5,4); Spawn("Nacre Shield Pearl",3,7); Spawn("Nacre Shield Pearl",5,7); Spawn("Nacre Shield Pearl",7,7); Spawn("Nacre Warden",5,8); }
            var e = entity as Enemy;
            if (e == null) return id;
            e.OnDeath += (s, a) => OnDeath(e);
            if (e.ObjectDesc.ObjectId == "Nacre Warden") { _warden = e; _warden.ApplyConditionEffect(ConditionEffectIndex.Invincible); }
            return id;
        }
        private void Spawn(string name, float x, float y) { var e = Entity.Resolve(Manager, name); if (e != null) { e.Move(x, y); EnterWorld(e); } }
        private void OnDeath(Enemy enemy)
        {
            if (enemy.ObjectDesc.ObjectId == "Reliquary Custodian" && _warden != null) _warden.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
            if (enemy.ObjectDesc.ObjectId == "Nacre Shield Pearl" && _warden != null && Enemies.Values.Count(x => x.ObjectDesc.ObjectId == "Nacre Shield Pearl") <= 1) _warden.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
            if (enemy.ObjectDesc.ObjectId == "Nacre Warden" && !_complete) { _complete = true; DungeonAnomalyService.Cleanup(this); foreach (var p in Players.Values) p.SendInfo("Sunken Reliquary cleared."); }
        }
    }
}
