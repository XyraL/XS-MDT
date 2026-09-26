// ── Shared Charge Picker ──────────────────────────────────────────────────
function renderChargePicker(pickerId, selectedId) {
    window._selectedCharges = [];
    const container = document.getElementById(pickerId);
    if (!container) return;

    // Not loaded yet, so fetch once. An empty result is an answer, not a reason
    // to ask again — `if (data)` is true for [], so the old version set an
    // empty list, re-entered, saw it was empty and asked the server forever.
    if (!MDT.penalCodes) {
        container.innerHTML = `<div class="skeleton skeleton-line w-full" style="height:110px;"></div>`;
        nuiFetch('getPenalCodes').then(data => {
            MDT.penalCodes = Array.isArray(data) ? data : [];
            renderChargePicker(pickerId, selectedId);
        });
        return;
    }

    if (!MDT.penalCodes.length) {
        container.innerHTML = `<div class="empty-state">
            <div class="empty-icon"><i class="i i-scale"></i></div>
            <div class="empty-title">No charges on file</div>
            <div class="empty-subtitle">Nothing to pick from yet. A supervisor can add codes in Penal Codes.</div>
        </div>`;
        return;
    }

    container.innerHTML = `
        <div class="charge-picker">
            <div class="charge-picker-search">
                <input id="${pickerId}-search" placeholder="Filter charges by name or code..." autocomplete="off">
            </div>
            <div class="charge-picker-list" id="${pickerId}-list">
                ${MDT.penalCodes.map(cat => `
                    <div class="charge-category">
                        <div class="charge-cat-header" onclick="toggleChargeCategory(this)">
                            <span>${cat.category}</span>
                            <span class="charge-cat-count">${cat.codes.length} charges<i class="i i-chevron"></i></span>
                        </div>
                        <div class="charge-list">
                            ${cat.codes.map(code => `
                                <div class="charge-item" data-code='${JSON.stringify(code).replace(/'/g,"&#39;")}'
                                     onclick="toggleCharge(this,'${pickerId}','${selectedId}')">
                                    <input type="checkbox" onclick="event.stopPropagation()">
                                    <span class="charge-code">${code.code}</span>
                                    <span class="charge-name">${esc(code.name)}</span>
                                    <span class="charge-type-pill tag-${code.type==='felony'?'red':code.type==='misdemeanor'?'yellow':'blue'} tag"
                                          style="font-size:9px;">${code.type[0].toUpperCase()}</span>
                                    ${code.fine_amount > 0 ? `<span class="charge-fine">${dollarFmt(code.fine_amount)}</span>` : ''}
                                </div>`).join('')}
                        </div>
                    </div>`).join('')}
            </div>
        </div>`;

    // Live filter
    document.getElementById(`${pickerId}-search`).addEventListener('input', (e) => {
        const q = e.target.value.toLowerCase().trim();
        container.querySelectorAll('.charge-item').forEach(item => {
            const matches = !q || item.textContent.toLowerCase().includes(q);
            item.style.display = matches ? '' : 'none';
        });
        container.querySelectorAll('.charge-category').forEach(cat => {
            const hasVisible = [...cat.querySelectorAll('.charge-item')].some(i => i.style.display !== 'none');
            cat.style.display = hasVisible ? '' : 'none';
            if (q && hasVisible) cat.querySelector('.charge-list').classList.add('open');
        });
    });
}

function toggleChargeCategory(header) {
    header.nextElementSibling.classList.toggle("open");
    header.classList.toggle("open");
}

function toggleCharge(itemEl, pickerId, selectedId) {
    const checkbox = itemEl.querySelector('input[type=checkbox]');
    checkbox.checked = !checkbox.checked;
    itemEl.classList.toggle('selected', checkbox.checked);
    const code = JSON.parse(itemEl.dataset.code);
    if (checkbox.checked) {
        if (!window._selectedCharges) window._selectedCharges = [];
        if (!window._selectedCharges.find(c => c.id === code.id)) window._selectedCharges.push(code);
    } else {
        window._selectedCharges = (window._selectedCharges || []).filter(c => c.id !== code.id);
    }
    updateSelectedChargesDisplay(selectedId);
    updateChargeTotals();
}

