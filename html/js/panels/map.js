/* XS-MDT — Live Map
 *
 * Leaflet over a tile pyramid of the San Andreas satellite render. The game's
 * own pause map can't be rendered inside NUI (it's an engine render target
 * CEF has no access to), so this is an image map calibrated to world coords.
 *
 * Tiles: html/assets/maps/tiles/{z}_{x}_{y}.webp — regenerate with
 * `node tools/build-map-tiles.js` after swapping the source image.
 */

const MAP = {
    imageW: 4096,
    imageH: 6144,
    tileSize: 512,
    nativeZoom: 4,     // zoom at which the render sits 1:1 (see the build script)
    maxZoom: 6,        // Leaflet upscales past nativeZoom so you can keep zooming

    // The GTA world rectangle this render covers. Fitted against the postal
    // set that is drawn on the render itself — six postals from the north
    // tip to LSIA, both coasts and dead centre, all land within two pixels.
    //
    // 9000 x 13500 is exactly 2:3, like the 4096 x 6144 image, so the pixels
    // are square. Never nudge one axis on its own — doing that is what put
    // players up to 300m out before.
    world: { minX: -4140, maxX: 4860, minY: -5100, maxY: 8400 },
};

// Mirrors the department colours in config.lua.
const JOB_COLOR = {
    police:'#6366f1', sheriff:'#818cf8', swat:'#4f46e5', statepolice:'#818cf8',
    ambulance:'#22c55e', ems:'#22c55e',
    fire:'#ef4444', firefighter:'#ef4444',
};
const jobColor = job => JOB_COLOR[job] || '#6366f1';

const LEGEND = [
    { label:'Police', color:'#6366f1' },
    { label:'EMS',    color:'#22c55e' },
    { label:'Fire',   color:'#ef4444' },
];

const PRIORITY_COLOR = { 1:'#ef4444', 2:'#f59e0b', 3:'#6366f1' };

let _map = null;
let _unitLayer = null, _callLayer = null;
let _unitMarkers = {}, _callMarkers = {};
let _mapInterval = null;
let _followCid = null;
let _mapUnits = [], _mapCalls = [];

// ── Coordinate transform ──────────────────────────────────────────────────
function worldToLatLng(wx, wy) {
    const W = MAP.world;
    const px = ((wx - W.minX) / (W.maxX - W.minX)) * MAP.imageW;
    const py = ((W.maxY - wy) / (W.maxY - W.minY)) * MAP.imageH;
    return _map.unproject([px, py], MAP.nativeZoom);
}

function latLngToWorld(latlng) {
    const W = MAP.world;
    const p = _map.project(latlng, MAP.nativeZoom);
    return {
        x: W.minX + (p.x / MAP.imageW) * (W.maxX - W.minX),
        y: W.maxY - (p.y / MAP.imageH) * (W.maxY - W.minY),
    };
}

// ── Markers ───────────────────────────────────────────────────────────────
function unitIcon(unit) {
    const color = jobColor(unit.job);
    const label = unit.badge && unit.badge !== 'N/A'
        ? `${esc((unit.name || '').split(' ')[0])} ${unit.badge}`
        : (unit.name || 'Unit').split(' ')[0];

    // The arrow points along the unit's heading; GTA headings run anticlockwise
    // from north, CSS rotation runs clockwise, hence the negation.
    return L.divIcon({
        className: 'cmap-unit',
        html: `
            <div class="cmap-unit-wrap">
                <div class="cmap-unit-arrow" style="transform:rotate(${-(unit.heading || 0)}deg);border-bottom-color:${color};"></div>
                <div class="cmap-unit-dot" style="background:${color};box-shadow:0 0 10px ${color};"></div>
                <div class="cmap-unit-label" style="border-color:${color};">${label}</div>
            </div>`,
        iconSize: [0, 0],
        iconAnchor: [0, 0],
    });
}

function callIcon(call) {
    const color = PRIORITY_COLOR[call.priority] || '#f59e0b';
    return L.divIcon({
        className: 'cmap-call',
        html: `
            <div class="cmap-call-wrap">
                <div class="cmap-call-pulse" style="background:${color};"></div>
                <div class="cmap-call-diamond" style="background:${color};"></div>
                <div class="cmap-call-label" style="border-color:${color};">${call.call_number || call.id}</div>
            </div>`,
        iconSize: [0, 0],
        iconAnchor: [0, 0],
    });
}

