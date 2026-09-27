// Does every name one side uses exist on the other?
//
// Three seams, each a runtime failure that nothing else catches:
//
//   nuiFetch('x')            needs  lib.callback.register('XS-MDT:server:x')
//   nuiPost('x')             needs  RegisterNUICallback('x')
//   a panel key in config    needs  a PANELS entry, a tab loader, and the
//                                   server's HasPanel to be asked about it
//
// A panel with no loader is a sidebar item that opens to nothing. A callback
// with no handler is a panel that shows its skeleton forever.
//
//   node tools/check-wiring.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.argv[2] || '.';

function walk(dir, ext, skip = []) {
  const out = [];
  (function go(d) {
    for (const e of readdirSync(d)) {
      if (skip.includes(e)) continue;
      const p = join(d, e);
      if (statSync(p).isDirectory()) go(p);
      else if (p.endsWith(ext)) out.push(p);
    }
  })(dir);
  return out;
}

const read = (p) => readFileSync(p, 'utf8');

const nuiJs = walk(join(ROOT, 'html', 'js'), '.js', ['vendor']).map(read).join('\n');
const serverLua = walk(join(ROOT, 'server'), '.lua').map(read).join('\n');
const clientLua = walk(join(ROOT, 'client'), '.lua').map(read).join('\n');
const config = read(join(ROOT, 'config.lua'));

const problems = [];
const names = (src, re) => new Set([...src.matchAll(re)].map((m) => m[1]));

// ── nuiFetch ↔ server callbacks ─────────────────────────────────────────────
const fetched = names(nuiJs, /nuiFetch\(\s*['"]([A-Za-z_]\w*)['"]/g);
const registered = names(serverLua, /lib\.callback\.register\(\s*['"]XS-MDT:server:([A-Za-z_]\w*)['"]/g);

for (const n of fetched) {
  if (!registered.has(n)) problems.push(`nuiFetch('${n}') has no lib.callback.register('XS-MDT:server:${n}')`);
}

// ── nuiPost ↔ client NUI callbacks ──────────────────────────────────────────
const posted = names(nuiJs, /nuiPost\(\s*['"]([A-Za-z_]\w*)['"]/g);
const nuiHandlers = names(clientLua, /RegisterNUICallback\(\s*['"]([A-Za-z_]\w*)['"]/g);

for (const n of posted) {
  if (!nuiHandlers.has(n)) problems.push(`nuiPost('${n}') has no RegisterNUICallback('${n}')`);
}

// ── panel keys ──────────────────────────────────────────────────────────────
// Every key any department lists must be a real panel on the NUI side.
const deptBlock = config.slice(config.indexOf('Config.Departments'), config.indexOf('Config.AuthorizedJobs'));
const configPanels = new Set();
for (const m of deptBlock.matchAll(/panels\s*=\s*\{([\s\S]*?)\}/g)) {
  for (const k of m[1].matchAll(/['"]([a-z]+)['"]/g)) configPanels.add(k[1]);
}

const appJs = read(join(ROOT, 'html', 'js', 'app.js'));
const registry = appJs.slice(appJs.indexOf('const PANELS = {'), appJs.indexOf('};', appJs.indexOf('const PANELS = {')));
const registryPanels = names(registry, /^\s*([a-z]+)\s*:/gm);

const loaderBlock = appJs.slice(appJs.indexOf('function onTabActivated'), appJs.indexOf('\n}', appJs.indexOf('function onTabActivated')));
const loaded = names(loaderBlock, /case\s+['"]([a-z]+)['"]/g);

for (const k of configPanels) {
  if (!registryPanels.has(k)) problems.push(`config lists panel '${k}' but PANELS in app.js has no entry for it`);
  if (!loaded.has(k)) problems.push(`config lists panel '${k}' but onTabActivated has no loader for it`);
}
for (const k of registryPanels) {
  if (!configPanels.has(k)) problems.push(`PANELS has '${k}' but no department can ever see it`);
  if (!loaded.has(k)) problems.push(`PANELS has '${k}' but onTabActivated has no loader for it`);
}

// Every loader named must exist as a function somewhere in the NUI.
for (const m of loaderBlock.matchAll(/case\s+['"][a-z]+['"]:\s*(\w+)\(/g)) {
  if (!new RegExp(`function\\s+${m[1]}\\s*\\(`).test(nuiJs)) {
    problems.push(`onTabActivated calls ${m[1]}(), which is not defined in any NUI script`);
  }
}

// ── icons ───────────────────────────────────────────────────────────────────
const iconsCss = read(join(ROOT, 'html', 'css', 'icons.css'));
const defined = names(iconsCss, /^\.i-([a-z-]+)\s*\{/gm);
const usedIcons = names(nuiJs + read(join(ROOT, 'html', 'index.html')), /\bi-([a-z-]+)\b/g);
for (const i of usedIcons) {
  if (['sm', 'lg', 'xl'].includes(i)) continue;
  if (!defined.has(i)) problems.push(`icon i-${i} is used but icons.css does not define it`);
}

console.log(`${fetched.size} server endpoints, ${posted.size} client endpoints, ${configPanels.size} panel keys, ${usedIcons.size} icons checked`);

if (problems.length) {
  console.log('\nPROBLEMS:');
  for (const p of [...new Set(problems)]) console.log('  ' + p);
  process.exit(1);
}

console.log('every seam is wired');
