// Generates html/css/icons.css from the paths below.
//
// Icons ship as CSS masks rather than inline <svg> so a panel only has to write
// <i class="i i-lock"></i>. The mask takes its colour from currentColor, which
// means an icon inside a red row is red without the panel knowing anything
// about it, and the 242 emoji this replaced are gone from the markup.
//
// Run after editing anything here:   node tools/build-icons.mjs
import { writeFileSync } from 'node:fs';

// 24x24 grid, 1.7 stroke, round caps. Drawn on whole and half units so lines
// land on pixel boundaries at 16px, which is the size the rail uses.
const S = (d) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;

const ICONS = {
  // Overview
  dashboard: S('<rect x="3" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.5"/>'),
  roster:    S('<path d="M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20"/><circle cx="10" cy="8" r="3.5"/><path d="M20 20v-1.5a3.5 3.5 0 0 0-2.6-3.4M15.5 4.7a3.5 3.5 0 0 1 0 6.6"/>'),
  map:       S('<path d="m9 4.5-5 2v13l5-2 6 2 5-2v-13l-5 2-6-2Z"/><path d="M9 4.5v13M15 6.5v13"/>'),

  // Lookups
  user:      S('<circle cx="12" cy="8" r="3.6"/><path d="M5.5 20v-1.4A4.6 4.6 0 0 1 10 14h4a4.6 4.6 0 0 1 4.5 4.6V20"/>'),
  car:       S('<path d="M4.5 16.5v2a.9.9 0 0 0 .9.9h1.7a.9.9 0 0 0 .9-.9v-2M16 16.5v2a.9.9 0 0 0 .9.9h1.7a.9.9 0 0 0 .9-.9v-2"/><path d="M3.5 16.5v-4l1.9-4.6A1.8 1.8 0 0 1 7.1 6.8h9.8a1.8 1.8 0 0 1 1.7 1.1l1.9 4.6v4Z"/><path d="M3.5 12.5h17M7 14.8h1.5M15.5 14.8H17"/>'),

  // Records
  scale:     S('<path d="M12 4.2v15.6M7.5 19.8h9M4 8.2h16M8 6.9l-4 1.3M16 6.9l4 1.3"/><path d="m4 8.2-2.2 5.2a2.6 2.6 0 0 0 4.4 0Zm16 0-2.2 5.2a2.6 2.6 0 0 0 4.4 0Z"/>'),
  eye:       S('<path d="M2.5 12S6 5.8 12 5.8 21.5 12 21.5 12 18 18.2 12 18.2 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="3"/>'),
  lock:      S('<rect x="4.5" y="10.3" width="15" height="10.2" rx="2"/><path d="M8 10.3V7.6a4 4 0 0 1 8 0v2.7M12 14.3v2.4"/>'),
  file:      S('<path d="M13.5 3.5H7a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9Z"/><path d="M13.5 3.5V9H19M8.5 13h7M8.5 16.5h4.5"/>'),
  clipboard: S('<path d="M9 4.5H7.5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2v-12a2 2 0 0 0-2-2H15"/><rect x="9" y="2.8" width="6" height="3.6" rx="1.1"/><path d="M8.8 12h6.4M8.8 15.5h4"/>'),
  list:      S('<path d="M8.5 6.5h11M8.5 12h11M8.5 17.5h11M4.6 6.5h.01M4.6 12h.01M4.6 17.5h.01"/>'),

  // Medical
  cross:     S('<path d="M9.4 3.6h5.2v5.8h5.8v5.2h-5.8v5.8H9.4v-5.8H3.6V9.4h5.8Z"/>'),
  heart:     S('<path d="M12 19.9S3.8 15 3.8 9.6a4.4 4.4 0 0 1 8.2-2.2 4.4 4.4 0 0 1 8.2 2.2c0 5.4-8.2 10.3-8.2 10.3Z"/>'),
  pill:      S('<rect x="2.6" y="8.4" width="18.8" height="7.2" rx="3.6" transform="rotate(-45 12 12)"/><path d="m9.2 9.2 5.6 5.6"/>'),
  droplet:   S('<path d="M12 3.4s5.6 5.4 5.6 9.2a5.6 5.6 0 1 1-11.2 0C6.4 8.8 12 3.4 12 3.4Z"/>'),

  // Fire
  flame:     S('<path d="M12 21c3.3 0 6-2.5 6-5.7 0-4.4-4.4-6-3.2-10.3-3.1.8-5.1 3.3-5.1 5.6 0 1.4.6 2.3.6 3.1 0 1-.8 1.8-1.7 1.8-.8 0-1.4-.5-1.7-1.2A6.4 6.4 0 0 0 6 15.3C6 18.5 8.7 21 12 21Z"/>'),
  hazard:    S('<path d="M10.6 3.6a1.6 1.6 0 0 1 2.8 0l8 14.2a1.6 1.6 0 0 1-1.4 2.4H4a1.6 1.6 0 0 1-1.4-2.4Z"/><path d="M12 9.3v4.1M12 17h.01"/>'),
  truck:     S('<path d="M2.8 16.6V8.4a1.6 1.6 0 0 1 1.6-1.6h8.2v9.8M12.6 9.8h3.6l3.4 3.4v3.4"/><circle cx="7.2" cy="17.6" r="1.9"/><circle cx="16.6" cy="17.6" r="1.9"/><path d="M9.1 17.6h5.6M2.8 17.6h2.5M18.5 17.6h2.7"/>'),

  // Dispatch
  signal:    S('<path d="M12 10.3v10.2M9.7 20.5h4.6"/><circle cx="12" cy="7.4" r="2"/><path d="M7.9 3.3a5.8 5.8 0 0 0 0 8.2M16.1 3.3a5.8 5.8 0 0 1 0 8.2M4.9 14.6a9.6 9.6 0 0 1 0-14M19.1 .6a9.6 9.6 0 0 1 0 14"/>'),
  clock:     S('<circle cx="12" cy="12" r="8.6"/><path d="M12 7.3V12l3.1 1.9"/>'),
  pin:       S('<path d="M14.6 2.6 21.4 9.4M17.7 5.7l-3.4 3.4.9 4.2-4.1 2-6.6-6.6 2-4.1 4.2.9ZM8.3 15.7 3.6 20.4"/>'),

  // Personnel
  camera:    S('<path d="M5 19.5A2.2 2.2 0 0 1 2.8 17.3V9.6a2.2 2.2 0 0 1 2.2-2.2h2.3l1.5-2.4h6.4l1.5 2.4H19a2.2 2.2 0 0 1 2.2 2.2v7.7a2.2 2.2 0 0 1-2.2 2.2Z"/><circle cx="12" cy="13.2" r="3.4"/>'),
  badge:     S('<path d="M12 2.8 4.6 5.6v6.2c0 4 3.1 7.7 7.4 9.4 4.3-1.7 7.4-5.4 7.4-9.4V5.6Z"/><path d="m8.9 11.9 2.2 2.2 4-4.3"/>'),

  // Chrome
  search:    S('<circle cx="10.8" cy="10.8" r="6.6"/><path d="m20 20-4.7-4.7"/>'),
  alert:     S('<path d="M10.6 3.6a1.6 1.6 0 0 1 2.8 0l8 14.2a1.6 1.6 0 0 1-1.4 2.4H4a1.6 1.6 0 0 1-1.4-2.4Z"/><path d="M12 9v4M12 16.7h.01"/>'),
  info:      S('<circle cx="12" cy="12" r="8.6"/><path d="M12 11.3v5M12 7.9h.01"/>'),
  'map-pin': S('<path d="M19 10.2c0 5.2-7 11-7 11s-7-5.8-7-11a7 7 0 0 1 14 0Z"/><circle cx="12" cy="10.1" r="2.6"/>'),
  radio:     S('<rect x="4.2" y="9" width="10.4" height="11.4" rx="1.8"/><path d="M6.8 12.3h5.2M6.8 15.4h2.4M17.4 12.4v5.4"/><path d="m11.6 7.4 7.3-3.6M17.4 9.6a1 1 0 0 1 2 0v.6h-2Z"/>'),
  video:     S('<rect x="2.8" y="6.4" width="13" height="11.2" rx="2.2"/><path d="m15.8 12.6 5.4 3.4V8l-5.4 3.4Z"/>'),
  edit:      S('<path d="M12.4 5.1H5.6a2 2 0 0 0-2 2v11.3a2 2 0 0 0 2 2h11.3a2 2 0 0 0 2-2v-6.8"/><path d="M17.7 3.5a2.1 2.1 0 0 1 3 3l-8.4 8.4-3.9.9.9-3.9Z"/>'),
  trash:     S('<path d="M3.9 6.5h16.2M8.6 6.5V4.8a1.6 1.6 0 0 1 1.6-1.6h3.6a1.6 1.6 0 0 1 1.6 1.6v1.7M18 6.5v13a1.8 1.8 0 0 1-1.8 1.8H7.8A1.8 1.8 0 0 1 6 19.5v-13M10.2 10.8v6M13.8 10.8v6"/>'),
  printer:   S('<path d="M6.6 9V3.6h10.8V9M6.6 17.4H5.2A2.2 2.2 0 0 1 3 15.2v-4A2.2 2.2 0 0 1 5.2 9h13.6a2.2 2.2 0 0 1 2.2 2.2v4a2.2 2.2 0 0 1-2.2 2.2h-1.4"/><rect x="6.6" y="13.8" width="10.8" height="6.6" rx="1.2"/>'),
  archive:   S('<rect x="2.8" y="3.6" width="18.4" height="4.6" rx="1.4"/><path d="M4.6 8.2v10.4a1.8 1.8 0 0 0 1.8 1.8h11.2a1.8 1.8 0 0 0 1.8-1.8V8.2M9.8 12.2h4.4"/>'),
  box:       S('<path d="m12 2.8 8.4 4.4v9.6L12 21.2 3.6 16.8V7.2Z"/><path d="M3.6 7.2 12 11.7l8.4-4.5M12 21.2v-9.5M7.8 5l8.4 4.4"/>'),
  bolt:      S('<path d="M12.8 2.6 4.4 13.4h6.4l-.6 8 8.4-10.8h-6.4Z"/>'),
  cash:      S('<rect x="2.6" y="6.2" width="18.8" height="11.6" rx="2"/><circle cx="12" cy="12" r="2.8"/><path d="M6.2 9.9v.01M17.8 14.1v.01"/>'),
  calendar:  S('<rect x="3.6" y="5.2" width="16.8" height="15.2" rx="2"/><path d="M3.6 10h16.8M8.2 2.8v4.4M15.8 2.8v4.4"/>'),
  phone:     S('<path d="M20.3 16.9v2.6a1.8 1.8 0 0 1-2 1.8 17.7 17.7 0 0 1-7.7-2.7 17.4 17.4 0 0 1-5.4-5.4A17.7 17.7 0 0 1 2.6 5.4a1.8 1.8 0 0 1 1.8-2H7a1.8 1.8 0 0 1 1.8 1.5 11.3 11.3 0 0 0 .6 2.5 1.8 1.8 0 0 1-.4 1.9L7.8 10.5a14.2 14.2 0 0 0 5.4 5.4l1.2-1.2a1.8 1.8 0 0 1 1.9-.4 11.3 11.3 0 0 0 2.5.6 1.8 1.8 0 0 1 1.5 1.8Z"/>'),
  id:        S('<rect x="2.6" y="5.2" width="18.8" height="13.6" rx="2"/><circle cx="8.6" cy="11.2" r="2.2"/><path d="M4.9 16.4a3.9 3.9 0 0 1 7.4 0M14.8 10h4.2M14.8 13.4h4.2"/>'),
  save:      S('<path d="M19.4 20.4H4.6a1.8 1.8 0 0 1-1.8-1.8V5.4a1.8 1.8 0 0 1 1.8-1.8h11l5.4 5.4v9.6a1.8 1.8 0 0 1-1.6 1.8Z"/><path d="M7.4 20.4v-6.6h9.2v6.6M7.4 3.6v4.6h6.6"/>'),
  trophy:    S('<path d="M7.6 3.6h8.8v6a4.4 4.4 0 0 1-8.8 0Z"/><path d="M7.6 5.4H4.8v1.7a3.2 3.2 0 0 0 2.8 3.1M16.4 5.4h2.8v1.7a3.2 3.2 0 0 1-2.8 3.1M12 14v3.4M8.4 20.4h7.2l-.7-3H9.1Z"/>'),
  chart:     S('<path d="M3.4 20.4h17.2"/><rect x="5" y="12" width="3.6" height="5.6" rx="1"/><rect x="10.2" y="7.4" width="3.6" height="10.2" rx="1"/><rect x="15.4" y="10" width="3.6" height="7.6" rx="1"/>'),
  folder:    S('<path d="M2.8 6.8a1.8 1.8 0 0 1 1.8-1.8h4.2l2 2.6h8.8a1.8 1.8 0 0 1 1.8 1.8v8.4a1.8 1.8 0 0 1-1.8 1.8H4.6a1.8 1.8 0 0 1-1.8-1.8Z"/>'),
  x:         S('<path d="m5.6 5.6 12.8 12.8M18.4 5.6 5.6 18.4"/>'),
  check:     S('<path d="m4.6 12.6 4.8 4.8 10-10.8"/>'),
  refresh:   S('<path d="M20.4 11a8.6 8.6 0 0 0-14.6-4.5L2.8 9.4M3.6 13a8.6 8.6 0 0 0 14.6 4.5l3-2.9"/><path d="M2.8 4.6v4.8h4.8M21.2 19.4v-4.8h-4.8"/>'),
  siren:     S('<path d="M6 17.4v-4.8a6 6 0 0 1 12 0v4.8"/><rect x="3.4" y="17.4" width="17.2" height="3.4" rx="1.4"/><path d="M12 3.4V1.8M3.9 7.2 2.5 6.4M20.1 7.2l1.4-.8"/>'),
  traffic:   S('<rect x="7.4" y="2.8" width="9.2" height="18.4" rx="3.2"/><path d="M12 7.2h.01M12 12h.01M12 16.8h.01"/>'),
  dot:       S('<circle cx="12" cy="12" r="5" fill="#000" stroke="none"/>'),
  plus:      S('<path d="M12 5.2v13.6M5.2 12h13.6"/>'),
  filter:    S('<path d="M3.4 5.2h17.2l-6.6 7.8v6.2l-4-2.2v-4Z"/>'),
  download:  S('<path d="M12 3.6v11.2M7.4 10.4 12 15l4.6-4.6M4.4 19.4h15.2"/>'),
  copy:      S('<rect x="8.4" y="8.4" width="11.2" height="11.2" rx="2"/><path d="M15.6 8.4V6.2a1.8 1.8 0 0 0-1.8-1.8H6.2a1.8 1.8 0 0 0-1.8 1.8v7.6a1.8 1.8 0 0 0 1.8 1.8h2.2"/>'),
  chevron:   S('<path d="m8.8 5.4 7 6.6-7 6.6"/>'),
  shield:    S('<path d="M12 2.8 4.6 5.6v6.2c0 4 3.1 7.7 7.4 9.4 4.3-1.7 7.4-5.4 7.4-9.4V5.6Z"/>'),
  link:      S('<path d="M10.2 13.8a3.8 3.8 0 0 0 5.7.4l2.8-2.8a3.8 3.8 0 0 0-5.4-5.4l-1.6 1.6M13.8 10.2a3.8 3.8 0 0 0-5.7-.4l-2.8 2.8a3.8 3.8 0 0 0 5.4 5.4l1.6-1.6"/>'),
};

