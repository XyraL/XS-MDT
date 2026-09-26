// ── Internal Affairs ──────────────────────────────────────────────────────
//
// Complaints, investigations and commendations against officers. Supervisors
// only, server-side — this panel never renders for anyone else because the
// callback returns nothing.

const IA_STATUS = {
    open:          { label: 'Open',          tag: 'tag-yellow' },
    investigating: { label: 'Investigating', tag: 'tag-blue' },
    sustained:     { label: 'Sustained',     tag: 'tag-red' },
    unfounded:     { label: 'Unfounded',     tag: 'tag-green' },
    closed:        { label: 'Closed',        tag: 'tag-gray' },
};

const IA_KIND = {
    complaint:     { label: 'Complaint',     icon: 'alert' },
    investigation: { label: 'Investigation', icon: 'folder' },
    commendation:  { label: 'Commendation',  icon: 'trophy' },
};

let _iaFilter = { status: 'all', search: '' };
let _iaData = null;

function loadIA() {
    const panel = document.getElementById('tab-ia');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Internal Affairs</div>
                <div class="panel-subtitle">Complaints, investigations and commendations</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="ia-status">
                    ${[['all', 'All'], ...Object.entries(IA_STATUS).map(([k, v]) => [k, v.label])]
                        .map(([k, label]) => `<button class="seg-btn ${_iaFilter.status === k ? 'active' : ''}" data-status="${k}">${label}</button>`).join('')}
                </div>
                <div class="search-bar" style="width:220px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="ia-search" placeholder="Officer, case number or title...">
                </div>
                <button class="btn btn-primary btn-sm" onclick="openIACase()">New Case</button>
            </div>
        </div>
        <div class="panel-body" id="ia-body">${skeletonLines(5)}</div>`;

    document.getElementById('ia-status').onclick = (e) => {
        const btn = e.target.closest('.seg-btn');
        if (!btn) return;
        _iaFilter.status = btn.dataset.status;
        btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
        fetchIA();
    };

    let timer;
    document.getElementById('ia-search').oninput = (e) => {
        clearTimeout(timer);
        _iaFilter.search = e.target.value.trim();
        timer = setTimeout(fetchIA, 250);
    };

    fetchIA();
}

function fetchIA() {
    nuiFetch('getIACases', _iaFilter).then(data => {
        _iaData = data;
        const body = document.getElementById('ia-body');
        if (!body) return;

        if (!data || !data.cases) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-lock"></i></div>
                <div class="empty-title">Supervisors only</div>
                <div class="empty-subtitle">Internal affairs files are not open to the whole department.</div>
            </div>`;
            return;
        }

        if (!data.cases.length) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-folder"></i></div>
                <div class="empty-title">No cases</div>
                <div class="empty-subtitle">Nothing matches this filter.</div>
            </div>`;
            return;
        }

        body.innerHTML = data.cases.map(c => {
            const st = IA_STATUS[c.status] || IA_STATUS.open;
            const kind = IA_KIND[c.kind] || IA_KIND.complaint;
            return `
            <div class="record-card clickable" onclick="openIACase(${c.id})">
                <div class="record-head">
                    <span class="record-icon"><i class="i i-${kind.icon}"></i></span>
                    <span class="mono record-no">${esc(c.case_number)}</span>
                    <span class="record-title">${esc(c.title)}</span>
                    <span class="tag ${st.tag}">${esc(st.label)}</span>
                    <span class="record-meta">${esc(c.officer_name)} · ${fmtDateShort(c.created_at)}</span>
                </div>
                ${c.detail ? `<div class="record-line">${esc(String(c.detail).slice(0, 220))}${String(c.detail).length > 220 ? '…' : ''}</div>` : ''}
            </div>`;
        }).join('');
    });
}

// An existing case is edited in place; a new one needs an officer picked
// first, which is what the name search is for.
function openIACase(id) {
    const c = id ? (_iaData.cases || []).find(x => x.id === id) : null;

    const body = `
        ${c ? `<div class="form-hint mono" style="margin-bottom:10px;">${esc(c.case_number)} · ${esc(c.officer_name)}</div>`
            : `<div class="form-group">
                   <label class="form-label">Officer</label>
                   <div id="ia-officer-search"></div>
               </div>`}

        <div class="form-row">
            <div class="form-group" style="width:180px;">
                <label class="form-label">Type</label>
                <select class="input select" id="ia-kind">
                    ${Object.entries(IA_KIND).map(([k, v]) =>
                        `<option value="${k}" ${c && c.kind === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Title</label>
                <input class="input" id="ia-title" value="${c ? esc(c.title) : ''}" placeholder="What the case is about">
            </div>
            <div class="form-group" style="width:170px;">
                <label class="form-label">Status</label>
                <select class="input select" id="ia-status-sel">
                    ${Object.entries(IA_STATUS).map(([k, v]) =>
                        `<option value="${k}" ${c && c.status === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
        </div>

        <div class="form-group">
            <label class="form-label">Detail</label>
            <textarea class="textarea" id="ia-detail" placeholder="What happened, who reported it, what was reviewed.">${c ? esc(c.detail || '') : ''}</textarea>
        </div>

        ${c ? `<div class="form-group">
            <label class="form-label">Outcome</label>
            <textarea class="textarea" id="ia-outcome" style="min-height:70px;"
                placeholder="Findings and any action taken.">${esc(c.outcome || '')}</textarea>
        </div>` : ''}`;

    const modal = createModal(c ? 'Case' : 'New Case', body, () => saveIA(c && c.id),
        c ? 'Save' : 'Open Case', '<i class="i i-folder"></i>');

    if (!c) {
        new NameSearch({
            container: modal.querySelector('#ia-officer-search'),
            endpoint: 'searchOfficers',
            placeholder: 'Search officers by name…',
            onSelect: (o) => {
                modal.dataset.officer = o ? o.citizenid : '';
                modal.dataset.officerName = o ? o.name : '';
            },
        });
    }
}

function saveIA(id) {
    const modal = document.querySelector('.modal-backdrop:last-of-type');
    const payload = {
        id,
        kind: document.getElementById('ia-kind').value,
        title: document.getElementById('ia-title').value.trim(),
        status: document.getElementById('ia-status-sel').value,
        detail: document.getElementById('ia-detail').value.trim(),
        outcome: document.getElementById('ia-outcome')?.value.trim(),
    };

    if (!id) {
        payload.citizenid = modal && modal.dataset.officer;
        payload.officer_name = modal && modal.dataset.officerName;
        if (!payload.citizenid) return showToast('Pick an officer', 'A case has to be about someone.', 'error');
    }

    nuiFetch('saveIACase', payload).then(res => {
        if (!res) return;
        closeModal(modal);
        showToast(id ? 'Case saved' : 'Case opened', '', 'success', 2500);
        fetchIA();
    });
}

window.loadIA = loadIA;
window.openIACase = openIACase;
window.saveIA = saveIA;
