// ── Cases ─────────────────────────────────────────────────────────────────
//
// The folder everything else gets filed into. A case view is a list of what is
// attached to it, because that is the only question anybody opens a case to
// answer: what do we have on this.

const CASE_STATUS = {
    open:   { label: 'Open',   tag: 'tag-yellow' },
    active: { label: 'Active', tag: 'tag-red' },
    cold:   { label: 'Cold',   tag: 'tag-blue' },
    closed: { label: 'Closed', tag: 'tag-gray' },
};

const CASE_ATTACHABLE = ['incident', 'arrest', 'citation', 'warrant', 'bolo', 'evidence', 'person', 'vehicle', 'weapon'];

let _caseFilter = { status: 'all', mine: false, search: '' };
let _cases = null;
let _openCase = null;

function loadCases() {
    const panel = document.getElementById('tab-cases');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Cases</div>
                <div class="panel-subtitle">Reports, evidence and people, filed together</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="case-status">
                    ${[['all', 'All'], ...Object.entries(CASE_STATUS).map(([k, v]) => [k, v.label])]
                        .map(([k, label]) => `<button class="seg-btn ${_caseFilter.status === k ? 'active' : ''}" data-status="${k}">${label}</button>`).join('')}
                </div>
                <button class="btn btn-ghost btn-sm" id="case-mine">Mine</button>
                <div class="search-bar" style="width:220px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="case-search" placeholder="Case number, title or summary...">
                </div>
                <button class="btn btn-primary btn-sm" onclick="openCaseEditor()">New Case</button>
            </div>
        </div>
        <div class="panel-body" id="case-body">${skeletonLines(5)}</div>`;

    document.getElementById('case-status').onclick = (e) => {
        const btn = e.target.closest('.seg-btn');
        if (!btn) return;
        _caseFilter.status = btn.dataset.status;
        btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
        fetchCases();
    };

    document.getElementById('case-mine').onclick = (e) => {
        _caseFilter.mine = !_caseFilter.mine;
        e.currentTarget.classList.toggle('active', _caseFilter.mine);
        fetchCases();
    };

    let timer;
    document.getElementById('case-search').oninput = (e) => {
        clearTimeout(timer);
        _caseFilter.search = e.target.value.trim();
        timer = setTimeout(fetchCases, 250);
    };

    fetchCases();
}

function fetchCases() {
    nuiFetch('getCases', _caseFilter).then(data => {
        _cases = data;
        const body = document.getElementById('case-body');
        if (!body) return;

        if (!data || !data.cases || !data.cases.length) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-folder"></i></div>
                <div class="empty-title">No cases</div>
                <div class="empty-subtitle">Open one and attach reports, evidence and people to it.</div>
            </div>`;
            return;
        }

        body.innerHTML = data.cases.map(c => {
            const st = CASE_STATUS[c.status] || CASE_STATUS.open;
            return `
            <div class="record-card clickable case-${c.status}" onclick="openCase(${c.id})">
                <div class="record-head">
                    <span class="mono record-no">${esc(c.case_number)}</span>
                    <span class="record-title">${esc(c.title)}</span>
                    <span class="tag ${st.tag}">${esc(st.label)}</span>
                    <span class="record-meta">${esc(c.lead_name || c.created_by_name)} · ${fmtDateShort(c.updated_at)}</span>
                </div>
                ${c.summary ? `<div class="record-line">${esc(String(c.summary).slice(0, 200))}${String(c.summary).length > 200 ? '…' : ''}</div>` : ''}
                <div class="case-counts">
                    <span><i class="i i-link"></i> ${c.links || 0} attached</span>
                    <span><i class="i i-edit"></i> ${Number(c.notes) || 0} notes</span>
                </div>
            </div>`;
        }).join('');
    });
}

// ── One case ──────────────────────────────────────────────────────────────

function openCase(id) {
    nuiFetch('getCase', id).then(data => {
        if (!data || !data.id) return;
        _openCase = data;
        drawCase();
    });
}