function unitPopup(u) {
    return `
        <div class="cmap-pop">
            <div class="cmap-pop-name" style="color:${jobColor(u.job)};">${esc(u.name || 'Unit')}</div>
            <div class="cmap-pop-meta">${esc((u.department || u.job || '').toUpperCase())} · Badge ${u.badge || '—'}</div>
            ${u.status ? `<div class="cmap-pop-meta">Status ${u.status}</div>` : ''}
            <div class="cmap-pop-actions">
                <button onclick="mapFollow('${u.citizenid}')">Follow</button>
                <button onclick="mapRouteTo(${(u.coords||{}).x||0},${(u.coords||{}).y||0})">Route</button>
            </div>
        </div>`;
}

function callPopup(c) {
    return `
        <div class="cmap-pop">
            <div class="cmap-pop-name">${c.call_number || ('#' + c.id)}</div>
            <div class="cmap-pop-meta">${c.call_type || c.type || 'Call'}</div>
            <div class="cmap-pop-meta">📍 ${esc(c.location || 'Unknown')}</div>
            <div class="cmap-pop-actions">
                <button onclick="switchTab('cad')">Open in CAD</button>
                ${c.coords ? `<button onclick="mapRouteTo(${c.coords.x||0},${c.coords.y||0})">Route</button>` : ''}
            </div>
        </div>`;
}

// ── Panel ─────────────────────────────────────────────────────────────────
function initMapPanel() {
    const panel = document.getElementById('tab-map');
    // No inline display/height: .tab-panel already sets those, and an inline
    // display would outrank the class and leave the map over every other tab.
    panel.innerHTML = `
        <div class="panel-header" style="flex-shrink:0;">
            <div class="panel-header-left">
                <div class="panel-title">Live Map</div>
                <div class="panel-subtitle" id="map-unit-count">Loading units…</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" id="map-follow-off" style="display:none;"
                        onclick="mapFollow(null)">✕ Stop following</button>
                <button class="btn btn-ghost btn-sm" onclick="mapResetView()">⤢ Reset</button>
                <button class="btn btn-ghost btn-sm" onclick="refreshMapData()">↻ Refresh</button>
            </div>
        </div>
        <div class="cmap-body">
            <div id="cmap-canvas"></div>
            <div class="cmap-side">
                <div class="cmap-side-head">On-Duty Units</div>
                <div id="map-unit-list" class="cmap-list"></div>
                <div class="cmap-legend">
                    <div class="cmap-side-head">Legend</div>
                    ${LEGEND.map(l => `
                        <div class="cmap-legend-row">
                            <span class="cmap-swatch" style="background:${l.color};box-shadow:0 0 5px ${l.color};"></span>
                            <span>${esc(l.label)}</span>
                        </div>`).join('')}
                    <div class="cmap-legend-row">
                        <span class="cmap-swatch cmap-swatch-diamond" style="background:#f59e0b;"></span>
                        <span>Active CAD call</span>
                    </div>
                    <div class="cmap-hint">Click the map to set a waypoint</div>
                </div>
            </div>
        </div>`;

    // Leaflet needs the container laid out before it measures, and the tab was
    // display:none until a moment ago — so build on the next frame.
    requestAnimationFrame(() => buildLeaflet());
}

