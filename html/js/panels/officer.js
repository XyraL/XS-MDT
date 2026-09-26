// Does the current player's department include this panel?
const hasPanel = p => (MDT.panels || []).includes(p);

// The dashboard is shared across departments, so its stat cards and quick
// actions are assembled from whichever panels the player actually has.
function statCard(cls, icon, label, id, trend) {
    return `
        <div class="stat-card ${cls}">
            <div class="stat-icon">${icon}</div>
            <div class="stat-label">${label}</div>
            <div class="stat-value" id="${id}"><div class="skeleton skeleton-line w-1/4" style="height:30px;"></div></div>
            <div class="stat-trend" ${id === 'stat-calls' ? 'id="stat-calls-sub"' : ''}>${trend}</div>
        </div>`;
}

function dashStatCards() {
    const cards = [];
    if (hasPanel('cad')) cards.push(statCard('accent', '<i class="i i-radio"></i>', 'Active Calls', 'stat-calls', 'Loading...'));

    if (hasPanel('warrants')) cards.push(statCard('red', '<i class="i i-scale"></i>', 'Active Warrants', 'stat-warrants', 'Currently open'));
    if (hasPanel('bolos'))    cards.push(statCard('yellow', '<i class="i i-signal"></i>', 'Active BOLOs', 'stat-bolos', 'Person &amp; vehicle'));

    if (hasPanel('pcr')) {
        cards.push(statCard('green', '<i class="i i-cross"></i>', 'PCRs Today', 'stat-pcrs', 'Reports filed'));
        cards.push(statCard('yellow', '<i class="i i-clipboard"></i>', 'Open Reports', 'stat-open-pcrs', 'Awaiting completion'));
    }

    if (hasPanel('fireincidents')) {
        cards.push(statCard('red', '<i class="i i-flame"></i>', 'Incidents Today', 'stat-fires', 'Runs logged'));
        cards.push(statCard('yellow', '<i class="i i-hazard"></i>', 'Active Hazmat', 'stat-hazmat', 'Not yet contained'));
    }

    cards.push(statCard('green', '<i class="i i-roster"></i>', 'Units On Duty', 'stat-officers', 'Currently active'));
    return cards.join('');
}

function dashQuickActions() {
    const btn = (panel, cls, icon, label, fn) =>
        hasPanel(panel)
            ? `<button class="btn ${cls} btn-sm w-full" style="justify-content:flex-start;" onclick="${fn}">${icon} ${label}</button>`
            : '';

    return [
        btn('civilians', 'btn-ghost', '<i class="i i-search"></i>', 'Lookup Civilian', "switchTab('civilians')"),
        btn('vehicles',  'btn-ghost', '<i class="i i-car"></i>', 'Plate Lookup',    "switchTab('vehicles')"),
        btn('map',       'btn-ghost', '<i class="i i-map"></i>', 'Live Map',        "switchTab('map')"),
        btn('cad',       'btn-ghost', '<i class="i i-radio"></i>', 'CAD Dispatch',    "switchTab('cad')"),

        btn('warrants',  'btn-ghost', '<i class="i i-scale"></i>', 'Warrants',  "switchTab('warrants')"),
        btn('bolos',     'btn-ghost', '<i class="i i-signal"></i>', 'BOLOs',     "switchTab('bolos')"),
        btn('incidents', 'btn-ghost', '<i class="i i-clipboard"></i>', 'Reports',   "switchTab('incidents')"),
        btn('citations', 'btn-success', '<i class="i i-file"></i>', 'Issue Citation', 'openNewCitationModal()'),
        btn('arrests',   'btn-danger',  '<i class="i i-lock"></i>', 'Log Arrest',     'openNewArrestModal()'),

        btn('medhistory', 'btn-ghost',  '<i class="i i-heart"></i>', 'Medical Records', "switchTab('medhistory')"),
        btn('narclog',    'btn-ghost',  '<i class="i i-pill"></i>', 'Narcotics Log',   "switchTab('narclog')"),
        btn('pcr',        'btn-success', '<i class="i i-cross"></i>', 'New PCR',         'openNewPCR()'),

        btn('apparatus',     'btn-ghost',  '<i class="i i-truck"></i>', 'Apparatus',     "switchTab('apparatus')"),
        btn('hazmat',        'btn-ghost',  '<i class="i i-hazard"></i>', 'Hazmat',        "switchTab('hazmat')"),
        btn('fireincidents', 'btn-danger', '<i class="i i-flame"></i>', 'New Incident',  'openNewFireIncident()'),
    ].filter(Boolean).join('');
}

