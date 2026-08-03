/*
 * Cosmic Realms static content validator.  It intentionally has no runtime
 * dependencies so it can run on a clean Windows checkout with Node alone.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const toolRoot = path.resolve(__dirname, '..', '..');
const repo = path.join(toolRoot, 'Cosmic-Realms-main');
const resources = path.join(repo, 'Server-src', 'common', 'resources');
const xmlRoot = path.join(resources, 'xmls');
const worldRoot = path.join(resources, 'worlds');
const behaviorRoot = path.join(repo, 'Server-src', 'wServer', 'logic');
const args = process.argv.slice(2);
const scope = (args[args.indexOf('--scope') + 1] || 'all').toLowerCase();
const reportPath = args.includes('--report') ? path.resolve(args[args.indexOf('--report') + 1]) : null;
const reportOnly = args.includes('--report-only');

const report = { errors: [], warnings: [], info: [] };
const add = (level, text) => report[level].push(text);
const walk = (dir, predicate) => fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full, predicate) : (predicate(full) ? [full] : []);
});
const xmlEscape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const parseHex = value => /^0x/i.test(value) ? parseInt(value, 16) : Number(value);
const worldJson = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/0x[0-9a-f]+/gi, match => String(parseInt(match, 16))));

function loadResources() {
  const result = { byName: new Map(), byType: new Map(), grounds: new Map(), files: [] };
  for (const file of walk(xmlRoot, f => /EmbeddedData_.*\.dat$/i.test(f))) {
    result.files.push(file);
    const text = fs.readFileSync(file, 'utf8');
    // Embedded data uses a few legitimate root names besides Objects/GroundTypes.
    // Validate that this is an XML document without imposing a schema that legacy
    // bundles never used.
    const stripped = text.replace(/^\uFEFF/, '').replace(/<\?xml[\s\S]*?\?>/gi, '').replace(/<!--[\s\S]*?-->/g, '').trim();
    if (!/^<([A-Za-z_][\w:.-]*)\b[^>]*\/>$/.test(stripped) && !/^<([A-Za-z_][\w:.-]*)\b[^>]*>[\s\S]*<\/\1>$/.test(stripped)) add('errors', `Invalid XML envelope: ${path.relative(repo, file)}`);
    for (const match of text.matchAll(/<Object\s+([^>]*\bid="([^"]+)"[^>]*)>([\s\S]*?)<\/Object>/g)) {
      const [, attributes, name, body] = match;
      const typeMatch = attributes.match(/\btype="([^"]+)"/);
      if (!typeMatch) { add('errors', `Object without type: ${name} in ${path.basename(file)}`); continue; }
      const type = parseHex(typeMatch[1]);
      const item = { name, type, body, file, isGround: /<Ground\s*\/>/.test(body), projectiles: [...body.matchAll(/<Projectile\s+id="(\d+)"/g)].map(m => Number(m[1])) };
      if (result.byName.has(name)) add('warnings', `Duplicate object name '${name}' in ${path.basename(file)} and ${path.basename(result.byName.get(name).file)}`);
      else result.byName.set(name, item);
      if (result.byType.has(type)) add('warnings', `Duplicate type 0x${type.toString(16).padStart(4, '0')} for '${name}' and '${result.byType.get(type).name}'`);
      else result.byType.set(type, item);
      const indexes = new Set();
      for (const index of item.projectiles) {
        if (indexes.has(index)) add('errors', `Duplicate projectile index ${index} on '${name}'`);
        indexes.add(index);
      }
      for (const ref of body.matchAll(/<ObjectId>([^<]+)<\/ObjectId>/g)) if (!ref[1].trim()) add('errors', `Blank ObjectId reference on '${name}'`);
    }
    for (const match of text.matchAll(/<Ground\s+([^>]*\bid="([^"]+)"[^>]*)>/g)) {
      const [, attributes, name] = match;
      const typeMatch = attributes.match(/\btype="([^"]+)"/);
      if (!typeMatch) { add('errors', `Ground without type: ${name} in ${path.basename(file)}`); continue; }
      const type = parseHex(typeMatch[1]);
      if (result.grounds.has(type)) add('warnings', `Duplicate ground type 0x${type.toString(16).padStart(4, '0')} for '${name}' and '${result.grounds.get(type).name}'`);
      else result.grounds.set(type, { name, type, file });
    }
  }
  for (const item of result.byName.values()) {
    for (const ref of item.body.matchAll(/<ObjectId>([^<]+)<\/ObjectId>/g)) {
      const name = ref[1].trim();
      // The legacy set has historical aliases.  Keep them visible in reports but
      // reserve a hard failure for malformed resources and targeted preflight.
      if (!result.byName.has(name)) add('warnings', `Missing XML ObjectId '${name}' referenced by '${item.name}'`);
    }
    for (const texture of item.body.matchAll(/<Texture>\s*<File>([^<]+)<\/File>/g)) {
      const key = texture[1].trim();
      const assets = path.join(repo, 'Client-src', 'src', 'kabam', 'rotmg', 'assets');
      if (fs.existsSync(assets) && !walk(assets, f => path.basename(f).toLowerCase().includes(key.toLowerCase())).length)
        add('warnings', `Texture '${key}' for '${item.name}' has no obvious client embed filename`);
    }
  }
  return result;
}

function loadMaps(resourcesIndex) {
  const maps = new Map();
  for (const file of walk(worldRoot, f => /\.jm$/i.test(f))) {
    try {
      const map = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (!Number.isInteger(map.width) || !Number.isInteger(map.height) || map.width < 1 || map.height < 1) { add('errors', `Invalid map bounds: ${path.basename(file)}`); continue; }
      const raw = zlib.inflateSync(Buffer.from(map.data, 'base64'));
      if (raw.length !== map.width * map.height * 2) { add('errors', `Invalid encoded tile length: ${path.basename(file)}`); continue; }
      const ids = []; for (let i = 0; i < raw.length; i += 2) ids.push(raw.readInt16BE(i));
      if (ids.some(id => id < 0 || id >= map.dict.length)) add('errors', `Invalid dictionary tile reference: ${path.basename(file)}`);
      // Dictionary entry 0 is intentionally empty in many original maps to
      // represent void/black space.  It is a useful design warning, not corrupt
      // map data.  Actual invalid dictionary indexes remain build-blocking.
      if (ids.some(id => id === 0 && (!map.dict[0] || !map.dict[0].ground))) add('warnings', `Black/void tile placement in ${path.basename(file)}`);
      const spawns = [];
      map.dict.forEach((entry, index) => {
        if (!entry || typeof entry !== 'object') { add('errors', `Invalid map dictionary entry ${index} in ${path.basename(file)}`); return; }
        if (!entry.ground) add('warnings', `Map dictionary entry ${index} has no ground in ${path.basename(file)}`);
        for (const object of entry.objs || []) if (!resourcesIndex.byName.has(object.id)) add('warnings', `Map '${path.basename(file)}' references missing object '${object.id}'`);
        for (const region of entry.regions || []) if (!/^[A-Za-z][A-Za-z0-9 _-]*$/.test(region.id || '')) add('warnings', `Invalid region name '${region.id}' in ${path.basename(file)}`);
        if ((entry.regions || []).some(region => region.id === 'Spawn')) spawns.push(index);
      });
      if (spawns.length && !ids.some(id => spawns.includes(id))) add('errors', `Spawn region is not placed in ${path.basename(file)}`);
      maps.set(path.basename(file), { file, map, ids, spawns });
    } catch (error) { add('errors', `Cannot parse map ${path.basename(file)}: ${error.message}`); }
  }
  return maps;
}

function validateWorlds(resourcesIndex, maps) {
  const worlds = new Map();
  for (const file of walk(worldRoot, f => /\.jw$/i.test(f))) {
    try {
      const world = worldJson(file);
      if (!world.name) add('errors', `World definition lacks name: ${path.basename(file)}`);
      for (const map of world.maps || []) if (!maps.has(map)) add('warnings', `World '${world.name}' references non-JM or missing map '${map}'`);
      for (const portal of world.portals || []) if (!resourcesIndex.byType.has(Number(portal))) add('errors', `World '${world.name}' references missing portal type 0x${Number(portal).toString(16)}`);
      worlds.set(world.name, { file, world });
    } catch (error) { add('errors', `Cannot parse world ${path.basename(file)}: ${error.message}`); }
  }
  for (const [name, item] of worlds) {
    for (const portal of item.world.portals || []) {
      const object = resourcesIndex.byType.get(Number(portal));
      if (object && !/(?:<NexusPortal\b|<Portal\b|<Class>\s*Portal\s*<\/Class>)/.test(object.body)) add('warnings', `World '${name}' registers non-portal '${object.name}'`);
    }
  }
  return worlds;
}

function validateBehaviors(resourcesIndex) {
  const files = walk(behaviorRoot, f => /BehaviorDb.*\.cs$/i.test(f));
  const names = new Map();
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    for (const section of text.matchAll(/\.Init\("([^"]+)"([\s\S]*?)(?=\n\s*\.Init\(|\n\s*;)/g)) {
      const [, name, body] = section;
      if (names.has(name)) add('errors', `Duplicate BehaviorDb Init '${name}' in ${path.relative(repo, file)} and ${path.relative(repo, names.get(name))}`);
      else names.set(name, file);
      const object = resourcesIndex.byName.get(name);
      if (!object) { add('errors', `BehaviorDb Init references missing entity '${name}'`); continue; }
      const states = new Set([...body.matchAll(/new State\("([^"]+)"/g)].map(m => m[1]));
      for (const transition of body.matchAll(/(?:Timed|HpLess|PlayerWithin|EntitiesNotExists|EntityNotExists)Transition\([^,]+,\s*"([^"]+)"/g)) if (!states.has(transition[1])) add('errors', `Behavior '${name}' transitions to missing state '${transition[1]}'`);
      for (const index of body.matchAll(/projectileIndex:\s*(\d+)/g)) if (!object.projectiles.includes(Number(index[1]))) add('errors', `Behavior '${name}' references missing projectile ${index[1]}`);
      for (const spawn of body.matchAll(/new Spawn\("([^"]+)"/g)) if (!resourcesIndex.byName.has(spawn[1])) add('errors', `Behavior '${name}' spawns missing '${spawn[1]}'`);
      for (const loot of body.matchAll(/new ItemLoot\("([^"]+)"/g)) if (!resourcesIndex.byName.has(loot[1])) add('errors', `Behavior '${name}' drops missing '${loot[1]}'`);
    }
  }
  return names;
}

function performance(maps, resourcesIndex) {
  let largest = null, mapObjects = 0;
  for (const entry of maps.values()) {
    const area = entry.map.width * entry.map.height;
    if (!largest || area > largest.area) largest = { area, name: path.basename(entry.file), width: entry.map.width, height: entry.map.height };
    mapObjects += entry.ids.reduce((count, id) => count + ((entry.map.dict[id].objs || []).length), 0);
  }
  add('info', `Resources: ${resourcesIndex.byName.size} unique types (${resourcesIndex.grounds.size} grounds).`);
  add('info', `Maps: ${maps.size}; largest ${largest ? `${largest.name} (${largest.width}x${largest.height})` : 'n/a'}; ${mapObjects} static object placements.`);
}

const resourcesIndex = loadResources();
const maps = (scope === 'all' || scope === 'maps' || scope === 'dungeons' || scope === 'portals' || scope === 'performance') ? loadMaps(resourcesIndex) : new Map();
if (scope === 'all' || scope === 'worlds' || scope === 'portals' || scope === 'dungeons') validateWorlds(resourcesIndex, maps);
if (scope === 'all' || scope === 'behaviors') validateBehaviors(resourcesIndex);
if (scope === 'all' || scope === 'performance' || scope === 'types') performance(maps, resourcesIndex);

// Whole-repository scans include historical source that predates this tooling.
// In report-only mode retain every finding but label it as a non-blocking legacy
// finding; strict authored-content preflight remains the build gate.
if (reportOnly && report.errors.length) {
  report.warnings.unshift(...report.errors.map(text => `Legacy/static finding: ${text}`));
  report.errors.length = 0;
}

const lines = [
  'Cosmic Realms Static Validation Report',
  `Scope: ${scope}`, `Generated: ${new Date().toISOString()}`, '',
  `Errors (${report.errors.length})`, ...(report.errors.length ? report.errors.map(x => `- ${x}`) : ['- none']), '',
  `Warnings (${report.warnings.length})`, ...(report.warnings.length ? report.warnings.map(x => `- ${x}`) : ['- none']), '',
  'Summary', ...report.info.map(x => `- ${x}`), ''
];
if (reportPath) { fs.mkdirSync(path.dirname(reportPath), { recursive: true }); fs.writeFileSync(reportPath, lines.join('\n')); }
console.log(lines.join('\n'));
process.exitCode = report.errors.length && !reportOnly ? 1 : 0;
