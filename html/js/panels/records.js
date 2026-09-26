// ── Arrest Modal ──────────────────────────────────────────────────────────
function openNewArrestModal(prefillPerson = null) {
    window._selectedCharges = [];
    let _arrestPerson = prefillPerson || null;

    const modal = createModal('Log Arrest', `
        <div class="form-group">
            <label class="form-label">Suspect</label>
            <div id="arrest-person-search"></div>
        </div>
        <div class="form-group">
            <label class="form-label">Select Charges</label>
            <div id="arrest-charge-picker"></div>
        </div>
        <div class="form-group">
            <label class="form-label">Selected Charges</label>
            <div class="selected-charges" id="arrest-selected-charges">
                <span class="text-muted text-sm" style="padding:4px;">No charges selected</span>
            </div>
        </div>
        <div id="charge-total-display" class="charge-total" style="display:none;"></div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Fine Amount ($)</label>
                <input class="input font-mono" id="arrest-fine" type="number" min="0" placeholder="Auto-calculated"
                       oninput="this.dataset.manual=this.value">
            </div>
            <div class="form-group">
                <label class="form-label">Jail Time (minutes)</label>
                <input class="input font-mono" id="arrest-jail" type="number" min="0" placeholder="0">
            </div>
            <div class="form-group">
                <label class="form-label">Location of Arrest</label>
                <input class="input" id="arrest-location" placeholder="e.g. Vinewood Blvd">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Arrest Narrative</label>
            <textarea class="textarea" id="arrest-narrative"
                placeholder="Describe the events leading to this arrest in detail. Include timeline, evidence, witness statements, etc."></textarea>
        </div>
        <div class="form-group">
            <label class="form-label" style="display:flex;align-items:center;gap:8px;cursor:pointer;font-weight:400;">
                <input type="checkbox" id="arrest-clear-warrants" checked style="accent-color:var(--accent);width:14px;height:14px;">
                <span>Automatically clear active warrants for this civilian upon arrest</span>
            </label>
        </div>
        <div class="alert alert-warn">
            <span><i class="i i-alert"></i></span>
            <span>Logging this arrest will appear permanently on the civilian's record.</span>
        </div>`,
        async () => {
            if (!_arrestPerson) { showToast('Missing', 'Search and select a suspect first.', 'error'); return; }
            const charges   = window._selectedCharges || [];
            const fine      = parseInt(document.getElementById('arrest-fine').value) || charges.reduce((s,c)=>s+(c.fine_amount||0),0);
            const jailTime  = parseInt(document.getElementById('arrest-jail').value) || 0;
            const location  = document.getElementById('arrest-location').value.trim();
            const narrative = document.getElementById('arrest-narrative').value.trim();
            const clearWarrants = document.getElementById('arrest-clear-warrants').checked;
            if (!charges.length){ showToast('Missing', 'Select at least one charge.', 'error'); return; }
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Logging...'; btn.disabled = true;
            const result = await nuiFetch('logArrest', {
                citizenid: _arrestPerson.citizenid, charges, fine, jailTime, location, narrative, clearWarrants
            });
            if (result) {
                showToast('Arrest Logged', `Arrest #${result} recorded for ${esc(_arrestPerson.name)}.`, 'success');
                closeModal(modal);
            } else {
                showToast('Error', 'Could not log arrest.', 'error');
                btn.textContent = 'Log Arrest'; btn.disabled = false;
            }
        }, 'Log Arrest', '<i class="i i-lock"></i>');

    // Initialize name search
    const ns = new NameSearch({
        container: '#arrest-person-search',
        placeholder: 'Search suspect by name…',
        onSelect: (p) => { _arrestPerson = p; },
    });
    if (prefillPerson) ns.setValue(prefillPerson);

    renderChargePicker('arrest-charge-picker', 'arrest-selected-charges');
    setTimeout(() => {
        const totalEl = document.getElementById('charge-total-display');
        if (totalEl) { totalEl.style.display = 'flex'; updateChargeTotals(); }
    }, 100);
}

