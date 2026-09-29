function loadBolos(focusId = null) {
    const panel = document.getElementById('tab-bolos');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">BOLOs</div>
                <div class="panel-subtitle">Be On Lookout — active alerts</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadBolos()"><i class="i i-refresh"></i> Refresh</button>
                <button class="btn btn-primary btn-sm" onclick="openIssueBolo()">+ Issue BOLO</button>
            </div>
        </div>
        <div class="panel-body" id="bolos-body">
            ${Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    nuiFetch('getBolos').then(bolos => {
        MDT.activeBolos = bolos || [];
        updateBoloBadge();
        const body = document.getElementById('bolos-body');
        if (!body) return;
        if (!bolos || bolos.length === 0) {
            body.innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon"><i class="i i-signal"></i></div>
                    <div class="empty-title">No active BOLOs</div>
                    <div class="empty-subtitle">All clear — no lookouts in effect</div>
                </div>`;
            return;
        }

        const persons  = bolos.filter(b => b.type === 'person');
        const vehicles = bolos.filter(b => b.type === 'vehicle');

        let html = '';
        if (vehicles.length) {
            html += `<div class="text-xs uppercase font-black text-muted mb-2" style="letter-spacing:.1em;"><i class="i i-car"></i> Vehicle BOLOs (${vehicles.length})</div>`;
            html += vehicles.map(b => boloCard(b)).join('');
        }
        if (persons.length) {
            if (vehicles.length) html += '<div class="divider"></div>';
            html += `<div class="text-xs uppercase font-black text-muted mb-2" style="letter-spacing:.1em;"><i class="i i-user"></i> Person BOLOs (${persons.length})</div>`;
            html += persons.map(b => boloCard(b)).join('');
        }
        body.innerHTML = html;

        if (focusId) {
            const card = document.getElementById(`bolo-card-${Number(focusId)}`);
            if (card) {
                card.scrollIntoView({ block: 'center' });
                card.classList.add('flash');
            } else {
                showToast('BOLO cleared', 'That BOLO is no longer active.', 'info', 3000);
            }
        }
    });
}

function boloCard(b) {
    const isVehicle = b.type === 'vehicle';
    const accentColor = isVehicle ? 'var(--orange)' : 'var(--purple)';
    const tagClass = isVehicle ? 'tag-orange' : 'tag-purple';
    return `
        <div class="card" id="bolo-card-${Number(b.id)}" style="border-left:3px solid ${accentColor};margin-bottom:10px;transition:var(--transition);"
             onmouseenter="this.style.borderColor='${accentColor}'" onmouseleave="this.style.borderColor='${accentColor}'">
            <div class="card-header" style="margin-bottom:8px;">
                <div style="display:flex;align-items:center;gap:8px;flex:1;flex-wrap:wrap;">
                    <span class="tag ${tagClass}">${isVehicle ? '<i class="i i-car"></i> VEHICLE' : '<i class="i i-user"></i> PERSON'}</span>
                    ${b.plate ? `<span class="font-mono font-bold" style="font-size:15px;color:var(--orange);">${esc(b.plate)}</span>` : ''}
                    <span class="text-xs text-muted font-mono">${timeAgo(b.created_at)}</span>
                </div>
                <button class="btn btn-danger btn-xs" onclick="clearBoloAndRefresh(${b.id})">Clear BOLO</button>
            </div>
            <div style="font-size:13.5px;font-weight:600;color:var(--text-primary);margin-bottom:5px;">${esc(b.description)}</div>
            <div style="font-size:12.5px;color:var(--text-secondary);margin-bottom:8px;">
                <strong style="color:var(--text-muted);font-size:10px;text-transform:uppercase;letter-spacing:.06em;">Reason: </strong>${esc(b.reason)}
            </div>
            <div style="font-size:11px;color:var(--text-muted);display:flex;align-items:center;gap:12px;">
                <span>Issued by: <strong class="text-secondary">${b.issued_by_name}</strong></span>
                <span>${fmtDateShort(b.created_at)}</span>
            </div>
        </div>`;
}

async function clearBoloAndRefresh(boloId) {
    const result = await nuiFetch('clearBolo', boloId);
    if (result) { showToast('BOLO Cleared', '', 'success'); loadBolos(); }
    else showToast('Error', 'Could not clear BOLO.', 'error');
}

function openIssueBolo(prefillType = 'person', prefillPlate = '') {
    const modal = createModal('Issue BOLO', `
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">BOLO Type</label>
                <select class="select" id="bolo-type" onchange="toggleBoloPlate(this.value)">
                    <option value="person" ${prefillType==='person'?'selected':''}><i class="i i-user"></i> Person</option>
                    <option value="vehicle" ${prefillType==='vehicle'?'selected':''}><i class="i i-car"></i> Vehicle</option>
                </select>
            </div>
            <div class="form-group" id="bolo-plate-group" style="${prefillType!=='vehicle'?'opacity:.4;pointer-events:none;':''}">
                <label class="form-label">License Plate</label>
                <input class="input" id="bolo-plate" value="${prefillPlate}"
                       placeholder="e.g. ABC1234" style="text-transform:uppercase;">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Description</label>
            <textarea class="textarea" id="bolo-desc" style="min-height:140px;"
                placeholder="Physical description or vehicle details: color, make, model, clothing, distinguishing features, last known location..."></textarea>
        </div>
        <div class="form-group">
            <label class="form-label">Reason / Wanted For</label>
            <input class="input" id="bolo-reason" placeholder="e.g. Armed and dangerous, Felony warrant, Stolen vehicle, Suspect in shooting">
        </div>
        <div class="alert alert-warn">
            <span><i class="i i-signal"></i></span>
            <span>This BOLO will be broadcast to all on-duty officers immediately.</span>
        </div>`,
        async () => {
            const type   = document.getElementById('bolo-type').value;
            const plate  = document.getElementById('bolo-plate').value.trim().toUpperCase();
            const desc   = document.getElementById('bolo-desc').value.trim();
            const reason = document.getElementById('bolo-reason').value.trim();
            if (!desc)   { showToast('Missing Info', 'Description is required.', 'error'); return; }
            if (!reason) { showToast('Missing Info', 'Reason is required.', 'error'); return; }
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Broadcasting...'; btn.disabled = true;
            const result = await nuiFetch('issueBolo', { type, plate: plate || null, description: desc, reason });
            if (result) {
                showToast('BOLO Issued', 'All on-duty officers notified.', 'success');
                closeModal(modal);
                loadBolos();
            } else {
                showToast('Error', 'Could not issue BOLO.', 'error');
                btn.textContent = 'Issue BOLO'; btn.disabled = false;
            }
        }, 'Issue BOLO', '<i class="i i-signal"></i>');
}

function toggleBoloPlate(type) {
    const group = document.getElementById('bolo-plate-group');
    if (group) {
        group.style.opacity    = type === 'vehicle' ? '1' : '0.4';
        group.style.pointerEvents = type === 'vehicle' ? 'all' : 'none';
    }
}

window.loadBolos = loadBolos;
window.clearBoloAndRefresh = clearBoloAndRefresh;
window.openIssueBolo = openIssueBolo;
window.toggleBoloPlate = toggleBoloPlate;
