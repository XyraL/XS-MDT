// ── Field training and standard operating procedures ──────────────────────
//
// Two small panels that share a file because they are the same kind of thing:
// a supervisor writes them, everyone else reads them.

const FTO_STATUS = {
    in_progress: { label: 'In progress', tag: 'tag-blue' },
    passed:      { label: 'Passed',      tag: 'tag-green' },
    failed:      { label: 'Failed',      tag: 'tag-red' },
};

let _fto = null;

function loadFTO() {
    const panel = document.getElementById('tab-fto');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Field Training</div>
                <div class="panel-subtitle">Trainees, phases and sign-offs</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadFTO()"><i class="i i-refresh"></i> Refresh</button>
                <button class="btn btn-primary btn-sm" id="fto-new">Start a Trainee</button>
            </div>
        </div>
        <div class="panel-body" id="fto-body">${skeletonLines(5)}</div>`;

    nuiFetch('getFTO').then(data => {
        _fto = data;
        const body = document.getElementById('fto-body');
        if (!body) return;

        const newBtn = document.getElementById('fto-new');
        if (newBtn) {
            newBtn.style.display = data && data.canManage ? '' : 'none';
            newBtn.onclick = () => openFTORecord();
        }

        if (!data || !data.records || !data.records.length) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-check"></i></div>
                <div class="empty-title">Nobody in training</div>
                <div class="empty-subtitle">Start a trainee to open their first phase.</div>
            </div>`;
            return;
        }

        // Grouped by trainee, because a phase on its own says nothing about
        // where somebody is up to.
        const byTrainee = {};
        for (const r of data.records) {
            (byTrainee[r.citizenid] ||= { name: r.trainee_name, rows: [] }).rows.push(r);
        }

        body.innerHTML = Object.entries(byTrainee).map(([cid, t]) => {
            const done = t.rows.filter(r => r.status === 'passed').length;
            const hours = t.rows.reduce((n, r) => n + Number(r.hours || 0), 0);
            return `
            <div class="card" style="margin-bottom:12px;">
                <div class="card-header">
                    <div class="card-title">
                        <div class="card-title-icon"><i class="i i-user"></i></div>
                        ${esc(t.name)}
                    </div>
                    <span class="record-meta">${done}/${(_fto.phases || []).length || t.rows.length} phases · ${hours.toFixed(1)} h</span>
                </div>
                <div class="fto-phases">
                    ${t.rows.map(r => {
                        const st = FTO_STATUS[r.status] || FTO_STATUS.in_progress;
                        return `
                        <div class="fto-row"${data.canManage ? ` onclick="openFTORecord(${r.id})"` : ''}>
                            <span class="fto-phase">${esc(r.phase)}</span>
                            <span class="tag ${st.tag}">${esc(st.label)}</span>
                            <span class="mono">${Number(r.hours || 0).toFixed(1)} h</span>
                            <span class="record-meta">${esc(r.trainer_name || 'No trainer')}</span>
                            ${r.notes ? `<span class="fto-note">${esc(r.notes)}</span>` : '<span></span>'}
                        </div>`;
                    }).join('')}
                </div>
            </div>`;
        }).join('');
    });
}

