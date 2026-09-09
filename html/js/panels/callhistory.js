// XS-MDT — Callout History Panel

function loadCallHistory() {
    const panel = document.getElementById('tab-callhistory');
    if (!panel) return;
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Callout History</div>
                <div class="panel-subtitle">Search all past dispatch calls</div>
            </div>
        </div>
        <div class="panel-body">
            <div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px;align-items:center">
                <input class="input" id="ch-type"   placeholder="Call type..."  style="width:160px">
                <select class="select" id="ch-status" style="width:140px">
                    <option value="">All Statuses</option>
                    <option value="completed">Completed</option>
                    <option value="cancelled">Cancelled</option>
                    <option value="active">Active</option>
                    <option value="enroute">En Route</option>
                    <option value="onscene">On Scene</option>
                </select>
                <input class="input" id="ch-from" type="date" style="width:145px">
                <input class="input" id="ch-to"   type="date" style="width:145px">
                <button class="btn btn-primary btn-sm" onclick="searchCallHistory()">Search</button>
                <button class="btn btn-ghost btn-sm" onclick="clearCallHistoryFilters()">Clear</button>
            </div>
            <div id="ch-results">
                <div class="empty-state"><div class="empty-icon">◷</div><div class="empty-title">Enter filters and press Search</div></div>
            </div>
        </div>
    `;
}

async function searchCallHistory() {
    const el = document.getElementById('ch-results');
    if (el) el.innerHTML = '<div class="empty-state"><div class="empty-icon">◷</div><div class="empty-title">Searching...</div></div>';

    const data = await nuiFetch('searchCallHistory', {
        callType: (document.getElementById('ch-type')   || {}).value || '',
        status:   (document.getElementById('ch-status') || {}).value || '',
        dateFrom: (document.getElementById('ch-from')   || {}).value || '',
        dateTo:   (document.getElementById('ch-to')     || {}).value || '',
    });

    renderCallHistory(data || []);
}

function clearCallHistoryFilters() {
    ['ch-type','ch-status','ch-from','ch-to'].forEach(function(id) {
        var el = document.getElementById(id);
        if (el) el.value = '';
    });
    var res = document.getElementById('ch-results');
    if (res) res.innerHTML = '<div class="empty-state"><div class="empty-icon">◷</div><div class="empty-title">Enter filters and press Search</div></div>';
}

function renderCallHistory(calls) {
    var el = document.getElementById('ch-results');
    if (!el) return;
    if (!calls.length) {
        el.innerHTML = '<div class="empty-state"><div class="empty-icon">◷</div><div class="empty-title">No calls found</div></div>';
        return;
    }
    var STATUS_COLORS = {
        completed: '#22c55e', cancelled: '#6b7280', active: '#3b82f6',
        enroute: '#f59e0b', onscene: '#8b5cf6', pending: '#94a3b8',
    };
    el.innerHTML = `
        <table class="data-table">
            <thead>
                <tr>
                    <th>Call #</th>
                    <th>Type</th>
                    <th>Location</th>
                    <th>Status</th>
                    <th>Caller</th>
                    <th>Date</th>
                </tr>
            </thead>
            <tbody>
                ${calls.map(function(c) {
                    var color = STATUS_COLORS[c.status] || '#94a3b8';
                    var date  = c.created_at ? new Date(c.created_at).toLocaleDateString([], { month:'short', day:'numeric', year:'numeric' }) : 'N/A';
                    return `<tr>
                        <td style="font-family:monospace;font-size:12px">${c.call_number || '—'}</td>
                        <td>${c.call_type || '—'}</td>
                        <td style="color:var(--text-muted);font-size:12px">${esc(c.location || '—')}</td>
                        <td><span class="badge" style="background:${color}22;color:${color}">${c.status || '—'}</span></td>
                        <td style="color:var(--text-muted);font-size:12px">${c.caller_name || '—'}</td>
                        <td style="color:var(--text-muted);font-size:12px">${date}</td>
                    </tr>`;
                }).join('')}
            </tbody>
        </table>
        <div style="padding:8px 4px;color:var(--text-muted);font-size:12px">${calls.length} result${calls.length !== 1 ? 's' : ''}</div>
    `;
}

window.loadCallHistory         = loadCallHistory;
window.searchCallHistory       = searchCallHistory;
window.clearCallHistoryFilters = clearCallHistoryFilters;
