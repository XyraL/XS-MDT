// XSMDT — Fire panels: Incident Reports, Hazmat, Apparatus.

const FIRE_TYPES = [
    'Structure Fire', 'Vehicle Fire', 'Brush / Wildland', 'Rubbish Fire',
    'Alarm Activation', 'Gas Leak', 'Electrical Hazard', 'Water Rescue',
    'Vehicle Extrication', 'Technical Rescue', 'Medical Assist', 'Public Assist',
];

const FIRE_CAUSES = [
    'undetermined', 'accidental', 'electrical', 'cooking', 'smoking',
    'arson', 'natural', 'equipment failure',
];

const STRUCTURE_TYPES = [
    'Residential', 'Commercial', 'Industrial', 'High-rise',
    'Vehicle', 'Outbuilding', 'None / Outdoor',
];

const ALARM_TAG = { 1: 'tag-blue', 2: 'tag-yellow', 3: 'tag-orange', 4: 'tag-red', 5: 'tag-red' };

const money = n => '$' + (Number(n) || 0).toLocaleString();

// ═══════════════════════════════════════════════════════════════════════════
//  FIRE INCIDENT REPORTS
// ═══════════════════════════════════════════════════════════════════════════

let _fireFilter = 'all';

function loadFireIncidents(filter) {
    if (filter) _fireFilter = filter;
    const panel = document.getElementById('tab-fireincidents');
    if (!panel) return;

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Fire Incident Reports</div>
                <div class="panel-subtitle">Type, cause, response and loss for every run</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadFireIncidents()">↻ Refresh</button>
                <button class="btn btn-primary btn-sm" onclick="openNewFireIncident()">+ New Report</button>
            </div>
        </div>
        <div class="panel-toolbar">
            <input type="text" class="input" id="fire-search" placeholder="Search address, type or narrative..." autocomplete="off">
            <div class="panel-actions">
                ${['all', 'mine', 'open'].map(f => `
                    <button class="btn btn-sm ${_fireFilter === f ? 'btn-primary' : 'btn-ghost'}"
                            onclick="loadFireIncidents('${f}')">${f === 'all' ? 'All' : f === 'mine' ? 'Mine' : 'Open'}</button>`).join('')}
            </div>
        </div>
        <div class="panel-body" id="fire-body">
            ${Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    const search = document.getElementById('fire-search');
    let debounce;
    search.addEventListener('input', () => {
        clearTimeout(debounce);
        debounce = setTimeout(() => fetchFireIncidents(search.value), 300);
    });

    fetchFireIncidents('');
}

function fetchFireIncidents(search) {
    nuiFetch('getFireIncidents', { filter: _fireFilter, search }).then(rows => {
        const body = document.getElementById('fire-body');
        if (!body) return;
        if (!rows || rows.length === 0) {
            body.innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon">🔥</div>
                    <div class="empty-title">No incident reports</div>
                    <div class="empty-subtitle">File one after your next run</div>
                </div>`;
            return;
        }
        body.innerHTML = rows.map(fireIncidentCard).join('');
    });
}

function fireIncidentCard(r) {
    const casualties = (r.casualties || []).length;
    return `
        <div class="card" style="border-left:3px solid var(--red);margin-bottom:10px;cursor:pointer;"
             onclick="openFireIncident(${r.id})">
            <div class="card-header" style="margin-bottom:8px;">
                <div style="display:flex;align-items:center;gap:8px;flex:1;flex-wrap:wrap;">
                    <span class="tag ${ALARM_TAG[r.alarm_level] || 'tag-blue'}">${r.alarm_level} ALARM</span>
                    <span class="font-bold" style="font-size:14px;">${r.incident_type}</span>
                    ${r.status === 'open' ? '<span class="tag tag-yellow">OPEN</span>' : ''}
                    ${casualties ? `<span class="tag tag-red">${casualties} CASUALT${casualties > 1 ? 'IES' : 'Y'}</span>` : ''}
                    <span class="text-xs text-muted font-mono">${timeAgo(r.created_at)}</span>
                </div>
                <span class="text-xs text-muted font-mono">#${r.id}</span>
            </div>
            <div style="font-size:13.5px;font-weight:600;color:var(--text-primary);margin-bottom:5px;">
                📍 ${esc(r.address)}
            </div>
            <div style="font-size:11px;color:var(--text-muted);display:flex;gap:12px;flex-wrap:wrap;">
                <span>Cause: <strong class="text-secondary">${r.cause}</strong></span>
                ${Number(r.damage_estimate) ? `<span>Loss: <strong class="text-secondary">${money(r.damage_estimate)}</strong></span>` : ''}
                ${(r.units_responded || []).length ? `<span>${r.units_responded.length} unit(s)</span>` : ''}
                <span>By: <strong class="text-secondary">${esc(r.created_by_name)}</strong></span>
            </div>
        </div>`;
}

function fireFormHTML(r = {}) {
    const list = a => (a || []).join(', ');
    return `
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Incident Type</label>
                <select class="input" id="fi-type">
                    ${FIRE_TYPES.map(t => `<option value="${t}" ${r.incident_type === t ? 'selected' : ''}>${t}</option>`).join('')}
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Alarm Level</label>
                <select class="input" id="fi-alarm">
                    ${[1, 2, 3, 4, 5].map(a => `<option value="${a}" ${String(r.alarm_level || 1) === String(a) ? 'selected' : ''}>${a}</option>`).join('')}
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Status</label>
                <select class="input" id="fi-status">
                    <option value="open"   ${r.status === 'open' ? 'selected' : ''}>Open</option>
                    <option value="closed" ${r.status === 'closed' ? 'selected' : ''}>Closed</option>
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Address</label>
            <input type="text" class="input" id="fi-address" value="${esc(r.address || '')}" placeholder="e.g. 12 Grove Street">
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Cause</label>
                <select class="input" id="fi-cause">
                    ${FIRE_CAUSES.map(c => `<option value="${c}" ${r.cause === c ? 'selected' : ''}>${c}</option>`).join('')}
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Structure Type</label>
                <select class="input" id="fi-structure">
                    <option value="">—</option>
                    ${STRUCTURE_TYPES.map(s => `<option value="${s}" ${r.structure_type === s ? 'selected' : ''}>${s}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Damage Estimate ($)</label>
                <input type="number" class="input" id="fi-damage" min="0" value="${r.damage_estimate || 0}">
            </div>
            <div class="form-group">
                <label class="form-label">Acres Burned</label>
                <input type="number" class="input" id="fi-acres" min="0" step="0.1" value="${r.acres_burned || 0}">
            </div>
            <div class="form-group">
                <label class="form-label">Water Used (gal)</label>
                <input type="number" class="input" id="fi-water" min="0" value="${r.water_used || 0}">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Units Responded <span class="form-hint">comma separated</span></label>
            <input type="text" class="input" id="fi-units" value="${list(r.units_responded)}"
                   placeholder="Engine 12, Ladder 3, Battalion 1">
        </div>
        <div class="form-group">
            <label class="form-label">Personnel <span class="form-hint">comma separated</span></label>
            <input type="text" class="input" id="fi-personnel" value="${list(r.personnel)}">
        </div>
        <div class="form-group">
            <label class="form-label">Casualties <span class="form-hint">comma separated — name (condition)</span></label>
            <input type="text" class="input" id="fi-casualties" value="${list(r.casualties)}"
                   placeholder="John Doe (smoke inhalation)">
        </div>
        <div class="form-group">
            <label class="form-label">Narrative</label>
            <textarea class="input" id="fi-narrative" rows="5"
                      placeholder="On arrival, heavy smoke showing from...">${esc(r.narrative || '')}</textarea>
        </div>`;
}

function readFireForm() {
    const val = id => (document.getElementById(id) || {}).value || '';
    const toList = t => (t || '').split(',').map(s => s.trim()).filter(Boolean);
    return {
        incident_type  : val('fi-type'),
        address        : val('fi-address'),
        alarm_level    : parseInt(val('fi-alarm')) || 1,
        cause          : val('fi-cause'),
        structure_type : val('fi-structure') || null,
        narrative      : val('fi-narrative'),
        units_responded: toList(val('fi-units')),
        personnel      : toList(val('fi-personnel')),
        casualties     : toList(val('fi-casualties')),
        damage_estimate: parseInt(val('fi-damage')) || 0,
        acres_burned   : parseFloat(val('fi-acres')) || 0,
        water_used     : parseInt(val('fi-water')) || 0,
        status         : val('fi-status') || 'open',
    };
}

function openNewFireIncident() {
    createModal('New Fire Incident Report', fireFormHTML(), async () => {
        const data = readFireForm();
        if (!data.address.trim()) return showToast('Missing address', 'An address is required.', 'error'), false;

        const id = await nuiFetch('createFireIncident', data);
        if (id) { showToast('Report Filed', `Incident #${id} created`, 'success'); loadFireIncidents(); }
        else showToast('Error', 'Could not file the report.', 'error');
    }, 'File Report', '🔥');
}

async function openFireIncident(id) {
    const r = await nuiFetch('getFireIncident', id);
    if (!r) return showToast('Error', 'Report not found.', 'error');

    createModal(`Incident #${r.id} — ${r.incident_type}`, fireFormHTML(r), async () => {
        const data = readFireForm();
        data.id = r.id;
        const ok = await nuiFetch('updateFireIncident', data);
        if (ok) { showToast('Report Updated', `Incident #${r.id} saved`, 'success'); loadFireIncidents(); }
        else showToast('Error', 'Could not save — you may not be the author.', 'error');
    }, 'Save Changes', '🔥');
}

// ═══════════════════════════════════════════════════════════════════════════
//  HAZMAT
// ═══════════════════════════════════════════════════════════════════════════

let _hazFilter = 'active';

function loadHazmat(filter) {
    if (filter) _hazFilter = filter;
    const panel = document.getElementById('tab-hazmat');
    if (!panel) return;

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Hazmat</div>
                <div class="panel-subtitle">Substance releases, containment and evacuation</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadHazmat()">↻ Refresh</button>
                <button class="btn btn-primary btn-sm" onclick="openNewHazmat()">+ Log Hazmat</button>
            </div>
        </div>
        <div class="panel-toolbar">
            <div class="panel-actions">
                <button class="btn btn-sm ${_hazFilter === 'active' ? 'btn-primary' : 'btn-ghost'}"
                        onclick="loadHazmat('active')">Active</button>
                <button class="btn btn-sm ${_hazFilter === 'all' ? 'btn-primary' : 'btn-ghost'}"
                        onclick="loadHazmat('all')">All</button>
            </div>
        </div>
        <div class="panel-body" id="haz-body">${skeletonLines(3)}</div>`;

    nuiFetch('getHazmat', { filter: _hazFilter }).then(rows => {
        const body = document.getElementById('haz-body');
        if (!body) return;
        updateHazmatBadge((rows || []).filter(h => h.status !== 'closed').length);

        if (!rows || !rows.length) {
            body.innerHTML = `<div class="empty-state"><div class="empty-icon">☣</div>
                <div class="empty-title">No hazmat incidents</div>
                <div class="empty-subtitle">Nothing active right now</div></div>`;
            return;
        }

        const STATUS_TAG = { active: 'tag-red', monitoring: 'tag-orange', closed: 'tag-gray' };
        body.innerHTML = rows.map(h => `
            <div class="card mb-2" style="border-left:3px solid ${h.status === 'closed' ? 'var(--text-muted)' : 'var(--orange)'};">
                <div class="card-header" style="margin-bottom:8px;">
                    <div style="display:flex;gap:8px;align-items:center;flex:1;flex-wrap:wrap;">
                        <span class="tag ${STATUS_TAG[h.status] || 'tag-gray'}">${h.status.toUpperCase()}</span>
                        <span class="font-bold" style="font-size:14px;">☣ ${h.substance}</span>
                        ${h.un_number ? `<span class="tag tag-gray font-mono">UN${h.un_number}</span>` : ''}
                        ${h.hazard_class ? `<span class="tag tag-orange">Class ${h.hazard_class}</span>` : ''}
                    </div>
                    ${h.status !== 'closed'
                        ? `<button class="btn btn-success btn-xs" onclick="closeHazmat(${h.id})">Mark Contained</button>`
                        : ''}
                </div>
                <div style="font-size:13px;color:var(--text-primary);margin-bottom:5px;">📍 ${esc(h.location)}</div>
                <div style="font-size:11px;color:var(--text-muted);display:flex;gap:12px;flex-wrap:wrap;">
                    ${h.quantity ? `<span>Qty: <strong class="text-secondary">${h.quantity}</strong></span>` : ''}
                    <span>Containment: <strong class="text-secondary">${h.containment}</strong></span>
                    ${Number(h.evacuation_radius) ? `<span>Evac: <strong class="text-secondary">${h.evacuation_radius}m</strong></span>` : ''}
                    ${Number(h.injuries) ? `<span class="tag tag-red">${h.injuries} injured</span>` : ''}
                    <span>${esc(h.created_by_name)}</span>
                </div>
                ${h.narrative ? `<div style="font-size:12px;color:var(--text-secondary);margin-top:6px;">${esc(h.narrative)}</div>` : ''}
            </div>`).join('');
    });
}

function openNewHazmat() {
    createModal('Log Hazmat Incident', `
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Substance</label>
                <input type="text" class="input" id="hz-substance" placeholder="Diesel fuel">
            </div>
            <div class="form-group">
                <label class="form-label">UN Number</label>
                <input type="text" class="input" id="hz-un" placeholder="1202">
            </div>
            <div class="form-group">
                <label class="form-label">Hazard Class</label>
                <input type="text" class="input" id="hz-class" placeholder="3">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Location</label>
            <input type="text" class="input" id="hz-location" placeholder="Interstate near Sandy Shores">
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Quantity</label>
                <input type="text" class="input" id="hz-qty" placeholder="~200 gallons">
            </div>
            <div class="form-group">
                <label class="form-label">Containment</label>
                <select class="input" id="hz-containment">
                    <option value="ongoing">Ongoing</option>
                    <option value="contained">Contained</option>
                    <option value="uncontrolled">Uncontrolled</option>
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Evac Radius (m)</label>
                <input type="number" class="input" id="hz-evac" min="0" value="0">
            </div>
            <div class="form-group">
                <label class="form-label">Injuries</label>
                <input type="number" class="input" id="hz-injuries" min="0" value="0">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Narrative</label>
            <textarea class="input" id="hz-narrative" rows="4"></textarea>
        </div>`, async () => {
        const val = id => (document.getElementById(id) || {}).value || '';
        if (!val('hz-substance').trim()) return showToast('Missing substance', 'Name the substance.', 'error'), false;
        if (!val('hz-location').trim())  return showToast('Missing location', 'A location is required.', 'error'), false;

        const id = await nuiFetch('createHazmat', {
            substance: val('hz-substance'), un_number: val('hz-un') || null,
            hazard_class: val('hz-class') || null, location: val('hz-location'),
            quantity: val('hz-qty') || null, containment: val('hz-containment'),
            evacuation_radius: parseInt(val('hz-evac')) || 0,
            injuries: parseInt(val('hz-injuries')) || 0,
            narrative: val('hz-narrative'), status: 'active',
        });
        if (id) { showToast('Hazmat Logged', '', 'success'); loadHazmat(); }
        else showToast('Error', 'Could not log the incident.', 'error');
    }, 'Log Incident', '☣');
}

async function closeHazmat(id) {
    const ok = await nuiFetch('updateHazmatStatus', { id, status: 'closed', containment: 'contained' });
    if (ok) { showToast('Hazmat Contained', '', 'success'); loadHazmat(); }
    else showToast('Error', 'Could not update.', 'error');
}

// ═══════════════════════════════════════════════════════════════════════════
//  APPARATUS
// ═══════════════════════════════════════════════════════════════════════════

const APPARATUS_TYPES = ['engine', 'ladder', 'rescue', 'tanker', 'brush', 'battalion', 'ambulance', 'utility'];
const APP_STATUS = {
    in_service    : { label: 'In Service',     tag: 'tag-green' },
    out_of_service: { label: 'Out of Service', tag: 'tag-red' },
    maintenance   : { label: 'Maintenance',    tag: 'tag-orange' },
    reserve       : { label: 'Reserve',        tag: 'tag-gray' },
};

function loadApparatus() {
    const panel = document.getElementById('tab-apparatus');
    if (!panel) return;

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Apparatus</div>
                <div class="panel-subtitle">Fleet status and inspection log</div>
            </div>
            <div class="panel-actions" id="app-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadApparatus()">↻ Refresh</button>
            </div>
        </div>
        <div class="panel-body" id="app-body">${skeletonLines(3)}</div>`;

    nuiFetch('getApparatus').then(d => {
        const body = document.getElementById('app-body');
        if (!body || !d) return;

        if (d.isSupervisor) {
            const actions = document.getElementById('app-actions');
            const btn = document.createElement('button');
            btn.className = 'btn btn-primary btn-sm';
            btn.textContent = '+ Add Unit';
            btn.onclick = () => openApparatusForm();
            actions.appendChild(btn);
        }

        if (!d.apparatus.length) {
            body.innerHTML = `<div class="empty-state"><div class="empty-icon">🚒</div>
                <div class="empty-title">No apparatus on the roster</div>
                <div class="empty-subtitle">${d.isSupervisor ? 'Add your first unit' : 'A supervisor needs to add units'}</div></div>`;
            return;
        }

        body.innerHTML = d.apparatus.map(a => {
            const st = APP_STATUS[a.status] || APP_STATUS.in_service;
            const li = a.last_inspection;
            return `
                <div class="card mb-2">
                    <div class="card-header" style="margin-bottom:8px;">
                        <div style="display:flex;gap:8px;align-items:center;flex:1;flex-wrap:wrap;">
                            <span class="font-bold" style="font-size:15px;">🚒 ${a.unit_id}</span>
                            <span class="tag tag-gray">${a.type}</span>
                            <span class="tag ${esc(st.tag)}">${esc(st.label)}</span>
                            ${a.station ? `<span class="text-xs text-muted">${a.station}</span>` : ''}
                        </div>
                        <div style="display:flex;gap:6px;">
                            <button class="btn btn-ghost btn-xs" onclick="openInspection(${a.id}, '${a.unit_id.replace(/'/g, "\\'")}')">Log Check</button>
                            <button class="btn btn-ghost btn-xs" onclick="viewApparatusLog(${a.id}, '${a.unit_id.replace(/'/g, "\\'")}')">History</button>
                            ${d.isSupervisor ? `<button class="btn btn-ghost btn-xs" onclick='openApparatusForm(${JSON.stringify(a).replace(/'/g, "&#39;")})'>Edit</button>` : ''}
                        </div>
                    </div>
                    <div style="font-size:11px;color:var(--text-muted);">
                        ${li
                            ? `Last check: <strong class="text-secondary">${li.check_type}</strong> —
                               <span class="${li.result === 'fail' ? 'text-danger' : ''}">${li.result}</span>
                               · ${li.author_name} · ${fmtDateShort(li.created_at)}`
                            : 'Never inspected'}
                    </div>
                    ${a.notes ? `<div style="font-size:12px;color:var(--text-secondary);margin-top:5px;">${esc(a.notes)}</div>` : ''}
                </div>`;
        }).join('');
    });
}

function openApparatusForm(a) {
    a = a || {};
    createModal(a.id ? `Edit ${a.unit_id}` : 'Add Apparatus', `
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Unit ID</label>
                <input type="text" class="input" id="ap-unit" value="${a.unit_id || ''}" placeholder="Engine 12">
            </div>
            <div class="form-group">
                <label class="form-label">Type</label>
                <select class="input" id="ap-type">
                    ${APPARATUS_TYPES.map(t => `<option value="${t}" ${a.type === t ? 'selected' : ''}>${t}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Station</label>
                <input type="text" class="input" id="ap-station" value="${a.station || ''}" placeholder="Station 1">
            </div>
            <div class="form-group">
                <label class="form-label">Status</label>
                <select class="input" id="ap-status">
                    ${Object.entries(APP_STATUS).map(([k, v]) =>
                        `<option value="${k}" ${a.status === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Notes</label>
            <textarea class="input" id="ap-notes" rows="3">${esc(a.notes || '')}</textarea>
        </div>
        ${a.id ? `<button class="btn btn-danger btn-sm" onclick="deleteApparatus(${a.id})">Delete Unit</button>` : ''}`,
    async () => {
        const val = id => (document.getElementById(id) || {}).value || '';
        if (!val('ap-unit').trim()) return showToast('Missing unit ID', 'Name the unit.', 'error'), false;

        const ok = await nuiFetch('saveApparatus', {
            id: a.id || null, unit_id: val('ap-unit'), type: val('ap-type'),
            station: val('ap-station'), status: val('ap-status'), notes: val('ap-notes'),
        });
        if (ok) { showToast('Apparatus Saved', '', 'success'); loadApparatus(); }
        else showToast('Error', 'Supervisor access required.', 'error');
    }, 'Save', '🚒');
}

async function deleteApparatus(id) {
    const ok = await nuiFetch('deleteApparatus', id);
    if (ok) {
        showToast('Unit Removed', '', 'success');
        document.querySelector('.modal-backdrop')?.remove();
        loadApparatus();
    } else showToast('Error', 'Supervisor access required.', 'error');
}

function openInspection(apparatusId, unitLabel) {
    createModal(`Inspection — ${unitLabel}`, `
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Check Type</label>
                <select class="input" id="ai-type">
                    <option value="daily">Daily</option>
                    <option value="weekly">Weekly</option>
                    <option value="monthly">Monthly</option>
                    <option value="post_incident">Post-Incident</option>
                    <option value="annual">Annual</option>
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Result</label>
                <select class="input" id="ai-result">
                    <option value="pass">Pass</option>
                    <option value="advisory">Pass w/ Advisory</option>
                    <option value="fail">Fail</option>
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Mileage</label>
                <input type="number" class="input" id="ai-mileage" min="0" value="0">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Notes</label>
            <textarea class="input" id="ai-notes" rows="3" placeholder="Defects found, items restocked..."></textarea>
        </div>
        <div class="form-hint">A <strong>Fail</strong> result puts the unit out of service automatically.</div>`,
    async () => {
        const val = id => (document.getElementById(id) || {}).value || '';
        const ok = await nuiFetch('logInspection', {
            apparatus_id: apparatusId, check_type: val('ai-type'),
            result: val('ai-result'), mileage: parseInt(val('ai-mileage')) || 0,
            notes: val('ai-notes'),
        });
        if (ok) { showToast('Inspection Logged', '', 'success'); loadApparatus(); }
        else showToast('Error', 'Could not log the inspection.', 'error');
    }, 'Log Check', '🚒');
}

async function viewApparatusLog(apparatusId, unitLabel) {
    const rows = await nuiFetch('getApparatusLog', apparatusId);
    const RESULT_TAG = { pass: 'tag-green', advisory: 'tag-yellow', fail: 'tag-red' };

    const m = createModal(`Inspection History — ${unitLabel}`,
        (rows && rows.length)
            ? rows.map(l => `
                <div style="padding:9px 0;border-bottom:1px solid var(--border);">
                    <div style="display:flex;gap:8px;align-items:center;">
                        <span class="tag ${RESULT_TAG[l.result] || 'tag-gray'}">${l.result}</span>
                        <span class="font-bold" style="font-size:12.5px;">${l.check_type}</span>
                        <span class="text-xs text-muted font-mono">${l.mileage} mi</span>
                        <span class="text-xs text-muted" style="margin-left:auto;">${fmtDateShort(l.created_at)}</span>
                    </div>
                    <div class="text-xs text-muted" style="margin-top:3px;">${l.author_name}</div>
                    ${l.notes ? `<div style="font-size:12px;color:var(--text-secondary);margin-top:4px;">${esc(l.notes)}</div>` : ''}
                </div>`).join('')
            : '<div class="text-xs text-muted">No inspections logged for this unit.</div>',
        () => closeModal(m), 'Close', '🚒');
}
