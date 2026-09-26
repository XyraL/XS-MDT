// Does fxmanifest's files{} list match what html/index.html actually loads?
//
// The list is written by hand, so a new panel is easy to add to the page and
// forget here — and a file FiveM does not serve is a 404 in NUI, which shows
// up as a panel that silently does nothing.
//
//   node tools/check-manifest.mjs
import { readFileSync } from 'node:fs';
import { existsSync } from 'node:fs';

const ROOT = process.argv[2] || '.';

const manifest = readFileSync(`${ROOT}/fxmanifest.lua`, 'utf8');
const html = readFileSync(`${ROOT}/html/index.html`, 'utf8');

const block = manifest.match(/files\s*\{([\s\S]*?)\n\}/);
if (!block) throw new Error('no files{} block in fxmanifest.lua');

const listed = new Set(
  [...block[1].matchAll(/['"]([^'"]+)['"]/g)].map((m) => m[1]),
);

// index.html itself is the page; everything else it pulls in is relative to it.
const referenced = [...html.matchAll(/(?:src|href)\s*=\s*["']([^"':]+)["']/g)]
  .map((m) => 'html/' + m[1].replace(/^\.\//, '').split('?')[0]);

const problems = [];

for (const ref of new Set(referenced)) {
  if (listed.has(ref)) continue;
  // A glob in the manifest covers a whole directory.
  const covered = [...listed].some((l) => {
    if (!l.includes('*')) return false;
    const re = new RegExp('^' + l.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, '.*').replace(/(?<!\.)\*/g, '[^/]*') + '$');
    return re.test(ref);
  });
  if (!covered) problems.push(`the page loads ${ref}, but fxmanifest does not ship it`);
}

for (const l of listed) {
  if (l.includes('*')) continue;
  if (!existsSync(`${ROOT}/${l}`)) problems.push(`fxmanifest ships ${l}, which does not exist`);
}

console.log(`${listed.size} path(s) in files{}, ${new Set(referenced).size} referenced by the page`);

if (problems.length) {
  console.log('\nPROBLEMS:');
  for (const p of problems) console.log('  ' + p);
  process.exit(1);
}

console.log('the page and the manifest agree');