function buildLeaflet() {
    const el = document.getElementById('cmap-canvas');
    if (!el || typeof L === 'undefined') return;

    if (_map) { _map.remove(); _map = null; }
    _unitMarkers = {}; _callMarkers = {};

    _map = L.map(el, {
        crs: L.CRS.Simple,
        minZoom: 1,
        maxZoom: MAP.maxZoom,
        zoomControl: true,
        attributionControl: false,
        zoomSnap: 0.25,
        wheelPxPerZoomLevel: 90,
        preferCanvas: false,
    });

    const sw = _map.unproject([0, MAP.imageH], MAP.nativeZoom);
    const ne = _map.unproject([MAP.imageW, 0], MAP.nativeZoom);
    const bounds = new L.LatLngBounds(sw, ne);

    // Flat filenames rather than {z}/{x}/{y} directories: fxmanifest expands a
    // single-level glob reliably, nested ** does not.
    const tiles = L.tileLayer('assets/maps/tiles/{z}_{x}_{y}.webp', {
        tileSize: MAP.tileSize,
        minZoom: 0,
        maxZoom: MAP.maxZoom,
        maxNativeZoom: MAP.nativeZoom,   // upscale past this instead of 404ing
        noWrap: true,
        bounds,
    }).addTo(_map);

    // A blank map with no explanation is the worst failure mode: the markers
    // still draw, so it looks like the map "just doesn't work". Say what is
    // actually missing, once, with the URL that failed.
    let tileErrors = 0;
    tiles.on('tileerror', (e) => {
        tileErrors++;
        const url = (e.tile && e.tile.src) || '(unknown)';
        if (tileErrors === 1) {
            console.error('[XS-MDT] map tile failed to load:', url);
            console.error('[XS-MDT] Check that fxmanifest ships ' +
                          'html/assets/maps/tiles/*.webp and that the tiles exist. ' +
                          'Rebuild with: node tools/build-map-tiles.js');
            showToast('Map tiles missing',
                      'The map image failed to load — see F8 console.', 'error', 9000);
        }
    });

    _map.setMaxBounds(bounds.pad(0.15));
    _map.fitBounds(bounds);

    _callLayer = L.layerGroup().addTo(_map);
    _unitLayer = L.layerGroup().addTo(_map);

    // Click anywhere to drop a GPS waypoint in-game.
    _map.on('click', (e) => {
        const w = latLngToWorld(e.latlng);
        nuiPost('setWaypoint', { x: w.x, y: w.y });
        showToast('Waypoint set', `${Math.round(w.x)}, ${Math.round(w.y)}`, 'success', 2500);
    });

    // Panning by hand cancels follow — otherwise the map fights you.
    _map.on('dragstart', () => { if (_followCid) mapFollow(null); });

    refreshMapData();
    if (_mapInterval) clearInterval(_mapInterval);
    _mapInterval = setInterval(refreshMapData, 5000);
}

function mapResetView() {
    if (!_map) return;
    _followCid = null;
    updateFollowButton();
    const sw = _map.unproject([0, MAP.imageH], MAP.nativeZoom);
    const ne = _map.unproject([MAP.imageW, 0], MAP.nativeZoom);
    _map.fitBounds(new L.LatLngBounds(sw, ne));
}

function updateFollowButton() {
    const b = document.getElementById('map-follow-off');
    if (b) b.style.display = _followCid ? '' : 'none';
}

function mapFollow(citizenid) {
    _followCid = citizenid || null;
    updateFollowButton();
    if (!_followCid) return;
    const u = _mapUnits.find(x => x.citizenid === _followCid);
    if (u && u.coords) _map.setView(worldToLatLng(u.coords.x, u.coords.y), Math.max(_map.getZoom(), 3));
}

function mapRouteTo(x, y) {
    nuiPost('setWaypoint', { x, y });
    showToast('Waypoint set', `${Math.round(x)}, ${Math.round(y)}`, 'success', 2500);
}

// ── Data ──────────────────────────────────────────────────────────────────
async function refreshMapData() {
    if (!_map) return;
    const [units, calls] = await Promise.all([
        nuiFetch('getUnits', {}),
        (MDT.panels || []).includes('cad') ? nuiFetch('getActiveCalls', {}) : Promise.resolve([]),
    ]);
    _mapUnits = Array.isArray(units) ? units : [];
    _mapCalls = Array.isArray(calls) ? calls : [];

    syncUnitMarkers();
    syncCallMarkers();
    renderUnitList();

    const sub = document.getElementById('map-unit-count');
    if (sub) {
        sub.textContent = `${_mapUnits.length} unit${_mapUnits.length !== 1 ? 's' : ''} online · ` +
                          `${_mapCalls.length} active call${_mapCalls.length !== 1 ? 's' : ''}`;
    }

    if (_followCid) {
        const u = _mapUnits.find(x => x.citizenid === _followCid);
        if (u && u.coords) _map.panTo(worldToLatLng(u.coords.x, u.coords.y), { animate: true, duration: 0.6 });
    }
}

