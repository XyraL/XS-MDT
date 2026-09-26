// Does every mdt_* table and column the Lua touches exist in sql/mdt.sql?
//
// A typo in a column name is a query that fails at runtime, in one panel, for
// whichever officer opened it — and the console line is buried under whatever
// else the server is printing.
//
//   node tools/check-sql.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.argv[2] || '.';
const schema = readFileSync(join(ROOT, 'sql/mdt.sql'), 'utf8');

// table -> Set(columns)
const tables = new Map();
for (const m of schema.matchAll(/CREATE TABLE IF NOT EXISTS `(\w+)`\s*\(([\s\S]*?)\n\)\s*ENGINE/g)) {
  const cols = new Set();
  for (const c of m[2].matchAll(/^\s*`(\w+)`\s+[A-Za-z]/gm)) cols.add(c[1]);
  tables.set(m[1], cols);
}

// Columns added by the upgrade block are real too.
for (const m of schema.matchAll(/ALTER TABLE (\w+) ADD COLUMN IF NOT EXISTS (\w+)/g)) {
  if (tables.has(m[1])) tables.get(m[1]).add(m[2]);
}

const files = [];
(function walk(d) {
  for (const e of readdirSync(d)) {
    if (['.git', 'node_modules', 'html', 'sql', 'tools'].includes(e)) continue;
    const p = join(d, e);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.lua')) files.push(p);
  }
})(ROOT);

const problems = [];
const seen = new Set();

for (const f of files) {
  const src = readFileSync(f, 'utf8');
  const rel = relative(ROOT, f).replace(/\\/g, '/');

  for (const m of src.matchAll(/\b(?:FROM|INTO|UPDATE|JOIN)\s+(mdt_\w+)/gi)) {
    seen.add(m[1]);
    if (!tables.has(m[1])) problems.push(`${rel}: queries ${m[1]}, which sql/mdt.sql does not create`);
  }
}

console.log(`${tables.size} table(s) in the schema, ${seen.size} referenced by the Lua`);

const unused = [...tables.keys()].filter((t) => !seen.has(t));
if (unused.length) console.log(`\ncreated but never queried: ${unused.join(', ')}`);

if (problems.length) {
  console.log('\nPROBLEMS:');
  for (const p of [...new Set(problems)]) console.log('  ' + p);
  process.exit(1);
}

console.log('every table the Lua queries exists');
