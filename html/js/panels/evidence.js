// ── Evidence locker ───────────────────────────────────────────────────────
//
// Evidence used to hang off an incident report, which meant it could only be
// logged after somebody wrote one. It is booked when it is collected now, and
// a report or a case is attached to it later if there is one.
//
// Every status change writes a custody row. An evidence log that cannot say
// who had it and when is not worth keeping.

const EV_STATUS = {
    booked:      { label: 'Booked',      tag: 'tag-green' },
    checked_out: { label: 'Checked out', tag: 'tag-yellow' },
    released:    { label: 'Released',    tag: 'tag-blue' },
    destroyed:   { label: 'Destroyed',   tag: 'tag-red' },
    lost:        { label: 'Lost',        tag: 'tag-red' },
};

const EV_KINDS = {
    item:    { label: 'Item',     icon: 'box' },
    weapon:  { label: 'Firearm',  icon: 'alert' },
    drug:    { label: 'Narcotic', icon: 'pill' },
    photo:   { label: 'Photo',    icon: 'camera' },
    print:   { label: 'Print',    icon: 'id' },
    dna:     { label: 'DNA',      icon: 'droplet' },
    doc:     { label: 'Document', icon: 'file' },
    note:    { label: 'Note',     icon: 'edit' },
};

let _evFilter = { status: 'all', search: '' };
let _ev = null;

function loadEvidence() {
    const panel = document.getElementById('tab-evidence');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Evidence</div>
                <div class="panel-subtitle">What is booked in, and who has it</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="ev-status">
                    ${[['all', 'All'], ...Object.entries(EV_STATUS).map(([k, v]) => [k, v.label])]
                        .map(([k, label]) => `<button class="seg-btn ${_evFilter.status === k ? 'active' : ''}" data-status="${k}">${label}</button>`).join('')}
                </div>
                <div class="search-bar" style="width:220px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="ev-search" placeholder="Number, item or shelf...">
                </div>
                <button class="btn btn-primary btn-sm" onclick="openBookEvidence()">Book In</button>
            </div>
        </div>
        <div class="panel-body" id="ev-body">${skeletonLines(5)}</div>`;

    document.getElementById('ev-status').onclick = (e) => {
        const btn = e.target.closest('.seg-btn');
        if (!btn) return;
        _evFilter.status = btn.dataset.status;
        btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
        fetchEvidence();
    };

    let timer;
    document.getElementById('ev-search').oninput = (e) => {
        clearTimeout(timer);
        _evFilter.search = e.target.value.trim();
        timer = setTimeout(fetchEvidence, 250);
    };

    fetchEvidence();
}

function fetchEvidence() {
    nuiFetch('getEvidence', _evFilter).then(data => {
        _ev = data;
        const body = document.getElementById('ev-body');
        if (!body) return;

        if (!data || !data.items || !data.items.length) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-box"></i></div>
                <div class="empty-title">Nothing booked in</div>
                <div class="empty-subtitle">Book an item when you collect it, not when the report is written.</div>
            </div>`;
            return;
        }

        body.innerHTML = `
            <div class="ev-table">
                <div class="ev-head">
                    <span>Number</span><span>Item</span><span>Type</span>
                    <span>Case</span><span>Location</span><span>Status</span><span>Booked by</span>
                </div>
                ${data.items.map(it => {
                    const st = EV_STATUS[it.status] || EV_STATUS.booked;
                    const kind = EV_KINDS[it.kind] || EV_KINDS.item;
                    return `
                    <div class="ev-row" onclick="openEvidenceItem(${it.id})">
                        <span class="mono ev-no">${esc(it.evidence_number || '#' + it.id)}</span>
                        <span class="ev-label">${esc(it.label)}</span>
                        <span class="ev-kind"><i class="i i-${kind.icon}"></i> ${esc(kind.label)}</span>
                        <span class="mono">${esc(it.case_number || '—')}</span>
                        <span>${esc(it.location || '—')}</span>
                        <span><span class="tag ${st.tag}">${esc(st.label)}</span></span>
                        <span class="record-meta">${esc(it.logged_by_name)}</span>
                    </div>`;
                }).join('')}
            </div>
            <div class="penal-count">${data.items.length} item${data.items.length === 1 ? '' : 's'}</div>`;
    });
}

