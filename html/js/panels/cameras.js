// ── Cameras and footage ───────────────────────────────────────────────────
//
// Two lists: which cameras exist and where, and what footage has been pulled.
// The MDT does not play video — it points you at the camera and records that
// somebody looked, which is the part that matters in a case file.

const CAM_STATUS = {
    online:      { label: 'Online',      tag: 'tag-green' },
    offline:     { label: 'Offline',     tag: 'tag-red' },
    maintenance: { label: 'Maintenance', tag: 'tag-yellow' },
};

const CAM_KINDS = {
    fixed:   'Street',
    traffic: 'Traffic',
    atm:     'ATM',
    transit: 'Transit',
    private: 'Private',
};

const FOOTAGE_SOURCE = {
    camera:  { label: 'Camera',  icon: 'video' },
    dashcam: { label: 'Dashcam', icon: 'car' },
    bodycam: { label: 'Bodycam', icon: 'badge' },
};

const FOOTAGE_STATUS = {
    requested: { label: 'Requested', tag: 'tag-yellow' },
    available: { label: 'Available', tag: 'tag-green' },
    archived:  { label: 'Archived',  tag: 'tag-blue' },
    purged:    { label: 'Purged',    tag: 'tag-gray' },
};

let _camView = 'cameras';
let _camFilter = { status: 'all', search: '' };
let _ftFilter = { source: 'all', search: '' };
let _cams = null;
let _clips = null;

function loadCameras() {
    const panel = document.getElementById('tab-cameras');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Cameras</div>
                <div class="panel-subtitle">Where the cameras are, and what has been pulled</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="cam-view">
                    <button class="seg-btn ${_camView === 'cameras' ? 'active' : ''}" data-view="cameras">Cameras</button>
                    <button class="seg-btn ${_camView === 'footage' ? 'active' : ''}" data-view="footage">Footage</button>
                    <button class="seg-btn ${_camView === 'live' ? 'active' : ''}" data-view="live">Body Cams</button>
                </div>
                <div class="search-bar" style="width:220px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="cam-search" placeholder="Code, name or area...">
                </div>
                <button class="btn btn-primary btn-sm" id="cam-add">Add</button>
            </div>
        </div>
        <div class="panel-body" id="cam-body">${skeletonLines(5)}</div>`;

    document.getElementById('cam-view').onclick = (e) => {
        const btn = e.target.closest('.seg-btn');
        if (!btn) return;
        _camView = btn.dataset.view;
        btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
        document.getElementById('cam-search').value = '';
        _camFilter.search = ''; _ftFilter.search = '';
        fetchCameraView();
    };

    let timer;
    document.getElementById('cam-search').oninput = (e) => {
        clearTimeout(timer);
        const v = e.target.value.trim();
        if (_camView === 'cameras') _camFilter.search = v; else _ftFilter.search = v;
        timer = setTimeout(fetchCameraView, 250);
    };

    fetchCameraView();
}

function fetchCameraView() {
    const add = document.getElementById('cam-add');
    if (add) {
        add.textContent = _camView === 'cameras' ? 'Add Camera' : 'Log Footage';
        add.style.display = _camView === 'live' ? 'none' : '';
        add.onclick = () => (_camView === 'cameras' ? openCameraEditor() : openFootageEditor());
    }
    // Hide the whole search row, not just the input — the magnifier lives in
    // a sibling span and was left floating on its own.
    const search = document.getElementById('cam-search');
    if (search && search.parentElement) search.parentElement.style.display = _camView === 'live' ? 'none' : '';

    if (_camView === 'live') return fetchLiveCams();
    return _camView === 'cameras' ? fetchCams() : fetchClips();
}

function fetchCams() {
    nuiFetch('getCameras', _camFilter).then(data => {
        _cams = data;
        const body = document.getElementById('cam-body');
        if (!body) return;

        const add = document.getElementById('cam-add');
        if (add) add.style.display = data && data.canManage ? '' : 'none';

        if (!data || !data.cameras || !data.cameras.length) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-video"></i></div>
                <div class="empty-title">No cameras on file</div>
                <div class="empty-subtitle">A camera resource can publish its list through RegisterCameras, or add them here.</div>
            </div>`;
            return;
        }

        const byArea = {};
        for (const c of data.cameras) (byArea[c.area || 'Unassigned'] ||= []).push(c);

        body.innerHTML = Object.entries(byArea).map(([area, list]) => `
            <div class="cam-group">
                <div class="cam-area">${esc(area)}<span class="penal-title-count">${list.length}</span></div>
                <div class="cam-grid">
                    ${list.map(c => {
                        const st = CAM_STATUS[c.status] || CAM_STATUS.online;
                        return `
                        <div class="cam-card cam-${c.status}">
                            <div class="cam-card-head">
                                <span class="mono cam-code">${esc(c.camera_code)}</span>
                                <span class="tag ${st.tag}">${esc(st.label)}</span>
                            </div>
                            <div class="cam-label">${esc(c.label)}</div>
                            <div class="cam-meta">${esc(CAM_KINDS[c.kind] || c.kind || 'Street')}</div>
                            <div class="cam-actions">
                                ${c.coords && c.status !== 'offline'
                                    ? `<button class="btn btn-primary btn-xs" onclick="viewCamera(${c.id})"><i class="i i-video"></i> View</button>`
                                    : `<button class="btn btn-ghost btn-xs" disabled>No feed</button>`}
                                ${c.coords ? `<button class="btn btn-ghost btn-xs" onclick="cameraWaypoint(${c.id})"><i class="i i-map-pin"></i></button>` : ''}
                                <button class="btn btn-ghost btn-xs" onclick="openFootageEditor(null, ${c.id})">Log</button>
                                ${data.canManage ? `<button class="btn btn-ghost btn-xs" onclick="aimCamera(${c.id})" title="Point it where you are looking">Aim here</button>` : ''}
                                ${data.canManage ? `<button class="btn btn-ghost btn-xs" onclick="openCameraEditor(${c.id})">Edit</button>` : ''}
                            </div>
                        </div>`;
                    }).join('')}
                </div>
            </div>`).join('');
    });
}

