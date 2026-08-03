/* Read-only type allocation helper. It never edits game resources. */
'use strict';
const fs=require('fs'), path=require('path');
const root=path.resolve(__dirname,'..','..','Cosmic-Realms-main','Server-src','common','resources','xmls');
const args=process.argv.slice(2), kind=(args[args.indexOf('--kind')+1]||'object').toLowerCase();
const range=(args[args.indexOf('--range')+1]||'F000-FFFF').split('-').map(x=>parseInt(x,16));
if(!['object','ground'].includes(kind)||range.some(Number.isNaN)||range[0]>range[1]) throw new Error('Use --kind object|ground --range F000-FFFF');
const used=new Map();
for(const file of fs.readdirSync(root).filter(f=>/^EmbeddedData_.*\.dat$/i.test(f))){
 const text=fs.readFileSync(path.join(root,file),'utf8');
 const tag=kind==='ground'?'Ground':'Object';
 for(const m of text.matchAll(new RegExp('<'+tag+'\\s+([^>]+)', 'g'))){ const id=m[1].match(/\btype="(0x[0-9a-f]+|\d+)"/i); if(id){const n=Number(id[1]);(used.get(n)||used.set(n,[]).get(n)).push(file);} }
}
const free=[]; for(let id=range[0];id<=range[1];id++) if(!used.has(id)) free.push(id);
const runs=[]; for(const id of free){const last=runs.at(-1);if(last&&last[1]===id-1)last[1]=id;else runs.push([id,id]);}
console.log(`${kind} IDs in 0x${range[0].toString(16)}-0x${range[1].toString(16)}: ${used.size} total used; ${free.length} free.`);
console.log('Free ranges: '+(runs.length?runs.map(r=>`0x${r[0].toString(16).padStart(4,'0')}${r[0]===r[1]?'':`-0x${r[1].toString(16).padStart(4,'0')}`}`).join(', '):'none'));