// Fill the department-specific stat cards. Each block is skipped unless its
// panel is present, so no callback is fired that would be refused anyway.
function loadDashDepartmentStats() {
    const set = (id, val) => {
        const el = document.getElementById(id);
        if (el) el.textContent = val;
    };

    if (hasPanel('warrants')) {
        nuiFetch('getWarrants', { filter: 'active' }).then(d => {
            if (d) { set('stat-warrants', d.length); updateWarrantBadge(d.length); }
        });
    }
    if (hasPanel('bolos')) {
        nuiFetch('getBolos').then(d => {
            if (d) { set('stat-bolos', d.length); MDT.activeBolos = d; updateBoloBadge(); }
        });
    }
    if (hasPanel('pcr')) {
        nuiFetch('getEMSStats').then(d => {
            if (!d) return;
            set('stat-pcrs', d.pcrs_today);
            set('stat-open-pcrs', d.open_pcrs);
        });
    }
    if (hasPanel('fireincidents')) {
        nuiFetch('getFireStats').then(d => {
            if (!d) return;
            set('stat-fires', d.incidents_today);
            set('stat-hazmat', d.active_hazmat);
            updateHazmatBadge(d.active_hazmat);
        });
    }
}

// The stats card. Totals and the daily chart for every officer; the
// per-officer leaderboard only arrives for supervisors, and the server decides
// that — the panel just renders whatever it was given.
function loadDeptStats(range) {
    ['7', '30'].forEach(r => {
        document.getElementById('dash-range-' + r)?.classList.toggle('active', String(range) === r);
    });

    nuiFetch('getDepartmentStats', { range }).then(stats => {
        const el = document.getElementById('sup-stats-body');
        if (!el || !stats) return;

        const rankClass = i => ['gold', 'silver', 'bronze'][i] || '';

        // Plain divs, no chart library. Bars sit on one baseline with the day
        // labels in their own row underneath, so a flat week reads as flat
        // instead of as bars floating at random heights.
        const series = stats.series || [];
        const peak = Math.max(1, ...series.map(d => d.arrests + d.citations));

        const bars = series.map(d => {
            const total = d.arrests + d.citations;
            const h = total ? Math.max(3, Math.round((total / peak) * 56)) : 0;
            const arrests = total ? Math.round((d.arrests / total) * h) : 0;
            const plural = (n, word) => n + ' ' + word + (n === 1 ? '' : 's');
            return `
                <div class="chart-col" title="${d.day} — ${plural(d.arrests, 'arrest')}, ${plural(d.citations, 'citation')}">
                    <div class="chart-bar${total ? '' : ' empty'}" style="height:${total ? h : 2}px;">
                        <div class="chart-bar-arrests" style="height:${arrests}px;"></div>
                    </div>
                </div>`;
        }).join('');

        const days = series.map(d => {
            const day = new Date(d.day + 'T00:00:00');
            const label = series.length <= 7
                ? day.toLocaleDateString('en-US', { weekday: 'short' })
                : (day.getDate() === 1 || d === series[0] ? day.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '');
            return `<div class="chart-day">${label}</div>`;
        }).join('');

        el.innerHTML = `
            <div class="sup-stat-row">
                <div class="sup-stat-cell">
                    <div class="sup-stat-num">${stats.arrests}</div>
                    <div class="sup-stat-lbl">Arrests</div>
                    <div class="sup-stat-sub">${stats.arrests_today} today</div>
                </div>
                <div class="sup-stat-cell">
                    <div class="sup-stat-num">${stats.citations}</div>
                    <div class="sup-stat-lbl">Citations</div>
                    <div class="sup-stat-sub">${stats.citations_today} today</div>
                </div>
                <div class="sup-stat-cell">
                    <div class="sup-stat-num">${stats.incidents}</div>
                    <div class="sup-stat-lbl">Reports</div>
                    <div class="sup-stat-sub">last ${stats.range} days</div>
                </div>
                <div class="sup-stat-cell">
                    <div class="sup-stat-num">${stats.warrants_active}</div>
                    <div class="sup-stat-lbl">Warrants</div>
                    <div class="sup-stat-sub">active now</div>
                </div>
                <div class="sup-stat-cell">
                    <div class="sup-stat-num">${dollarFmt(stats.fines)}</div>
                    <div class="sup-stat-lbl">Fines Issued</div>
                    <div class="sup-stat-sub">arrests + citations</div>
                </div>
            </div>

            <div class="stat-chart">
                <div class="chart-plot">${bars}</div>
                <div class="chart-days">${days}</div>
                <div class="chart-key">
                    <span><i class="key-swatch arrests"></i>Arrests</span>
                    <span><i class="key-swatch citations"></i>Citations</span>
                    <span class="chart-peak">peak ${peak}/day</span>
                </div>
            </div>

            ${stats.isSupervisor ? (stats.top_officers && stats.top_officers.length ? `
            <div style="font-size:10px;font-weight:800;letter-spacing:.08em;color:var(--text-muted);text-transform:uppercase;margin-bottom:8px;">
                <i class="i i-trophy"></i> Top Arresting Officers <span class="tag tag-purple" style="font-size:9px;margin-left:4px;">Supervisor</span>
            </div>
            ${stats.top_officers.map((o, i) => `
                <div class="top-officer-row">
                    <div class="top-officer-rank ${rankClass(i)}">${i + 1}</div>
                    <div style="flex:1;font-size:12.5px;font-weight:600;">${esc(o.officer_name)}</div>
                    <div style="font-size:11px;color:var(--text-muted);">${o.arrest_count} arrest${o.arrest_count !== 1 ? 's' : ''}</div>
                    <div style="width:80px;background:var(--bg-base);border-radius:4px;height:5px;overflow:hidden;margin-left:8px;">
                        <div style="background:var(--accent);height:100%;width:${Math.min(100, Math.round(o.arrest_count / stats.top_officers[0].arrest_count * 100))}%;border-radius:4px;"></div>
                    </div>
                </div>`).join('')}` : '<div class="text-muted text-sm">No arrests in this range</div>') : ''}`;
    });
}

