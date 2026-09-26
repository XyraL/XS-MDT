// ── Roster and officer files ──────────────────────────────────────────────
//
// The roster used to be a grid of everyone currently on duty, which is the
// right thing for a shift and the wrong thing for managing people: the officer
// you need to promote is usually the one who just logged off. It now lists the
// whole department and marks who is on, and a supervisor opens anyone's file
// from it.

let _rosterView = 'all';
let _rosterData = null;

function loadRoster() {
    const panel = document.getElementById('tab-roster');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Roster</div>
                <div class="panel-subtitle">Department personnel</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="roster-view">
                    <button class="seg-btn ${_rosterView === 'all' ? 'active' : ''}" data-view="all">All</button>
                    <button class="seg-btn ${_rosterView === 'duty' ? 'active' : ''}" data-view="duty">On Duty</button>
                </div>
                <div class="search-bar" style="width:220px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="roster-search" placeholder="Name, badge or callsign...">
                </div>
                <button class="btn btn-ghost btn-sm" onclick="loadRoster()"><i class="i i-refresh"></i> Refresh</button>
            </div>
        </div>
        <div class="panel-body" id="roster-body">${skeletonLines(6)}</div>`;

    nuiFetch('getPersonnel').then(data => {
        if (!data) return;
        _rosterData = data;
        renderRoster();

        document.getElementById('roster-search')?.addEventListener('input', renderRoster);
        document.getElementById('roster-view')?.addEventListener('click', (e) => {
            const btn = e.target.closest('.seg-btn');
            if (!btn) return;
            _rosterView = btn.dataset.view;
            btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
            renderRoster();
        });
    });
}

function renderRoster() {
    const body = document.getElementById('roster-body');
    if (!body || !_rosterData) return;

    const q = (document.getElementById('roster-search')?.value || '').toLowerCase().trim();
    const list = (_rosterData.officers || []).filter(o => {
        if (_rosterView === 'duty' && !o.onduty) return false;
        if (!q) return true;
        return [o.name, o.badge, o.callsign, o.rank].some(v => String(v || '').toLowerCase().includes(q));
    });

    if (!list.length) {
        body.innerHTML = `<div class="empty-state">
            <div class="empty-icon"><i class="i i-roster"></i></div>
            <div class="empty-title">${_rosterView === 'duty' ? 'Nobody on duty' : 'No personnel on file'}</div>
            <div class="empty-subtitle">An officer's file is created the first time they open the MDT.</div>
        </div>`;
        return;
    }

    const manage = _rosterData.canManage;

    body.innerHTML = `
        <div class="roster-table${manage ? ' manage' : ''}">
            <div class="roster-head">
                <span></span><span>Officer</span><span>Rank</span><span>Badge</span>
                <span>Callsign</span><span>Status</span><span>Certs</span>
                ${manage ? '<span></span>' : ''}
            </div>
            ${list.map(o => {
                const st = getStatusConfig(o.status || '10-8');
                return `
                <div class="roster-line${o.onduty ? ' on' : ''}" onclick="openOfficerFile('${o.citizenid}')">
                    <span class="roster-state"><i class="dot ${o.onduty ? 'duty-on' : o.online ? 'duty-off' : 'duty-away'}"></i></span>
                    <span class="roster-who">
                        <span class="roster-name">${esc(o.name)}</span>
                        ${o.ia_open > 0 ? `<span class="tag tag-red" style="font-size:9px;">IA ${o.ia_open}</span>` : ''}
                    </span>
                    <span class="roster-rank">${esc(o.rank || '—')}</span>
                    <span class="mono">#${esc(o.badge)}</span>
                    <span class="mono">${esc(o.callsign || '—')}</span>
                    <span class="roster-status">${o.onduty ? `${st.code} ${esc(st.label)}` : o.online ? 'Off duty' : 'Offline'}</span>
                    <span class="mono">${o.certs || 0}</span>
                    ${manage ? `<span class="roster-manage"><button class="btn btn-ghost btn-xs">Manage</button></span>` : ''}
                </div>`;
            }).join('')}
        </div>
        <div class="penal-count">${list.length} of ${(_rosterData.officers || []).length} on the books</div>`;
}

// ── Officer file ──────────────────────────────────────────────────────────
//
// One modal, five tabs, because everything in it is about the same person and
// splitting it across panels would mean picking them again each time.

let _file = null;
let _fileTab = 'rank';

function openOfficerFile(citizenid) {
    nuiFetch('getOfficerFile', citizenid).then(data => {
        if (!data) return showToast('No file', 'That officer has no MDT record yet', 'error');
        _file = data;
        _fileTab = 'rank';
        drawOfficerFile();
    });
}

function drawOfficerFile() {
    const p = _file.profile;
    const can = _file.canManage;

    const existing = document.querySelector('.modal-backdrop.officer-file');
    if (existing) existing.remove();

    const backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop officer-file';
    backdrop.innerHTML = `
        <div class="modal modal-lg">
            <div class="modal-header">
                <div class="modal-header-icon"><i class="i i-badge"></i></div>
                <div class="modal-title">
                    ${esc(p.name || p.badge)}
                    <div class="modal-subtitle">${esc(p.rank || '—')} · #${esc(p.badge)} · ${esc(p.callsign || 'no callsign')}</div>
                </div>
                <button class="modal-close" title="Close"><i class="i i-x"></i></button>
            </div>
            <div class="profile-tabs" id="file-tabs">
                ${[['rank', 'Rank'], ['callsign', 'Callsign'], ['certs', 'Certifications'],
                   ['ppr', 'PPR'], ['ia', 'IA History']]
                    .map(([k, label]) => `<div class="profile-tab ${_fileTab === k ? 'active' : ''}" data-tab="${k}">${label}</div>`).join('')}
            </div>
            <div class="modal-body" id="file-body"></div>
        </div>`;

    document.body.appendChild(backdrop);
    backdrop.querySelector('.modal-close').onclick = () => backdrop.remove();
    backdrop.onclick = (e) => { if (e.target === backdrop) backdrop.remove(); };

    backdrop.querySelector('#file-tabs').onclick = (e) => {
        const tab = e.target.closest('.profile-tab');
        if (!tab) return;
        _fileTab = tab.dataset.tab;
        backdrop.querySelectorAll('.profile-tab').forEach(t => t.classList.toggle('active', t === tab));
        drawFileTab();
    };

    drawFileTab();

    function drawFileTab() {
        const body = document.getElementById('file-body');
        if (!body) return;
        body.innerHTML = ({
            rank:     () => fileRank(p, can),
            callsign: () => fileCallsign(p, can),
            certs:    () => fileCerts(can),
            ppr:      () => filePPR(can),
            ia:       () => fileIA(),
        }[_fileTab] || (() => ''))();
    }
}

function refreshOfficerFile() {
    const cid = _file && _file.profile && _file.profile.citizenid;
    if (!cid) return;
    nuiFetch('getOfficerFile', cid).then(data => {
        if (!data) return;
        _file = data;
        drawOfficerFile();
        loadRoster();
    });
}

// ── Tabs ──────────────────────────────────────────────────────────────────

function fileRank(p, can) {
    const grades = _file.grades || [];

    if (!grades.length) {
        return `<div class="empty-state">
            <div class="empty-icon"><i class="i i-scale"></i></div>
            <div class="empty-title">No ranks to show</div>
            <div class="empty-subtitle">The framework did not return any grades for ${esc(p.job || 'this job')}.</div>
        </div>`;
    }

    return `
        <div class="rank-list">
            ${grades.map(g => {
                const current = String(g.label) === String(p.rank);
                const tooHigh = g.grade > (_file.myGrade ?? 0);
                return `
                <div class="rank-row${current ? ' current' : ''}${tooHigh ? ' locked' : ''}">
                    <span class="rank-no">${g.grade}</span>
                    <span class="rank-label">${esc(g.label)}</span>
                    ${g.isboss ? '<span class="tag tag-purple" style="font-size:9px;">Command</span>' : ''}
                    <span class="rank-action">
                        ${current ? '<span class="text-muted text-xs">Current</span>'
                          : !can ? ''
                          : tooHigh ? '<span class="text-muted text-xs">Above you</span>'
                          : `<button class="btn btn-ghost btn-xs" onclick="setOfficerRank(${g.grade})">Set</button>`}
                    </span>
                </div>`;
            }).join('')}
        </div>
        ${can ? `<div class="form-hint">A rank change needs the officer online — it goes through the framework, not just this file.</div>` : ''}
        ${fileHistory('rank')}`;
}

function setOfficerRank(grade) {
    const p = _file.profile;
    nuiFetch('setOfficerRank', { citizenid: p.citizenid, grade, job: p.job }).then(res => {
        if (!res) return;
        showToast('Rank updated', '', 'success', 2500);
        refreshOfficerFile();
    });
}

function fileCallsign(p, can) {
    if (!can) {
        return `<div class="info-grid">
            <div class="info-row"><div class="info-key">Badge</div><div class="info-val mono">#${esc(p.badge)}</div></div>
            <div class="info-row"><div class="info-key">Callsign</div><div class="info-val mono">${esc(p.callsign || '—')}</div></div>
        </div>${fileHistory('callsign')}`;
    }

    return `
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Callsign</label>
                <input class="input mono" id="of-callsign" value="${esc(p.callsign || '')}" placeholder="1-ADAM-12" maxlength="20">
            </div>
            <div class="form-group" style="width:150px;">
                <label class="form-label">Badge</label>
                <input class="input mono" id="of-badge" value="${esc(p.badge || '')}" maxlength="20">
            </div>
        </div>
        <div class="form-hint">Badge numbers are unique across the server. Changing one updates the label on their map blip.</div>
        <div class="modal-actions"><button class="btn btn-primary btn-sm" onclick="saveOfficerCallsign()">Save</button></div>
        ${fileHistory('callsign')}`;
}

function saveOfficerCallsign() {
    const p = _file.profile;
    nuiFetch('setOfficerCallsign', {
        citizenid: p.citizenid,
        callsign: document.getElementById('of-callsign').value.trim(),
        badge: document.getElementById('of-badge').value.trim(),
    }).then(res => {
        if (!res) return;
        showToast('Saved', '', 'success', 2500);
        refreshOfficerFile();
    });
}

function fileCerts(can) {
    const held = new Set((_file.certs || []).map(c => c.cert));
    const available = _file.available || [];

    if (!available.length) {
        return `<div class="empty-state">
            <div class="empty-icon"><i class="i i-check"></i></div>
            <div class="empty-title">No certifications configured</div>
            <div class="empty-subtitle">Add some under Config.Certifications for this department.</div>
        </div>`;
    }

    return `
        <div class="cert-grid">
            ${available.map(cert => {
                const row = (_file.certs || []).find(c => c.cert === cert);
                const has = held.has(cert);
                return `
                <div class="cert-row${has ? ' held' : ''}">
                    <span class="cert-check"><i class="i i-${has ? 'check' : 'plus'}"></i></span>
                    <span class="cert-name">${esc(cert)}</span>
                    <span class="cert-meta">${row ? `${esc(row.issued_by_name)} · ${fmtDateShort(row.issued_at)}` : ''}</span>
                    ${can ? `<button class="btn btn-ghost btn-xs"
                        onclick="toggleCert('${cert.replace(/'/g, "\\'")}', ${has})">${has ? 'Revoke' : 'Issue'}</button>` : ''}
                </div>`;
            }).join('')}
        </div>
        ${fileHistory('certification')}`;
}

function toggleCert(cert, has) {
    const p = _file.profile;
    nuiFetch(has ? 'revokeCertification' : 'grantCertification', { citizenid: p.citizenid, cert }).then(res => {
        if (!res) return;
        refreshOfficerFile();
    });
}

function filePPR(can) {
    const list = _file.ppr || [];
    return `
        ${can ? `
        <div class="card" style="margin-bottom:14px;">
            <div class="card-header"><div class="card-title">New review</div></div>
            <div class="form-row">
                <div class="form-group" style="flex:1;">
                    <label class="form-label">Period</label>
                    <input class="input" id="ppr-period" placeholder="Q3, or a month">
                </div>
                <div class="form-group" style="width:150px;">
                    <label class="form-label">Rating</label>
                    <select class="input select" id="ppr-rating">
                        ${[5, 4, 3, 2, 1].map(n => `<option value="${n}" ${n === 3 ? 'selected' : ''}>${n} — ${['', 'Unsatisfactory', 'Needs work', 'Meets standard', 'Exceeds', 'Outstanding'][n]}</option>`).join('')}
                    </select>
                </div>
            </div>
            <div class="form-group">
                <label class="form-label">What went well</label>
                <textarea class="textarea" id="ppr-strengths" style="min-height:64px;"></textarea>
            </div>
            <div class="form-group">
                <label class="form-label">What to work on</label>
                <textarea class="textarea" id="ppr-improve" style="min-height:64px;"></textarea>
            </div>
            <div class="modal-actions"><button class="btn btn-primary btn-sm" onclick="savePPR()">File review</button></div>
        </div>` : ''}

        ${list.length ? list.map(r => `
            <div class="record-card">
                <div class="record-head">
                    <span class="record-title">${esc(r.period || 'Review')}</span>
                    <span class="rating">${'●'.repeat(r.rating || 0)}<span class="rating-off">${'●'.repeat(5 - (r.rating || 0))}</span></span>
                    <span class="record-meta">${esc(r.reviewed_by_name)} · ${fmtDateShort(r.created_at)}</span>
                </div>
                ${r.strengths ? `<div class="record-line"><span class="record-key">Went well</span>${esc(r.strengths)}</div>` : ''}
                ${r.improve ? `<div class="record-line"><span class="record-key">To work on</span>${esc(r.improve)}</div>` : ''}
            </div>`).join('')
        : `<div class="empty-state"><div class="empty-icon"><i class="i i-chart"></i></div>
             <div class="empty-title">No reviews on file</div></div>`}`;
}

function savePPR() {
    const p = _file.profile;
    nuiFetch('savePPR', {
        citizenid: p.citizenid,
        period: document.getElementById('ppr-period').value.trim(),
        rating: document.getElementById('ppr-rating').value,
        strengths: document.getElementById('ppr-strengths').value.trim(),
        improve: document.getElementById('ppr-improve').value.trim(),
    }).then(res => {
        if (!res) return;
        showToast('Review filed', '', 'success', 2500);
        refreshOfficerFile();
    });
}

function fileIA() {
    const list = _file.ia || [];
    if (!list.length) {
        return `<div class="empty-state">
            <div class="empty-icon"><i class="i i-folder"></i></div>
            <div class="empty-title">Nothing on file</div>
            <div class="empty-subtitle">Complaints, investigations and commendations all show here.</div>
        </div>`;
    }

    return list.map(c => `
        <div class="record-card ia-${c.kind}">
            <div class="record-head">
                <span class="mono record-no">${esc(c.case_number)}</span>
                <span class="record-title">${esc(c.title)}</span>
                <span class="tag ${{ open: 'tag-yellow', investigating: 'tag-blue', sustained: 'tag-red',
                                     unfounded: 'tag-green', closed: 'tag-gray' }[c.status] || 'tag-gray'}">${esc(c.status)}</span>
                <span class="record-meta">${esc(c.opened_by_name)} · ${fmtDateShort(c.created_at)}</span>
            </div>
            ${c.detail ? `<div class="record-line">${esc(c.detail)}</div>` : ''}
            ${c.outcome ? `<div class="record-line"><span class="record-key">Outcome</span>${esc(c.outcome)}</div>` : ''}
        </div>`).join('');
}

// Shared tail: what changed on this file, filtered to the tab you are on.
function fileHistory(field) {
    const rows = (_file.history || []).filter(h => h.field === field);
    if (!rows.length) return '';
    return `
        <div class="file-history">
            <div class="file-history-head">History</div>
            ${rows.slice(0, 8).map(h => `
                <div class="file-history-row">
                    <span class="mono">${fmtDateShort(h.created_at)}</span>
                    <span>${h.old_value ? `${esc(h.old_value)} → ` : ''}${esc(h.new_value || 'removed')}</span>
                    <span class="text-muted">${esc(h.changed_by_name)}</span>
                </div>`).join('')}
        </div>`;
}

window.loadRoster           = loadRoster;
window.openOfficerFile      = openOfficerFile;
window.setOfficerRank       = setOfficerRank;
window.saveOfficerCallsign  = saveOfficerCallsign;
window.toggleCert           = toggleCert;
window.savePPR              = savePPR;
