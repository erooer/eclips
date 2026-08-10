using System.Linq;
using common.resources;
using wServer.realm.entities;
namespace wServer.realm.worlds.logic
{
    // Three compact clusters and the optional chamber are represented by the
    // spawn progression; final art/map is intentionally a functional placeholder.
    class SunkenReliquary : World
    {
        private Enemy _warden; private bool _complete;
        public SunkenReliquary(ProtoWorld proto) : base(proto) { DungeonAnomalyService.Attach(this, DungeonAnomalyService.Roll(DungeonCodexService.All.FirstOrDefault(d => d.Key == "SunkenReliquary"), new System.Random(Id))); }
        public override int EnterWorld(Entity entity)
        {
            var id = base.EnterWorld(entity); var e = entity as Enemy;
            if (e == null) return id;
            e.OnDeath += (s, a) => OnDeath(e);
            if (e.ObjectDesc.ObjectId == "Nacre Warden") { _warden = e; _warden.ApplyConditionEffect(ConditionEffectIndex.Invincible); }
            return id;
        }
        private void OnDeath(Enemy enemy)
        {
            if (enemy.ObjectDesc.ObjectId == "Reliquary Custodian" && _warden != null) _warden.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
            if (enemy.ObjectDesc.ObjectId == "Nacre Shield Pearl" && _warden != null && Enemies.Values.Count(x => x.ObjectDesc.ObjectId == "Nacre Shield Pearl") <= 1) _warden.ApplyConditionEffect(ConditionEffectIndex.Invincible, 0);
            if (enemy.ObjectDesc.ObjectId == "Nacre Warden" && !_complete) { _complete = true; DungeonAnomalyService.Cleanup(this); foreach (var p in Players.Values) p.SendInfo("Sunken Reliquary cleared."); }
        }
    }
}
