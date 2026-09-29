// ── Evidence locker ───────────────────────────────────────────────────────
//
// Evidence used to hang off an incident report, which meant it could only be
// logged after somebody wrote one. It is booked when it is collected now, and
// a report, an arrest or a case is attached to it later if there is one.
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
let _evItemModal = null;

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
    if (!document.getElementById('ev-body')) return;
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
                    <span>Filed under</span><span>Location</span><span>Status</span><span>Booked by</span>
                </div>
                ${data.items.map(it => {
                    const st = EV_STATUS[it.status] || EV_STATUS.booked;
                    const kind = EV_KINDS[it.kind] || EV_KINDS.item;
                    const filed = [it.case_number, it.report_number, it.arrest_id ? 'Arrest #' + it.arrest_id : null].filter(Boolean);
                    return `
                    <div class="ev-row" onclick="openEvidenceItem(${Number(it.id)})">
                        <span class="mono ev-no">${esc(it.evidence_number || '#' + it.id)}</span>
                        <span class="ev-label">${esc(it.label)}</span>
                        <span class="ev-kind"><i class="i i-${kind.icon}"></i> ${esc(kind.label)}</span>
                        <span class="mono">${filed.length ? esc(filed.join(' · ')) : '—'}</span>
                        <span>${esc(it.location || '—')}</span>
                        <span><span class="tag ${st.tag}">${esc(st.label)}</span></span>
                        <span class="record-meta">${esc(it.logged_by_name)}</span>
                    </div>`;
                }).join('')}
            </div>
            <div class="penal-count">${data.items.length} item${data.items.length === 1 ? '' : 's'}</div>`;
    });
}

// opts: { report, arrest, case } as { ref, label } to start attached, and
// after() to run once it is booked.
function openBookEvidence(opts = {}) {
    const body = `
        <div class="form-row">
            <div class="form-group" style="width:170px;">
                <label class="form-label">Type</label>
                <select class="input select" id="ev-kind"
                        onchange="document.getElementById('ev-photo-row').style.display = this.value === 'photo' ? '' : 'none'">
                    ${Object.entries(EV_KINDS).map(([k, v]) => `<option value="${k}">${esc(v.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Item</label>
                <input class="input" id="ev-label" placeholder="9mm casing, red hoodie, phone">
            </div>
        </div>
        <div class="form-group" id="ev-photo-row" style="display:none;">
            <label class="form-label">Photo link</label>
            <input class="input" id="ev-photo" placeholder="Direct image link">
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Where it is</label>
                <input class="input" id="ev-loc" placeholder="Locker 3, shelf B">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Detail</label>
            <textarea class="textarea" id="ev-detail" placeholder="Where it was found, condition, anything a chain of custody should say."></textarea>
        </div>
        <div class="ev-attach-grid">
            <div class="form-group">
                <label class="form-label">Incident report <span class="text-muted">(optional)</span></label>
                <div id="ev-pick-report"></div>
            </div>
            <div class="form-group">
                <label class="form-label">Arrest <span class="text-muted">(optional)</span></label>
                <div id="ev-pick-arrest"></div>
            </div>
            ${canOpenKind('case') ? `
            <div class="form-group">
                <label class="form-label">Case <span class="text-muted">(optional)</span></label>
                <div id="ev-pick-case"></div>
            </div>` : ''}
        </div>`;

    const pickers = {};
    const modal = createModal('Book In Evidence', body, async () => {
        const first = (p) => (p && p.refs()[0]) || null;
        const res = await nuiFetch('bookEvidence', {
            kind: document.getElementById('ev-kind').value,
            label: document.getElementById('ev-label').value.trim(),
            location: document.getElementById('ev-loc').value.trim(),
            detail: document.getElementById('ev-detail').value.trim(),
            photo: document.getElementById('ev-photo').value.trim() || null,
            incidentId: first(pickers.report),
            arrestId: first(pickers.arrest),
            caseId: first(pickers.case),
        });
        if (!res || !res.id) return;
        closeModal(modal);
        showToast('Booked in', res.number || '', 'success', 3000);
        if (opts.after) opts.after();
        else fetchEvidence();
    }, 'Book In', '<i class="i i-box"></i>');
    modal.querySelector('.modal').classList.add('modal-lg');

    if (canOpenKind('incident')) {
        pickers.report = new RecordPicker({ container: modal.querySelector('#ev-pick-report'), kind: 'incident',
            placeholder: 'Search reports...', value: opts.report ? [opts.report] : [] });
    } else {
        modal.querySelector('#ev-pick-report').closest('.form-group').remove();
    }
    if (canOpenKind('arrest')) {
        pickers.arrest = new RecordPicker({ container: modal.querySelector('#ev-pick-arrest'), kind: 'arrest',
            placeholder: 'Search arrests by name...', value: opts.arrest ? [opts.arrest] : [] });
    } else {
        modal.querySelector('#ev-pick-arrest').closest('.form-group').remove();
    }
    if (canOpenKind('case')) {
        pickers.case = new RecordPicker({ container: modal.querySelector('#ev-pick-case'), kind: 'case',
            placeholder: 'Search cases...', value: opts.case ? [opts.case] : [] });
    }
    setTimeout(() => document.getElementById('ev-label')?.focus(), 30);
}

function evidenceLinkRow(it, kind, label, target) {
    const canPick = canOpenKind(kind);
    const text = target
        ? `<a class="ev-link" onclick="openRecord('${kind}', ${Number(target.id)})">${esc(target.text)}</a>`
        : '<span class="ev-link-none">Not attached</span>';
    return `
        <div class="ev-link-row">
            <span class="record-key">${label}</span>
            ${text}
            ${canPick ? `<button class="btn btn-ghost btn-xs" onclick="pickEvidenceLink(${Number(it.id)}, '${kind}')">${target ? 'Change' : 'Attach'}</button>` : ''}
            ${canPick && target ? `<button class="btn btn-ghost btn-xs" onclick="setEvidenceLink(${Number(it.id)}, '${kind}', 0)">Remove</button>` : ''}
        </div>`;
}

function openEvidenceItem(id) {
    nuiFetch('getEvidenceItem', id).then(it => {
        if (!it || !it.id) return;
        if (_evItemModal) closeModal(_evItemModal);
        const st = EV_STATUS[it.status] || EV_STATUS.booked;

        const report = it.report ? { id: it.report.id, text: (it.report.case_number || '#' + it.report.id) + ' — ' + it.report.title } : null;
        const arrest = it.arrest ? { id: it.arrest.id, text: 'Arrest #' + it.arrest.id + ' — ' + it.arrest.civilian_name } : null;
        const caseRef = it.case_id ? { id: it.case_id, text: (it.case_number || 'Case #' + it.case_id) + (it.case_title ? ' — ' + it.case_title : '') } : null;

        const body = `
            <div class="info-grid">
                <div class="info-row"><div class="info-key">Number</div><div class="info-val mono">${esc(it.evidence_number || '#' + it.id)}</div></div>
                <div class="info-row"><div class="info-key">Item</div><div class="info-val">${esc(it.label)}</div></div>
                <div class="info-row"><div class="info-key">Type</div><div class="info-val">${esc((EV_KINDS[it.kind] || { label: it.kind }).label)}</div></div>
                <div class="info-row"><div class="info-key">Booked by</div><div class="info-val">${esc(it.logged_by_name)} · ${fmtDateShort(it.created_at)}</div></div>
            </div>
            ${it.photo ? `<img class="ev-photo" src="${esc(it.photo)}" alt="" onerror="this.remove()">` : ''}

            <div class="case-section-head">Attached to</div>
            <div class="ev-links">
                ${evidenceLinkRow(it, 'incident', 'Report', report)}
                ${evidenceLinkRow(it, 'arrest', 'Arrest', arrest)}
                ${evidenceLinkRow(it, 'case', 'Case', caseRef)}
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

        const modal = createModal(`${esc(it.evidence_number || 'Evidence')} — ${esc(st.label)}`, body, () => {
            nuiFetch('updateEvidence', {
                id: it.id,
                status: document.getElementById('evd-status').value,
                location: document.getElementById('evd-loc').value.trim(),
                detail: document.getElementById('evd-detail').value.trim(),
                note: document.getElementById('evd-note').value.trim(),
            }).then(res => {
                if (!res) return;
                closeModal(modal);
                _evItemModal = null;
                showToast('Saved', '', 'success', 2000);
                fetchEvidence();
            });
        }, 'Save', '<i class="i i-box"></i>');
        _evItemModal = modal;
    });
}

function pickEvidenceLink(id, kind) {
    const titles = { incident: 'Attach to Report', arrest: 'Attach to Arrest', case: 'File Under Case' };
    const hints = { incident: 'Search reports by number or title...', arrest: 'Search arrests by name or number...', case: 'Search cases...' };
    pickRecord(titles[kind] || 'Attach', kind, hints[kind] || '', async (r) => {
        const ok = await nuiFetch('linkEvidence', { id, kind, ref: r.ref });
        if (!ok) return false;
        showToast('Attached', r.label, 'success', 2500);
        openEvidenceItem(id);
        fetchEvidence();
    });
}

async function setEvidenceLink(id, kind, ref) {
    const ok = await nuiFetch('linkEvidence', { id, kind, ref });
    if (!ok) return;
    openEvidenceItem(id);
    fetchEvidence();
}

window.loadEvidence = loadEvidence;
window.openBookEvidence = openBookEvidence;
window.openEvidenceItem = openEvidenceItem;
window.pickEvidenceLink = pickEvidenceLink;
window.setEvidenceLink = setEvidenceLink;