function openBookEvidence() {
    const body = `
        <div class="form-row">
            <div class="form-group" style="width:170px;">
                <label class="form-label">Type</label>
                <select class="input select" id="ev-kind">
                    ${Object.entries(EV_KINDS).map(([k, v]) => `<option value="${k}">${esc(v.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Item</label>
                <input class="input" id="ev-label" placeholder="9mm casing, red hoodie, phone">
            </div>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Where it is</label>
                <input class="input" id="ev-loc" placeholder="Locker 3, shelf B">
            </div>
            <div class="form-group" style="width:170px;">
                <label class="form-label">Case <span class="text-muted">(optional)</span></label>
                <input class="input mono" id="ev-case" placeholder="Case id">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Detail</label>
            <textarea class="textarea" id="ev-detail" placeholder="Where it was found, condition, anything a chain of custody should say."></textarea>
        </div>`;

    const modal = createModal('Book In Evidence', body, () => {
        nuiFetch('bookEvidence', {
            kind: document.getElementById('ev-kind').value,
            label: document.getElementById('ev-label').value.trim(),
            location: document.getElementById('ev-loc').value.trim(),
            caseId: Number(document.getElementById('ev-case').value.trim()) || null,
            detail: document.getElementById('ev-detail').value.trim(),
        }).then(res => {
            if (!res) return;
            closeModal(modal);
            showToast('Booked in', typeof res === 'string' ? res : '', 'success', 3000);
            fetchEvidence();
        });
    }, 'Book In', '<i class="i i-box"></i>');
}

function openEvidenceItem(id) {
    nuiFetch('getEvidenceItem', id).then(it => {
        if (!it || !it.id) return;
        const st = EV_STATUS[it.status] || EV_STATUS.booked;

        const body = `
            <div class="info-grid">
                <div class="info-row"><div class="info-key">Number</div><div class="info-val mono">${esc(it.evidence_number || '#' + it.id)}</div></div>
                <div class="info-row"><div class="info-key">Item</div><div class="info-val">${esc(it.label)}</div></div>
                <div class="info-row"><div class="info-key">Case</div><div class="info-val mono">${esc(it.case_number || '—')}</div></div>
                <div class="info-row"><div class="info-key">Booked by</div><div class="info-val">${esc(it.logged_by_name)} · ${fmtDateShort(it.created_at)}</div></div>
            </div>

            <div class="form-row" style="margin-top:14px;">
                <div class="form-group" style="width:190px;">
                    <label class="form-label">Status</label>
                    <select class="input select" id="evd-status">
                        ${Object.entries(EV_STATUS).map(([k, v]) =>
                            `<option value="${k}" ${it.status === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                    </select>
                </div>
                <div class="form-group" style="flex:1;">
                    <label class="form-label">Where it is</label>
                    <input class="input" id="evd-loc" value="${esc(it.location || '')}">
                </div>
            </div>
            <div class="form-group">
                <label class="form-label">Detail</label>
                <textarea class="textarea" id="evd-detail" style="min-height:80px;">${esc(it.detail || '')}</textarea>
            </div>
            <div class="form-group">
                <label class="form-label">Custody note <span class="text-muted">(saved with the change)</span></label>
                <input class="input" id="evd-note" placeholder="Signed out for lab, returned, released to owner">
            </div>
            <div class="form-hint">Releasing or destroying evidence is a supervisor's call.</div>

            <div class="case-section-head">Chain of custody</div>
            ${(it.custody || []).length ? `
                <div class="custody">
                    ${it.custody.map(c => `
                        <div class="custody-row">
                            <span class="tag ${(EV_STATUS[c.action] || { tag: 'tag-gray' }).tag}">${esc((EV_STATUS[c.action] || { label: c.action }).label)}</span>
                            <span class="custody-detail">${esc(c.detail || '')}</span>
                            <span class="record-meta">${esc(c.officer_name)} · ${fmtDateShort(c.created_at)}</span>
                        </div>`).join('')}
                </div>`
            : '<div class="text-muted text-sm">Nothing logged yet.</div>'}`;

        const modal = createModal(`${it.evidence_number || 'Evidence'} — ${esc(st.label)}`, body, () => {
            nuiFetch('updateEvidence', {
                id: it.id,
                status: document.getElementById('evd-status').value,
                location: document.getElementById('evd-loc').value.trim(),
                detail: document.getElementById('evd-detail').value.trim(),
                note: document.getElementById('evd-note').value.trim(),
            }).then(res => {
                if (!res) return;
                closeModal(modal);
                showToast('Saved', '', 'success', 2000);
                fetchEvidence();
            });
        }, 'Save', '<i class="i i-box"></i>');
    });
}

window.loadEvidence = loadEvidence;
window.openBookEvidence = openBookEvidence;
window.openEvidenceItem = openEvidenceItem;