function updateSelectedChargesDisplay(selectedId) {
    const el = document.getElementById(selectedId);
    if (!el) return;
    const charges = window._selectedCharges || [];
    if (charges.length === 0) {
        el.innerHTML = '<span class="text-muted text-sm" style="padding:4px;">No charges selected</span>';
        return;
    }
    el.innerHTML = charges.map(c => `
        <span class="selected-charge-tag">
            <span>${c.code}</span>
            <button onclick="removeCharge(${c.id},'${selectedId}')">×</button>
        </span>`).join('');
}

function updateChargeTotals() {
    const totalEl = document.getElementById('charge-total-display');
    if (!totalEl) return;
    const total = (window._selectedCharges || []).reduce((s, c) => s + (c.fine_amount || 0), 0);
    const jail = (window._selectedCharges || []).reduce((s, c) => s + (c.jail_time || 0), 0);
    totalEl.innerHTML = `
        <span class="charge-total-label">Total Fine</span>
        <span class="charge-total-value">${dollarFmt(total)}</span>
        ${jail > 0 ? `<span class="text-muted text-xs">· ${jail} min jail</span>` : ''}`;

    // Auto-fill fine inputs if they exist
    ['arrest-fine','cite-fine'].forEach(id => {
        const inp = document.getElementById(id);
        if (inp && total > 0 && !inp.dataset.manual) inp.value = total;
    });
}

function removeCharge(codeId, selectedId) {
    window._selectedCharges = (window._selectedCharges || []).filter(c => c.id !== codeId);
    updateSelectedChargesDisplay(selectedId);
    updateChargeTotals();
    document.querySelectorAll('.charge-item').forEach(item => {
        try {
            const code = JSON.parse(item.dataset.code || '{}');
            if (code.id === codeId) {
                item.querySelector('input').checked = false;
                item.classList.remove('selected');
            }
        } catch(e) {}
    });
}

// ── Penal Code Browser + Admin Editor ────────────────────────────────────
let _penalClass = 'all';