const uri = (svg) =>
  `url("data:image/svg+xml,${encodeURIComponent(svg).replace(/'/g, '%27').replace(/\(/g, '%28').replace(/\)/g, '%29')}")`;

const out = [
`/*  Icon sprite — GENERATED by tools/build-icons.mjs. Do not hand-edit.
 *
 *  Usage:  <i class="i i-lock"></i>
 *
 *  Each class is a CSS mask, so the glyph is painted in currentColor. An icon
 *  in a red row is red; an icon in the rail is the rail's text colour. Size
 *  follows font-size, and .i-sm / .i-lg / .i-xl step off that.
 */

.i {
  display: inline-block;
  width: 1.08em; height: 1.08em;
  flex: none;
  vertical-align: -0.16em;
  background-color: currentColor;
  -webkit-mask-repeat: no-repeat; mask-repeat: no-repeat;
  -webkit-mask-position: center;  mask-position: center;
  -webkit-mask-size: contain;     mask-size: contain;
}

.i-sm { width: .9em;  height: .9em; }
.i-lg { width: 1.3em; height: 1.3em; }
.i-xl { width: 1.7em; height: 1.7em; }
`];

for (const [name, svg] of Object.entries(ICONS)) {
  out.push(`.i-${name} { -webkit-mask-image: ${uri(svg)}; mask-image: ${uri(svg)}; }`);
}

writeFileSync('html/css/icons.css', out.join('\n') + '\n');
console.log(`${Object.keys(ICONS).length} icons written to html/css/icons.css`);