function fetchClips() {
    nuiFetch('getFootage', _ftFilter).then(data => {
        _clips = data;
        const body = document.getElementById('cam-body');
        if (!body) return;

        const add = document.getElementById('cam-add');
        if (add) add.style.display = '';

        body.innerHTML = `
            <div class="seg" id="ft-source" style="margin-bottom:12px;">
                ${[['all', 'All'], ...Object.entries(FOOTAGE_SOURCE).map(([k, v]) => [k, v.label])]
                    .map(([k, label]) => `<button class="seg-btn ${_ftFilter.source === k ? 'active' : ''}" data-source="${k}">${label}</button>`).join('')}
            </div>` + ((!data || !data.clips || !data.clips.length)
            ? `<div class="empty-state">
                   <div class="empty-icon"><i class="i i-video"></i></div>
                   <div class="empty-title">No footage logged</div>
                   <div class="empty-subtitle">Log a clip when you pull it, so the case shows it exists.</div>
               </div>`
            : `<div class="ft-table">
                   <div class="ft-head">
                       <span>Number</span><span>Source</span><span>What it shows</span>
                       <span>From</span><span>Case</span><span>Length</span><span>Status</span>
                   </div>
                   ${data.clips.map(f => {
                       const src = FOOTAGE_SOURCE[f.source] || FOOTAGE_SOURCE.camera;
                       const st = FOOTAGE_STATUS[f.status] || FOOTAGE_STATUS.available;
                       return `
                       <div class="ft-row" onclick="openFootageEditor(${f.id})">
                           <span class="mono ft-no">${esc(f.footage_number)}</span>
                           <span class="ft-src"><i class="i i-${src.icon}"></i> ${esc(src.label)}</span>
                           <span class="ft-label">${esc(f.label)}</span>
                           <span>${esc(f.camera_code || f.unit_name || '—')}</span>
                           <span class="mono">${esc(f.case_number || '—')}</span>
                           <span class="mono">${fmtDuration(f.duration)}</span>
                           <span><span class="tag ${st.tag}">${esc(st.label)}</span></span>
                       </div>`;
                   }).join('')}
               </div>
               <div class="penal-count">${data.clips.length} clip${data.clips.length === 1 ? '' : 's'}</div>`);

        document.getElementById('ft-source').onclick = (e) => {
            const btn = e.target.closest('.seg-btn');
            if (!btn) return;
            _ftFilter.source = btn.dataset.source;
            fetchClips();
        };
    });
}

