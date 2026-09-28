// ── Management ────────────────────────────────────────────────────────────
//
// How the MDT is actually wired, read live rather than from config — the
// question being asked is "is it working", and config only says what was
// intended. Plus the audit trail, which used to be a modal buried behind a
// button on the dashboard.

let _mgmtTab = 'status';
let _mgmt = null;

function loadManagement() {
    const panel = document.getElementById('tab-management');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Management</div>
                <div class="panel-subtitle">Integrations, records and the audit trail</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="mgmt-tabs">
                    <button class="seg-btn ${_mgmtTab === 'status' ? 'active' : ''}" data-tab="status">Status</button>
                    <button class="seg-btn ${_mgmtTab === 'audit' ? 'active' : ''}" data-tab="audit">Audit Trail</button>
                </div>
                <button class="btn btn-ghost btn-sm" onclick="loadManagement()"><i class="i i-refresh"></i> Refresh</button>
            </div>
        </div>
        <div class="panel-body" id="mgmt-body">${skeletonLines(6)}</div>`;

    document.getElementById('mgmt-tabs').onclick = (e) => {
        const btn = e.target.closest('.seg-btn');
        if (!btn) return;
        _mgmtTab = btn.dataset.tab;
        btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
        _mgmtTab === 'audit' ? renderAuditTrail() : renderStatus();
    };

    nuiFetch('getManagement').then(data => {
        _mgmt = data;
        _mgmtTab === 'audit' ? renderAuditTrail() : renderStatus();
    });
}

function renderStatus() {
    const body = document.getElementById('mgmt-body');
    if (!body) return;

    if (!_mgmt || !_mgmt.framework) {
        body.innerHTML = `<div class="empty-state">
            <div class="empty-icon"><i class="i i-lock"></i></div>
            <div class="empty-title">Supervisors only</div>
        </div>`;
        return;
    }

    const m = _mgmt;
    const light = (on) => `<i class="dot ${on ? 'duty-on' : 'duty-away'}"></i>`;

    const COUNT_LABELS = [
        ['officers', 'Officers'], ['cases', 'Cases'], ['incidents', 'Reports'],
        ['arrests', 'Arrests'], ['citations', 'Citations'], ['warrants', 'Active warrants'],
        ['bolos', 'Active BOLOs'], ['evidence', 'Evidence'], ['weapons', 'Firearms'],
        ['cameras', 'Cameras'], ['footage', 'Footage'], ['charges', 'Charges'],
        ['ia_open', 'IA open'], ['audit', 'Audit rows'],
    ];

    body.innerHTML = `
        <div class="mgmt-grid">
            <div class="card">
                <div class="card-header"><div class="card-title">
                    <div class="card-title-icon"><i class="i i-link"></i></div>Framework
                </div></div>
                <div class="info-grid">
                    <div class="info-row"><div class="info-key">Running</div><div class="info-val">${esc(m.framework.name || 'none detected')}</div></div>
                    <div class="info-row"><div class="info-key">Config</div><div class="info-val mono">${esc(m.framework.configured)}</div></div>
                </div>
            </div>

            <div class="card">
                <div class="card-header"><div class="card-title">
                    <div class="card-title-icon"><i class="i i-signal"></i></div>Dispatch
                </div></div>
                <div class="info-grid">
                    <div class="info-row"><div class="info-key">CAD</div><div class="info-val">${m.dispatch.provider === 'internal' ? 'This MDT' : esc(m.dispatch.provider)}</div></div>
                    <div class="info-row"><div class="info-key">Mode</div><div class="info-val mono">${esc(m.dispatch.mode)}</div></div>
                    <div class="info-row"><div class="info-key">Alerts</div><div class="info-val mono">${esc(m.dispatch.setting)}</div></div>
                </div>
                <div class="mgmt-list">
                    ${(m.dispatch.alerts || []).map(t => `
                        <div class="mgmt-row">
                            ${light(t.enabled)}
                            <span class="mono">${esc(t.id)}</span>
                            <span class="record-meta">${t.enabled ? 'receiving alerts' : t.started ? 'started, not enabled' : 'not running'}${t.resource && t.resource !== t.id ? ' (' + esc(t.resource) + ')' : ''}</span>
                        </div>`).join('') || '<div class="text-muted text-sm">No dispatch resources detected.</div>'}
                </div>
            </div>

            <div class="card">
                <div class="card-header"><div class="card-title">
                    <div class="card-title-icon"><i class="i i-box"></i></div>Resources
                </div></div>
                <div class="mgmt-list">
                    ${(m.integrations || []).map(r => `
                        <div class="mgmt-row">
                            ${light(r.started)}
                            <span class="mono">${esc(r.name)}</span>
                            <span class="record-meta">${esc(r.note)}${r.started ? '' : ' — ' + esc(r.state)}</span>
                        </div>`).join('')}
                </div>
            </div>

            <div class="card mgmt-wide">
                <div class="card-header"><div class="card-title">
                    <div class="card-title-icon"><i class="i i-roster"></i></div>Departments
                </div></div>
                <div class="mgmt-list">
                    ${(m.departments || []).map(d => `
                        <div class="mgmt-row">
                            <span class="tag tag-gray">${esc(d.short || d.key)}</span>
                            <span>${esc(d.label)}</span>
                            <span class="record-meta">${(d.jobs || []).map(esc).join(', ')} · supervisor at grade ${d.supervisorGrade} · ${d.panels} panels</span>
                        </div>`).join('')}
                </div>
            </div>

            <div class="card mgmt-wide">
                <div class="card-header"><div class="card-title">
                    <div class="card-title-icon"><i class="i i-chart"></i></div>Records
                </div></div>
                <div class="stat-grid" style="margin-bottom:0;">
                    ${COUNT_LABELS.map(([k, label]) => `
                        <div>
                            <div class="stat-label">${label}</div>
                            <div class="stat-value">${Number((m.counts || {})[k] || 0).toLocaleString()}</div>
                        </div>`).join('')}
                </div>
                <div class="modal-actions">
                    <button class="btn btn-ghost btn-sm" onclick="openPruneAudit()">Trim audit log</button>
                </div>
            </div>
        </div>`;
}

function openPruneAudit() {
    const modal = createModal('Trim Audit Log', `
        <p class="text-sm text-muted">Every action writes a row, so a busy server collects them faster than anyone reads them. This deletes rows older than the cutoff and cannot be undone.</p>
        <div class="form-group" style="margin-top:12px;">
            <label class="form-label">Keep the last</label>
            <select class="input select" id="prune-days">
                <option value="30">30 days</option>
                <option value="60">60 days</option>
                <option value="90" selected>90 days</option>
                <option value="180">180 days</option>
                <option value="365">1 year</option>
            </select>
        </div>
        <div class="form-hint">The trim itself is written to the log, so the record of it survives.</div>`,
        () => {
            nuiFetch('pruneAuditLog', document.getElementById('prune-days').value).then(res => {
                if (!res) return;
                closeModal(modal);
                showToast('Audit log trimmed', '', 'success', 2500);
                loadManagement();
            });
        }, 'Trim', '<i class="i i-trash"></i>');
}

// ── Audit trail ───────────────────────────────────────────────────────────

function renderAuditTrail() {
    const body = document.getElementById('mgmt-body');
    if (!body) return;

    body.innerHTML = `
        <div class="audit-filters">
            <input class="input" id="audit-action" placeholder="Action (ARREST_LOGGED, RANK_CHANGED…)" style="flex:1;">
            <input class="input" id="audit-officer" placeholder="Officer name" style="flex:1;">
            <input class="input mono" id="audit-from" type="date" style="width:160px;">
            <input class="input mono" id="audit-to" type="date" style="width:160px;">
            <button class="btn btn-primary btn-sm" onclick="runAuditTrail()">Search</button>
            <button class="btn btn-ghost btn-sm" onclick="clearAuditTrail()">Clear</button>
        </div>
        <div id="audit-results">${skeletonLines(5)}</div>`;

    runAuditTrail();
}

function runAuditTrail() {
    const val = id => (document.getElementById(id) || {}).value || '';
    nuiFetch('getAuditLog', {
        action: val('audit-action').trim(),
        officer: val('audit-officer').trim(),
        dateFrom: val('audit-from'),
        dateTo: val('audit-to'),
    }).then(rows => {
        const out = document.getElementById('audit-results');
        if (!out) return;

        if (!rows || !rows.length) {
            out.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-clipboard"></i></div>
                <div class="empty-title">Nothing logged for that</div>
            </div>`;
            return;
        }

        out.innerHTML = `
            <div class="audit-table">
                <div class="audit-head">
                    <span>When</span><span>Action</span><span>Officer</span><span>Subject</span><span>Detail</span>
                </div>
                ${rows.map(r => `
                    <div class="audit-row">
                        <span class="mono">${fmtDate(r.created_at)}</span>
                        <span class="audit-action">${esc(r.action)}</span>
                        <span>${esc(r.officer_name)}${r.citizenid ? ` <span class="mono audit-cid">${esc(r.citizenid)}</span>` : ''}</span>
                        <span class="mono">${esc(r.target_name || r.target_citizenid || '—')}</span>
                        <span class="audit-detail">${esc(r.details || '')}</span>
                    </div>`).join('')}
            </div>
            <div class="penal-count">${rows.length} row${rows.length === 1 ? '' : 's'}${rows.length === 200 ? ' — narrow the search to see older ones' : ''}</div>`;
    });
}

function clearAuditTrail() {
    ['audit-action', 'audit-officer', 'audit-from', 'audit-to'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });
    runAuditTrail();
}

window.loadManagement = loadManagement;
window.openPruneAudit = openPruneAudit;
window.runAuditTrail = runAuditTrail;
window.clearAuditTrail = clearAuditTrail;
