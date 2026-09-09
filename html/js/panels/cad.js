const PRIORITY_LABELS = { 1: 'P1 — Emergency', 2: 'P2 — Urgent', 3: 'P3 — Routine' };
const PRIORITY_COLORS = { 1: '#f87171', 2: '#fbbf24', 3: '#34d399' };

let _cadTimerInterval = null;

function elapsedMins(ts) {
    if (!ts) return 0;
    return Math.max(0, Math.floor((Date.now() - new Date(ts)) / 60000));
}
function formatElapsed(mins) {
    if (mins < 60) return mins + 'm';
    return Math.floor(mins / 60) + 'h ' + (mins % 60) + 'm';
}
function elapsedClass(mins) {
    if (mins >= 30) return 'critical';
    if (mins >= 15) return 'urgent';
    return '';
}
function startCADTimer() {
    if (_cadTimerInterval) clearInterval(_cadTimerInterval);
    _cadTimerInterval = setInterval(() => {
        document.querySelectorAll('.elapsed-chip[data-created]').forEach(el => {
            const mins = elapsedMins(el.dataset.created);
            el.textContent = '⏱ ' + formatElapsed(mins);
            el.className = 'elapsed-chip ' + elapsedClass(mins);
        });
    }, 30000);
}

const CALL_TYPES = [
    '10-11 Animal Complaint','10-15 Civil Disturbance','10-16 Domestic Disturbance',
    '10-31 Crime in Progress','10-32 Person with a Gun','10-33 Emergency',
    '10-40 Silent Alarm','10-50 Vehicle Accident','10-53 Road Hazard',
    '10-70 Pursuit in Progress','10-80 Chase in Progress',
    '11-41 Ambulance Needed','11-99 Officer Needs Help',
    'Armed Robbery','Bank Robbery','Burglary','Drug Activity','Gang Activity',
    'Hit and Run','Homicide','Missing Person','Noise Complaint',
    'Public Intoxication','Shots Fired','Stolen Vehicle',
    'Suspicious Person','Suspicious Vehicle','Theft','Trespassing',
];

const STATUS_LABELS = {
    pending:'PENDING', enroute:'EN ROUTE', onscene:'ON SCENE',
    active:'ACTIVE', completed:'COMPLETED', cancelled:'CANCELLED',
};

let _selectedCallId = null;

