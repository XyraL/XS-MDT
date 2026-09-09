// The NUI host must equal the resource folder name exactly, and that name is
// case-sensitive on Linux servers. Ask the game for it rather than hardcoding.
const MDT_RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'XS-MDT';

// ── State ─────────────────────────────────────────────────────────────────
const MDT = {
    officer      : null,
    activeTab    : 'dashboard',
    panels       : [],
    penalCodes   : [],
    activeCalls  : [],
    activeBolos  : [],
    searchHistory: [],   // [{ type:'plate'|'name', query, ts }]
};

// ── UI Sounds (Web Audio API — no files needed) ───────────────────────────
let _audioCtx = null;
function _getAC() {
    if (!_audioCtx) _audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    return _audioCtx;
}

const SOUND_PRESETS = {
    open:    { notes:[560,720],           dur:0.07, gap:0.04, vol:0.07, wave:'sine' },
    close:   { notes:[480,320],           dur:0.09, gap:0.04, vol:0.06, wave:'sine' },
    success: { notes:[660,880,1100],      dur:0.07, gap:0.035,vol:0.07, wave:'sine' },
    error:   { notes:[380,260],           dur:0.12, gap:0.05, vol:0.09, wave:'sawtooth' },
    notify:  { notes:[820],              dur:0.1,  gap:0,    vol:0.07, wave:'sine' },
    alert:   { notes:[880,660,880],       dur:0.09, gap:0.05, vol:0.10, wave:'sine' },
    panic:   { notes:[1000,750,1000,750,1000], dur:0.09, gap:0.04, vol:0.18, wave:'square' },
    newcall: { notes:[620,840],           dur:0.09, gap:0.05, vol:0.08, wave:'sine' },
    warrant: { notes:[740,920],           dur:0.08, gap:0.04, vol:0.09, wave:'sine' },
};

function playUISound(type) {
    try {
        const ac = _getAC();
        const p  = SOUND_PRESETS[type] || SOUND_PRESETS.notify;
        let t = ac.currentTime + 0.01;
        p.notes.forEach(freq => {
            const osc  = ac.createOscillator();
            const gain = ac.createGain();
            osc.type = p.wave || 'sine';
            osc.frequency.setValueAtTime(freq, t);
            gain.gain.setValueAtTime(p.vol, t);
            gain.gain.exponentialRampToValueAtTime(0.0001, t + p.dur);
            osc.connect(gain);
            gain.connect(ac.destination);
            osc.start(t);
            osc.stop(t + p.dur + 0.02);
            t += p.dur + p.gap;
        });
    } catch(_) {}
}

const UNIT_STATUSES = [
    { code: '10-8',  label: 'Available',        color: '#22c55e' },
    { code: '10-6',  label: 'Busy / On Scene',  color: '#f59e0b' },
    { code: '10-7',  label: 'Out of Service',   color: '#6b7280' },
    { code: 'CODE3', label: 'Code 3 — Enroute', color: '#ef4444' },
    { code: 'CODE4', label: 'Code 4 — Clear',   color: '#6366f1' },
    { code: 'BKUP',  label: 'Need Backup',      color: '#f87171' },
];

function addSearchHistory(type, query) {
    MDT.searchHistory = MDT.searchHistory.filter(h => !(h.type === type && h.query === query));
    MDT.searchHistory.unshift({ type, query, ts: Date.now() });
    if (MDT.searchHistory.length > 12) MDT.searchHistory.length = 12;
}

function getStatusConfig(code) {
    return UNIT_STATUSES.find(s => s.code === code) || UNIT_STATUSES[0];
}

// ── NUI Bridge ────────────────────────────────────────────────────────────
function nuiFetch(endpoint, payload = {}) {
    return fetch(`https://${MDT_RESOURCE}/request`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ endpoint, payload }),
    }).then(r => r.json()).catch(() => null);
}

