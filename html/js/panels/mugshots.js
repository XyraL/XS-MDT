// XS-MDT — Mugshot Gallery Panel

var _mugshotSearch = '';

function loadMugshots() {
    const panel = document.getElementById('tab-mugshots');
    if (!panel) return;
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Mugshot Gallery</div>
                <div class="panel-subtitle">Browse all civilian mugshots on file</div>
            </div>
            <div class="panel-actions">
                <div class="search-wrap" style="width:260px">
                    <span class="search-icon">⌕</span>
                    <input class="search-input" id="mugshot-search" placeholder="Search by name..."
                        oninput="filterMugshots(this.value)" value="${_mugshotSearch}">
                </div>
                <button class="btn btn-ghost btn-sm" onclick="loadMugshots()">↻ Refresh</button>
            </div>
        </div>
        <div class="panel-body">
            <div id="mugshot-grid" class="mugshot-grid">
                <div class="empty-state"><div class="empty-icon">📷</div><div class="empty-title">Loading mugshots...</div></div>
            </div>
        </div>
    `;

    nuiFetch('getMugshots', { search: _mugshotSearch }).then(function(data) {
        renderMugshotGrid(data || []);
    });
}

function filterMugshots(q) {
    _mugshotSearch = q;
    clearTimeout(window._mugshotTimer);
    window._mugshotTimer = setTimeout(function() {
        nuiFetch('getMugshots', { search: q }).then(function(data) {
            renderMugshotGrid(data || []);
        });
    }, 400);
}

function renderMugshotGrid(items) {
    const el = document.getElementById('mugshot-grid');
    if (!el) return;
    if (!items || !items.length) {
        el.innerHTML = '<div class="empty-state"><div class="empty-icon">📷</div><div class="empty-title">No mugshots on file</div></div>';
        return;
    }
    el.innerHTML = items.map(function(c) {
        const name     = (c.firstname || '') + ' ' + (c.lastname || '');
        const arrests  = c.arrest_count || 0;
        const warrants = c.active_warrants || 0;
        const wBadge   = warrants > 0
            ? `<span class="badge" style="background:rgba(239,68,68,0.15);color:#ef4444;font-size:10px">⚖ ${warrants}w</span>`
            : '';
        return `<div class="mugshot-card" onclick="switchTab('civilians');setTimeout(function(){openCivilianProfile('${c.citizenid}')},80)">
            <div class="mugshot-img-wrap">
                <img src="${esc(c.image)}" alt="${esc(name)}" class="mugshot-img"
                     onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">
                <div class="mugshot-fallback" style="display:none">👤</div>
            </div>
            <div class="mugshot-info">
                <div class="mugshot-name">${name}</div>
                <div class="mugshot-meta">${arrests} arrest${arrests !== 1 ? 's' : ''}</div>
                ${wBadge}
            </div>
        </div>`;
    }).join('');
}

window.loadMugshots   = loadMugshots;
window.filterMugshots = filterMugshots;
