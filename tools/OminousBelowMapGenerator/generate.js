/* Deterministic authored map generator for The Ominous Below. */
const fs = require('fs');
const zlib = require('zlib');
const path = require('path');
const out = path.resolve(__dirname, '../../Cosmic-Realms-main/Server-src/common/resources/worlds/OminousBelow.jm');
const width = 115, height = 61;
const dict = [
  { ground: '1GroundOmen1' },
  { ground: '1GroundOmen1', objs: [{ id: '1CreepyWall1' }] },
  { ground: '1GroundOmen1', regions: [{ id: 'Spawn' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Drowned Pilgrim' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Lantern Wraith' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Riverbound Hound' }] },
  { ground: '1GroundOmen1', objs: [{ id: "Ferryman's Attendant" }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Soul Collector' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Ominous Soul Lantern' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'The Faceless Ferryman' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Soul Barge Anchor' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Shackled Revenant' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Oathbreaker Judge' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Iron Gaoler' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Condemned Oracle' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'The First Gaoler' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'The Last Gaoler' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Veyra, Warden of Chains' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Chain Anchor' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Abyssal Remnant' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Ominous Eye' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Hollow Devourer' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Ominous Seal' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'The Ominous One' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Ritual Pillar' }] },
  { ground: '1GroundOmen1', objs: [{ id: 'Ominous Return Portal' }] }
];
const tiles = Array(width * height).fill(0);
const put = (x, y, id) => { if (x < 0 || y < 0 || x >= width || y >= height) throw new Error('out of bounds'); tiles[y * width + x] = id; };
// Outer walls and two server-controlled gates.  OminousBelow.cs removes the
// gate entities only after the local instance completes the required phase.
for (let x=0; x<width; x++) { put(x,0,1); put(x,height-1,1); }
for (let y=0; y<height; y++) { put(0,y,1); put(width-1,y,1); }
// The first section is a larger authored river-crypt maze. Each wall has a
// five-tile opening, creating readable loops rather than one-tile choke points.
for (const divider of [32, 47, 81]) for (let y=1; y<height-1; y++) put(divider,y,1);
for (let y=2; y<=42; y++) if (y<7 || y>11) put(7,y,1);
for (let y=18; y<=59; y++) if (y<32 || y>36) put(13,y,1);
for (let y=1; y<=45; y++) if (y<14 || y>18) put(19,y,1);
for (let y=16; y<=59; y++) if (y<44 || y>48) put(25,y,1);
for (let y=1; y<=42; y++) if (y<25 || y>29) put(30,y,1);
put(3,30,2);
[[5,26,3],[9,14,3],[16,33,3],[21,42,3],[27,34,3],[10,9,4],[17,28,4],[22,45,5],[24,21,6],[27,37,6],[28,29,7],[10,8,8],[16,34,8],[22,46,8],[40,30,9],
 [54,16,11],[58,35,11],[63,14,12],[69,36,13],[73,20,14],[72,30,14],[56,25,15],[73,25,16],[64,25,17],
 [87,17,19],[89,34,19],[94,14,20],[97,36,21],[90,25,22],[103,25,22],[96,14,22],[96,36,22],[96,25,23],[108,25,25]
].forEach(([x,y,id])=>put(x,y,id));
const raw=Buffer.alloc(width*height*2); tiles.forEach((v,i)=>raw.writeInt16BE(v,i*2));
const map={width,height,dict,data:zlib.deflateSync(raw).toString('base64')};
fs.writeFileSync(out,JSON.stringify(map,null,2)+'\n');
console.log('Wrote '+out+' ('+width+'x'+height+', '+tiles.length+' assigned tiles).');
