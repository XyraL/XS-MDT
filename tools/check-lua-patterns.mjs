// Do the Lua patterns in this resource have balanced captures and classes?
//
// A broken pattern is a perfectly valid Lua string, so nothing else here sees
// it — not a syntax check, not a block count. It fails at runtime, once, from
// whichever line runs it, with "unfinished capture" and no file or reason.
//
// The trap it exists for: in a Lua pattern `%(` and `%)` are ESCAPED LITERAL
// parens. They do not open or close a capture. So this
//
//     s:match('(CREATE TABLE `' .. name .. '`.-\n%) ENGINE[^;]*;')
//
// opens a capture that nothing ever closes, because the only paren after it is
// escaped.
//
//   node tools/check-lua-patterns.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.argv[2] || '.';
const CALLS = /[:.](match|gmatch|gsub|find)\s*\(/g;

const files = [];
(function walk(d) {
  for (const e of readdirSync(d)) {
    if (['.git', 'node_modules', 'html', 'sql'].includes(e)) continue;
    const p = join(d, e);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.lua')) files.push(p);
  }
})(ROOT);

// The pattern argument, as written — every string literal up to the comma that
// ends the first argument, concatenated. Concatenation is how a pattern gets
// a table name spliced into it, and each half is unbalanced on its own.
function patternArg(line, from) {
  let out = '';
  let i = from;

  while (i < line.length) {
    const ch = line[i];

    if (ch === "'" || ch === '"') {
      const quote = ch;
      i++;
      while (i < line.length) {
        if (line[i] === '\\') { out += line[i] + (line[i + 1] || ''); i += 2; continue; }
        if (line[i] === quote) { i++; break; }
        out += line[i];
        i++;
      }
      continue;
    }

    // A comma outside a string ends the first argument — unless we have not
    // seen a literal yet, which means the pattern is a variable we cannot read.
    if (ch === ',') break;
    if (ch === ')' && !out) break;
    i++;
  }

  return out;
}

const problems = [];

for (const f of files) {
  const rel = relative(ROOT, f).replace(/\\/g, '/');

  readFileSync(f, 'utf8').split(/\r?\n/).forEach((line, n) => {
    if (/^\s*--/.test(line)) return;

    for (const m of line.matchAll(CALLS)) {
      const pat = patternArg(line, m.index + m[0].length);
      if (!pat) continue;

      let captures = 0, classes = 0;

      for (let i = 0; i < pat.length; i++) {
        if (pat[i] === '%') { i++; continue; }            // escaped: skip both
        if (pat[i] === '(') captures++;
        else if (pat[i] === ')') captures--;
        else if (pat[i] === '[') classes++;
        else if (pat[i] === ']' && classes > 0) classes--;

        if (captures < 0) {
          problems.push(`${rel}:${n + 1}  closes a capture that was never opened`);
          break;
        }
      }

      if (captures > 0) problems.push(`${rel}:${n + 1}  unfinished capture in ${m[1]} — ${captures} unclosed "("`);
      if (classes > 0) problems.push(`${rel}:${n + 1}  unfinished character class in ${m[1]} — ${classes} unclosed "["`);
    }
  });
}

console.log(`${files.length} Lua files scanned for pattern errors`);

if (problems.length) {
  console.log('\nPROBLEMS:');
  for (const p of [...new Set(problems)]) console.log('  ' + p);
  process.exit(1);
}

console.log('every Lua pattern balances');