// ── Citation Modal ────────────────────────────────────────────────────────
function openNewCitationModal(prefillPerson = null) {
    window._selectedCharges = [];
    let _citePerson = prefillPerson || null;

    const modal = createModal('Issue Citation', `
        <div class="form-group">
            <label class="form-label">Civilian</label>
            <div id="cite-person-search"></div>
        </div>
        <div class="form-group">
            <label class="form-label">Select Charges</label>
            <div id="cite-charge-picker"></div>
        </div>
        <div class="form-group">
            <label class="form-label">Selected Charges</label>
            <div class="selected-charges" id="cite-selected-charges">
                <span class="text-muted text-sm" style="padding:4px;">No charges selected</span>
            </div>
        </div>
        <div id="charge-total-display" class="charge-total" style="display:none;"></div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Fine Amount ($)</label>
                <input class="input font-mono" id="cite-fine" type="number" min="0" placeholder="Auto-calculated"
                       oninput="this.dataset.manual=this.value">
            </div>
            <div class="form-group">
                <label class="form-label">Location</label>
                <input class="input" id="cite-location" placeholder="Where was this citation issued?">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Notes (optional)</label>
            <input class="input" id="cite-notes" placeholder="Additional notes about this citation">
        </div>
        <div class="form-group">
            <label class="form-label" style="display:flex;align-items:center;gap:8px;cursor:pointer;font-weight:400;">
                <input type="checkbox" id="cite-autopay" style="accent-color:var(--accent);width:14px;height:14px;">
                <span>Deduct fine from player's bank account immediately</span>
            </label>
        </div>`,
        async () => {
            if (!_citePerson) { showToast('Missing', 'Search and select a civilian first.', 'error'); return; }
            const charges = window._selectedCharges || [];
            const fine    = parseInt(document.getElementById('cite-fine').value) || charges.reduce((s,c)=>s+(c.fine_amount||0),0);
            const location= document.getElementById('cite-location').value.trim();
            const notes   = document.getElementById('cite-notes').value.trim();
            const autoPay = document.getElementById('cite-autopay').checked;
            if (!charges.length){ showToast('Missing', 'Select at least one charge.', 'error'); return; }
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Issuing...'; btn.disabled = true;
            const result = await nuiFetch('issueCitation', {
                citizenid: _citePerson.citizenid, charges, fine, location, notes, autoPay
            });
            if (result) {
                showToast('Citation Issued', `Citation #${result} — ${dollarFmt(fine)} for ${esc(_citePerson.name)}`, 'success');
                closeModal(modal);
            } else {
                showToast('Error', 'Could not issue citation.', 'error');
                btn.textContent = 'Issue Citation'; btn.disabled = false;
            }
        }, 'Issue Citation', '<i class="i i-file"></i>');

    new NameSearch({
        container: '#cite-person-search',
        placeholder: 'Search civilian by name…',
        onSelect: (p) => { _citePerson = p; },
    });
    if (prefillPerson) {
        const ns = document.querySelector('#cite-person-search');
        // setValue after component init
        setTimeout(() => {
            if (ns && ns._ns) ns._ns.setValue(prefillPerson);
        }, 50);
    }

    renderChargePicker('cite-charge-picker', 'cite-selected-charges');
    setTimeout(() => {
        const totalEl = document.getElementById('charge-total-display');
        if (totalEl) { totalEl.style.display = 'flex'; updateChargeTotals(); }
    }, 100);
}

// ── Shared filter row builder ─────────────────────────────────────────────
function _filterRow(type) {
    const isA = type === 'arrest';
    const pfx = isA ? 'arrest' : 'cite';
    return `
        <div class="records-filter-row">
            <div class="search-bar" style="flex:1.4;min-width:160px;">
                <span class="search-icon"><i class="i i-user"></i></span>
                <input type="text" id="${pfx}-search-input" placeholder="Civilian name or Citizen ID…" autocomplete="off">
            </div>
            <div class="search-bar" style="flex:1;min-width:140px;">
                <span class="search-icon"><i class="i i-badge"></i></span>
                <input type="text" id="${pfx}-officer-input" placeholder="Officer name…" autocomplete="off">
            </div>
            <span class="filter-label">From</span>
            <input type="date" id="${pfx}-date-from">
            <span class="filter-label">To</span>
            <input type="date" id="${pfx}-date-to">
            <button class="btn btn-primary btn-sm" onclick="${isA?'searchArrests':'searchCitations'}()">Search</button>
            <button class="btn btn-ghost btn-sm" onclick="${isA?'clearArrestFilters':'clearCitationFilters'}()">Clear</button>
        </div>`;
}

function _getFilters(pfx) {
    return {
        query:    document.getElementById(`${pfx}-search-input`)?.value.trim() || '',
        officer:  document.getElementById(`${pfx}-officer-input`)?.value.trim() || '',
        dateFrom: document.getElementById(`${pfx}-date-from`)?.value || '',
        dateTo:   document.getElementById(`${pfx}-date-to`)?.value || '',
    };
}

