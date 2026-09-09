// XSMDT — Shift Log Panel

var _shiftClockedIn = false;
var _shiftStartTime = null;
var _shiftTimer     = null;

function loadShiftLog() {
    const panel = document.getElementById('tab-shiftlog');
    if (!panel) return;

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Shift Log</div>
                <div class="panel-subtitle">Track officer duty hours</div>
            </div>
        </div>
        <div class="panel-body">
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px">
                <div class="card">
                    <div class="card-header"><div class="card-title">My Shift</div></div>
                    <div class="card-body" style="text-align:center;padding:20px 16px">
                        <div id="shift-status-label" style="font-size:13px;color:var(--text-muted);margin-bottom:8px">Loading...</div>
                        <div id="shift-timer" style="font-size:28px;font-weight:700;font-family:monospace;color:var(--accent-2);margin-bottom:16px">00:00:00</div>
                        <button id="shift-btn" class="btn btn-primary" onclick="toggleShift()" style="width:140px">Loading...</button>
                    </div>
                </div>
                <div class="card">
                    <div class="card-header">
                        <div class="card-title">Weekly Hours</div>
                        <button class="btn btn-ghost btn-sm" onclick="loadWeeklyHours()">↻</button>
                    </div>
                    <div class="card-body" id="weekly-hours-list" style="padding:8px 16px">
                        <div class="empty-state" style="padding:20px 0"><div class="empty-icon" style="font-size:20px">⏱</div><div class="empty-title">Loading...</div></div>
                    </div>
                </div>
            </div>

            <div class="card">
                <div class="card-header">
                    <div class="card-title">Shift History</div>
                    <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
                        <input class="input" id="sh-officer" placeholder="Officer name..." style="width:160px">
                        <input class="input" id="sh-from" type="date" style="width:140px">
                        <input class="input" id="sh-to"   type="date" style="width:140px">
                        <button class="btn btn-primary btn-sm" onclick="searchShiftHistory()">Search</button>
                    </div>
                </div>
                <div id="shift-history-table">
                    <div class="empty-state"><div class="empty-icon">⏱</div><div class="empty-title">Enter filters to search history</div></div>
                </div>
            </div>
        </div>
    `;

    _loadShiftStatus();
    loadWeeklyHours();
}

async function _loadShiftStatus() {
    const data = await nuiFetch('getShiftStatus', {});
    if (!data) return;
    _shiftClockedIn = data.clockedIn || false;
    _updateShiftUI();
    if (_shiftClockedIn) {
        _shiftStartTime = Date.now();
        _startShiftTimer();
    }
}

function _updateShiftUI() {
    const label = document.getElementById('shift-status-label');
    const btn   = document.getElementById('shift-btn');
    if (!label || !btn) return;
    if (_shiftClockedIn) {
        label.textContent = '● Currently On Duty';
        label.style.color = '#22c55e';
        btn.textContent   = 'Clock Out';
        btn.className     = 'btn btn-danger';
    } else {
        label.textContent = '○ Off Duty';
        label.style.color = 'var(--text-muted)';
        btn.textContent   = 'Clock In';
        btn.className     = 'btn btn-success';
        const timerEl = document.getElementById('shift-timer');
        if (timerEl) timerEl.textContent = '00:00:00';
    }
    btn.style.width = '140px';
}

function _startShiftTimer() {
    if (_shiftTimer) clearInterval(_shiftTimer);
    _shiftTimer = setInterval(function() {
        const el = document.getElementById('shift-timer');
        if (!el) { clearInterval(_shiftTimer); _shiftTimer = null; return; }
        const secs = Math.floor((Date.now() - (_shiftStartTime || Date.now())) / 1000);
        const h    = String(Math.floor(secs / 3600)).padStart(2, '0');
        const m    = String(Math.floor((secs % 3600) / 60)).padStart(2, '0');
        const s    = String(secs % 60).padStart(2, '0');
        el.textContent = h + ':' + m + ':' + s;
    }, 1000);
}

async function toggleShift() {
    const btn = document.getElementById('shift-btn');
    if (btn) btn.disabled = true;

    if (_shiftClockedIn) {
        const res = await nuiFetch('clockOut', {});
        if (res && res.ok) {
            _shiftClockedIn = false;
            if (_shiftTimer) { clearInterval(_shiftTimer); _shiftTimer = null; }
            _shiftStartTime = null;
            const dur = res.durationMinutes || 0;
            showToast('Clocked Out', 'Shift ended — ' + Math.floor(dur / 60) + 'h ' + (dur % 60) + 'm on duty', 'success');
        } else {
            showToast('Error', (res && res.error) || 'Could not clock out', 'error');
        }
    } else {
        const res = await nuiFetch('clockIn', {});
        if (res && res.ok) {
            _shiftClockedIn = true;
            _shiftStartTime = Date.now();
            _startShiftTimer();
            showToast('Clocked In', 'Shift started', 'success');
        } else {
            showToast('Error', (res && res.error) || 'Could not clock in', 'error');
        }
    }

    _updateShiftUI();
    if (btn) btn.disabled = false;
    loadWeeklyHours();
}

async function loadWeeklyHours() {
    const el = document.getElementById('weekly-hours-list');
    if (!el) return;
    const data = await nuiFetch('getWeeklyHours', {});
    if (!data || !data.length) {
        el.innerHTML = '<div style="color:var(--text-muted);font-size:13px;padding:4px 0">No shifts logged this week</div>';
        return;
    }
    el.innerHTML = data.map(function(r) {
        const total = r.total_minutes || 0;
        const hrs  = Math.floor(total / 60);
        const mins = total % 60;
        return `<div style="display:flex;align-items:center;gap:8px;padding:5px 0;border-bottom:1px solid var(--border)">
            <span style="flex:1;font-size:13px">${esc(r.officer_name)}</span>
            <span style="color:var(--text-muted);font-size:12px">${hrs}h ${mins}m</span>
        </div>`;
    }).join('');
}

async function searchShiftHistory() {
    const el = document.getElementById('shift-history-table');
    if (el) el.innerHTML = '<div class="empty-state"><div class="empty-icon">⏱</div><div class="empty-title">Searching...</div></div>';

    const data = await nuiFetch('getShiftHistory', {
        officerName: (document.getElementById('sh-officer') || {}).value || '',
        dateFrom:    (document.getElementById('sh-from')    || {}).value || '',
        dateTo:      (document.getElementById('sh-to')      || {}).value || '',
    });

    renderShiftHistory(data || []);
}

function renderShiftHistory(rows) {
    const el = document.getElementById('shift-history-table');
    if (!el) return;
    if (!rows.length) {
        el.innerHTML = '<div class="empty-state"><div class="empty-icon">⏱</div><div class="empty-title">No shifts found</div></div>';
        return;
    }
    el.innerHTML = `
        <table class="data-table">
            <thead>
                <tr>
                    <th>Officer</th>
                    <th>Badge</th>
                    <th>Clock In</th>
                    <th>Clock Out</th>
                    <th>Duration</th>
                </tr>
            </thead>
            <tbody>
                ${rows.map(function(r) {
                    const dur  = r.duration_minutes != null
                        ? Math.floor(r.duration_minutes / 60) + 'h ' + (r.duration_minutes % 60) + 'm'
                        : '<span style="color:var(--accent-2)">● Active</span>';
                    const cin  = r.clock_in  ? new Date(r.clock_in).toLocaleString([], { month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' }) : '—';
                    const cout = r.clock_out ? new Date(r.clock_out).toLocaleString([], { month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' }) : '—';
                    return `<tr>
                        <td>${esc(r.officer_name)}</td>
                        <td style="color:var(--text-muted);font-size:12px">${r.badge || '—'}</td>
                        <td style="color:var(--text-muted);font-size:12px">${cin}</td>
                        <td style="color:var(--text-muted);font-size:12px">${cout}</td>
                        <td>${dur}</td>
                    </tr>`;
                }).join('')}
            </tbody>
        </table>
    `;
}

window.loadShiftLog       = loadShiftLog;
window.toggleShift        = toggleShift;
window.loadWeeklyHours    = loadWeeklyHours;
window.searchShiftHistory = searchShiftHistory;
