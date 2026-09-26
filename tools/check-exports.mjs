// Does every exports['XS-MDT']:Name() call have a matching exports('Name', …)?
//
// A missing one is nil at runtime and only shows up when somebody opens the
// panel that uses it, which is how a personnel module shipped calling a
// WriteAudit that never existed.
//
//   node tools/check-exports.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.argv[2] || '.';

const files = [];
(function walk(d) {
  for (const e of readdirSync(d)) {
    if (['.git', 'node_modules', 'html', 'sql'].includes(e)) continue;
    const p = join(d, e);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.lua')) files.push(p);
  }
})(ROOT);

const declared = new Set();
const used = new Map();

for (const f of files) {
  const src = readFileSync(f, 'utf8');
  const rel = relative(ROOT, f).replace(/\\/g, '/');

  // Comments document integration hooks a server owner implements themselves,
  // so a name in one is not a call. Blanking them keeps those out of the list.
  const code = src.replace(/^\s*--.*$/gm, '');

  for (const m of src.matchAll(/^\s*exports\(\s*['"]([A-Za-z_][\w]*)['"]/gm)) declared.add(m[1]);

  for (const m of code.matchAll(/exports\[['"]XS-MDT['"]\]\s*:\s*([A-Za-z_][\w]*)/g)) {
    if (!used.has(m[1])) used.set(m[1], new Set());
    used.get(m[1]).add(rel);
  }
}

const missing = [...used].filter(([n]) => !declared.has(n));

console.log(`${declared.size} export(s) declared, ${used.size} called by name`);

if (missing.length) {
  console.log('\nCALLED BUT NEVER EXPORTED:');
  for (const [n, where] of missing) console.log(`  ${n}  — ${[...where].join(', ')}`);
  process.exit(1);
}

const unused = [...declared].filter((n) => !used.has(n));
console.log(unused.length ? `\nexported but never called internally: ${unused.join(', ')}` : '');
console.log('every internal export call resolves');
