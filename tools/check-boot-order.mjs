// Does anything query the database at boot without waiting for the migration?
//
// server/schema-check.lua brings the database up to date on start. Anything
// that runs a query before it finishes is racing it, and the symptom is an
// "Unknown column" error for a column that is about to exist — which reads
// exactly like the schema being wrong when it is not.
//
// The rule: an onResourceStart handler that touches MySQL has to go through
// MdtSchema.Wait() first.
//
//   node tools/check-boot-order.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.argv[2] || '.';
const DIR = join(ROOT, 'server');

const problems = [];

for (const file of readdirSync(DIR).filter((f) => f.endsWith('.lua'))) {
  const src = readFileSync(join(DIR, file), 'utf8');
  const lines = src.split(/\r?\n/);

  // Functions in this file that end up touching the database.
  const dbFunctions = new Set();
  for (const m of src.matchAll(/(?:local\s+)?function\s+([\w.:]+)\s*\(([\s\S]*?)\n(?:local\s+)?end/g)) {
    if (/MySQL\./.test(m[2])) dbFunctions.add(m[1].replace(/^.*[.:]/, ''));
  }

  lines.forEach((line, i) => {
    if (!/AddEventHandler\(\s*['"]onResourceStart['"]/.test(line)) return;

    // The handler body: from here to the line that closes it at the same
    // indent. Good enough — these handlers are short by convention.
    const indent = line.length - line.trimStart().length;
    let end = lines.length;
    for (let j = i + 1; j < lines.length; j++) {
      const t = lines[j];
      if (t.trim() === 'end)' && (t.length - t.trimStart().length) === indent) { end = j; break; }
    }

    const body = lines.slice(i, end + 1).join('\n');

    const touchesDb = /MySQL\./.test(body)
      || [...dbFunctions].some((fn) => new RegExp(`\\b${fn}\\b`).test(body));

    if (touchesDb && !/MdtSchema\.Wait\(\)/.test(body)) {
      problems.push(`server/${file}:${i + 1}  queries the database on start without MdtSchema.Wait()`);
    }
  });
}

console.log(`${readdirSync(DIR).filter((f) => f.endsWith('.lua')).length} server files checked for boot ordering`);

if (problems.length) {
  console.log('\nPROBLEMS:');
  for (const p of problems) console.log('  ' + p);
  process.exit(1);
}

console.log('nothing queries the database before the migration finishes');
