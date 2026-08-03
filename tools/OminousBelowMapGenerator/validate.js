const fs=require('fs'), zlib=require('zlib'), path=require('path');
const root=path.resolve(__dirname,'../../Cosmic-Realms-main');
const map=JSON.parse(fs.readFileSync(path.join(root,'Server-src/common/resources/worlds/OminousBelow.jm'),'utf8'));
const raw=zlib.inflateSync(Buffer.from(map.data,'base64'));
if(raw.length!==map.width*map.height*2) throw new Error('encoded map length does not match dimensions');
const ids=[]; for(let i=0;i<raw.length;i+=2){const id=raw.readInt16BE(i);if(id<0||id>=map.dict.length)throw new Error('invalid tile dictionary index '+id);ids.push(id)}
if(ids.some(x=>x===undefined)) throw new Error('unassigned map tile');
let xml=''; for(const f of fs.readdirSync(path.join(root,'Server-src/common/resources/xmls'))){if(f.endsWith('.dat'))xml+=fs.readFileSync(path.join(root,'Server-src/common/resources/xmls',f),'utf8')}
const objects=new Map();
for(const match of xml.matchAll(/<Object\s+type="([^"]+)"\s+id="([^"]+)"[^>]*>([\s\S]*?)<\/Object>/g)) objects.set(match[2],match[3]);
for(const entry of map.dict) for(const obj of (entry.objs||[])) if(!new RegExp('<Object[^>]*\\bid="'+obj.id.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'"').test(xml)) throw new Error('map object does not resolve: '+obj.id);
const spawn=map.dict.findIndex(d=>(d.regions||[]).some(r=>r.id==='Spawn'));
if(spawn<0||!ids.includes(spawn)) throw new Error('missing valid Spawn tile');
const parseWorld = file => JSON.parse(fs.readFileSync(file,'utf8').replace(/0x[0-9a-f]+/gi, value => String(parseInt(value,16))));
const world=parseWorld(path.join(root,'Server-src/common/resources/worlds/OminousBelow.jw'));
if(world.name!=='OminousBelow'||!world.portals.includes(0xF900)) throw new Error('world/class name or entrance portal registration is invalid');
const nexus=parseWorld(path.join(root,'Server-src/common/resources/worlds/Nexus.jw'));
if(!nexus.portals.includes(0xF919)) throw new Error('return portal is not registered to Nexus');
const gateYs=[28,29,30,31,32];
for(const x of [32,47,81]) for(const y of gateYs) if(ids[y*map.width+x]!==1) throw new Error('gate wall missing at '+x+','+y);
const mapObjects=ids.map(i=>map.dict[i]).flatMap(d=>(d.objs||[]).map(o=>o.id));
const count=name=>mapObjects.filter(x=>x===name).length;
if(count('Ominous Soul Lantern')!==3 || count('Ominous Seal')!==4) throw new Error('map objective count is invalid');
if(count('Soul Barge Anchor')!==0 || count('Chain Anchor')!==0 || count('Ritual Pillar')!==0) throw new Error('phase anchors must be behavior-spawned, not map-spawned');
const objectPositions=name=>ids.flatMap((id,index)=>(map.dict[id].objs||[]).some(o=>o.id===name)?[{x:index%map.width,y:Math.floor(index/map.width)}]:[]);
const spawnIndex=ids.indexOf(spawn), spawnPos={x:spawnIndex%map.width,y:Math.floor(spawnIndex/map.width)};
const reachable=(openGates=[])=>{
  const queue=[spawnPos], seen=new Set([spawnPos.x+','+spawnPos.y]);
  while(queue.length){
    const p=queue.shift();
    for(const [dx,dy] of [[1,0],[-1,0],[0,1],[0,-1]]){
      const x=p.x+dx,y=p.y+dy,key=x+','+y;
      if(x<0||y<0||x>=map.width||y>=map.height||seen.has(key)) continue;
      const isOpenGate=openGates.includes(x)&&gateYs.includes(y);
      if(ids[y*map.width+x]===1&&!isOpenGate) continue;
      seen.add(key); queue.push({x,y});
    }
  }
  return seen;
};
const reaches=(seen,points,label)=>{ for(const p of points) if(!seen.has(p.x+','+p.y)) throw new Error(label+' is not reachable at '+p.x+','+p.y); };
// Verify the intended progression route, not merely that the objects exist.
reaches(reachable(),objectPositions('Ominous Soul Lantern'),'lantern');
reaches(reachable([32]),objectPositions('The Faceless Ferryman'),'Ferryman');
reaches(reachable([32,47]),objectPositions('Veyra, Warden of Chains'),'section-two objective');
const behavior=fs.readFileSync(path.join(root,'Server-src/wServer/logic/db/BehaviorDb.OminousBelow.cs'),'utf8');
const sections=[...behavior.matchAll(/\.Init\("([^"]+)"([\s\S]*?)(?=\n\s*\.Init\(|\n\s*;)/g)];
if(sections.length<20) throw new Error('expected Ominous behavior definitions were not found');
for(const section of sections){
  const [,name,body]=section; if(!objects.has(name)) throw new Error('BehaviorDb Init does not resolve: '+name);
  const objectXml=objects.get(name); const projectileIds=[...objectXml.matchAll(/<Projectile\s+id="(\d+)"/g)].map(m=>+m[1]);
  for(const m of body.matchAll(/projectileIndex:\s*(\d+)/g)) if(!projectileIds.includes(+m[1])) throw new Error(name+' references missing projectile '+m[1]);
  for(const m of body.matchAll(/new Spawn\("([^"]+)"/g)) if(!objects.has(m[1])) throw new Error(name+' spawns missing object '+m[1]);
  for(const m of body.matchAll(/new ItemLoot\("([^"]+)"/g)) if(!objects.has(m[1])) throw new Error(name+' drops missing item '+m[1]);
  const states=[...body.matchAll(/new State\("([^"]+)"/g)].map(m=>m[1]);
  for(const m of body.matchAll(/(?:Timed|HpLess|PlayerWithin)Transition\([^,]+,\s*"([^"]+)"/g)) if(!states.includes(m[1])) throw new Error(name+' transitions to missing state '+m[1]);
}
for(const entry of map.dict) for(const obj of (entry.objs||[])) {
  const definition=objects.get(obj.id)||'';
  for(const projectile of definition.matchAll(/<Projectile[^>]*>[\s\S]*?<ObjectId>([^<]+)<\/ObjectId>[\s\S]*?<\/Projectile>/g))
    if(!objects.has(projectile[1])) throw new Error(obj.id+' projectile references missing object '+projectile[1]);
}
console.log('PASS: map '+map.width+'x'+map.height+', '+ids.length+' assigned tiles, objective counts, resources/portal return mapping, gates, and '+sections.length+' behavior definitions.');