function fmtDuration(secs) {
    const n = Number(secs);
    if (!n) return '—';
    const m = Math.floor(n / 60);
    return `${m}:${String(n % 60).padStart(2, '0')}`;
}

function viewCamera(id) {
    const cam = (_cams.cameras || []).find(c => c.id === id);
    if (!cam || !cam.coords) return;

    nuiPost('viewCamera', {
        id: cam.id,
        camera_code: cam.camera_code,
        label: cam.label,
        area: cam.area,
        coords: cam.coords,
        heading: cam.heading,
        pitch: cam.pitch,
    }).then(res => {
        if (!res || res.ok !== true) showToast('No feed', 'That camera could not be reached.', 'error', 3500);
    });
}

// Stand where the camera should be, look at what it should see.
function aimCamera(id) {
    const cam = (_cams.cameras || []).find(c => c.id === id);
    if (!cam) return;

    nuiPost('myView').then(view => {
        if (!view || view.x === undefined) return;
        nuiFetch('saveCamera', {
            id: cam.id,
            camera_code: cam.camera_code,
            label: cam.label,
            area: cam.area,
            kind: cam.kind,
            status: cam.status,
            notes: cam.notes,
            coords: { x: view.x, y: view.y, z: view.z },
            heading: view.heading,
            pitch: view.pitch,
        }).then(res => {
            if (!res) return;
            showToast('Camera aimed', esc(cam.camera_code) + ' now looks where you were', 'success', 3000);
            fetchCams();
        });
    });
}

function cameraWaypoint(id) {
    const cam = (_cams.cameras || []).find(c => c.id === id);
    if (!cam || !cam.coords) return;
    nuiPost('setWaypoint', cam.coords);
    showToast('Waypoint set', esc(cam.label), 'success', 2500);
}