function _hasActiveFilters(pfx) {
    const f = _getFilters(pfx);
    return f.query || f.officer || f.dateFrom || f.dateTo;
}

function _bindFilterKeys(pfx, searchFn) {
    [`${pfx}-search-input`, `${pfx}-officer-input`].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.addEventListener('keydown', e => { if (e.key === 'Enter') searchFn(); });
    });
}

// ── Arrests Tab ───────────────────────────────────────────────────────────
function initArrestsPanel() {
    const panel = document.getElementById('tab-arrests');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Arrest Records</div>
                <div class="panel-subtitle">Recent 25 by default — use filters to narrow results</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-danger btn-sm" onclick="openNewArrestModal()"><i class="i i-lock"></i> Log Arrest</button>
            </div>
        </div>
        ${_filterRow('arrest')}
        <div class="panel-body" id="arrests-body">
            ${Array(4).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;
    _bindFilterKeys('arrest', searchArrests);
    loadRecentArrests();
}

async function loadRecentArrests() {
    const body = document.getElementById('arrests-body');
    if (!body) return;
    const results = await nuiFetch('getRecentArrests');
    renderRecordBody(body, results, renderArrestsList, '<i class="i i-lock"></i>', 'No arrest records yet');
}

async function searchArrests() {
    const filters = _getFilters('arrest');
    if (!_hasActiveFilters('arrest')) { loadRecentArrests(); return; }
    const body = document.getElementById('arrests-body');
    body.innerHTML = Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('');
    const results = await nuiFetch('searchArrests', filters);
    renderRecordBody(body, results, renderArrestsList, '<i class="i i-lock"></i>', 'No arrest records found');
}

function clearArrestFilters() {
    ['arrest-search-input','arrest-officer-input','arrest-date-from','arrest-date-to']
        .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
    loadRecentArrests();
}

// ── Citations Tab ─────────────────────────────────────────────────────────
function initCitationsPanel() {
    const panel = document.getElementById('tab-citations');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Citations</div>
                <div class="panel-subtitle">Recent 25 by default — use filters to narrow results</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-success btn-sm" onclick="openNewCitationModal()"><i class="i i-file"></i> Issue Citation</button>
            </div>
        </div>
        ${_filterRow('citation')}
        <div class="panel-body" id="citations-body">
            ${Array(4).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;
    _bindFilterKeys('cite', searchCitations);
    loadRecentCitations();
}

async function loadRecentCitations() {
    const body = document.getElementById('citations-body');
    if (!body) return;
    const results = await nuiFetch('getRecentCitations');
    renderRecordBody(body, results, renderCitationsList, '<i class="i i-file"></i>', 'No citations yet');
}

async function searchCitations() {
    const filters = _getFilters('cite');
    if (!_hasActiveFilters('cite')) { loadRecentCitations(); return; }
    const body = document.getElementById('citations-body');
    body.innerHTML = Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('');
    const results = await nuiFetch('searchCitations', filters);
    renderRecordBody(body, results, renderCitationsList, '<i class="i i-file"></i>', 'No citations found');
}

function clearCitationFilters() {
    ['cite-search-input','cite-officer-input','cite-date-from','cite-date-to']
        .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
    loadRecentCitations();
}

function renderRecordBody(body, results, renderFn, icon, emptyMsg) {
    if (!body) return;
    if (!results || !results.length) {
        body.innerHTML = `<div class="empty-state"><div class="empty-icon">${icon}</div><div class="empty-title">${emptyMsg}</div></div>`;
        return;
    }
    body.innerHTML = renderFn(results);
}

// ── Tag System ────────────────────────────────────────────────────────────
const TAG_PRESETS = [
    'Gang Related','Drug Related','Weapon Involved','Repeat Offender',
    'Fleeing','Court Date Set','High Profile','ATL','Domestic','DUI','Warrant Issued',
];

function parseTags(raw) {
    if (!raw) return [];
    try { return typeof raw === 'string' ? JSON.parse(raw) : raw; } catch(e) { return []; }
}

function renderRecordTags(type, id, tags) {
    const list = parseTags(tags);
    return `
        <div class="record-tags-row" id="tags-row-${type}-${id}">
            ${list.map((t, i) => `
                <span class="record-user-tag">
                    ${esc(t)}<button class="tag-remove" title="Remove" onclick="removeRecordTag('${type}',${id},${i})">×</button>
                </span>`).join('')}
            <button class="btn-add-tag" onclick="openTagPicker(event,'${type}',${id})">+ Tag</button>
        </div>`;
}

function openTagPicker(e, type, id) {
    e.stopPropagation();
    document.querySelectorAll('.tag-picker-popup').forEach(el => el.remove());
    const row = document.getElementById(`tags-row-${type}-${id}`);
    const existing = parseTags(_getRecordTagsFromRow(row));
    const popup = document.createElement('div');
    popup.className = 'tag-picker-popup';
    popup.innerHTML = `
        <input type="text" id="tag-custom-input" placeholder="Type a tag or pick below…">
        <div class="tag-preset-grid">
            ${TAG_PRESETS.filter(t => !existing.includes(t)).map(t =>
                `<button class="tag-preset-btn" onclick="addRecordTagDirect('${type}',${id},'${t}')">${t}</button>`
            ).join('')}
        </div>`;
    const rect = e.target.getBoundingClientRect();
    popup.style.top  = (rect.bottom + 6) + 'px';
    popup.style.left = rect.left + 'px';
    document.body.appendChild(popup);
    const inp = popup.querySelector('#tag-custom-input');
    inp.focus();
    inp.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') {
            const val = inp.value.trim();
            if (val) addRecordTagDirect(type, id, val);
        }
        if (ev.key === 'Escape') popup.remove();
    });
    setTimeout(() => {
        document.addEventListener('click', function closeIt(ev) {
            if (!popup.contains(ev.target)) { popup.remove(); document.removeEventListener('click', closeIt); }
        }, { capture: true });
    }, 100);
}