// nuiFetch() relays to a SERVER callback. nuiPost() hits a client-side
// RegisterNUICallback directly, for things the game handles locally.
function nuiPost(name, payload = {}) {
    return fetch(`https://${MDT_RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
    }).then(r => r.json()).catch(() => null);
}

function closeMDT() {
    if (typeof stopMap === 'function') stopMap();
    fetch(`https://${MDT_RESOURCE}/close`, { method: 'POST' });
    document.getElementById('mdt-overlay').classList.add('hidden');
}

// ── Toast ─────────────────────────────────────────────────────────────────
const TOAST_ICONS = { info: 'ℹ', success: '✓', error: '✕', warning: '⚠' };

function showToast(title, body = '', type = 'info', duration = 5000) {
    const soundMap = { success:'success', error:'error', warning:'alert', info:'notify' };
    playUISound(soundMap[type] || 'notify');
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `
        <div class="toast-icon">${TOAST_ICONS[type] || 'ℹ'}</div>
        <div class="toast-content">
            <div class="toast-title">${title}</div>
            ${body ? `<div class="toast-body">${body}</div>` : ''}
        </div>`;
    document.getElementById('toast-container').appendChild(el);
    setTimeout(() => {
        el.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
        el.style.opacity = '0';
        el.style.transform = 'translateX(20px)';
        setTimeout(() => el.remove(), 300);
    }, duration);
}

// ── Panel Registry ────────────────────────────────────────────────────────
// Every panel the MDT knows how to render. Which of these a given player
// actually gets is decided server-side by Config.Departments[dept].panels —
// this table only says how to label and group them.
const PANELS = {
    dashboard  : { label: 'Dashboard',   icon: '▦', section: 'Overview' },
    roster     : { label: 'Roster',      icon: '◉', section: 'Overview' },
    map        : { label: 'Live Map',    icon: '🗺', section: 'Overview' },

    civilians  : { label: 'Civilians',   icon: '◎', section: 'Lookups' },
    vehicles   : { label: 'Vehicles',    icon: '◈', section: 'Lookups' },

    warrants   : { label: 'Warrants',    icon: '⚖', section: 'Records', badge: 'red' },
    bolos      : { label: 'BOLOs',       icon: '◉', section: 'Records', badge: 'yellow' },
    arrests    : { label: 'Arrests',     icon: '⬡', section: 'Records' },
    citations  : { label: 'Citations',   icon: '◧', section: 'Records' },
    incidents  : { label: 'Incidents',   icon: '◫', section: 'Records' },
    penal      : { label: 'Penal Codes', icon: '≡', section: 'Records' },

    pcr        : { label: 'Patient Care',    icon: '✚', section: 'Medical' },
    medhistory : { label: 'Medical Records', icon: '❤', section: 'Medical' },
    narclog    : { label: 'Narcotics Log',   icon: '💊', section: 'Medical' },

    fireincidents: { label: 'Fire Incidents', icon: '🔥', section: 'Fire Ops' },
    hazmat       : { label: 'Hazmat',         icon: '☣', section: 'Fire Ops', badge: 'yellow' },
    apparatus    : { label: 'Apparatus',      icon: '🚒', section: 'Fire Ops' },

    cad        : { label: 'CAD',          icon: '◈', section: 'Dispatch', badge: 'blue' },
    callhistory: { label: 'Call History', icon: '◷', section: 'Dispatch' },
    bulletins  : { label: 'Bulletins',    icon: '📌', section: 'Dispatch' },

    mugshots   : { label: 'Mugshots',  icon: '📷', section: 'Personnel' },
    shiftlog   : { label: 'Shift Log', icon: '⏱', section: 'Personnel' },
};

// Order sections appear in the sidebar. Anything unlisted lands at the end.
const SECTION_ORDER = ['Overview', 'Lookups', 'Records', 'Medical', 'Fire Ops', 'Dispatch', 'Personnel'];

// Build the sidebar + tab containers from the panel list the server sent.
// A panel the department doesn't have is never rendered here *and* its
// callbacks refuse to answer, so the two can't drift apart.
function buildInterface(panels) {
    const nav  = document.getElementById('mdt-nav');
    const main = document.getElementById('mdt-content');
    nav.innerHTML = '';
    main.innerHTML = '';

    const allowed = (panels || []).filter(p => PANELS[p]);
    MDT.panels = allowed;

    const bySection = {};
    for (const key of allowed) {
        const sec = PANELS[key].section || 'Other';
        (bySection[sec] = bySection[sec] || []).push(key);
    }

    const sections = Object.keys(bySection).sort((a, b) => {
        const ia = SECTION_ORDER.indexOf(a), ib = SECTION_ORDER.indexOf(b);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
    });

    for (const sec of sections) {
        const head = document.createElement('li');
        head.className = 'nav-section';
        head.textContent = sec;
        nav.appendChild(head);

        for (const key of bySection[sec]) {
            const p  = PANELS[key];
            const li = document.createElement('li');
            li.className = 'nav-item';
            li.dataset.tab = key;
            li.innerHTML = `<span class="nav-icon">${p.icon}</span> ${esc(p.label)}` +
                (p.badge ? `<span class="nav-badge ${p.badge}" id="badge-${key}"></span>` : '');
            nav.appendChild(li);
        }
    }

    for (const key of allowed) {
        const div = document.createElement('div');
        div.id = `tab-${key}`;
        div.className = 'tab-panel';
        main.appendChild(div);
    }
}

// Paint the department's accent colour over the theme.
function applyDepartmentTheme(officer) {
    const root = document.documentElement;
    if (officer.departmentColor) {
        root.style.setProperty('--accent', officer.departmentColor);
        root.style.setProperty('--accent-2', officer.departmentColor);
        root.style.setProperty('--accent-glow', officer.departmentColor + '26'); // ~15% alpha
    }
    const logo = document.querySelector('.logo-hex');
    if (logo && officer.departmentIcon) logo.textContent = officer.departmentIcon;
    const ver = document.querySelector('.logo-version');
    if (ver) ver.textContent = `${officer.departmentShort || '--'} · LIVE`;
}

// ── Tab Router ────────────────────────────────────────────────────────────
function switchTab(tab) {
    // Never open a panel this department doesn't have — the server would
    // refuse the data anyway, and an empty panel just looks broken.
    if (MDT.panels && MDT.panels.length && !MDT.panels.includes(tab)) return;

    document.querySelectorAll('.nav-item[data-tab]').forEach(el =>
        el.classList.toggle('active', el.dataset.tab === tab));
    document.querySelectorAll('.tab-panel').forEach(el =>
        el.classList.toggle('active', el.id === `tab-${tab}`));
    if (MDT.activeTab === 'map' && tab !== 'map' && typeof stopMap === 'function') stopMap();
    MDT.activeTab = tab;
    onTabActivated(tab);
}

let _mapScriptLoading = null;

function ensureMapLoaded() {
    if (typeof window.initMapPanel === 'function') {
        window.initMapPanel();
        return;
    }

    const panel = document.getElementById('tab-map');
    if (panel) panel.innerHTML = '<div class="empty-state"><div class="empty-title">Loading Live Map...</div><div class="empty-subtitle">Initializing unit telemetry</div></div>';

    if (!_mapScriptLoading) {
        _mapScriptLoading = new Promise((resolve, reject) => {
            const existing = document.querySelector('script[data-xs-map]');
            if (existing) { existing.addEventListener('load', resolve, { once:true }); existing.addEventListener('error', reject, { once:true }); return; }
            const script = document.createElement('script');
            script.src = 'js/panels/map.js';
            script.dataset.xsMap = 'true';
            script.onload = resolve;
            script.onerror = reject;
            document.body.appendChild(script);
        });
    }

    _mapScriptLoading.then(() => {
        if (typeof window.initMapPanel === 'function') window.initMapPanel();
        else throw new Error('Map panel loaded without initMapPanel');
    }).catch(error => {
        console.error('[XS-MDT] Failed to load Live Map:', error);
        if (panel) panel.innerHTML = '<div class="empty-state"><div class="empty-title">Live Map unavailable</div><div class="empty-subtitle">Verify html/js/panels/map.js was uploaded with the resource.</div></div>';
        _mapScriptLoading = null;
    });
}

function onTabActivated(tab) {
    switch (tab) {
        case 'dashboard': renderDashboard(); break;
        case 'roster':    loadRoster(); break;
        case 'civilians': initCivilianPanel(); break;
        case 'vehicles':  initVehiclePanel(); break;
        case 'warrants':  loadWarrants(); break;
        case 'bolos':     loadBolos(); break;
        case 'arrests':   initArrestsPanel(); break;
        case 'citations': initCitationsPanel(); break;
        case 'penal':     loadPenalCodes(); break;
        case 'incidents':  loadIncidents(); break;
        case 'bulletins':   loadBulletins(); break;
        case 'cad':         loadCAD(); break;
        case 'mugshots':    loadMugshots(); break;
        case 'callhistory': loadCallHistory(); break;
        case 'shiftlog':    loadShiftLog(); break;
        case 'map':         ensureMapLoaded(); break;
        case 'pcr':         loadPCRs(); break;
        case 'medhistory':  loadMedicalRecords(); break;
        case 'narclog':     loadNarcLog(); break;
        case 'fireincidents': loadFireIncidents(); break;
        case 'hazmat':      loadHazmat(); break;
        case 'apparatus':   loadApparatus(); break;
    }
}

// ── Open / Close ──────────────────────────────────────────────────────────
function openMDT(officer) {
    MDT.officer = officer;
    buildInterface(officer.panels);
    applyDepartmentTheme(officer);
    updateOfficerCard(officer);
    document.getElementById('mdt-overlay').classList.remove('hidden');
    switchTab(MDT.panels.includes('dashboard') ? 'dashboard' : (MDT.panels[0] || 'dashboard'));

    // Only prefetch what this department is allowed to see.
    const has = p => MDT.panels.includes(p);
    if (has('penal'))     nuiFetch('getPenalCodes').then(d => { if (d) MDT.penalCodes = d; });
    if (has('cad'))       nuiFetch('getActiveCalls').then(d => { if (d) { MDT.activeCalls = d; updateCADBadge(); } });
    if (has('bolos'))     nuiFetch('getBolos').then(d => { if (d) { MDT.activeBolos = d; updateBoloBadge(); } });
    if (has('warrants'))  nuiFetch('getWarrants', { filter: 'active' }).then(d => { if (d) updateWarrantBadge(d.length); });
    if (has('hazmat'))    nuiFetch('getHazmat', { filter: 'active' }).then(d => { if (d) updateHazmatBadge(d.length); });
}

function updateOfficerCard(officer) {
    document.getElementById('officer-name').textContent = officer.name || 'Unknown Officer';
    document.getElementById('officer-sub').textContent =
        `${officer.departmentShort || '--'} · Badge #${officer.badge || '---'} · ${officer.callsign || 'No Callsign'}`;
    const dot = document.getElementById('officer-dot');
    if (dot) {
        dot.className = 'status-dot ' + (officer.onduty ? 'on' : 'off');
        const cfg = getStatusConfig(officer.status || '10-8');
        dot.style.background = officer.onduty ? cfg.color : '';
    }
}

function updateCADBadge() {
    const pending = MDT.activeCalls.filter(c => c.status === 'pending').length;
    const badge = document.getElementById('badge-cad');
    if (!badge) return;
    badge.textContent = MDT.activeCalls.length;
    badge.classList.toggle('show', MDT.activeCalls.length > 0);
}

function updateHazmatBadge(count) {
    const badge = document.getElementById('badge-hazmat');
    if (!badge) return;
    badge.textContent = count;
    badge.classList.toggle('show', count > 0);
}

function updateBoloBadge() {
    const badge = document.getElementById('badge-bolos');
    if (!badge) return;
    badge.textContent = MDT.activeBolos.length;
    badge.classList.toggle('show', MDT.activeBolos.length > 0);
}

function updateWarrantBadge(count) {
    const badge = document.getElementById('badge-warrants');
    if (!badge) return;
    badge.textContent = count;
    badge.classList.toggle('show', count > 0);
}

// ── Live Clock ────────────────────────────────────────────────────────────
function startClock() {
    const DAYS = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    function tick() {
        const now = new Date();
        const h = String(now.getHours()).padStart(2,'0');
        const m = String(now.getMinutes()).padStart(2,'0');
        const s = String(now.getSeconds()).padStart(2,'0');
        const timeEl = document.getElementById('clock-time');
        const dateEl = document.getElementById('clock-date');
        if (timeEl) timeEl.textContent = `${h}:${m}:${s}`;
        if (dateEl) dateEl.textContent = `${DAYS[now.getDay()]}, ${MONTHS[now.getMonth()]} ${now.getDate()}`;
    }
    tick();
    setInterval(tick, 1000);
}

// ── Keyboard Shortcuts ────────────────────────────────────────────────────
const TAB_KEYS = {
    '1': 'dashboard', '2': 'roster', '3': 'civilians', '4': 'vehicles',
    '5': 'warrants',  '6': 'bolos',  '7': 'arrests',   '8': 'citations',
    '9': 'incidents', '0': 'cad',
};

document.addEventListener('keydown', (e) => {
    if (document.getElementById('mdt-overlay').classList.contains('hidden')) return;
    if (e.key === 'Escape') { closeMDT(); return; }
    if ((e.ctrlKey || e.metaKey) && TAB_KEYS[e.key]) {
        e.preventDefault();
        switchTab(TAB_KEYS[e.key]);
    }
});

// ── Quick Search ──────────────────────────────────────────────────────────
const searchInput = document.getElementById('sidebar-search-input');
if (searchInput) {
    let searchTimer = null;
    searchInput.addEventListener('input', (e) => {
        clearTimeout(searchTimer);
        const q = e.target.value.trim();
        if (!q) return;
        searchTimer = setTimeout(() => {
            // Route to civilian search if query looks like a name
            if (q.length >= 2) {
                switchTab('civilians');
                setTimeout(() => {
                    const civInput = document.getElementById('civ-search');
                    if (civInput) {
                        civInput.value = q;
                        civInput.dispatchEvent(new Event('input'));
                        searchInput.value = '';
                    }
                }, 80);
            }
        }, 400);
    });
}

// ── Message Handler ───────────────────────────────────────────────────────
window.addEventListener('message', (e) => {
    const data = e.data;
    switch (data.action) {
        case 'open':
            openMDT(data.officer);
            break;
        case 'close':
            if (typeof stopMap === 'function') stopMap();
            document.getElementById('mdt-overlay').classList.add('hidden');
            break;
        case 'warrantAlert':
            showToast('WARRANT ISSUED', `${data.data.subject} — ${data.data.charges.length} charge(s)`, 'error', 9000);
            if (MDT.activeTab === 'warrants') loadWarrants();
            break;
        case 'boloAlert':
            showToast('BOLO ISSUED', data.data.description, 'warning', 10000);
            MDT.activeBolos.unshift(data.data);
            updateBoloBadge();
            if (MDT.activeTab === 'bolos') loadBolos();
            break;
        case 'boloCleared':
            MDT.activeBolos = MDT.activeBolos.filter(b => b.id !== data.id);
            updateBoloBadge();
            if (MDT.activeTab === 'bolos') loadBolos();
            break;
        case 'newCall':
            showToast('NEW CALL — ' + data.call.call_number, data.call.type + ' @ ' + data.call.location, 'info', 10000);
            playUISound('newcall');
            MDT.activeCalls.unshift(data.call);
            updateCADBadge();
            if (MDT.activeTab === 'cad') loadCAD();
            break;
        case 'callUpdated':
            MDT.activeCalls = MDT.activeCalls.map(c => c.id === data.data.id ? { ...c, ...data.data } : c);
            if (MDT.activeTab === 'cad') loadCAD();
            break;
        case 'callClosed':
            MDT.activeCalls = MDT.activeCalls.filter(c => c.id !== data.id);
            updateCADBadge();
            if (MDT.activeTab === 'cad') loadCAD();
            break;
        case 'callNoteAdded':
            if (MDT.activeTab === 'cad') loadCAD();
            break;
        case 'panicAlert': {
            const p = data.data;
            showPanicAlert(p);
            playUISound('panic');
            if (MDT.activeTab === 'cad') loadCAD();
            break;
        }
        case 'expiringWarrant':
            showToast('WARRANT EXPIRING SOON', (data.data.subject || '') + ' — expires in ' + (data.data.hoursLeft || '?') + 'h', 'warning', 12000);
            break;
        case 'playSound':
            playUISound(data.sound);
            break;
        case 'warrantAlert':
            playUISound('warrant');
            break;
        case 'openForTarget':
            openMDT(data.officer);
            setTimeout(() => {
                if (data.mode === 'citation') openNewCitationModal(data.data);
                else { switchTab('civilians'); setTimeout(() => openCivilianProfile(data.data.citizenid), 80); }
            }, 350);
            break;
        case 'targetResult':
            if (data.mode === 'citation') openNewCitationModal(data.data);
            else { switchTab('civilians'); setTimeout(() => openCivilianProfile(data.data.citizenid), 80); }
            break;
    }
});

// ── Nav Binding ───────────────────────────────────────────────────────────
// Delegated: the nav list is rebuilt every time the MDT opens, so binding
// individual items at load time would attach to elements that no longer exist.
document.getElementById('mdt-nav').addEventListener('click', (e) => {
    const item = e.target.closest('.nav-item[data-tab]');
    if (item) switchTab(item.dataset.tab);
});

// ── Modal Factory ─────────────────────────────────────────────────────────
function createModal(title, bodyHTML, onConfirm, confirmLabel = 'Save', iconEmoji = '◈') {
    const backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop';
    backdrop.innerHTML = `
        <div class="modal">
            <div class="modal-header">
                <div class="modal-header-icon" style="background:var(--accent-glow);color:var(--accent-2);">${iconEmoji}</div>
                <div class="modal-title">${title}</div>
                <button class="modal-close" title="Close">✕</button>
            </div>
            <div class="modal-body">${bodyHTML}</div>
            <div class="modal-footer">
                <button class="btn btn-ghost" id="modal-cancel">Cancel</button>
                <button class="btn btn-primary" id="modal-confirm">${confirmLabel}</button>
            </div>
        </div>`;
    document.body.appendChild(backdrop);
    backdrop.querySelector('.modal-close').onclick = () => closeModal(backdrop);
    backdrop.querySelector('#modal-cancel').onclick  = () => closeModal(backdrop);
    backdrop.querySelector('#modal-confirm').onclick = () => onConfirm && onConfirm();
    // Close on backdrop click
    backdrop.addEventListener('click', (e) => { if (e.target === backdrop) closeModal(backdrop); });
    return backdrop;
}

function closeModal(modal) { modal && modal.remove(); }

// ── Skeleton Helpers ──────────────────────────────────────────────────────
function skeletonLines(count = 3) {
    const widths = ['w-full','w-3/4','w-1/2','w-full','w-3/4'];
    return Array.from({ length: count }, (_, i) =>
        `<div class="skeleton skeleton-line ${widths[i % widths.length]}"></div>`).join('');
}

function skeletonCard(rows = 3) {
    return `<div class="card">${skeletonLines(rows)}</div>`;
}

// ── Helpers ───────────────────────────────────────────────────────────────

// Escapes text before it goes into innerHTML.
//
// Almost everything this panel renders was typed by a player: arrest
// narratives, officer notes, bulletin bodies, civilian names. It is then read
// by a DIFFERENT player, which is what makes this matter — an unescaped `<` in
// an arrest report is not a formatting bug, it is script execution inside
// another officer's game client. CEF runs it exactly like a browser would.
//
// Use on every value that originated from a person. Numbers, ids, dates and
// enum values from our own code do not need it, and wrapping them only adds
// noise.
function esc(value) {
    if (value === null || value === undefined) return '';
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function fmtDate(ts) {
    if (!ts) return '—';
    const d = new Date(ts);
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
        + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
}

function fmtDateShort(ts) {
    if (!ts) return '—';
    return new Date(ts).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function chargeTypeTag(type) {
    const map = { felony: 'tag-red', misdemeanor: 'tag-yellow', infraction: 'tag-blue' };
    return `<span class="tag ${map[type] || 'tag-blue'}">${type}</span>`;
}

function dollarFmt(n) {
    return '$' + Number(n || 0).toLocaleString();
}

function statusColor(status) {
    return { pending:'yellow', enroute:'blue', onscene:'green', active:'orange', completed:'gray', cancelled:'red' }[status] || 'blue';
}

function timeAgo(ts) {
    if (!ts) return '—';
    const diff = Math.floor((Date.now() - new Date(ts)) / 1000);
    if (diff < 60) return 'just now';
    if (diff < 3600) return Math.floor(diff/60) + 'm ago';
    if (diff < 86400) return Math.floor(diff/3600) + 'h ago';
    return Math.floor(diff/86400) + 'd ago';
}

// ── Panic Alert ───────────────────────────────────────────────────────────
function showPanicAlert(data) {
    const el = document.createElement('div');
    el.style.cssText = `
        position:fixed;top:0;left:0;right:0;z-index:99999;
        background:linear-gradient(135deg,#7f1d1d,#991b1b);
        border-bottom:3px solid #ef4444;
        padding:18px 28px;display:flex;align-items:center;gap:20px;
        animation:panicSlideIn .3s ease;box-shadow:0 8px 40px rgba(239,68,68,.5);`;
    el.innerHTML = `
        <div style="font-size:28px;animation:panicPulse 1s infinite;">🚨</div>
        <div style="flex:1;">
            <div style="font-size:14px;font-weight:900;letter-spacing:.08em;color:#fca5a5;
                        text-transform:uppercase;">Officer Needs Assistance</div>
            <div style="font-size:16px;font-weight:700;color:#fff;margin:3px 0;">
                ${data.officerName} · Badge #${data.badge}</div>
            <div style="font-size:13px;color:#fca5a5;">📍 ${esc(data.location)}</div>
        </div>
        <div style="display:flex;flex-direction:column;gap:6px;align-items:flex-end;">
            <span style="font-size:11px;font-weight:800;letter-spacing:.1em;color:#fca5a5;">${data.callNumber}</span>
            <button onclick="this.closest('div[style]').remove()"
                    style="background:rgba(255,255,255,.15);border:1px solid rgba(255,255,255,.3);
                           color:#fff;border-radius:6px;padding:5px 14px;cursor:pointer;font-size:12px;">
                Acknowledge
            </button>
        </div>`;
    document.body.appendChild(el);

    if (!document.getElementById('panic-anim-style')) {
        const s = document.createElement('style');
        s.id = 'panic-anim-style';
        s.textContent = `
            @keyframes panicSlideIn { from{transform:translateY(-100%)} to{transform:translateY(0)} }
            @keyframes panicPulse   { 0%,100%{transform:scale(1)} 50%{transform:scale(1.25)} }`;
        document.head.appendChild(s);
    }

    // Auto-remove after 30 seconds if not acknowledged
    setTimeout(() => el.remove(), 30000);
}

// ── Status Picker ─────────────────────────────────────────────────────────
async function setMyStatus(code) {
    const ok = await nuiFetch('setUnitStatus', code);
    if (ok) {
        const cfg = getStatusConfig(code);
        showToast('Status Updated', cfg.label, 'success', 3000);
        if (MDT.officer) MDT.officer.status = code;
        const dot = document.getElementById('officer-dot');
        if (dot) dot.style.background = cfg.color;
        // Re-render the status picker button in-place so the label updates immediately
        const wrap = document.getElementById('status-picker-wrap');
        if (wrap) {
            const tmp = document.createElement('div');
            tmp.innerHTML = renderStatusPicker(code);
            wrap.replaceWith(tmp.firstElementChild);
        }
    }
}

function renderStatusPicker(currentCode) {
    const current = getStatusConfig(currentCode || '10-8');
    return `
        <div style="position:relative;display:inline-block;" id="status-picker-wrap">
            <button onclick="toggleStatusPicker()" style="
                background:${current.color}22;border:1px solid ${current.color};
                color:${current.color};border-radius:8px;padding:6px 14px;
                font-size:12px;font-weight:700;cursor:pointer;letter-spacing:.04em;
                display:flex;align-items:center;gap:8px;">
                <span style="width:8px;height:8px;border-radius:50%;background:${current.color};display:inline-block;"></span>
                ${current.code} — ${esc(current.label)}
                <span style="opacity:.6;font-size:10px;">▾</span>
            </button>
            <div id="status-dropdown" style="
                display:none;position:absolute;top:calc(100%+6px);left:0;
                background:var(--bg-panel);border:1px solid var(--border-light);
                border-radius:var(--radius);z-index:9999;min-width:200px;
                box-shadow:0 12px 40px rgba(0,0,0,.6);overflow:hidden;">
                ${UNIT_STATUSES.map(s => `
                    <div onclick="setMyStatus('${s.code}');document.getElementById('status-dropdown').style.display='none';"
                         style="padding:10px 14px;cursor:pointer;display:flex;align-items:center;gap:10px;
                                border-bottom:1px solid var(--border);transition:background .1s;"
                         onmouseenter="this.style.background='var(--bg-hover)'"
                         onmouseleave="this.style.background=''">
                        <span style="width:9px;height:9px;border-radius:50%;background:${s.color};flex-shrink:0;"></span>
                        <div>
                            <div style="font-size:12px;font-weight:700;color:${s.color};">${s.code}</div>
                            <div style="font-size:11px;color:var(--text-muted);">${esc(s.label)}</div>
                        </div>
                    </div>`).join('')}
            </div>
        </div>`;
}

function toggleStatusPicker() {
    const dd = document.getElementById('status-dropdown');
    if (dd) dd.style.display = dd.style.display === 'none' ? 'block' : 'none';
    document.addEventListener('click', function closeIt(e) {
        if (!document.getElementById('status-picker-wrap')?.contains(e.target)) {
            if (dd) dd.style.display = 'none';
            document.removeEventListener('click', closeIt);
        }
    }, { capture: true });
}

// ── Search History ────────────────────────────────────────────────────────
function renderSearchHistory(containerEl) {
    if (!MDT.searchHistory.length) {
        containerEl.innerHTML = '<div class="text-muted text-sm" style="padding:8px 4px;">No recent searches</div>';
        return;
    }
    containerEl.innerHTML = MDT.searchHistory.map(h => `
        <div onclick="${h.type === 'plate' ? `switchTab('vehicles');setTimeout(()=>{document.getElementById('plate-search').value='${h.query}';lookupPlate();},80)` : `switchTab('civilians');setTimeout(()=>{document.getElementById('civ-search').value='${h.query}';document.getElementById('civ-search').dispatchEvent(new Event('input'));},80)`}"
             style="display:flex;align-items:center;gap:10px;padding:7px 8px;cursor:pointer;
                    border-radius:6px;transition:background .1s;"
             onmouseenter="this.style.background='var(--bg-hover)'"
             onmouseleave="this.style.background=''">
            <span style="font-size:13px;opacity:.6;">${h.type === 'plate' ? '🚗' : '👤'}</span>
            <span style="font-size:13px;font-family:var(--font-mono);color:var(--text-secondary);">${esc(h.query)}</span>
            <span style="margin-left:auto;font-size:10px;color:var(--text-muted);">${timeAgo(h.ts)}</span>
        </div>`).join('');
}

// ── Clipboard Helper ──────────────────────────────────────────────────────
function copyToClipboard(text, label = 'Copied') {
    const fallback = () => {
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select(); document.execCommand('copy');
        document.body.removeChild(ta);
    };
    if (navigator.clipboard) {
        navigator.clipboard.writeText(text).catch(fallback);
    } else { fallback(); }
}

function copyBtn(text, label = '⎘') {
    // A row missing the field would otherwise throw and take down the whole
    // list render, so render nothing rather than blowing up the panel.
    if (text === undefined || text === null || text === '') return '';
    return `<button class="btn-copy" title="Copy" onclick="event.stopPropagation();_doCopy(this,'${String(text).replace(/'/g,"\\'")}');">${label}</button>`;
}
function _doCopy(btn, text) {
    copyToClipboard(text);
    btn.classList.add('copied');
    btn.textContent = '✓';
    setTimeout(() => { btn.classList.remove('copied'); btn.textContent = '⎘'; }, 1500);
}

// ── Init ──────────────────────────────────────────────────────────────────
startClock();

// Expose everything globally
Object.assign(window, {
    MDT, nuiFetch, closeMDT, showToast, switchTab,
    fmtDate, fmtDateShort, chargeTypeTag, dollarFmt,
    statusColor, timeAgo, createModal, closeModal,
    skeletonLines, skeletonCard, updateOfficerCard,
    updateCADBadge, updateBoloBadge, updateWarrantBadge,
    UNIT_STATUSES, getStatusConfig, addSearchHistory,
    renderStatusPicker, toggleStatusPicker, setMyStatus,
    renderSearchHistory, showPanicAlert, playUISound,
    copyToClipboard, copyBtn, _doCopy,
});