function drawCase() {
    const c = _openCase;
    const st = CASE_STATUS[c.status] || CASE_STATUS.open;

    const existing = document.querySelector('.modal-backdrop.case-view');
    if (existing) existing.remove();

    const byKind = {};
    for (const l of c.links || []) (byKind[l.kind] ||= []).push(l);

    const backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop case-view';
    backdrop.innerHTML = `
        <div class="modal modal-lg">
            <div class="modal-header">
                <div class="modal-header-icon"><i class="i i-folder"></i></div>
                <div class="modal-title">
                    ${esc(c.title)}
                    <div class="modal-subtitle">${esc(c.case_number)} · lead ${esc(c.lead_name || '—')}</div>
                </div>
                <span class="tag ${st.tag}">${esc(st.label)}</span>
                <button class="modal-close" title="Close"><i class="i i-x"></i></button>
            </div>
            <div class="modal-body">
                ${c.summary ? `<div class="case-summary">${esc(c.summary).replace(/\n/g, '<br>')}</div>` : ''}

                <div class="case-section-head">
                    Attached
                    <button class="btn btn-ghost btn-xs" onclick="openCaseLink()">Attach</button>
                </div>
                ${Object.keys(byKind).length ? Object.entries(byKind).map(([kind, list]) => `
                    <div class="case-links">
                        <div class="case-link-kind">${esc((RECORD_KINDS[kind] || { label: kind }).label)}</div>
                        ${list.map(l => `
                            <div class="case-link clickable" onclick="openCaseAttachment(${Number(l.id)})" title="Open">
                                <span class="case-link-icon"><i class="i i-${(RECORD_KINDS[kind] || { icon: 'file' }).icon}"></i></span>
                                <span class="case-link-label">${esc(l.label || (kind + ' #' + l.ref_id))}</span>
                                <span class="record-meta">${esc(l.added_by_name)}</span>
                                <button class="btn btn-ghost btn-xs" title="Take off the case" onclick="event.stopPropagation();unlinkCase(${Number(l.id)})"><i class="i i-x"></i></button>
                            </div>`).join('')}
                    </div>`).join('')
                : '<div class="text-muted text-sm">Nothing attached yet.</div>'}

                <div class="case-section-head">
                    Notes
                    <button class="btn btn-ghost btn-xs" onclick="openCaseNote()">Add note</button>
                </div>
                ${(c.notes || []).length ? c.notes.map(n => `
                    <div class="case-note">
                        <div class="case-note-head">
                            <span>${esc(n.author_name)}</span>
                            <span class="record-meta">${fmtDateShort(n.created_at)}</span>
                        </div>
                        <div class="case-note-body">${esc(n.body).replace(/\n/g, '<br>')}</div>
                    </div>`).join('')
                : '<div class="text-muted text-sm">No notes.</div>'}
            </div>
            <div class="modal-footer">
                <button class="btn btn-ghost" onclick="openCaseEditor(${c.id})">Edit case</button>
                <button class="btn btn-primary" id="case-done">Done</button>
            </div>
        </div>`;

    document.body.appendChild(backdrop);
    backdrop.querySelector('.modal-close').onclick = () => backdrop.remove();
    backdrop.querySelector('#case-done').onclick = () => backdrop.remove();
    backdrop.onclick = (e) => { if (e.target === backdrop) backdrop.remove(); };
}

function refreshCase() {
    if (!_openCase) return;
    nuiFetch('getCase', _openCase.id).then(data => {
        if (!data || !data.id) return;
        _openCase = data;
        drawCase();
        fetchCases();
    });
}