function loadCAD() {
    const panel = document.getElementById('tab-cad');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">CAD Dispatch</div>
                <div class="panel-subtitle">Live call management</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadCAD()">↻ Refresh</button>
                <button class="btn btn-ghost btn-sm" onclick="showCADHistory()">📋 History</button>
                <button class="btn btn-primary btn-sm" onclick="openNewCallModal()">+ Create Call</button>
            </div>
        </div>
        <div class="cad-layout">
            <div class="cad-list">
                <div class="cad-list-header">
                    <span class="text-xs font-black uppercase text-muted" style="letter-spacing:.1em;">
                        Active Calls <span id="cad-count" style="color:var(--accent-2);"></span>
                    </span>
                    <span class="text-xs text-muted">Select to view</span>
                </div>
                <div class="cad-list-body" id="cad-call-list">
                    ${Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
                </div>
            </div>
            <div class="cad-detail" id="cad-call-detail">
                <div class="empty-state" style="height:100%;">
                    <div class="empty-icon">📻</div>
                    <div class="empty-title">Select a call</div>
                    <div class="empty-subtitle">Click any active call to view details and respond</div>
                </div>
            </div>
        </div>`;

    nuiFetch('getActiveCalls').then(calls => {
        MDT.activeCalls = calls || [];
        updateCADBadge();
        const countEl = document.getElementById('cad-count');
        if (countEl) countEl.textContent = `(${MDT.activeCalls.length})`;
        renderCallList(MDT.activeCalls);
        if (_selectedCallId) {
            const call = MDT.activeCalls.find(c => c.id === _selectedCallId);
            if (call) openCallDetail(call.id);
        }
        startCADTimer();
    });
}

function renderCallList(calls) {
    const el = document.getElementById('cad-call-list');
    if (!el) return;
    if (!calls.length) {
        el.innerHTML = `
            <div class="empty-state">
                <div class="empty-icon">📻</div>
                <div class="empty-title">No active calls</div>
            </div>`;
        return;
    }
    const pri = c => c.priority || 2;
    el.innerHTML = calls.map(c => {
        const mins = elapsedMins(c.created_at);
        return `
        <div class="call-card status-${c.status} ${_selectedCallId===c.id?'selected':''}"
             id="call-card-${c.id}" onclick='openCallDetail(${JSON.stringify(c.id)})'>
            <div class="call-card-top">
                <span class="call-number">${c.call_number}</span>
                <span class="priority-badge priority-${pri(c)}" style="margin-left:6px;">${pri(c) === 1 ? '🔴' : pri(c) === 3 ? '🟢' : '🟡'} P${pri(c)}</span>
                <span class="tag tag-${statusColor(c.status)} ml-auto" style="font-size:9.5px;">${STATUS_LABELS[c.status]||c.status}</span>
            </div>
            <div class="call-type">${c.call_type || c.type}</div>
            <div class="call-location" style="display:flex;align-items:center;gap:8px;">
                <span>📍 ${esc(c.location)}</span>
                <span class="elapsed-chip ${elapsedClass(mins)}" data-created="${c.created_at}">⏱ ${formatElapsed(mins)}</span>
            </div>
            <div class="call-units">
                ${(c.units||[]).map(u=>`<span class="call-unit-chip">${esc(u.name.split(' ')[0])}</span>`).join('')}
                ${(!c.units||c.units.length===0)?'<span class="text-xs text-muted">No units</span>':''}
            </div>
        </div>`;
    }).join('');
}

function openCallDetail(callId) {
    _selectedCallId = callId;
    document.querySelectorAll('.call-card').forEach(el => el.classList.remove('selected'));
    const card = document.getElementById(`call-card-${callId}`);
    if (card) card.classList.add('selected');

    const call = MDT.activeCalls.find(c => c.id === callId);
    if (!call) return;

    const detail = document.getElementById('cad-call-detail');
    detail.innerHTML = `
        <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:18px;gap:16px;flex-wrap:wrap;">
            <div>
                <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px;">
                    <div class="font-mono text-muted text-xs">${call.call_number}</div>
                    <span class="priority-badge priority-${call.priority||2}">${call.priority===1?'🔴':call.priority===3?'🟢':'🟡'} ${PRIORITY_LABELS[call.priority||2]}</span>
                </div>
                <div style="font-size:22px;font-weight:800;margin-bottom:4px;">${call.call_type || call.type}</div>
                <div style="font-size:13px;color:var(--text-secondary);">📍 ${esc(call.location)}</div>
                <div style="font-size:11px;color:var(--text-muted);margin-top:4px;display:flex;align-items:center;gap:10px;">
                    <span>Created by ${esc(call.created_by_name||'CAD')} · ${timeAgo(call.created_at)}</span>
                    <span class="elapsed-chip ${elapsedClass(elapsedMins(call.created_at))}" data-created="${call.created_at}">⏱ ${formatElapsed(elapsedMins(call.created_at))}</span>
                </div>
            </div>
            <div style="display:flex;flex-direction:column;gap:8px;align-items:flex-end;">
                <span class="tag tag-${statusColor(call.status)}" style="font-size:12px;padding:5px 12px;">
                    ${STATUS_LABELS[call.status]||call.status}
                </span>
                <div style="display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end;">
                    ${call.coords ? `<button class="btn btn-ghost btn-sm" onclick="routeToCall(${JSON.stringify(call.coords).replace(/"/g,"'")}, '${esc(call.location)}')">🗺 GPS Route</button>` : ''}
                    <button class="btn btn-success btn-sm" onclick='respondToCall(${JSON.stringify(callId)})'>✓ Respond</button>
                    <button class="btn btn-ghost btn-sm" onclick='openUpdateStatusModal(${JSON.stringify(callId)},${JSON.stringify(call.status)})'>Update Status</button>
                </div>
            </div>
        </div>

        <div class="card mb-3">
            <div class="card-header" style="margin-bottom:6px;">
                <div class="card-title">Description</div>
            </div>
            <div style="font-size:13.5px;line-height:1.7;color:var(--text-secondary);">${esc(call.description)}</div>
        </div>

        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:12px;">
            <div class="card">
                <div class="card-header" style="margin-bottom:8px;">
                    <div class="card-title">Assigned Units (${(call.units||[]).length})</div>
                </div>
                ${!(call.units||[]).length
                    ? '<div class="text-muted text-sm">No units assigned — click Respond to join</div>'
                    : call.units.map(u => `
                        <div style="padding:6px 0;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;">
                            <div>
                                <div class="font-bold text-sm">${esc(u.name)}</div>
                                <div class="text-xs text-muted font-mono">Responded at ${u.respondedAt}</div>
                            </div>
                            <span class="tag tag-green">ACTIVE</span>
                        </div>`).join('')}
            </div>

            <div class="card">
                <div class="card-header" style="margin-bottom:6px;">
                    <div style="display:flex;align-items:center;justify-content:space-between;width:100%;">
                        <div class="card-title">Unit Notes (${(call.notes||[]).length})</div>
                        <button class="btn btn-ghost btn-xs" onclick='openAddNoteModal(${JSON.stringify(callId)})'>+ Add Note</button>
                    </div>
                </div>
                <div id="call-notes-${callId}" style="max-height:200px;overflow-y:auto;">
                    ${!(call.notes||[]).length
                        ? '<div class="text-muted text-sm">No notes yet</div>'
                        : call.notes.map(n => `
                            <div style="padding:6px 0;border-bottom:1px solid var(--border);">
                                <div class="text-xs text-muted font-mono">[${n.time}] ${esc(n.author)}</div>
                                <div style="font-size:12.5px;margin-top:2px;">${esc(n.text)}</div>
                            </div>`).join('')}
                </div>
            </div>
        </div>

        <div style="display:flex;gap:8px;padding-top:4px;border-top:1px solid var(--border);">
            <button class="btn btn-warning btn-sm" onclick='openUpdateStatusModal(${JSON.stringify(callId)},${JSON.stringify(call.status)})'>Change Status</button>
            <button class="btn btn-ghost btn-sm" onclick='openAddNoteModal(${JSON.stringify(callId)})'>Add Note</button>
            ${call.status !== 'completed' && call.status !== 'cancelled'
                ? `<button class="btn btn-success btn-sm ml-auto" onclick='quickClose(${JSON.stringify(callId)},"completed")'>✓ Complete Call</button>
                   <button class="btn btn-danger btn-sm" onclick='quickClose(${JSON.stringify(callId)},"cancelled")'>✕ Cancel Call</button>`
                : ''}
        </div>`;
}

async function respondToCall(callId) {
    const btn = event.target;
    btn.textContent = 'Responding...'; btn.disabled = true;
    const result = await nuiFetch('respondToCall', callId);
    if (result) {
        showToast('Responding to Call', 'You are now assigned to this call.', 'success');
        nuiFetch('getActiveCalls').then(calls => {
            MDT.activeCalls = calls || [];
            renderCallList(MDT.activeCalls);
            openCallDetail(callId);
        });
    } else {
        showToast('Error', 'Could not respond.', 'error');
        btn.textContent = '✓ Respond'; btn.disabled = false;
    }
}

async function quickClose(callId, status) {
    const result = await nuiFetch('updateCallStatus', { callId, status });
    if (result) {
        showToast('Call ' + (status === 'completed' ? 'Completed' : 'Cancelled'), '', status === 'completed' ? 'success' : 'warning');
        _selectedCallId = null;
        nuiFetch('getActiveCalls').then(calls => { MDT.activeCalls = calls || []; loadCAD(); });
    }
}

function openUpdateStatusModal(callId, currentStatus) {
    const modal = createModal('Update Call Status', `
        <div class="form-group">
            <label class="form-label">New Status</label>
            <select class="select" id="call-status-select">
                ${Object.entries(STATUS_LABELS).map(([v,l]) =>
                    `<option value="${v}" ${v===currentStatus?'selected':''}>${l}</option>`).join('')}
            </select>
        </div>`,
        async () => {
            const status = document.getElementById('call-status-select').value;
            const result = await nuiFetch('updateCallStatus', { callId, status });
            if (result) {
                showToast('Status Updated', STATUS_LABELS[status], 'success');
                closeModal(modal);
                nuiFetch('getActiveCalls').then(calls => {
                    MDT.activeCalls = calls || [];
                    renderCallList(MDT.activeCalls);
                    if (status !== 'completed' && status !== 'cancelled') openCallDetail(callId);
                    else { _selectedCallId = null; document.getElementById('cad-call-detail').innerHTML = '<div class="empty-state"><div class="empty-icon">📻</div><div class="empty-title">Select a call</div></div>'; }
                });
            }
        }, 'Update Status', '📻');
}

function openAddNoteModal(callId) {
    const modal = createModal('Add Unit Note', `
        <div class="form-group">
            <label class="form-label">Note</label>
            <textarea class="textarea" id="note-text" style="min-height:140px;" placeholder="Enter your note for this call — updates are visible to all units..."></textarea>
        </div>`,
        async () => {
            const text = document.getElementById('note-text').value.trim();
            if (!text) return;
            const result = await nuiFetch('addCallNote', { callId, text });
            if (result) { showToast('Note Added', '', 'success'); closeModal(modal); openCallDetail(callId); }
            else showToast('Error', 'Could not add note.', 'error');
        }, 'Add Note', '📝');
}

function openNewCallModal() {
    const modal = createModal('Create CAD Call', `
        <div class="form-row">
            <div class="form-group" style="flex:1.5;">
                <label class="form-label">Call Type</label>
                <select class="select" id="call-type">
                    ${CALL_TYPES.map(t => `<option value="${t}">${t}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Priority</label>
                <select class="select" id="call-priority">
                    <option value="1">🔴 Priority 1 — Emergency</option>
                    <option value="2" selected>🟡 Priority 2 — Urgent</option>
                    <option value="3">🟢 Priority 3 — Routine</option>
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Location</label>
            <input class="input" id="call-location" placeholder="Street address, intersection, or landmark">
        </div>
        <div class="form-group">
            <label class="form-label">Description / Caller Information</label>
            <textarea class="textarea" id="call-desc" style="min-height:160px;"
                placeholder="Caller details, description of situation, number of suspects, weapons involved, etc."></textarea>
        </div>`,
        async () => {
            const type        = document.getElementById('call-type').value;
            const location    = document.getElementById('call-location').value.trim();
            const description = document.getElementById('call-desc').value.trim();
            if (!location)     { showToast('Missing', 'Location is required.', 'error'); return; }
            if (!description)  { showToast('Missing', 'Description is required.', 'error'); return; }
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Creating...'; btn.disabled = true;
            const priority = parseInt(document.getElementById('call-priority').value) || 2;
            const result = await nuiFetch('createCall', { type, location, description, priority });
            if (result) {
                showToast('Call Created', result.call_number + ' dispatched', 'success');
                closeModal(modal);
                loadCAD();
            } else {
                showToast('Error', 'Could not create call.', 'error');
                btn.textContent = 'Create Call'; btn.disabled = false;
            }
        }, 'Create Call', '📻');
}

async function showCADHistory() {
    const detail = document.getElementById('cad-call-detail');
    detail.innerHTML = `<div>${Array(4).fill(0).map(() => `<div class="card mb-2">${skeletonLines(2)}</div>`).join('')}</div>`;
    const calls = await nuiFetch('getCallHistory');
    if (!calls || !calls.length) {
        detail.innerHTML = `<div class="empty-state"><div class="empty-icon">📋</div><div class="empty-title">No call history</div></div>`;
        return;
    }
    detail.innerHTML = `
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px;">
            <div style="font-size:15px;font-weight:700;">Call History</div>
            <button class="btn btn-ghost btn-sm" onclick="openCallDetail(${_selectedCallId||0})">← Back to Call</button>
        </div>
        <div class="data-table-wrap">
            <table class="data-table">
                <thead><tr><th>Call #</th><th>Type</th><th>Location</th><th>Status</th><th>Units</th><th>Date</th></tr></thead>
                <tbody>
                    ${calls.map(c => `
                        <tr style="cursor:default;">
                            <td class="font-mono text-accent">${c.call_number}</td>
                            <td class="font-bold">${c.call_type || c.type}</td>
                            <td class="text-secondary">${esc(c.location)}</td>
                            <td><span class="tag tag-${c.status==='completed'?'green':'red'}">${STATUS_LABELS[c.status]||c.status}</span></td>
                            <td>${(c.units||[]).length} units</td>
                            <td class="font-mono text-sm text-muted">${fmtDateShort(c.created_at)}</td>
                        </tr>`).join('')}
                </tbody>
            </table>
        </div>`;
}

function routeToCall(coords, location) {
    fetch(`https://${MDT_RESOURCE}/routeToCall`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ coords, location }),
    });
    showToast('GPS Set', 'Routing to ' + location, 'success');
}

window.startCADTimer = startCADTimer;
window.loadCAD = loadCAD;
window.openCallDetail = openCallDetail;
window.respondToCall = respondToCall;
window.quickClose = quickClose;
window.openUpdateStatusModal = openUpdateStatusModal;
window.openAddNoteModal = openAddNoteModal;
window.openNewCallModal = openNewCallModal;
window.showCADHistory = showCADHistory;
window.routeToCall = routeToCall;