function _getRecordTagsFromRow(row) {
    if (!row) return [];
    return [...row.querySelectorAll('.record-user-tag')].map(el => el.childNodes[0].textContent.trim());
}

function addRecordTagDirect(type, id, tag) {
    document.querySelectorAll('.tag-picker-popup').forEach(el => el.remove());
    const row = document.getElementById(`tags-row-${type}-${id}`);
    const tags = _getRecordTagsFromRow(row);
    if (!tags.includes(tag)) tags.push(tag);
    _saveAndRerenderTags(type, id, tags);
}

function removeRecordTag(type, id, idx) {
    const row = document.getElementById(`tags-row-${type}-${id}`);
    const tags = _getRecordTagsFromRow(row);
    tags.splice(idx, 1);
    _saveAndRerenderTags(type, id, tags);
}

function _saveAndRerenderTags(type, id, tags) {
    const row = document.getElementById(`tags-row-${type}-${id}`);
    if (!row) return;
    // Re-render in place
    const dummy = document.createElement('div');
    dummy.innerHTML = renderRecordTags(type, id, tags);
    row.replaceWith(dummy.firstElementChild);
    // Save to server
    nuiFetch('updateRecordTags', { type, id, tags });
}

// ── Render Helpers ────────────────────────────────────────────────────────
function renderArrestsList(list) {
    return list.map(a => {
        let charges = [];
        try { charges = typeof a.charges === 'string' ? JSON.parse(a.charges) : (a.charges || []); } catch(e){}
        const hasNarr = !!a.narrative;
        const detailId = `arrest-detail-${a.id}`;
        return `
            <div class="card mb-2">
                <div class="card-header" style="cursor:pointer;" onclick="toggleRecordDetail('${detailId}',this)">
                    <div class="card-title">
                        <div class="card-title-icon"><i class="i i-lock"></i></div>
                        ${esc(a.civilian_name || a.citizenid)}
                        ${copyBtn(a.citizenid)}
                        <span class="tag tag-red" style="margin-left:8px;">ARREST</span>
                    </div>
                    <div style="display:flex;align-items:center;gap:10px;">
                        <div style="font-size:11px;color:var(--text-muted);">#${a.id} · ${fmtDate(a.created_at)} · by ${esc(a.officer_name)}</div>
                        ${hasNarr ? '<button class="record-expand-btn">▸ Details</button>' : ''}
                    </div>
                </div>
                <div style="margin-bottom:6px;display:flex;flex-wrap:wrap;gap:4px;">
                    ${charges.map(c => chargeTypeTag(c.type||'misdemeanor') + ` <span style="font-size:11px;vertical-align:middle;">${esc(c.name||c.title)}</span>`).join(' ')}
                </div>
                <div style="display:flex;gap:16px;font-size:12px;color:var(--text-muted);">
                    ${a.fine > 0 ? `<span><i class="i i-cash"></i><strong style="color:var(--green);">${dollarFmt(a.fine)}</strong></span>` : ''}
                    ${a.jail_time > 0 ? `<span><i class="i i-clock"></i><strong style="color:var(--yellow);">${a.jail_time} min</strong></span>` : ''}
                    ${a.location ? `<span><i class="i i-map-pin"></i> ${esc(a.location)}</span>` : ''}
                </div>
                ${hasNarr ? `
                <div id="${detailId}" class="record-detail-body" style="display:none;">
                    <div style="font-size:12px;color:var(--text-secondary);line-height:1.65;white-space:pre-wrap;">${esc(a.narrative)}</div>
                </div>` : ''}
                ${renderRecordTags('arrest', a.id, a.tags)}
            </div>`;
    }).join('');
}