function openCaseEditor(id) {
    const c = id ? (_openCase && _openCase.id === id ? _openCase : (_cases.cases || []).find(x => x.id === id)) : null;

    const body = `
        <div class="form-group">
            <label class="form-label">Title</label>
            <input class="input" id="cs-title" value="${c ? esc(c.title) : ''}" placeholder="What the case is about">
        </div>
        <div class="form-row">
            <div class="form-group" style="width:180px;">
                <label class="form-label">Status</label>
                <select class="input select" id="cs-status">
                    ${Object.entries(CASE_STATUS).map(([k, v]) =>
                        `<option value="${k}" ${c && c.status === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Lead officer</label>
                <div id="cs-lead"></div>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Summary</label>
            <textarea class="textarea" id="cs-summary" placeholder="What is known so far.">${c ? esc(c.summary || '') : ''}</textarea>
        </div>`;

    const modal = createModal(c ? 'Edit Case' : 'New Case', body, () => {
        nuiFetch('saveCase', {
            id,
            title: document.getElementById('cs-title').value.trim(),
            status: document.getElementById('cs-status').value,
            summary: document.getElementById('cs-summary').value.trim(),
            lead_citizenid: modal.dataset.lead || (c && c.lead_citizenid),
            lead_name: modal.dataset.leadName || (c && c.lead_name),
        }).then(res => {
            if (!res) return;
            closeModal(modal);
            showToast(id ? 'Case saved' : 'Case opened', '', 'success', 2500);
            if (id && _openCase) refreshCase(); else fetchCases();
        });
    }, 'Save', '<i class="i i-folder"></i>');

    new NameSearch({
        container: modal.querySelector('#cs-lead'),
        endpoint: 'searchOfficers',
        placeholder: c && c.lead_name ? `${c.lead_name} — search to change…` : 'Search officers…',
        onSelect: (o) => {
            modal.dataset.lead = o ? o.citizenid : '';
            modal.dataset.leadName = o ? o.name : '';
        },
    });
}

function openCaseLink() {
    const kinds = CASE_ATTACHABLE.filter(canOpenKind);
    if (!kinds.length) return;
    let kind = kinds[0];
    let added = 0;

    const modal = createModal('Attach to Case', `
        <div class="form-row">
            <div class="form-group" style="width:170px;">
                <label class="form-label">What</label>
                <select class="input select" id="cl-kind">
                    ${kinds.map(k => `<option value="${k}">${esc(RECORD_KINDS[k].label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Find it</label>
                <div id="cl-picker"></div>
            </div>
        </div>
        <div class="form-hint">Pick as many as you need. Each one is attached as soon as you click it.</div>
        <div class="linked-persons" id="cl-added"></div>`,
        () => finish(), 'Done', '<i class="i i-link"></i>');
    modal.querySelector('#modal-cancel').style.display = 'none';

    const finish = () => {
        closeModal(modal);
        if (added) refreshCase();
    };
    modal.querySelector('.modal-close').onclick = finish;
    modal.addEventListener('click', (e) => { if (e.target === modal && added) refreshCase(); });

    const mount = () => {
        new RecordPicker({
            container: modal.querySelector('#cl-picker'),
            kind,
            placeholder: {
                incident: 'Report number or title...', arrest: 'Name, citizen ID or arrest number...',
                citation: 'Name, citizen ID or citation number...', warrant: 'Name or warrant number...',
                bolo: 'Description or plate...', evidence: 'Evidence number or item...',
                person: 'Name or citizen ID...', vehicle: 'Plate...', weapon: 'Serial, model or owner...',
            }[kind],
            onPick: async (item) => {
                const ok = await nuiFetch('linkToCase', { caseId: _openCase.id, kind, refId: item.ref, label: item.label });
                if (!ok) return;
                added++;
                const list = modal.querySelector('#cl-added');
                if (list) list.insertAdjacentHTML('beforeend', `<span class="linked-person-tag"><i class="i i-check"></i> ${esc(item.label)}</span>`);
                setTimeout(() => modal.querySelector('.rp-input')?.focus(), 10);
            },
        });
        setTimeout(() => modal.querySelector('.rp-input')?.focus(), 30);
    };

    modal.querySelector('#cl-kind').onchange = (e) => { kind = e.target.value; mount(); };
    mount();
}

function openCaseAttachment(linkId) {
    const c = _openCase;
    const link = c && (c.links || []).find(l => Number(l.id) === Number(linkId));
    if (!link) return;
    openRecord(link.kind, link.ref_id, { id: c.id, number: c.case_number });
}

function unlinkCase(id) {
    nuiFetch('unlinkFromCase', id).then(res => { if (res) refreshCase(); });
}

function openCaseNote() {
    const modal = createModal('Add Note',
        `<div class="form-group">
            <label class="form-label">Note</label>
            <textarea class="textarea" id="cn-body" style="min-height:140px;" placeholder="What you found, who you spoke to, what is next."></textarea>
        </div>`,
        () => {
            nuiFetch('addCaseNote', {
                caseId: _openCase.id,
                body: document.getElementById('cn-body').value.trim(),
            }).then(res => {
                if (!res) return;
                closeModal(modal);
                refreshCase();
            });
        }, 'Add', '<i class="i i-edit"></i>');
}

window.loadCases = loadCases;
window.openCase = openCase;
window.openCaseEditor = openCaseEditor;
window.openCaseLink = openCaseLink;
window.openCaseAttachment = openCaseAttachment;
window.unlinkCase = unlinkCase;
window.openCaseNote = openCaseNote;