function loadPenalCodes() {
    const isAdmin = MDT.officer && MDT.officer.isSupervisor;
    const panel = document.getElementById('tab-penal');
    _penalClass = 'all';

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Penal Codes</div>
                <div class="panel-subtitle">Charge reference${isAdmin ? ' · admin mode' : ''}</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="penal-class">
                    <button class="seg-btn active" data-class="all">All</button>
                    <button class="seg-btn" data-class="felony">Felony</button>
                    <button class="seg-btn" data-class="misdemeanor">Misd.</button>
                    <button class="seg-btn" data-class="infraction">Infraction</button>
                </div>
                <div class="search-bar" style="width:230px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="penal-filter" placeholder="Search code or charge...">
                </div>
                ${isAdmin ? `<button class="btn btn-primary btn-sm" onclick="openAddPenalCodeModal()">Add Code</button>` : ''}
            </div>
        </div>
        <div class="panel-body" id="penal-body">${skeletonLines(6)}</div>`;

    const matches = (c, q) =>
        (_penalClass === 'all' || c.type === _penalClass) &&
        (!q || c.name.toLowerCase().includes(q) || c.code.toLowerCase().includes(q)
            || (c.description || '').toLowerCase().includes(q));

    // One grid for the whole book, with the titles as rows inside it. Drawing a
    // table per title gave every title its own column widths.
    const render = () => {
        const body = document.getElementById('penal-body');
        if (!body) return;

        const q = (document.getElementById('penal-filter')?.value || '').toLowerCase().trim();
        const all = MDT.penalCodes || [];
        const titles = all
            .map(cat => ({ ...cat, codes: cat.codes.filter(c => matches(c, q)) }))
            .filter(cat => cat.codes.length);

        const shown = titles.reduce((n, t) => n + t.codes.length, 0);
        const total = all.reduce((n, t) => n + t.codes.length, 0);

        if (!shown) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-scale"></i></div>
                <div class="empty-title">Nothing matched</div>
                <div class="empty-subtitle">Try a code, a charge name, or clear the class filter.</div>
            </div>`;
            return;
        }

        const row = c => `
            <div class="penal-row">
                <span class="penal-code">${esc(c.code)}</span>
                <span class="penal-name">${esc(c.name)}</span>
                <span>${chargeTypeTag(c.type)}</span>
                <span class="penal-fine ta-right">${c.fine_amount > 0 ? dollarFmt(c.fine_amount) : '—'}</span>
                <span class="penal-jail ta-right">${c.jail_time > 0 ? c.jail_time + ' min' : '—'}</span>
                ${isAdmin ? `<span class="penal-actions">
                    <button class="btn btn-ghost btn-xs"
                        onclick="openEditPenalCodeModal(${JSON.stringify(c).replace(/"/g, '&quot;')})">Edit</button>
                    <button class="btn btn-ghost btn-xs btn-danger"
                        onclick="deletePenalCode(${c.id},'${c.name.replace(/'/g, "\\'")}')"><i class="i i-trash"></i></button>
                </span>` : ''}
            </div>`;

        body.innerHTML = `
            <div class="penal-book${isAdmin ? ' admin' : ''}">
                <div class="penal-head">
                    <span>Code</span><span>Charge</span><span>Class</span>
                    <span class="ta-right">Fine</span><span class="ta-right">Jail</span>
                    ${isAdmin ? '<span></span>' : ''}
                </div>
                ${titles.map(cat => `
                    <div class="penal-title">${esc(cat.category)}<span class="penal-title-count">${cat.codes.length}</span></div>
                    ${cat.codes.map(row).join('')}`).join('')}
            </div>
            <div class="penal-count">${shown === total ? `${total} charges` : `${shown} of ${total} charges`}</div>`;
    };

    nuiFetch('getPenalCodes').then(data => {
        if (!data) return;
        MDT.penalCodes = data;
        render();

        document.getElementById('penal-filter')?.addEventListener('input', render);

        document.getElementById('penal-class')?.addEventListener('click', (e) => {
            const btn = e.target.closest('.seg-btn');
            if (!btn) return;
            _penalClass = btn.dataset.class;
            btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
            render();
        });
    });
}

function _penalCodeModalBody(code = {}) {
    // The seven titles of the book. A server that writes its own charges can
    // still use any category it likes; this list is only what the dropdown
    // offers.
    const CATEGORIES = [
        'Offences Against Persons', 'Offences Against Property',
        'Offences Against Public Order', 'Controlled Substances',
        'Vehicle and Traffic', 'Weapons and Explosives',
        'Offences Against the Government',
    ];
    return `
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Category</label>
                <select class="input" id="pc-category">
                    ${CATEGORIES.map(c => `<option value="${c}" ${code.category===c?'selected':''}>${c}</option>`).join('')}
                    ${code.category && !CATEGORIES.includes(code.category) ? `<option value="${code.category}" selected>${code.category}</option>` : ''}
                </select>
            </div>
            <div class="form-group" style="width:120px;">
                <label class="form-label">Code</label>
                <input class="input font-mono" id="pc-code" value="${code.code||''}" placeholder="PC 5.01 A">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Charge Name</label>
            <input class="input" id="pc-name" value="${esc(code.name || '')}" placeholder="e.g. Speeding">
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Type</label>
                <select class="input" id="pc-type">
                    <option value="infraction"  ${code.type==='infraction' ?'selected':''}>Infraction</option>
                    <option value="misdemeanor" ${code.type==='misdemeanor'?'selected':''}>Misdemeanor</option>
                    <option value="felony"      ${code.type==='felony'     ?'selected':''}>Felony</option>
                </select>
            </div>
            <div class="form-group" style="width:140px;">
                <label class="form-label">Fine ($)</label>
                <input class="input font-mono" id="pc-fine" type="number" min="0" value="${code.fine_amount||0}">
            </div>
            <div class="form-group" style="width:140px;">
                <label class="form-label">Jail (min)</label>
                <input class="input font-mono" id="pc-jail" type="number" min="0" value="${code.jail_time||0}">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Description <span class="text-muted">(optional)</span></label>
            <textarea class="textarea" id="pc-desc" style="min-height:80px;" placeholder="Brief description of this charge...">${esc(code.description||'')}</textarea>
        </div>`;
}

