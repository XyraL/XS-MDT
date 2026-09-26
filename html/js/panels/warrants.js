function loadWarrants(filter = 'active') {
    const panel = document.getElementById('tab-warrants');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Warrants</div>
                <div class="panel-subtitle">Manage and track active warrants</div>
            </div>
            <div class="panel-actions">
                <div style="display:flex;background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden;">
                    <button class="btn btn-sm ${filter==='active'?'btn-primary':'btn-ghost'}" style="border-radius:0;border:none;"
                            onclick="loadWarrants('active')">Active</button>
                    <button class="btn btn-sm ${filter==='cleared'?'btn-primary':'btn-ghost'}" style="border-radius:0;border:none;border-left:1px solid var(--border);"
                            onclick="loadWarrants('cleared')">Cleared</button>
                    <button class="btn btn-sm ${filter==='expired'?'btn-primary':'btn-ghost'}" style="border-radius:0;border:none;border-left:1px solid var(--border);"
                            onclick="loadWarrants('expired')">Expired</button>
                </div>
                <button class="btn btn-primary btn-sm" onclick="openIssueWarrantModal()">+ Issue Warrant</button>
            </div>
        </div>
        <div class="panel-body" id="warrants-body">
            <div class="data-table-wrap">${skeletonLines(5)}</div>
        </div>`;

    nuiFetch('getWarrants', { filter }).then(warrants => {
        const body = document.getElementById('warrants-body');
        if (!body) return;
        if (!warrants || warrants.length === 0) {
            body.innerHTML = `<div class="empty-state"><div class="empty-icon"><i class="i i-scale"></i></div><div class="empty-title">No ${filter} warrants</div></div>`;
            return;
        }
        body.innerHTML = `
            <div class="data-table-wrap">
                <table class="data-table">
                    <thead>
                        <tr><th>Subject</th><th>DOB</th><th>Charges</th><th>Issued By</th><th>Issued</th><th>Expires</th><th>Status</th><th></th></tr>
                    </thead>
                    <tbody>
                        ${warrants.map(w => {
                            const isExpiringSoon = w.expires_at && w.status === 'active' &&
                                (new Date(w.expires_at) - Date.now()) < 86400000 * 3;
                            return `
                            <tr onclick="openCivilianProfile('${w.citizenid}');switchTab('civilians');">
                                <td>
                                    <div class="font-bold">${w.subject_name || w.citizenid}</div>
                                    <div class="text-xs font-mono text-muted">${w.citizenid}</div>
                                </td>
                                <td class="font-mono text-sm">${w.dob || '—'}</td>
                                <td>
                                    <div style="display:flex;flex-wrap:wrap;gap:3px;">
                                        ${(w.charges||[]).slice(0,3).map(c=>`<span class="tag tag-red" style="font-size:9.5px;">${c.code}</span>`).join('')}
                                        ${(w.charges||[]).length > 3 ? `<span class="tag tag-gray">+${w.charges.length-3}</span>` : ''}
                                    </div>
                                </td>
                                <td class="text-secondary">${w.issued_by_name}</td>
                                <td class="font-mono text-sm text-muted">${fmtDateShort(w.created_at)}</td>
                                <td class="font-mono text-sm ${isExpiringSoon?'text-red font-bold':'text-muted'}">
                                    ${w.expires_at ? fmtDateShort(w.expires_at) + (isExpiringSoon?' <i class="i i-alert"></i>':'') : '—'}
                                </td>
                                <td><span class="tag ${w.status==='active'?'tag-red':w.status==='expired'?'tag-orange':'tag-green'}">${w.status.toUpperCase()}</span></td>
                                <td>
                                    <div style="display:flex;gap:5px;">
                                        ${w.status==='active' ? `<button class="btn btn-success btn-xs" onclick="event.stopPropagation();clearWarrantRow(${w.id})">Clear</button>` : ''}
                                        <button class="btn btn-ghost btn-xs" onclick="event.stopPropagation();openCivilianProfile('${w.citizenid}');switchTab('civilians');">View</button>
                                    </div>
                                </td>
                            </tr>`;}).join('')}
                    </tbody>
                </table>
            </div>`;
        if (filter === 'active') updateWarrantBadge(warrants.length);
    });
}

async function clearWarrantRow(warrantId) {
    const result = await nuiFetch('clearWarrant', warrantId);
    if (result) { showToast('Warrant Cleared', '', 'success'); loadWarrants(); }
    else showToast('Error', 'Could not clear warrant.', 'error');
}

function openIssueWarrantModal(prefillPerson = null) {
    window._selectedCharges = [];
    let _warrantPerson = prefillPerson || null;

    const modal = createModal('Issue Warrant', `
        <div class="form-group">
            <label class="form-label">Subject</label>
            <div id="warrant-person-search"></div>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Select Charges</label>
                <div id="warrant-charge-picker"></div>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Selected Charges</label>
            <div class="selected-charges" id="warrant-selected-charges">
                <span class="text-muted text-sm" style="padding:4px;">No charges selected</span>
            </div>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Description / Probable Cause</label>
                <textarea class="textarea" id="warrant-desc" placeholder="Describe the reason for this warrant, evidence gathered, and any relevant details..."></textarea>
            </div>
            <div class="form-group" style="flex:0 0 160px;">
                <label class="form-label">Warrant Expires In</label>
                <select class="select" id="warrant-expiry">
                    <option value="0">No Expiry</option>
                    <option value="7">7 Days</option>
                    <option value="14">14 Days</option>
                    <option value="30">30 Days</option>
                    <option value="60">60 Days</option>
                    <option value="90">90 Days</option>
                </select>
            </div>
        </div>
        <div class="alert alert-warn">
            <span><i class="i i-alert"></i></span>
            <span>Issuing a warrant will notify all on-duty officers and appear on the subject's record.</span>
        </div>`,
        async () => {
            if (!_warrantPerson) { showToast('Missing Info', 'Search and select a subject first.', 'error'); return; }
            const charges = window._selectedCharges || [];
            const desc = document.getElementById('warrant-desc').value.trim();
            const expiryDays = parseInt(document.getElementById('warrant-expiry').value) || 0;
            if (!charges.length) { showToast('Missing Info', 'Select at least one charge.', 'error'); return; }
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Issuing...'; btn.disabled = true;
            const result = await nuiFetch('issueWarrant', {
                citizenid: _warrantPerson.citizenid, charges, description: desc, expiryDays
            });
            if (result) {
                showToast('Warrant Issued', `Warrant #${result} on ${esc(_warrantPerson.name)} — all units notified.`, 'success');
                closeModal(modal);
                loadWarrants();
            } else {
                showToast('Error', 'Could not issue warrant.', 'error');
                btn.textContent = 'Issue Warrant'; btn.disabled = false;
            }
        }, 'Issue Warrant', '<i class="i i-scale"></i>');

    new NameSearch({
        container: '#warrant-person-search',
        placeholder: 'Search subject by name…',
        onSelect: (p) => { _warrantPerson = p; },
    });
    if (prefillPerson) {
        setTimeout(() => {
            const ns = document.querySelector('#warrant-person-search')?._ns;
            if (ns) ns.setValue(prefillPerson);
        }, 50);
    }

    renderChargePicker('warrant-charge-picker', 'warrant-selected-charges');
}

window.loadWarrants = loadWarrants;
window.clearWarrantRow = clearWarrantRow;
window.openIssueWarrantModal = openIssueWarrantModal;