function renderDashboard() {
    const panel = document.getElementById('tab-dashboard');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Dashboard</div>
                <div class="panel-subtitle">Overview & quick actions</div>
            </div>
            <div class="panel-actions">
                <span class="text-xs text-muted">Press <span class="kbd">Ctrl+1–0</span> to switch tabs</span>
                ${MDT.officer && MDT.officer.isSupervisor ? `<button class="btn btn-ghost btn-sm" onclick="openAuditLogViewer()"><i class="i i-clipboard"></i> Audit Log</button>` : ''}
                <button class="btn btn-ghost btn-sm" onclick="openBodyCamLog()"><i class="i i-video"></i> Body Cam</button>
                <button class="btn btn-ghost btn-sm" onclick="renderDashboard()"><i class="i i-refresh"></i> Refresh</button>
            </div>
        </div>
        <div class="panel-body">
            <div class="stat-grid" id="dash-stats">
                ${dashStatCards()}
            </div>

            ${hasPanel('arrests') ? `
            <div class="card" id="dash-sup-stats" style="margin-bottom:16px;">
                <div class="card-header">
                    <div class="card-title">
                        <div class="card-title-icon"><i class="i i-chart"></i></div>
                        Department Statistics
                    </div>
                    <div style="display:flex;gap:6px;">
                        <button class="btn btn-ghost btn-sm active" id="dash-range-7" onclick="loadDeptStats(7)">7 days</button>
                        <button class="btn btn-ghost btn-sm" id="dash-range-30" onclick="loadDeptStats(30)">30 days</button>
                    </div>
                </div>
                <div id="sup-stats-body">${skeletonLines(3)}</div>
            </div>` : ''}

            <div style="display:grid;grid-template-columns:1fr 1.4fr;gap:16px;">
                <!-- Left column -->
                <div>
                    <div class="card accent-border">
                        <div class="card-header">
                            <div class="card-title">
                                <div class="card-title-icon"><i class="i i-badge"></i></div>
                                My Profile
                            </div>
                            <button class="btn btn-ghost btn-sm" onclick="openProfileEditor()">Edit</button>
                        </div>
                        <div id="dash-profile-body">${skeletonLines(4)}</div>
                    </div>

                    <div class="card">
                        <div class="card-header">
                            <div class="card-title">
                                <div class="card-title-icon"><i class="i i-bolt"></i></div>
                                Quick Actions
                            </div>
                        </div>
                        <div style="display:grid;grid-template-columns:1fr 1fr;gap:7px;">
                            ${dashQuickActions()}
                        </div>
                    </div>
                </div>

                <!-- Right column -->
                <div style="display:flex;flex-direction:column;gap:14px;">
                    <div class="card" style="flex:1;">
                        <div class="card-header">
                            <div class="card-title">
                                <div class="card-title-icon"><i class="i i-radio"></i></div>
                                Active CAD Calls
                            </div>
                            <button class="btn btn-ghost btn-sm" onclick="switchTab('cad')">View All →</button>
                        </div>
                        <div id="dash-recent-calls">${skeletonCard(3)}</div>
                    </div>
                    <div class="card">
                        <div class="card-header">
                            <div class="card-title">
                                <div class="card-title-icon"><i class="i i-bolt"></i></div>
                                Department Activity
                            </div>
                        </div>
                        <div id="dash-activity-feed">${skeletonLines(4)}</div>
                    </div>
                </div>
            </div>
        </div>`;

    // Load stats async
    nuiFetch('getActiveCalls').then(calls => {
        if (!calls) return;
        MDT.activeCalls = calls;
        updateCADBadge();
        document.getElementById('stat-calls').textContent = calls.length;
        document.getElementById('stat-calls-sub').textContent =
            calls.filter(c => c.status === 'pending').length + ' pending response';

        const callsEl = document.getElementById('dash-recent-calls');
        if (calls.length === 0) {
            callsEl.innerHTML = `<div class="empty-state"><div class="empty-icon"><i class="i i-radio"></i></div><div class="empty-title">No active calls</div><div class="empty-subtitle">All clear</div></div>`;
        } else {
            callsEl.innerHTML = calls.slice(0, 6).map(c => `
                <div class="call-card status-${c.status}" onclick="switchTab('cad')" style="margin-bottom:8px;">
                    <div class="call-card-top">
                        <span class="call-number">${c.call_number}</span>
                        <span class="tag tag-${statusColor(c.status)}" style="margin-left:auto;">${c.status.toUpperCase()}</span>
                    </div>
                    <div class="call-type">${c.call_type || c.type}</div>
                    <div class="call-location"><i class="i i-map-pin"></i> ${esc(c.location)}</div>
                    <div class="call-units">
                        ${(c.units||[]).map(u=>`<span class="call-unit-chip">${esc(u.name.split(' ')[0])}</span>`).join('')}
                        ${(!c.units||c.units.length===0)?'<span class="text-xs text-muted">No units assigned</span>':''}
                    </div>
                </div>`).join('');
        }
    });

    loadDashDepartmentStats();

    nuiFetch('getMyOfficerProfile').then(profile => {
        if (!profile) return;
        MDT.officer = { ...MDT.officer, ...profile };
        updateOfficerCard(MDT.officer);
        document.getElementById('dash-profile-body').innerHTML = `
            <div class="info-grid">
                <div class="info-row">
                    <div class="info-key">Badge</div>
                    <div class="info-val font-mono">#${profile.badge || '—'}</div>
                </div>
                <div class="info-row">
                    <div class="info-key">Callsign</div>
                    <div class="info-val font-mono">${profile.callsign || 'Not set'}</div>
                </div>
                <div class="info-row">
                    <div class="info-key">Rank</div>
                    <div class="info-val">${profile.rank || '—'}</div>
                </div>
                <div class="info-row">
                    <div class="info-key">Department</div>
                    <div class="info-val">${profile.department || '—'}</div>
                </div>
            </div>
            <div style="margin-top:12px;display:flex;align-items:center;gap:10px;flex-wrap:wrap;">
                <span class="status-badge ${profile.onduty ? 'on-duty' : 'off-duty'}">${profile.onduty ? 'On Duty' : 'Off Duty'}</span>
                ${renderStatusPicker(profile.status || MDT.officer?.status || '10-8')}
            </div>`;
    });

    nuiFetch('getRoster').then(roster => {
        if (roster) document.getElementById('stat-officers').textContent = roster.length;
    });

    // Department stats — arrests and citations only mean something for police.
    if (hasPanel('arrests')) loadDeptStats(7);

    // Department activity feed — merge recent arrests + citations (police only)
    if (!hasPanel('arrests')) {
        const feedEl = document.getElementById('dash-activity-feed');
        if (feedEl) feedEl.innerHTML = '<div class="text-xs text-muted">No activity feed for this department.</div>';
    } else Promise.all([
        nuiFetch('getRecentArrests'),
        nuiFetch('getRecentCitations'),
    ]).then(([arrests, citations]) => {
        const feedEl = document.getElementById('dash-activity-feed');
        if (!feedEl) return;
        const items = [];
        (arrests || []).slice(0, 6).forEach(a => items.push({
            ts: a.created_at, icon: '<i class="i i-lock"></i>', iconBg: 'rgba(239,68,68,.12)',
            title: (a.civilian_name || a.citizenid) + ' — Arrested',
            sub: 'by ' + a.officer_name + (a.charges?.length ? ' · ' + a.charges.length + ' charge(s)' : ''),
        }));
        (citations || []).slice(0, 6).forEach(c => items.push({
            ts: c.created_at, icon: '<i class="i i-file"></i>', iconBg: 'rgba(99,102,241,.12)',
            title: (c.civilian_name || c.citizenid) + ' — Citation',
            sub: 'by ' + c.officer_name + (c.fine ? ' · ' + dollarFmt(c.fine) : ''),
        }));
        items.sort((a, b) => new Date(b.ts) - new Date(a.ts));
        if (!items.length) {
            feedEl.innerHTML = '<div class="text-muted text-sm" style="padding:8px 4px;">No recent activity</div>';
            return;
        }
        feedEl.innerHTML = items.slice(0, 8).map(i => `
            <div class="activity-item">
                <div class="activity-icon" style="background:${i.iconBg};">${i.icon}</div>
                <div class="activity-meta">
                    <div class="activity-title">${esc(i.title)}</div>
                    <div class="activity-sub">${i.sub}</div>
                </div>
                <div class="activity-time">${timeAgo(i.ts)}</div>
            </div>`).join('');
    });
}

// The roster moved to panels/personnel.js in 3.0, where it grew officer
// files. getStatusConfig and the status vocabulary still live in app.js.

// ── Profile Editor ────────────────────────────────────────────────────────
function openProfileEditor() {
    nuiFetch('getMyOfficerProfile').then(profile => {
        if (!profile) return;
        const modal = createModal('Edit My Profile', `
            <div class="form-row">
                <div class="form-group">
                    <label class="form-label">Badge Number</label>
                    <input class="input" id="edit-badge" value="${profile.badge || ''}" placeholder="e.g. 4821">
                </div>
                <div class="form-group">
                    <label class="form-label">Callsign</label>
                    <input class="input" id="edit-callsign" value="${profile.callsign || ''}" placeholder="e.g. Adam-12">
                </div>
            </div>
            <div class="alert alert-info">
                <span><i class="i i-info"></i></span>
                <span>Badge number must be unique. Your callsign is visible to all on-duty officers.</span>
            </div>`,
            async () => {
                const badge    = document.getElementById('edit-badge').value.trim();
                const callsign = document.getElementById('edit-callsign').value.trim();
                const btn = modal.querySelector('#modal-confirm');
                btn.textContent = 'Saving...'; btn.disabled = true;
                const result = await nuiFetch('updateOfficerProfile', { badge, callsign });
                if (result) {
                    showToast('Profile Updated', 'Badge & callsign saved.', 'success');
                    closeModal(modal);
                    MDT.officer.badge = badge; MDT.officer.callsign = callsign;
                    updateOfficerCard(MDT.officer);
                    if (MDT.activeTab === 'dashboard') renderDashboard();
                } else {
                    showToast('Error', 'Badge may already be in use.', 'error');
                    btn.textContent = 'Save'; btn.disabled = false;
                }
            }, 'Save Changes', '<i class="i i-badge"></i>');
    });
}

// ── Body Camera Log ───────────────────────────────────────────────────────
async function openBodyCamLog(targetCitizenid) {
    const ACTION_LABELS = {
        MDT_OPENED:       { icon: '<i class="i i-folder"></i>', label: 'MDT Opened',        color: 'var(--text-muted)' },
        ARREST_LOGGED:    { icon: '<i class="i i-lock"></i>', label: 'Arrest Logged',     color: 'var(--red)' },
        CITATION_ISSUED:  { icon: '<i class="i i-file"></i>', label: 'Citation Issued',   color: 'var(--yellow)' },
        WARRANT_ISSUED:   { icon: '<i class="i i-scale"></i>',  label: 'Warrant Issued',    color: 'var(--red)' },
        WARRANT_CLEARED:  { icon: '✓',  label: 'Warrant Cleared',   color: 'var(--green)' },
        CALL_RESPONDED:   { icon: '<i class="i i-radio"></i>', label: 'Responded to Call', color: 'var(--accent-2)' },
        PANIC_BUTTON:     { icon: '<i class="i i-siren"></i>', label: 'Panic Button',      color: 'var(--red)' },
    };

    const titleSuffix = targetCitizenid ? ' (Officer Log)' : ' (My Log)';
    const modal = createModal('<i class="i i-video"></i> Body Camera Log' + titleSuffix, `
        <div id="bodycam-log-body" style="max-height:460px;overflow-y:auto;">
            ${skeletonLines(5)}
        </div>`, () => closeModal(modal), 'Close', '<i class="i i-video"></i>');

    modal.querySelector('#modal-cancel').style.display = 'none';

    const logs = await nuiFetch('getBodyCamLog', targetCitizenid || null);
    const body = document.getElementById('bodycam-log-body');
    if (!body) return;

    if (!logs || !logs.length) {
        body.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="i i-video"></i></div><div class="empty-title">No body cam entries</div></div>';
        return;
    }

    body.innerHTML = `
        <div class="data-table-wrap">
            <table class="data-table">
                <thead><tr><th>Time</th><th>Action</th><th>Details</th></tr></thead>
                <tbody>
                    ${logs.map(e => {
                        const cfg = ACTION_LABELS[e.action] || { icon: '•', label: e.action, color: 'var(--text-muted)' };
                        return `
                        <tr>
                            <td class="font-mono text-xs text-muted" style="white-space:nowrap;">${fmtDate(e.created_at)}</td>
                            <td style="white-space:nowrap;">
                                <span style="color:${cfg.color};font-weight:700;font-size:12px;">
                                    ${cfg.icon} ${esc(cfg.label)}
                                </span>
                            </td>
                            <td class="text-sm text-secondary">${e.details || '—'}</td>
                        </tr>`;
                    }).join('')}
                </tbody>
            </table>
        </div>`;
}

// ── Audit Log Viewer (supervisor only) ────────────────────────────────────
const AUDIT_ACTIONS = [
    'Arrest Logged','Citation Issued','Warrant Issued','Warrant Cleared',
    'BOLO Created','BOLO Cleared','Incident Created','Incident Updated',
    'CAD Call Created','Call Status Updated','Bulletin Posted',
    'Penal Code Added','Penal Code Deleted',
];
const AUDIT_ICONS = {
    'Arrest Logged':'<i class="i i-lock"></i>','Citation Issued':'<i class="i i-file"></i>','Warrant Issued':'<i class="i i-scale"></i>',
    'Warrant Cleared':'✓','BOLO Created':'<i class="i i-signal"></i>','BOLO Cleared':'✓',
    'Incident Created':'<i class="i i-clipboard"></i>','CAD Call Created':'<i class="i i-radio"></i>','Bulletin Posted':'<i class="i i-pin"></i>',
};

function openAuditLogViewer() {
    const modal = createModal('Audit Log', `
        <div class="records-filter-row" style="margin-bottom:14px;">
            <select class="select" id="audit-action" style="min-width:160px;">
                <option value="">All Actions</option>
                ${AUDIT_ACTIONS.map(a => `<option value="${a}">${a}</option>`).join('')}
            </select>
            <input class="input" id="audit-officer" placeholder="Officer name..." style="flex:1;">
            <span class="filter-label">From</span>
            <input class="input" id="audit-from" type="date" style="flex:0.8;">
            <span class="filter-label">To</span>
            <input class="input" id="audit-to" type="date" style="flex:0.8;">
            <button class="btn btn-ghost btn-sm" onclick="runAuditSearch()">Search</button>
            <button class="btn btn-ghost btn-sm" onclick="clearAuditSearch()">Clear</button>
        </div>
        <div id="audit-results" style="max-height:460px;overflow-y:auto;">${skeletonLines(5)}</div>`,
        () => closeModal(modal), 'Close', '<i class="i i-clipboard"></i>');
    modal.querySelector('#modal-cancel').style.display = 'none';
    setTimeout(runAuditSearch, 60);
}

async function runAuditSearch() {
    const body = document.getElementById('audit-results');
    if (body) body.innerHTML = skeletonLines(4);
    const logs = await nuiFetch('getAuditLog', {
        action:   document.getElementById('audit-action')?.value || '',
        officer:  document.getElementById('audit-officer')?.value.trim() || '',
        dateFrom: document.getElementById('audit-from')?.value || '',
        dateTo:   document.getElementById('audit-to')?.value || '',
    });
    if (!body) return;
    if (!logs || !logs.length) {
        body.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="i i-clipboard"></i></div><div class="empty-title">No entries found</div></div>';
        return;
    }
    body.innerHTML = `
        <div class="data-table-wrap">
            <table class="data-table">
                <thead><tr><th>Time</th><th>Action</th><th>Officer</th><th>Details</th></tr></thead>
                <tbody>
                    ${logs.map(e => `
                    <tr>
                        <td class="font-mono text-xs text-muted" style="white-space:nowrap;">${fmtDate(e.created_at)}</td>
                        <td style="white-space:nowrap;font-weight:700;font-size:12px;">
                            ${AUDIT_ICONS[e.action] || '•'} ${e.action}
                        </td>
                        <td class="text-sm font-bold">${esc(e.officer_name)}</td>
                        <td class="text-sm text-secondary">${e.details || '—'}</td>
                    </tr>`).join('')}
                </tbody>
            </table>
        </div>`;
}

function clearAuditSearch() {
    ['audit-action','audit-officer','audit-from','audit-to'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });
    runAuditSearch();
}

window.loadDeptStats = loadDeptStats;
window.renderDashboard   = renderDashboard;
window.openProfileEditor = openProfileEditor;
window.openBodyCamLog    = openBodyCamLog;
window.openAuditLogViewer = openAuditLogViewer;
window.runAuditSearch    = runAuditSearch;
window.clearAuditSearch  = clearAuditSearch;