function _getPenalFormData() {
    return {
        category   : document.getElementById('pc-category').value,
        code       : document.getElementById('pc-code').value.trim(),
        name       : document.getElementById('pc-name').value.trim(),
        type       : document.getElementById('pc-type').value,
        fine_amount: parseInt(document.getElementById('pc-fine').value) || 0,
        jail_time  : parseInt(document.getElementById('pc-jail').value) || 0,
        description: document.getElementById('pc-desc').value.trim(),
    };
}

function openAddPenalCodeModal() {
    const modal = createModal('Add Penal Code', _penalCodeModalBody(),
        async () => {
            const data = _getPenalFormData();
            if (!data.code || !data.name) { showToast('Missing', 'Code and name are required.', 'error'); return; }
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Saving…'; btn.disabled = true;
            const ok = await nuiFetch('addPenalCode', data);
            if (ok) {
                showToast('Code Added', `${data.code} — ${esc(data.name)}`, 'success');
                closeModal(modal);
                MDT.penalCodes = null; // bust cache
                loadPenalCodes();
            } else {
                showToast('Error', 'Could not add penal code. Check your grade.', 'error');
                btn.textContent = 'Add Code'; btn.disabled = false;
            }
        }, 'Add Code', '<i class="i i-scale"></i>');
}

function openEditPenalCodeModal(code) {
    const modal = createModal('Edit Penal Code', _penalCodeModalBody(code),
        async () => {
            const data = { ..._getPenalFormData(), id: code.id };
            if (!data.code || !data.name) { showToast('Missing', 'Code and name are required.', 'error'); return; }
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Saving…'; btn.disabled = true;
            const ok = await nuiFetch('updatePenalCode', data);
            if (ok) {
                showToast('Code Updated', `${data.code} — ${esc(data.name)}`, 'success');
                closeModal(modal);
                MDT.penalCodes = null;
                loadPenalCodes();
            } else {
                showToast('Error', 'Could not update penal code.', 'error');
                btn.textContent = 'Save Changes'; btn.disabled = false;
            }
        }, 'Save Changes', '<i class="i i-scale"></i>');
}

async function deletePenalCode(id, name) {
    const modal = createModal('Delete Penal Code', `
        <div class="alert alert-danger">
            <span><i class="i i-alert"></i></span>
            <div>
                <strong>Delete "${name}"?</strong><br>
                <span style="font-size:12px;">This will permanently remove the code from all charge pickers.
                Existing records that used this code are not affected.</span>
            </div>
        </div>`,
        async () => {
            const ok = await nuiFetch('deletePenalCode', id);
            if (ok) {
                showToast('Code Deleted', name, 'success');
                closeModal(modal);
                MDT.penalCodes = null;
                loadPenalCodes();
            } else {
                showToast('Error', 'Could not delete penal code.', 'error');
            }
        }, 'Delete', '<i class="i i-trash"></i>');
}

window.renderChargePicker = renderChargePicker;
window.toggleChargeCategory = toggleChargeCategory;
window.toggleCharge = toggleCharge;
window.removeCharge = removeCharge;
window.updateChargeTotals = updateChargeTotals;
window.updateSelectedChargesDisplay = updateSelectedChargesDisplay;
window.loadPenalCodes = loadPenalCodes;
window.openAddPenalCodeModal  = openAddPenalCodeModal;
window.openEditPenalCodeModal = openEditPenalCodeModal;
window.deletePenalCode        = deletePenalCode;
