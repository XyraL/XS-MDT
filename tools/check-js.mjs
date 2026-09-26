// Do the NUI scripts actually parse?
//
// A panel with a syntax error takes the whole page down, and nothing else here
// catches it — block counting and class audits both happily read a file that
// would never run. new Function() compiles without executing, which is the
// same parse the browser does.
//
//   node tools/check-js.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.argv[2] || '.';
const HTML = join(ROOT, 'html');

const files = [];
(function walk(d) {
  for (const e of readdirSync(d)) {
    if (e === 'vendor') continue;
    const p = join(d, e);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.js')) files.push(p);
  }
})(HTML);

const bad = [];

for (const f of files.sort()) {
  const src = readFileSync(f, 'utf8');
  try {
    new Function(src);
  } catch (err) {
    bad.push(`${relative(ROOT, f).replace(/\\/g, '/')}  ${err.message}`);
  }
}

if (bad.length) {
  console.log('SYNTAX ERRORS:');
  for (const b of bad) console.log('  ' + b);
  process.exit(1);
}

console.log(`${files.length} NUI scripts parse`);