// Move existing markers rather than rebuilding the layer, so popups stay open
// and the icons don't flicker every refresh.
function syncUnitMarkers() {
    const seen = {};
    for (const u of _mapUnits) {
        if (!u.coords) continue;
        seen[u.citizenid] = true;
        const ll = worldToLatLng(u.coords.x, u.coords.y);
        const existing = _unitMarkers[u.citizenid];
        if (existing) {
            existing.setLatLng(ll);
            existing.setIcon(unitIcon(u));
            existing.setPopupContent(unitPopup(u));
        } else {
            const m = L.marker(ll, { icon: unitIcon(u), riseOnHover: true })
                .bindPopup(unitPopup(u), { className: 'cmap-popup', closeButton: false })
                .addTo(_unitLayer);
            _unitMarkers[u.citizenid] = m;
        }
    }
    for (const cid of Object.keys(_unitMarkers)) {
        if (!seen[cid]) { _unitLayer.removeLayer(_unitMarkers[cid]); delete _unitMarkers[cid]; }
    }
}

function syncCallMarkers() {
    const seen = {};
    for (const c of _mapCalls) {
        const co = c.coords;
        if (!co || (!co.x && !co.y)) continue;
        seen[c.id] = true;
        const ll = worldToLatLng(co.x, co.y);
        const existing = _callMarkers[c.id];
        if (existing) {
            existing.setLatLng(ll);
            existing.setPopupContent(callPopup(c));
        } else {
            _callMarkers[c.id] = L.marker(ll, { icon: callIcon(c) })
                .bindPopup(callPopup(c), { className: 'cmap-popup', closeButton: false })
                .addTo(_callLayer);
        }
    }
    for (const id of Object.keys(_callMarkers)) {
        if (!seen[id]) { _callLayer.removeLayer(_callMarkers[id]); delete _callMarkers[id]; }
    }
}

function renderUnitList() {
    const list = document.getElementById('map-unit-list');
    if (!list) return;
    if (!_mapUnits.length) {
        list.innerHTML = '<div class="cmap-empty">No units on duty</div>';
        return;
    }
    list.innerHTML = _mapUnits.map(u => {
        const color = jobColor(u.job);
        return `
            <div class="cmap-unit-row ${_followCid === u.citizenid ? 'cmap-following' : ''}"
                 onclick="mapFocusUnit('${u.citizenid}')">
                <span class="cmap-swatch" style="background:${color};box-shadow:0 0 5px ${color};"></span>
                <div class="cmap-unit-row-main">
                    <div class="cmap-unit-row-name">${esc(u.name || 'Unit')}</div>
                    <div class="cmap-unit-row-sub">#${u.badge || '—'}${u.status ? ' · ' + u.status : ''}</div>
                </div>
                <span class="cmap-unit-row-dept" style="color:${color};">
                    ${esc((u.department || u.job || '').toUpperCase())}
                </span>
            </div>`;
    }).join('');
}

function mapFocusUnit(citizenid) {
    const u = _mapUnits.find(x => x.citizenid === citizenid);
    if (!u || !u.coords || !_map) return;
    _map.setView(worldToLatLng(u.coords.x, u.coords.y), Math.max(_map.getZoom(), 3));
    const m = _unitMarkers[citizenid];
    if (m) m.openPopup();
}

// ── Tab entry / exit ──────────────────────────────────────────────────────
function loadMap() { initMapPanel(); }

function stopMap() {
    if (_mapInterval) { clearInterval(_mapInterval); _mapInterval = null; }
    // Leaflet keeps resize/animation handlers alive; drop the instance so a
    // reopened tab starts clean rather than measuring a detached container.
    if (_map) { _map.remove(); _map = null; }
    _unitMarkers = {}; _callMarkers = {};
}