function openFTORecord(id) {
    const r = id ? (_fto.records || []).find(x => x.id === id) : null;
    const phases = _fto.phases || [];

    const body = `
        ${r ? `<div class="form-hint" style="margin-bottom:10px;">${esc(r.trainee_name)} · ${esc(r.phase)}</div>`
            : `<div class="form-group">
                   <label class="form-label">Trainee</label>
                   <div id="fto-trainee-search"></div>
               </div>
               <div class="form-group">
                   <label class="form-label">Phase</label>
                   <select class="input select" id="fto-phase">
                       ${phases.map(p => `<option value="${esc(p)}">${esc(p)}</option>`).join('')}
                   </select>
               </div>`}

        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Status</label>
                <select class="input select" id="fto-status">
                    ${Object.entries(FTO_STATUS).map(([k, v]) =>
                        `<option value="${k}" ${r && r.status === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="width:140px;">
                <label class="form-label">Hours</label>
                <input class="input mono" id="fto-hours" type="number" step="0.5" min="0" value="${r ? Number(r.hours || 0) : 0}">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Notes</label>
            <textarea class="textarea" id="fto-notes" placeholder="How the phase went.">${r ? esc(r.notes || '') : ''}</textarea>
        </div>`;

    const modal = createModal(r ? 'Training Phase' : 'Start a Trainee', body, () => saveFTO(r),
        r ? 'Save' : 'Open Phase', '<i class="i i-check"></i>');

    if (!r) {
        new NameSearch({
            container: modal.querySelector('#fto-trainee-search'),
            endpoint: 'searchOfficers',
            placeholder: 'Search officers by name…',
            onSelect: (o) => {
                modal.dataset.trainee = o ? o.citizenid : '';
                modal.dataset.traineeName = o ? o.name : '';
            },
        });
    }
}

function saveFTO(existing) {
    const modal = document.querySelector('.modal-backdrop:last-of-type');
    const payload = {
        id: existing && existing.id,
        phase: existing ? existing.phase : document.getElementById('fto-phase').value,
        status: document.getElementById('fto-status').value,
        hours: document.getElementById('fto-hours').value,
        notes: document.getElementById('fto-notes').value.trim(),
        citizenid: existing ? existing.citizenid : (modal && modal.dataset.trainee),
        trainee_name: existing ? existing.trainee_name : (modal && modal.dataset.traineeName),
    };

    if (!payload.citizenid) return showToast('Pick a trainee', 'A phase belongs to somebody.', 'error');

    nuiFetch('saveFTO', payload).then(res => {
        if (!res) return;
        closeModal(modal);
        showToast('Saved', '', 'success', 2000);
        loadFTO();
    });
}

// ── SOP ───────────────────────────────────────────────────────────────────

let _sop = null;
let _sopOpen = null;

function loadSOP() {
    const panel = document.getElementById('tab-sop');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Standard Operating Procedures</div>
                <div class="panel-subtitle">Department policy</div>
            </div>
            <div class="panel-actions">
                <div class="search-bar" style="width:220px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="sop-search" placeholder="Search procedures...">
                </div>
                <button class="btn btn-primary btn-sm" id="sop-new">New Document</button>
            </div>
        </div>
        <div class="panel-body" id="sop-body">${skeletonLines(4)}</div>`;

    nuiFetch('getSOP').then(data => {
        _sop = data;
        const newBtn = document.getElementById('sop-new');
        if (newBtn) {
            newBtn.style.display = data && data.canManage ? '' : 'none';
            newBtn.onclick = () => openSOPEditor();
        }
        document.getElementById('sop-search')?.addEventListener('input', renderSOP);
        renderSOP();
    });
}

function renderSOP() {
    const body = document.getElementById('sop-body');
    if (!body || !_sop) return;

    const q = (document.getElementById('sop-search')?.value || '').toLowerCase().trim();
    const docs = (_sop.docs || []).filter(d =>
        !q || d.title.toLowerCase().includes(q) || (d.category || '').toLowerCase().includes(q)
           || (d.body || '').toLowerCase().includes(q));

    if (!docs.length) {
        body.innerHTML = `<div class="empty-state">
            <div class="empty-icon"><i class="i i-archive"></i></div>
            <div class="empty-title">${_sop.docs && _sop.docs.length ? 'Nothing matched' : 'No procedures yet'}</div>
            <div class="empty-subtitle">${_sop.canManage ? 'Write the first one with New Document.' : 'Command has not published any yet.'}</div>
        </div>`;
        return;
    }

    const byCat = {};
    for (const d of docs) (byCat[d.category || 'General'] ||= []).push(d);

    body.innerHTML = Object.entries(byCat).map(([cat, list]) => `
        <div class="sop-group">
            <div class="sop-cat">${esc(cat)}</div>
            ${list.map(d => `
                <div class="sop-doc${_sopOpen === d.id ? ' open' : ''}">
                    <div class="sop-head" onclick="toggleSOP(${d.id})">
                        ${d.pinned ? '<span class="sop-pin"><i class="i i-pin"></i></span>' : ''}
                        <span class="sop-title">${esc(d.title)}</span>
                        <span class="mono sop-ver">v${esc(d.version || '1.0')}</span>
                        <span class="record-meta">${d.updated_by_name ? esc(d.updated_by_name) + ' · ' : ''}${fmtDateShort(d.updated_at)}</span>
                        <span class="sop-chevron"><i class="i i-chevron"></i></span>
                    </div>
                    <div class="sop-body">
                        ${esc(d.body).replace(/\n/g, '<br>')}
                        ${_sop.canManage ? `
                        <div class="modal-actions">
                            <button class="btn btn-ghost btn-xs" onclick="event.stopPropagation();openSOPEditor(${d.id})">Edit</button>
                            <button class="btn btn-ghost btn-xs btn-danger" onclick="event.stopPropagation();removeSOP(${d.id})">Delete</button>
                        </div>` : ''}
                    </div>
                </div>`).join('')}
        </div>`).join('');
}

function toggleSOP(id) {
    _sopOpen = _sopOpen === id ? null : id;
    renderSOP();
}

function openSOPEditor(id) {
    const d = id ? (_sop.docs || []).find(x => x.id === id) : null;

    const body = `
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Title</label>
                <input class="input" id="sop-title" value="${d ? esc(d.title) : ''}" placeholder="Use of Force">
            </div>
            <div class="form-group" style="width:170px;">
                <label class="form-label">Category</label>
                <input class="input" id="sop-cat" value="${d ? esc(d.category || 'General') : 'General'}">
            </div>
            <div class="form-group" style="width:110px;">
                <label class="form-label">Version</label>
                <input class="input mono" id="sop-ver" value="${d ? esc(d.version || '1.0') : '1.0'}">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Body</label>
            <textarea class="textarea" id="sop-text" style="min-height:260px;">${d ? esc(d.body) : ''}</textarea>
        </div>
        <label class="check-row">
            <input type="checkbox" id="sop-pinned" ${d && d.pinned ? 'checked' : ''}>
            Pin to the top of the list
        </label>`;

    const modal = createModal(d ? 'Edit Procedure' : 'New Procedure', body, () => {
        nuiFetch('saveSOP', {
            id,
            title: document.getElementById('sop-title').value.trim(),
            category: document.getElementById('sop-cat').value.trim(),
            version: document.getElementById('sop-ver').value.trim(),
            body: document.getElementById('sop-text').value,
            pinned: document.getElementById('sop-pinned').checked,
        }).then(res => {
            if (!res) return;
            closeModal(modal);
            showToast('Saved', '', 'success', 2000);
            loadSOP();
        });
    }, 'Save', '<i class="i i-archive"></i>');
}

function removeSOP(id) {
    const d = (_sop.docs || []).find(x => x.id === id);
    if (!d) return;

    const modal = createModal('Delete Procedure',
        `<p>Delete <strong>${esc(d.title)}</strong>? Everyone in the department loses it.</p>`,
        () => {
            nuiFetch('deleteSOP', id).then(res => {
                closeModal(modal);
                if (!res) return;
                showToast('Deleted', '', 'success', 2000);
                loadSOP();
            });
        }, 'Delete', '<i class="i i-trash"></i>');
}

window.loadFTO = loadFTO;
window.openFTORecord = openFTORecord;
window.saveFTO = saveFTO;
window.loadSOP = loadSOP;
window.toggleSOP = toggleSOP;
window.openSOPEditor = openSOPEditor;
window.removeSOP = removeSOP;