function openCameraEditor(id) {
    const c = id ? (_cams.cameras || []).find(x => x.id === id) : null;

    const body = `
        <div class="form-row">
            <div class="form-group" style="width:150px;">
                <label class="form-label">Code</label>
                <input class="input mono" id="cm-code" value="${c ? esc(c.camera_code) : ''}" placeholder="CAM-014" maxlength="20">
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Name</label>
                <input class="input" id="cm-label" value="${c ? esc(c.label) : ''}" placeholder="Legion Square, north corner">
            </div>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Area</label>
                <input class="input" id="cm-area" value="${c ? esc(c.area || '') : ''}" placeholder="Downtown">
            </div>
            <div class="form-group" style="width:150px;">
                <label class="form-label">Type</label>
                <select class="input select" id="cm-kind">
                    ${Object.entries(CAM_KINDS).map(([k, v]) =>
                        `<option value="${k}" ${c && c.kind === k ? 'selected' : ''}>${v}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="width:160px;">
                <label class="form-label">Status</label>
                <select class="input select" id="cm-status">
                    ${Object.entries(CAM_STATUS).map(([k, v]) =>
                        `<option value="${k}" ${c && c.status === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Notes</label>
            <textarea class="textarea" id="cm-notes" style="min-height:70px;">${c ? esc(c.notes || '') : ''}</textarea>
        </div>
        <label class="check-row">
            <input type="checkbox" id="cm-here" ${c && c.coords ? '' : 'checked'}>
            Use my position for this camera${c && c.coords ? ' (replaces the one on file)' : ''}
        </label>
        ${c ? `<div class="modal-actions"><button class="btn btn-ghost btn-xs btn-danger" onclick="removeCamera(${c.id})">Remove camera</button></div>` : ''}`;

    const modal = createModal(c ? 'Camera' : 'Add Camera', body, async () => {
        let coords = null;
        if (document.getElementById('cm-here').checked) {
            coords = await nuiPost('myPosition');
            if (!coords || coords.x === undefined) coords = null;
        }

        nuiFetch('saveCamera', {
            id,
            camera_code: document.getElementById('cm-code').value.trim(),
            label: document.getElementById('cm-label').value.trim(),
            area: document.getElementById('cm-area').value.trim(),
            kind: document.getElementById('cm-kind').value,
            status: document.getElementById('cm-status').value,
            notes: document.getElementById('cm-notes').value.trim(),
            coords,
        }).then(res => {
            if (!res) return;
            closeModal(modal);
            showToast('Saved', '', 'success', 2000);
            fetchCams();
        });
    }, 'Save', '<i class="i i-video"></i>');
}

function removeCamera(id) {
    const open = document.querySelector('.modal-backdrop:last-of-type');
    nuiFetch('deleteCamera', id).then(res => {
        if (!res) return;
        closeModal(open);
        showToast('Removed', '', 'success', 2000);
        fetchCams();
    });
}

function openFootageEditor(id, cameraId) {
    const f = id ? (_clips.clips || []).find(x => x.id === id) : null;
    const cam = cameraId ? (_cams.cameras || []).find(c => c.id === cameraId) : null;

    if (f) {
        const src = FOOTAGE_SOURCE[f.source] || FOOTAGE_SOURCE.camera;
        const st = FOOTAGE_STATUS[f.status] || FOOTAGE_STATUS.available;
        const modal = createModal(f.footage_number, `
            <div class="info-grid">
                <div class="info-row"><div class="info-key">Source</div><div class="info-val">${esc(src.label)} · ${esc(f.camera_code || f.unit_name || '—')}</div></div>
                <div class="info-row"><div class="info-key">Shows</div><div class="info-val">${esc(f.label)}</div></div>
                <div class="info-row"><div class="info-key">Length</div><div class="info-val mono">${fmtDuration(f.duration)}</div></div>
                <div class="info-row"><div class="info-key">Case</div><div class="info-val mono">${esc(f.case_number || '—')}</div></div>
                <div class="info-row"><div class="info-key">Status</div><div class="info-val"><span class="tag ${st.tag}">${esc(st.label)}</span></div></div>
                <div class="info-row"><div class="info-key">Logged</div><div class="info-val">${esc(f.logged_by_name)} · ${fmtDateShort(f.created_at)}</div></div>
            </div>
            ${f.detail ? `<div class="record-line" style="margin-top:12px;">${esc(f.detail)}</div>` : ''}
            <div class="modal-actions"><button class="btn btn-ghost btn-xs btn-danger" onclick="removeFootage(${f.id})">Remove entry</button></div>`,
            () => closeModal(modal), 'Done', '<i class="i i-video"></i>');
        return;
    }

    const body = `
        <div class="form-row">
            <div class="form-group" style="width:170px;">
                <label class="form-label">Source</label>
                <select class="input select" id="ft-source-sel">
                    ${Object.entries(FOOTAGE_SOURCE).map(([k, v]) =>
                        `<option value="${k}" ${cam && k === 'camera' ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">${cam ? 'Camera' : 'Camera code or unit'}</label>
                <input class="input mono" id="ft-from" value="${cam ? esc(cam.camera_code) : ''}" placeholder="CAM-014 or 1-ADAM-12">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">What it shows</label>
            <input class="input" id="ft-label" placeholder="Two suspects leaving northbound on foot">
        </div>
        <div class="form-row">
            <div class="form-group" style="width:170px;">
                <label class="form-label">Length (seconds)</label>
                <input class="input mono" id="ft-dur" type="number" min="0" placeholder="214">
            </div>
            <div class="form-group" style="width:170px;">
                <label class="form-label">Case <span class="text-muted">(optional)</span></label>
                <input class="input mono" id="ft-case" placeholder="Case id">
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Status</label>
                <select class="input select" id="ft-status">
                    ${Object.entries(FOOTAGE_STATUS).map(([k, v]) =>
                        `<option value="${k}" ${k === 'available' ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Detail</label>
            <textarea class="textarea" id="ft-detail" placeholder="Timestamps that matter, what is visible, who pulled it."></textarea>
        </div>`;

    const modal = createModal('Log Footage', body, () => {
        const source = document.getElementById('ft-source-sel').value;
        const from = document.getElementById('ft-from').value.trim();
        nuiFetch('logFootage', {
            source,
            camera_id: cam ? cam.id : null,
            camera_code: source === 'camera' ? from : null,
            unit_name: source === 'camera' ? null : from,
            label: document.getElementById('ft-label').value.trim(),
            detail: document.getElementById('ft-detail').value.trim(),
            duration: document.getElementById('ft-dur').value,
            caseId: Number(document.getElementById('ft-case').value.trim()) || null,
            status: document.getElementById('ft-status').value,
        }).then(res => {
            if (!res) return;
            closeModal(modal);
            showToast('Logged', typeof res === 'string' ? res : '', 'success', 3000);
            _camView = 'footage';
            loadCameras();
        });
    }, 'Log', '<i class="i i-video"></i>');
}

function removeFootage(id) {
    const open = document.querySelector('.modal-backdrop:last-of-type');
    nuiFetch('deleteFootage', id).then(res => {
        if (!res) return;
        closeModal(open);
        showToast('Removed', '', 'success', 2000);
        fetchClips();
    });
}

// ── Live body cams ────────────────────────────────────────────────────────
//
// Who is on duty and wearing one. Watching opens a spectate view of what their
// chest camera sees, and the officer is told it is happening.

function fetchLiveCams() {
    nuiFetch('getLiveCams').then(data => {
        const body = document.getElementById('cam-body');
        if (!body) return;

        const add = document.getElementById('cam-add');
        if (add) add.style.display = 'none';

        if (!data || !data.canWatch) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-lock"></i></div>
                <div class="empty-title">Supervisors only</div>
                <div class="empty-subtitle">Watching an officer's camera is a command function.</div>
            </div>`;
            return;
        }

        if (!data.units || !data.units.length) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-badge"></i></div>
                <div class="empty-title">No other units on duty</div>
                <div class="empty-subtitle">Body cams are worn by officers, so the list shows whoever else is working right now. Your own camera is not in it.</div>
            </div>`;
            return;
        }

        body.innerHTML = `
            <div class="form-hint" style="margin-bottom:12px;">
                The officer is told when you open their camera, and every viewing is written to the audit log.
                Press <span class="kbd">ESC</span> to come back.
            </div>
            <div class="live-grid">
                ${data.units.map(u => `
                    <div class="live-card" onclick="watchBodyCam(${u.serverId}, '${String(u.callsign || '').replace(/'/g, "\\'")}', '${String(u.badge || '').replace(/'/g, "\\'")}')">
                        <div class="live-feed">
                            <div class="live-dot"></div>
                            <div class="live-label">LIVE</div>
                            <div class="live-lines"></div>
                        </div>
                        <div class="live-body">
                            <div class="live-unit">${esc(u.callsign || ('#' + u.badge))}</div>
                            <div class="live-name">${esc(u.name)}</div>
                            <div class="live-meta">${esc(u.rank || '')} · ${esc(u.status || '10-8')}</div>
                        </div>
                        <div class="live-watch"><i class="i i-video"></i> Watch</div>
                    </div>`).join('')}
            </div>`;
    });
}

function watchBodyCam(serverId, callsign, badge) {
    nuiPost('startBodyCam', { serverId, callsign, badge }).then(res => {
        if (!res || res.ok !== true) {
            showToast('No feed', 'That unit could not be reached.', 'error', 3500);
        }
    });
}

window.fetchLiveCams = fetchLiveCams;
window.watchBodyCam = watchBodyCam;

window.loadCameras = loadCameras;
window.viewCamera = viewCamera;
window.aimCamera = aimCamera;
window.cameraWaypoint = cameraWaypoint;
window.openCameraEditor = openCameraEditor;
window.removeCamera = removeCamera;
window.openFootageEditor = openFootageEditor;
window.removeFootage = removeFootage;
