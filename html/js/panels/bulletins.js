function loadBulletins() {
    const panel = document.getElementById('tab-bulletins');
    const isSup = MDT.officer && MDT.officer.isSupervisor;
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Department Bulletins</div>
                <div class="panel-subtitle">Active notices and departmental communications</div>
            </div>
            <div class="panel-actions">
                ${isSup ? `<button class="btn btn-primary btn-sm" onclick="openNewBulletinModal()">+ New Bulletin</button>` : ''}
            </div>
        </div>
        <div class="panel-body" id="bulletins-body">
            ${Array(3).fill(0).map(() => `<div class="bulletin-card">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    nuiFetch('getBulletins').then(bulletins => {
        const body = document.getElementById('bulletins-body');
        if (!body) return;
        if (!bulletins || bulletins.length === 0) {
            body.innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon"><i class="i i-pin"></i></div>
                    <div class="empty-title">No active bulletins</div>
                    <div class="empty-subtitle">Check back later for department notices</div>
                </div>`;
            return;
        }
        body.innerHTML = bulletins.map(b => renderBulletinCard(b)).join('');
    });
}

function renderBulletinCard(b) {
    const isSup = MDT.officer && MDT.officer.isSupervisor;
    const priLabel = { normal: 'Notice', urgent: 'Urgent', critical: 'CRITICAL' }[b.priority] || 'Notice';
    return `
        <div class="bulletin-card bulletin-${b.priority}">
            <div class="bulletin-header">
                <div style="display:flex;align-items:center;gap:8px;flex:1;min-width:0;">
                    ${b.pinned ? '<span class="bulletin-pin" title="Pinned"><i class="i i-pin"></i></span>' : ''}
                    <span class="bulletin-priority-badge bulletin-badge-${b.priority}">${priLabel}</span>
                    <span class="bulletin-title">${esc(b.title)}</span>
                </div>
                <div style="display:flex;align-items:center;gap:6px;flex-shrink:0;">
                    <span class="bulletin-meta">${timeAgo(b.created_at)}</span>
                    ${isSup ? `
                        <button class="btn btn-ghost btn-xs" onclick="toggleBulletinPin(${b.id},${b.pinned ? 0 : 1})" title="${b.pinned ? 'Unpin' : 'Pin to top'}">
                            ${b.pinned ? 'Unpin' : '<i class="i i-pin"></i> Pin'}
                        </button>
                        <button class="btn btn-danger btn-xs" onclick="deleteBulletin(${b.id})"><i class="i i-x"></i></button>
                    ` : ''}
                </div>
            </div>
            <div class="bulletin-body">${b.body.replace(/\n/g, '<br>')}</div>
            <div class="bulletin-footer">
                <span>Posted by <strong>${esc(b.created_by_name)}</strong></span>
                ${b.expires_at ? `<span style="color:var(--yellow);">· Expires ${fmtDateShort(b.expires_at)}</span>` : ''}
            </div>
        </div>`;
}

function openNewBulletinModal() {
    const modal = createModal('New Department Bulletin', `
        <div class="form-group">
            <label class="form-label">Title</label>
            <input class="input" id="bul-title" placeholder="Brief, clear headline">
        </div>
        <div class="form-group">
            <label class="form-label">Body</label>
            <textarea class="textarea" id="bul-body" style="min-height:160px;" placeholder="Full bulletin content..."></textarea>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Priority</label>
                <select class="select" id="bul-priority">
                    <option value="normal">Normal — Standard notice</option>
                    <option value="urgent">Urgent — Needs attention</option>
                    <option value="critical">Critical — Immediate action</option>
                </select>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Auto-Expire (hours, 0 = never)</label>
                <input class="input" id="bul-expiry" type="number" min="0" value="0">
            </div>
        </div>
        <div class="form-group">
            <label style="display:flex;align-items:center;gap:10px;cursor:pointer;">
                <input type="checkbox" id="bul-pinned" style="width:16px;height:16px;accent-color:var(--accent);">
                <span class="form-label" style="margin:0;">Pin to top of bulletin board</span>
            </label>
        </div>`,
        async () => {
            const title = document.getElementById('bul-title').value.trim();
            const body = document.getElementById('bul-body').value.trim();
            if (!title || !body) { showToast('Missing Info', 'Title and body are required.', 'error'); return; }
            const id = await nuiFetch('createBulletin', {
                title,
                body,
                priority: document.getElementById('bul-priority').value,
                expiryHours: parseInt(document.getElementById('bul-expiry').value) || 0,
                pinned: document.getElementById('bul-pinned').checked,
            });
            if (id) {
                showToast('Bulletin Posted', `#${id}`, 'success');
                closeModal(modal);
                loadBulletins();
            } else {
                showToast('Error', 'Could not post bulletin. Supervisor rank required.', 'error');
            }
        }, 'Post Bulletin', '<i class="i i-pin"></i>');
}

async function deleteBulletin(id) {
    const ok = await nuiFetch('deleteBulletin', id);
    if (ok) { showToast('Bulletin Removed', '', 'success'); loadBulletins(); }
    else showToast('Error', 'Could not remove bulletin.', 'error');
}

async function toggleBulletinPin(id, pinned) {
    const ok = await nuiFetch('pinBulletin', { id, pinned: !!pinned });
    if (ok) loadBulletins();
}

window.loadBulletins       = loadBulletins;
window.renderBulletinCard  = renderBulletinCard;
window.openNewBulletinModal = openNewBulletinModal;
window.deleteBulletin      = deleteBulletin;
window.toggleBulletinPin   = toggleBulletinPin;