// ── Styles ────────────────────────────────────────────────────────────────
(function injectMapStyles() {
    if (document.getElementById('cmap-styles')) return;
    const s = document.createElement('style');
    s.id = 'cmap-styles';
    s.textContent = `
.cmap-body { flex:1; display:grid; grid-template-columns:1fr 260px; gap:12px; min-height:0; padding:0 18px 18px; }
#cmap-canvas { border-radius:var(--radius); overflow:hidden; border:1px solid var(--border); background:#0a0d14; }
.leaflet-container { background:#0a0d14; font-family:var(--font-sans); outline:none; }
.leaflet-control-zoom a { background:var(--bg-panel); color:var(--text-primary); border-color:var(--border); }
.leaflet-control-zoom a:hover { background:var(--bg-hover); }

.cmap-side { display:flex; flex-direction:column; gap:10px; overflow:hidden; min-height:0; }
.cmap-side-head { font-size:10px; font-weight:800; letter-spacing:.1em; color:var(--text-muted);
                  text-transform:uppercase; flex-shrink:0; }
.cmap-list { flex:1; overflow-y:auto; display:flex; flex-direction:column; gap:4px; min-height:0; }
.cmap-empty { font-size:12px; color:var(--text-muted); font-style:italic; padding:10px 0; }

.cmap-unit-row { display:flex; align-items:center; gap:9px; padding:8px 10px; cursor:pointer;
                 border-radius:var(--radius); background:var(--bg-input); border:1px solid transparent; }
.cmap-unit-row:hover { background:var(--bg-hover); }
.cmap-unit-row.cmap-following { border-color:var(--accent); }
.cmap-unit-row-main { flex:1; min-width:0; }
.cmap-unit-row-name { font-size:12.5px; font-weight:600; color:var(--text-primary);
                      white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.cmap-unit-row-sub { font-size:10.5px; color:var(--text-muted); font-family:var(--font-mono); }
.cmap-unit-row-dept { font-size:9.5px; font-weight:800; letter-spacing:.06em; flex-shrink:0; }

.cmap-swatch { width:9px; height:9px; border-radius:50%; flex-shrink:0; display:inline-block; }
.cmap-swatch-diamond { border-radius:2px; transform:rotate(45deg); }
.cmap-legend { border-top:1px solid var(--border); padding-top:10px; flex-shrink:0;
               display:flex; flex-direction:column; gap:5px; }
.cmap-legend-row { display:flex; align-items:center; gap:8px; font-size:12px; color:var(--text-muted); }
.cmap-hint { font-size:10.5px; color:var(--text-muted); font-style:italic; margin-top:4px; }

/* Unit marker: heading arrow + dot + name tag */
.cmap-unit-wrap, .cmap-call-wrap { position:relative; width:0; height:0; }
.cmap-unit-dot { position:absolute; left:-5px; top:-5px; width:10px; height:10px; border-radius:50%;
                 border:1.5px solid rgba(255,255,255,.85); }
.cmap-unit-arrow { position:absolute; left:-6px; top:-16px; width:0; height:0;
                   border-left:6px solid transparent; border-right:6px solid transparent;
                   border-bottom:9px solid currentColor; transform-origin:50% 16px; opacity:.95; }
.cmap-unit-label { position:absolute; left:9px; top:-9px; white-space:nowrap; font-size:10px;
                   font-weight:700; padding:1px 6px; border-radius:3px; color:#fff;
                   background:rgba(10,13,20,.82); border:1px solid; pointer-events:none; }

/* CAD call marker */
.cmap-call-diamond { position:absolute; left:-5px; top:-5px; width:10px; height:10px;
                     transform:rotate(45deg); border:1.5px solid rgba(255,255,255,.9); }
.cmap-call-pulse { position:absolute; left:-9px; top:-9px; width:18px; height:18px; border-radius:50%;
                   opacity:.35; animation:cmapPulse 1.8s ease-out infinite; }
@keyframes cmapPulse { 0% { transform:scale(.5); opacity:.5; } 100% { transform:scale(1.6); opacity:0; } }
.cmap-call-label { position:absolute; left:10px; top:-9px; white-space:nowrap; font-size:10px;
                   font-weight:700; padding:1px 6px; border-radius:3px; color:#fff;
                   background:rgba(10,13,20,.82); border:1px solid; pointer-events:none;
                   font-family:var(--font-mono); }

/* Popups */
.cmap-popup .leaflet-popup-content-wrapper { background:var(--bg-panel); color:var(--text-primary);
    border:1px solid var(--border-light); border-radius:var(--radius); box-shadow:0 12px 40px rgba(0,0,0,.6); }
.cmap-popup .leaflet-popup-content { margin:10px 12px; }
.cmap-popup .leaflet-popup-tip { background:var(--bg-panel); border:1px solid var(--border-light); }
.cmap-pop-name { font-size:13px; font-weight:800; }
.cmap-pop-meta { font-size:11px; color:var(--text-muted); margin-top:2px; }
.cmap-pop-actions { display:flex; gap:6px; margin-top:8px; }
.cmap-pop-actions button { flex:1; font-size:11px; font-weight:600; padding:4px 8px; cursor:pointer;
    background:var(--bg-input); color:var(--text-primary);
    border:1px solid var(--border); border-radius:4px; }
.cmap-pop-actions button:hover { background:var(--bg-hover); border-color:var(--accent); }

@media (max-width:1200px) { .cmap-body { grid-template-columns:1fr 210px; } }
`;
    document.head.appendChild(s);
}());