function toggleRecordDetail(id, headerEl) {
    const body = document.getElementById(id);
    if (!body) return;
    const open = body.style.display !== 'none';
    body.style.display = open ? 'none' : 'block';
    const btn = headerEl?.querySelector('.record-expand-btn');
    if (btn) btn.textContent = open ? '▸ Details' : '▾ Details';
}

function renderCitationsList(list) {
    const isSupervisor = MDT.officer && MDT.officer.isSupervisor;
    return list.map(c => {
        let charges = [];
        try { charges = typeof c.charges === 'string' ? JSON.parse(c.charges) : (c.charges || []); } catch(e){}
        const paid = c.paid == 1 || c.paid === true;
        return `
            <div class="card mb-2" id="citation-card-${c.id}">
                <div class="card-header">
                    <div class="card-title">
                        <div class="card-title-icon"><i class="i i-file"></i></div>
                        ${esc(c.civilian_name || c.citizenid)}
                        ${copyBtn(c.citizenid)}
                        <span class="tag tag-blue" style="margin-left:8px;">CITATION</span>
                        <span class="tag ${paid ? 'tag-green' : 'tag-red'}" style="margin-left:4px;">${paid ? 'PAID' : 'UNPAID'}</span>
                    </div>
                    <div style="display:flex;align-items:center;gap:8px;">
                        ${!paid && isSupervisor ? `<button class="btn btn-success btn-xs" onclick="event.stopPropagation();markCitationPaid(${c.id})">✓ Mark Paid</button>` : ''}
                        <div style="font-size:11px;color:var(--text-muted);">#${c.id} · ${fmtDate(c.created_at)} · by ${esc(c.officer_name)}</div>
                    </div>
                </div>
                <div style="margin-bottom:6px;display:flex;flex-wrap:wrap;gap:4px;">
                    ${charges.map(ch => chargeTypeTag(ch.type||'infraction') + ` <span style="font-size:11px;vertical-align:middle;">${esc(ch.name||ch.title)}</span>`).join(' ')}
                </div>
                <div style="display:flex;gap:16px;font-size:12px;color:var(--text-muted);">
                    ${c.fine > 0 ? `<span><i class="i i-cash"></i><strong style="color:var(--yellow);">${dollarFmt(c.fine)}</strong></span>` : ''}
                    ${c.location ? `<span><i class="i i-map-pin"></i> ${esc(c.location)}</span>` : ''}
                    ${c.notes ? `<span style="color:var(--text-secondary);">${esc(c.notes)}</span>` : ''}
                </div>
                ${renderRecordTags('citation', c.id, c.tags)}
            </div>`;
    }).join('');
}

async function markCitationPaid(id) {
    const result = await nuiFetch('markCitationPaid', id);
    if (result) {
        showToast('Citation Marked Paid', '', 'success');
        const card = document.getElementById('citation-card-' + id);
        if (card) {
            card.querySelector('.tag-red')?.classList.replace('tag-red', 'tag-green');
            const el = card.querySelector('.tag-green');
            if (el) el.textContent = 'PAID';
            card.querySelector('button[onclick*="markCitationPaid"]')?.remove();
        }
    } else {
        showToast('Error', 'Could not mark citation as paid.', 'error');
    }
}

window.clearArrestFilters   = clearArrestFilters;
window.clearCitationFilters = clearCitationFilters;
window.openNewArrestModal   = openNewArrestModal;
window.openNewCitationModal = openNewCitationModal;
window.initArrestsPanel     = initArrestsPanel;
window.initCitationsPanel   = initCitationsPanel;
window.searchArrests        = searchArrests;
window.searchCitations      = searchCitations;
window.renderArrestsList    = renderArrestsList;
window.renderCitationsList  = renderCitationsList;
window.markCitationPaid     = markCitationPaid;
window.toggleRecordDetail   = toggleRecordDetail;
window.renderRecordTags     = renderRecordTags;
window.openTagPicker        = openTagPicker;
window.addRecordTagDirect   = addRecordTagDirect;
window.removeRecordTag      = removeRecordTag;
