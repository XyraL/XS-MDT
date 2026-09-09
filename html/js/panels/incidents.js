// Where a report is in its life, as opposed to how bad the incident was.
// Severity describes the event; status describes the paperwork.
const INCIDENT_STATUS_LABELS = {
    draft:  { label: 'Draft',        tag: 'tag-gray'   },
    open:   { label: 'Open',         tag: 'tag-blue'   },
    review: { label: 'Under Review', tag: 'tag-yellow' },
    closed: { label: 'Closed',       tag: 'tag-green'  },
};

// Narrative skeletons.
//
// These exist because the hard part of a report is not typing, it is
// remembering what to include at 3am — and a report missing the time, the
// location or what was actually seized is the one that falls apart later.
// Edit these freely; they are prompts, not a schema.
const INCIDENT_TEMPLATES = {
    'Traffic stop': [
        'Date/time of stop:',
        'Location:',
        'Vehicle (plate, make, colour):',
        'Reason for stop:',
        'Observations on approach:',
        'Action taken (warning / citation / arrest):',
        'Outcome:',
    ],
    'Use of force': [
        'Date/time:',
        'Location:',
        'Subject:',
        'What was the subject doing immediately before force was used:',
        'Verbal commands given:',
        'Force used and why that level:',
        'Injuries and medical attention provided:',
        'Witnesses:',
        'Supervisor notified:',
    ],
    'Pursuit': [
        'Date/time pursuit began:',
        'Start location and direction:',
        'Reason for pursuit:',
        'Speeds and road conditions:',
        'Units involved:',
        'Termination reason and location:',
        'Outcome:',
    ],
    'Robbery / theft': [
        'Date/time reported:',
        'Location:',
        'Victim:',
        'Property taken and estimated value:',
        'Suspect description:',
        'Evidence collected:',
        'Witnesses:',
    ],
    'Assault': [
        'Date/time:',
        'Location:',
        'Victim and injuries:',
        'Suspect:',
        'Weapon involved:',
        'Medical response:',
        'Witnesses:',
    ],
};

const SEVERITY_LABELS = {
    low:      { label: 'Low',      color: 'var(--green)',  tag: 'tag-green'  },
    moderate: { label: 'Moderate', color: 'var(--yellow)', tag: 'tag-yellow' },
    high:     { label: 'High',     color: 'var(--orange)', tag: 'tag-orange' },
    critical: { label: 'Critical', color: 'var(--red)',    tag: 'tag-red'    },
};

function loadIncidents(filter = 'all') {
    const panel = document.getElementById('tab-incidents');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Incident Reports</div>
                <div class="panel-subtitle">Officer field reports and documentation</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm ${filter==='all'?'active':''}" onclick="loadIncidents('all')">All</button>
                <button class="btn btn-ghost btn-sm ${filter==='mine'?'active':''}" onclick="loadIncidents('mine')">Mine</button>
                <button class="btn btn-ghost btn-sm ${filter==='drafts'?'active':''}" onclick="loadIncidents('drafts')">Drafts</button>
                <button class="btn btn-ghost btn-sm ${filter==='open'?'active':''}" onclick="loadIncidents('open')">Open</button>
                <button class="btn btn-ghost btn-sm ${filter==='review'?'active':''}" onclick="loadIncidents('review')">Review</button>
                <input class="input input-sm" id="inc-search" placeholder="🔍 Search reports…" style="width:190px;"
                       oninput="queueIncidentSearch()">
                <button class="btn btn-primary btn-sm" onclick="openNewIncidentModal()">+ New Report</button>
            </div>
        </div>
        <div class="panel-body" id="incidents-body">
            ${Array(4).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    // 'drafts' is not a status the server knows by that name — it is the draft
    // status filtered to this officer, which the server enforces anyway.
    const query = filter === 'drafts' ? { filter: 'mine', status: 'draft' }
        : (filter === 'open' || filter === 'review' || filter === 'closed') ? { filter: 'all', status: filter }
        : { filter };

    nuiFetch('getIncidents', query).then(incidents => {
        const body = document.getElementById('incidents-body');
        if (!incidents || incidents.length === 0) {
            body.innerHTML = '<div class="empty-state"><div class="empty-icon">📋</div><div class="empty-title">No incident reports found</div></div>';
            return;
        }
        body.innerHTML = incidentCards(incidents);
    });
}

// One renderer for the list, the filters and search, so a report card looks
// the same however it was found.
function incidentCards(incidents) {
    return incidents.map(i => {
        const sev = SEVERITY_LABELS[i.severity] || null;
        return `
        <div class="card mb-2" onclick="openIncidentDetail(${i.id})" style="cursor:pointer;">
            <div class="card-header">
                <div class="card-title">
                    <div class="card-title-icon" style="background:rgba(99,102,241,.12);color:var(--accent-2);">📋</div>
                    <span class="font-bold">${esc(i.title)}</span>
                    ${sev ? `<span class="tag ${esc(sev.tag)}" style="margin-left:8px;">${esc(sev.label)}</span>` : ''}
                    ${statusTag(i.status)}
                </div>
                <div style="font-size:11px;color:var(--text-muted);">
                    ${i.case_number ? esc(i.case_number) : '#' + i.id} · By ${esc(i.created_by_name)} · ${timeAgo(i.created_at)}
                </div>
            </div>
            <div style="display:flex;align-items:center;gap:12px;font-size:11.5px;color:var(--text-muted);">
                <span>👮 ${(i.involved_officers||[]).length} officer(s)</span>
                <span>👤 ${(i.involved_civilians||[]).length} civilian(s)</span>
                <span style="margin-left:auto;" class="font-mono">${fmtDateShort(i.created_at)}</span>
            </div>
            ${renderRecordTags('incident', i.id, i.tags)}
        </div>`;
    }).join('');
}

// ── Search ──────────────────────────────────────────────────────────────────
// Case numbers, titles, narratives and authors, in one box. Debounced so it
// searches thoughts, not keystrokes.
let _incSearchTimer = null;

function queueIncidentSearch() {
    clearTimeout(_incSearchTimer);
    _incSearchTimer = setTimeout(runIncidentSearch, 300);
}

async function runIncidentSearch() {
    const input = document.getElementById('inc-search');
    const body = document.getElementById('incidents-body');
    if (!input || !body) return;

    const query = input.value.trim();
    if (query.length < 2) { loadIncidents('all'); return; }

    body.innerHTML = `<div class="card mb-2">${skeletonLines(3)}</div>`;
    const results = await nuiFetch('searchIncidents', query);

    if (input.value.trim() !== query) return;   // they kept typing

    if (!results || !results.length) {
        body.innerHTML = `<div class="empty-state"><div class="empty-icon">🔍</div><div class="empty-title">Nothing matched "${esc(query)}"</div><div class="empty-subtitle">Case numbers, titles, narratives and officers are all searched.</div></div>`;
        return;
    }
    body.innerHTML = incidentCards(results);
}

async function openIncidentDetail(id) {
    const panel = document.getElementById('tab-incidents');
    // Placeholder while loading — edit buttons added once we know ownership
    panel.innerHTML = `<div class="panel-header">
        <div class="panel-title">Incident Report</div>
        <div class="panel-actions" id="incident-header-actions">
            <button class="btn btn-ghost btn-sm" onclick="loadIncidents()">← Back</button>
        </div>
    </div>
    <div class="panel-body" id="incident-detail">${Array(3).fill(0).map(()=>`<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}</div>`;

    const incident = await nuiFetch('getIncident', id);
    if (!incident) {
        document.getElementById('incident-detail').innerHTML = '<div class="empty-state"><div class="empty-icon">⚠</div><div class="empty-text">Incident not found</div></div>';
        return;
    }

    const canEdit = MDT.officer && (
        MDT.officer.citizenid === incident.created_by ||
        MDT.officer.isSupervisor
    );
    const actions = document.getElementById('incident-header-actions');
    const sev = SEVERITY_LABELS[incident.severity] || null;
    if (actions && canEdit) {
        actions.innerHTML = `
            <button class="btn btn-ghost btn-sm" onclick="loadIncidents()">← Back</button>
            <button class="btn btn-ghost btn-sm" onclick="printIncidentReport(${id})">🖨 Print</button>
            <button class="btn btn-ghost btn-sm" onclick="openEditIncidentModal(${id})">✏ Edit</button>
            ${statusControl(incident)}
            <button class="btn btn-danger btn-sm" onclick="deleteIncident(${id})">🗑 Delete</button>`;
    } else if (actions) {
        actions.innerHTML = `
            <button class="btn btn-ghost btn-sm" onclick="loadIncidents()">← Back</button>
            <button class="btn btn-ghost btn-sm" onclick="printIncidentReport(${id})">🖨 Print</button>`;
    }

    document.getElementById('incident-detail').innerHTML = `
        <div class="card" style="margin-bottom:14px;">
            <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:12px;">
                <div>
                    <div style="font-size:20px;font-weight:800;margin-bottom:4px;">${esc(incident.title)}</div>
                    <div style="display:flex;flex-wrap:wrap;gap:12px;font-size:11.5px;color:var(--text-muted);">
                        <span class="font-mono">Report #${incident.id}</span>
                        <span>By: <strong style="color:var(--text-secondary);">${esc(incident.created_by_name)}</strong></span>
                        <span>${fmtDate(incident.created_at)}</span>
                        ${incident.updated_at !== incident.created_at ? `<span style="color:var(--accent-2);">Updated ${timeAgo(incident.updated_at)}</span>` : ''}
                        ${canEdit ? `<span style="cursor:pointer;color:var(--accent-2)" onclick="openCaseNumberModal(${incident.id},'${(incident.case_number||'').replace(/'/g,"\\'")}')" title="Set Case Number">
                            ${incident.case_number ? `<strong style="color:var(--accent-2)">Case: ${incident.case_number}</strong>` : '+ Link Case #'}
                        </span>` : (incident.case_number ? `<span style="color:var(--accent-2)">Case: ${incident.case_number}</span>` : '')}
                    </div>
                </div>
                ${sev ? `<span class="tag ${esc(sev.tag)}" style="font-size:12px;padding:5px 12px;flex-shrink:0;">${esc(sev.label)}</span>` : ''}
            </div>
            <div style="font-size:10px;font-weight:800;letter-spacing:.1em;color:var(--text-muted);margin-bottom:8px;text-transform:uppercase;">Narrative</div>
            <div style="font-size:13px;line-height:1.75;white-space:pre-wrap;color:var(--text-secondary);">${esc(incident.narrative)}</div>
            ${renderRecordTags('incident', incident.id, incident.tags)}
        </div>

        <div class="card" style="margin-bottom:14px;">
            <div class="card-header">
                <div class="card-title">
                    <div class="card-title-icon" style="background:rgba(245,165,36,.12);color:var(--yellow);">🗃</div>
                    Evidence (${(incident.evidence || []).length})
                </div>
                <button class="btn btn-ghost btn-sm" onclick="openEvidenceModal(${incident.id})">+ Log Evidence</button>
            </div>
            ${renderEvidenceList(incident.evidence || [], incident.id)}
        </div>

        <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;">
            <div class="card">
                <div class="card-header"><div class="card-title">Involved Civilians (${incident.involved_civilians.length})</div></div>
                ${incident.involved_civilians.length === 0 ? '<div class="text-muted text-sm">None listed</div>' :
                    incident.involved_civilians.map(c => `
                        <div style="padding:7px 0;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;">
                            <div>
                                <div style="font-weight:600;font-size:13px;">${esc(c.name)} ${copyBtn(c.citizenid)}</div>
                                <div class="text-muted text-sm font-mono">${c.citizenid}</div>
                            </div>
                            <button class="btn btn-ghost btn-sm" onclick="switchTab('civilians');setTimeout(()=>openCivilianProfile('${c.citizenid}'),80);">View Profile</button>
                        </div>`).join('')}
            </div>
            <div class="card">
                <div class="card-header"><div class="card-title">Involved Officers (${incident.involved_officers.length})</div></div>
                ${incident.involved_officers.length === 0 ? '<div class="text-muted text-sm">None listed</div>' :
                    incident.involved_officers.map(o => `
                        <div style="padding:7px 0;border-bottom:1px solid var(--border);">
                            <div style="font-weight:600;font-size:13px;">${esc(o.name)}</div>
                            <div class="text-muted text-sm font-mono">${o.citizenid}</div>
                        </div>`).join('')}
            </div>
        </div>
        <div id="incident-linked-records-section"></div>`;

    // Load linked arrests + citations if any
    const linkedArrests   = incident.linked_arrests   || [];
    const linkedCitations = incident.linked_citations || [];
    if (linkedArrests.length > 0 || linkedCitations.length > 0) {
        const section = document.getElementById('incident-linked-records-section');
        if (section) {
            section.innerHTML = `<div class="card" style="margin-top:14px;">
                <div class="card-header"><div class="card-title">Linked Records</div></div>
                <div id="linked-records-rows">${skeletonLines(2)}</div>
            </div>`;
            nuiFetch('getRecordsByIds', { arrests: linkedArrests, citations: linkedCitations }).then(records => {
                const rows = document.getElementById('linked-records-rows');
                if (!rows) return;
                let html = '';
                (records?.arrests || []).forEach(a => {
                    html += `<div style="padding:8px 0;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:10px;">
                        <span class="tag tag-red">Arrest #${a.id}</span>
                        <div style="flex:1;">
                            <span style="font-size:12px;font-weight:600;">${a.citizenid}</span>
                            <span class="text-muted text-sm"> · By ${esc(a.officer_name)} · ${fmtDateShort(a.created_at)}</span>
                        </div>
                        <span class="text-muted text-sm">${(a.charges||[]).length} charge(s)${a.fine ? ' · ' + dollarFmt(a.fine) : ''}</span>
                    </div>`;
                });
                (records?.citations || []).forEach(c => {
                    html += `<div style="padding:8px 0;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:10px;">
                        <span class="tag tag-yellow">Citation #${c.id}</span>
                        <div style="flex:1;">
                            <span style="font-size:12px;font-weight:600;">${c.citizenid}</span>
                            <span class="text-muted text-sm"> · By ${esc(c.officer_name)} · ${fmtDateShort(c.created_at)}</span>
                        </div>
                        <span style="font-size:12px;color:var(--green);">${dollarFmt(c.fine)}</span>
                    </div>`;
                });
                rows.innerHTML = html || '<div class="text-muted text-sm">No matching records found.</div>';
            });
        }
    }
}

// ── Record Linker (link arrests / citations to an incident) ───────────────

function createRecordLinker(containerId, type) {
    const linkedKey = type === 'arrest' ? '_linkedArrests' : '_linkedCitations';
    if (!window[linkedKey]) window[linkedKey] = [];
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = `
        <div class="person-linker">
            <div class="person-linker-input-row">
                <input class="input" id="${containerId}-input"
                    placeholder="Search by civilian name..."
                    autocomplete="off">
            </div>
            <div class="person-linker-dropdown hidden" id="${containerId}-dropdown"></div>
        </div>
        <div class="linked-persons" id="${containerId}-linked">
            <span style="color:var(--text-muted);font-size:11px;padding:2px 4px;">No ${type}s linked</span>
        </div>`;

    let timer = null;
    const input = document.getElementById(`${containerId}-input`);
    const dropdown = document.getElementById(`${containerId}-dropdown`);

    input.addEventListener('input', () => {
        clearTimeout(timer);
        const q = input.value.trim();
        if (q.length < 2) { dropdown.classList.add('hidden'); return; }
        timer = setTimeout(async () => {
            const endpoint = type === 'arrest' ? 'searchArrests' : 'searchCitations';
            const results = await nuiFetch(endpoint, { query: q });
            if (!results || results.length === 0) {
                dropdown.innerHTML = '<div class="person-linker-result"><span class="text-muted text-sm">No results</span></div>';
            } else {
                dropdown.innerHTML = results.slice(0, 8).map(r => `
                    <div class="person-linker-result" onclick="linkRecord('${containerId}',${r.id},'${(r.civilian_name || r.citizenid).replace(/'/g,"\\'")}','${type}')">
                        <div>
                            <div class="person-linker-result-name">${esc(r.civilian_name || r.citizenid)}</div>
                            <div class="person-linker-result-meta">#${r.id} · ${fmtDateShort(r.created_at)} · By ${esc(r.officer_name)}</div>
                        </div>
                        <span class="tag ${type === 'arrest' ? 'tag-red' : 'tag-yellow'}">${type === 'arrest' ? 'Arrest' : 'Citation'}</span>
                    </div>`).join('');
            }
            dropdown.classList.remove('hidden');
        }, 280);
    });
    document.addEventListener('click', (e) => {
        if (!container.contains(e.target)) dropdown.classList.add('hidden');
    }, { capture: true });
}

function linkRecord(containerId, id, label, type) {
    const linkedKey = type === 'arrest' ? '_linkedArrests' : '_linkedCitations';
    if (!window[linkedKey]) window[linkedKey] = [];
    if (window[linkedKey].find(r => r.id === id)) {
        document.getElementById(`${containerId}-dropdown`)?.classList.add('hidden');
        return;
    }
    window[linkedKey].push({ id, label });
    document.getElementById(`${containerId}-dropdown`)?.classList.add('hidden');
    document.getElementById(`${containerId}-input`).value = '';
    refreshLinkedRecordsDisplay(containerId, type);
}

function unlinkRecord(containerId, id, type) {
    const linkedKey = type === 'arrest' ? '_linkedArrests' : '_linkedCitations';
    window[linkedKey] = (window[linkedKey] || []).filter(r => r.id !== id);
    refreshLinkedRecordsDisplay(containerId, type);
}

function refreshLinkedRecordsDisplay(containerId, type) {
    const linkedKey = type === 'arrest' ? '_linkedArrests' : '_linkedCitations';
    const list = window[linkedKey] || [];
    const el = document.getElementById(`${containerId}-linked`);
    if (!el) return;
    if (list.length === 0) {
        el.innerHTML = `<span style="color:var(--text-muted);font-size:11px;padding:2px 4px;">No ${type}s linked</span>`;
        return;
    }
    const color = type === 'arrest' ? '' : 'officer-tag';
    el.innerHTML = list.map(r => `
        <span class="linked-person-tag ${color}">
            #${r.id} — ${esc(r.label)}
            <button onclick="unlinkRecord('${containerId}',${r.id},'${type}')">×</button>
        </span>`).join('');
}

// ── Person Linker ─────────────────────────────────────────────────────────

function createPersonLinker(containerId, type = 'civilian') {
    const isCiv = type === 'civilian';
    const linkedKey = isCiv ? '_linkedCivilians' : '_linkedOfficers';
    if (!window[linkedKey]) window[linkedKey] = [];

    const container = document.getElementById(containerId);
    if (!container) return;

    container.innerHTML = `
        <div class="person-linker">
            <div class="person-linker-input-row">
                <input class="input" id="${containerId}-input"
                    placeholder="Search by name..."
                    autocomplete="off">
            </div>
            <div class="person-linker-dropdown hidden" id="${containerId}-dropdown"></div>
        </div>
        <div class="linked-persons" id="${containerId}-linked">
            <span style="color:var(--text-muted);font-size:11px;padding:2px 4px;">No ${isCiv ? 'civilians' : 'officers'} linked</span>
        </div>`;

    let searchTimer = null;
    const input = document.getElementById(`${containerId}-input`);
    const dropdown = document.getElementById(`${containerId}-dropdown`);

    input.addEventListener('input', () => {
        clearTimeout(searchTimer);
        const q = input.value.trim();
        if (q.length < 2) { dropdown.classList.add('hidden'); return; }
        searchTimer = setTimeout(async () => {
            const endpoint = isCiv ? 'searchCivilians' : 'searchOfficers';
            const results = await nuiFetch(endpoint, q);
            if (!results || results.length === 0) {
                dropdown.innerHTML = '<div class="person-linker-result"><span class="text-muted text-sm">No results</span></div>';
            } else {
                dropdown.innerHTML = results.slice(0, 8).map(r => `
                    <div class="person-linker-result" onclick="linkPerson('${containerId}','${r.citizenid}','${(r.firstname ? r.firstname + ' ' + r.lastname : r.name).replace(/'/g,"\\'")}','${type}')">
                        <div>
                            <div class="person-linker-result-name">${esc(r.firstname ? r.firstname + ' ' + r.lastname : r.name)}</div>
                            <div class="person-linker-result-meta">${isCiv ? (r.dob || r.citizenid) : (r.grade + ' · Badge #' + r.badge)}</div>
                        </div>
                        <span class="tag ${isCiv ? 'tag-blue' : 'tag-purple'}">${isCiv ? 'Civilian' : 'Officer'}</span>
                    </div>`).join('');
            }
            dropdown.classList.remove('hidden');
        }, 280);
    });

    // Close dropdown on outside click
    document.addEventListener('click', (e) => {
        if (!container.contains(e.target)) dropdown.classList.add('hidden');
    }, { capture: true });
}

function linkPerson(containerId, citizenid, name, type) {
    const linkedKey = type === 'civilian' ? '_linkedCivilians' : '_linkedOfficers';
    if (!window[linkedKey]) window[linkedKey] = [];

    // Prevent duplicates
    if (window[linkedKey].find(p => p.citizenid === citizenid)) {
        document.getElementById(`${containerId}-dropdown`).classList.add('hidden');
        document.getElementById(`${containerId}-input`).value = '';
        return;
    }

    window[linkedKey].push({ citizenid, name });
    document.getElementById(`${containerId}-dropdown`).classList.add('hidden');
    document.getElementById(`${containerId}-input`).value = '';
    refreshLinkedDisplay(containerId, type);
}

function unlinkPerson(containerId, citizenid, type) {
    const linkedKey = type === 'civilian' ? '_linkedCivilians' : '_linkedOfficers';
    window[linkedKey] = (window[linkedKey] || []).filter(p => p.citizenid !== citizenid);
    refreshLinkedDisplay(containerId, type);
}

function refreshLinkedDisplay(containerId, type) {
    const linkedKey = type === 'civilian' ? '_linkedCivilians' : '_linkedOfficers';
    const list = window[linkedKey] || [];
    const el = document.getElementById(`${containerId}-linked`);
    if (!el) return;
    if (list.length === 0) {
        el.innerHTML = `<span style="color:var(--text-muted);font-size:11px;padding:2px 4px;">No ${type === 'civilian' ? 'civilians' : 'officers'} linked</span>`;
        return;
    }
    el.innerHTML = list.map(p => `
        <span class="linked-person-tag ${type === 'officer' ? 'officer-tag' : ''}">
            ${esc(p.name)}
            <button onclick="unlinkPerson('${containerId}','${p.citizenid}','${type}')">×</button>
        </span>`).join('');
}

// ── New Incident Modal ────────────────────────────────────────────────────

function printIncidentReport(id) {
    nuiFetch('getIncident', id).then(incident => {
        if (!incident) return;
        const win = window.open('', '_blank');
        const sev = SEVERITY_LABELS[incident.severity];
        win.document.write(`<!DOCTYPE html><html><head><title>Incident Report #${incident.id}</title>
        <style>
            body { font-family: Arial, sans-serif; font-size: 12pt; color: #111; padding: 32px; max-width: 800px; margin: 0 auto; }
            h1 { font-size: 20pt; margin-bottom: 4px; }
            .meta { color: #555; font-size: 10pt; margin-bottom: 24px; border-bottom: 1px solid #ccc; padding-bottom: 12px; }
            .label { font-size: 9pt; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: #555; margin-bottom: 4px; }
            .narrative { line-height: 1.7; white-space: pre-wrap; border: 1px solid #ddd; padding: 14px; border-radius: 4px; margin-bottom: 24px; }
            table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
            th { background: #f0f0f0; text-align: left; padding: 8px; font-size: 10pt; }
            td { padding: 8px; border-bottom: 1px solid #eee; font-size: 10.5pt; }
            .badge { display: inline-block; border: 1px solid #999; border-radius: 4px; padding: 2px 8px; font-size: 9pt; font-weight: 700; }
        </style></head><body>
        <h1>${esc(incident.title)}</h1>
        <div class="meta">
            Report #${incident.id} &nbsp;|&nbsp; By: ${esc(incident.created_by_name)} &nbsp;|&nbsp; ${new Date(incident.created_at).toLocaleString()}
            ${sev ? ` &nbsp;|&nbsp; <span class="badge">${esc(sev.label)}</span>` : ''}
        </div>
        <div class="label">Narrative</div>
        <div class="narrative">${esc(incident.narrative)}</div>
        ${(incident.evidence || []).length ? `
        <div class="label">Evidence</div>
        <table><thead><tr><th>Type</th><th>Label</th><th>Details</th><th>Logged by</th></tr></thead><tbody>
            ${incident.evidence.map(e => `<tr><td>${esc(e.kind)}</td><td>${esc(e.label)}</td><td>${esc(e.detail || '')}</td><td>${esc(e.logged_by_name)}</td></tr>`).join('')}
        </tbody></table>` : ''}
        ${incident.involved_civilians.length ? `
        <div class="label">Involved Civilians</div>
        <table><thead><tr><th>Name</th><th>Citizen ID</th></tr></thead><tbody>
            ${incident.involved_civilians.map(c => `<tr><td>${esc(c.name)}</td><td>${c.citizenid}</td></tr>`).join('')}
        </tbody></table>` : ''}
        ${incident.involved_officers.length ? `
        <div class="label">Involved Officers</div>
        <table><thead><tr><th>Name</th><th>Citizen ID</th></tr></thead><tbody>
            ${incident.involved_officers.map(o => `<tr><td>${esc(o.name)}</td><td>${o.citizenid}</td></tr>`).join('')}
        </tbody></table>` : ''}
        <div style="margin-top:40px;font-size:9pt;color:#888;border-top:1px solid #ddd;padding-top:12px;">
            Generated by XSMDT — ${new Date().toLocaleString()}
        </div>
        </body></html>`);
        win.document.close();
        win.print();
    });
}

function openNewIncidentModal() {
    window._linkedCivilians = [];
    window._linkedOfficers = [];
    window._linkedArrests = [];
    window._linkedCitations = [];

    const modal = createModal('New Incident Report', `
        <div class="form-row">
            <div class="form-group" style="flex:2;">
                <label class="form-label">Title</label>
                <input class="input" id="inc-title" placeholder="Brief incident title">
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Severity</label>
                <select class="select" id="inc-severity">
                    <option value="">— None —</option>
                    <option value="low">Low</option>
                    <option value="moderate">Moderate</option>
                    <option value="high">High</option>
                    <option value="critical">Critical</option>
                </select>
            </div>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:2;">
                <label class="form-label">Location</label>
                <input class="input" id="inc-location" placeholder="Where did this happen?">
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Start from a template</label>
                <select class="select" id="inc-template" onchange="applyIncidentTemplate()">
                    <option value="">— Blank —</option>
                    ${Object.keys(INCIDENT_TEMPLATES).map(t => `<option value="${esc(t)}">${esc(t)}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Narrative</label>
            <textarea class="textarea" id="inc-narrative" style="min-height:240px;" placeholder="Write a detailed account of the incident. Include timeline of events, actions taken, evidence collected, etc." oninput="queueDraftAutosave()"></textarea>
            <div class="form-hint" id="inc-autosave-note">Saved to this machine as you type, so a misclick cannot lose it.</div>
        </div>
        <button class="btn btn-ghost btn-sm" onclick="saveIncidentDraft()">💾 Save as draft</button>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Link Civilians</label>
                <div id="inc-civ-linker"></div>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Link Officers</label>
                <div id="inc-off-linker"></div>
            </div>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Link Arrests</label>
                <div id="inc-arrest-linker"></div>
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Link Citations</label>
                <div id="inc-citation-linker"></div>
            </div>
        </div>`,
        async () => {
            const title = document.getElementById('inc-title').value.trim();
            const narrative = document.getElementById('inc-narrative').value.trim();
            if (!title || !narrative) { showToast('Missing Info', 'Title and narrative are required.', 'error'); return; }

            const severity = document.getElementById('inc-severity')?.value || '';
            const result = await nuiFetch('createIncident', {
                title,
                narrative,
                severity,
                location: document.getElementById('inc-location')?.value.trim() || '',
                involved_civilians: window._linkedCivilians || [],
                involved_officers: window._linkedOfficers || [],
                linked_arrests:    (window._linkedArrests || []).map(r => r.id),
                linked_citations:  (window._linkedCitations || []).map(r => r.id),
            });
            if (result) {
                clearIncidentDraft();
                showToast('Report Created', 'Filed as ' + (result.caseNumber || ('#' + (result.id || result))), 'success');
                closeModal(modal);
                loadIncidents();
            } else {
                showToast('Error', 'Could not create report.', 'error');
            }
        }, 'Submit Report');

    setTimeout(() => {
        createPersonLinker('inc-civ-linker', 'civilian');
        createPersonLinker('inc-off-linker', 'officer');
        createRecordLinker('inc-arrest-linker', 'arrest');
        createRecordLinker('inc-citation-linker', 'citation');
        restoreIncidentDraft();
    }, 50);
}

// ── Report writing helpers ──────────────────────────────────────────────────

function statusTag(status) {
    const s = INCIDENT_STATUS_LABELS[status];
    if (!s || status === 'open') return '';   // "Open" is the norm; badging it is noise
    return `<span class="tag ${s.tag}" style="margin-left:6px;">${s.label}</span>`;
}

// Where a report can go next. A draft is unfiled, so its only move is to be
// filed; everything else can go back and forth while an investigation runs.
const STATUS_NEXT = {
    draft:  [['open', 'File report']],
    open:   [['review', 'Send for review'], ['closed', 'Close']],
    review: [['open', 'Reopen'], ['closed', 'Close']],
    closed: [['open', 'Reopen']],
};

function statusControl(incident) {
    const moves = STATUS_NEXT[incident.status || 'open'] || [];
    return moves.map(([status, label]) =>
        `<button class="btn btn-ghost btn-sm" onclick="changeIncidentStatus(${incident.id},'${status}')">${label}</button>`
    ).join('');
}

async function changeIncidentStatus(id, status) {
    const res = await nuiFetch('setIncidentStatus', { id, status });
    if (res && res.ok) {
        showToast('Report updated', (INCIDENT_STATUS_LABELS[status] || {}).label || status, 'success');
        openIncidentDetail(id);
    } else {
        showToast('Could not update', (res && res.error) || 'Unknown error', 'error');
    }
}

function applyIncidentTemplate() {
    const name = document.getElementById('inc-template')?.value;
    const box = document.getElementById('inc-narrative');
    if (!name || !box) return;

    const skeleton = (INCIDENT_TEMPLATES[name] || []).join('\n\n');

    // Never overwrite work already done. Someone who picks a template halfway
    // through a narrative wants the prompts, not a blank page.
    box.value = box.value.trim() ? box.value.trimEnd() + '\n\n' + skeleton : skeleton;
    box.focus();
    queueDraftAutosave();
}

// ── Local autosave ──────────────────────────────────────────────────────────
// Separate from server-side drafts and solving a different problem: this is
// crash and misclick insurance for the text in front of you right now. A
// server draft is for finishing a report next shift.
const DRAFT_KEY = 'XS-MDT:incident-draft';
let _draftTimer = null;

function queueDraftAutosave() {
    clearTimeout(_draftTimer);
    _draftTimer = setTimeout(saveIncidentDraftLocal, 800);
}

function saveIncidentDraftLocal() {
    try {
        const payload = {
            title:     document.getElementById('inc-title')?.value || '',
            narrative: document.getElementById('inc-narrative')?.value || '',
            location:  document.getElementById('inc-location')?.value || '',
            severity:  document.getElementById('inc-severity')?.value || '',
            at: Date.now(),
        };
        if (!payload.title && !payload.narrative) return;
        localStorage.setItem(DRAFT_KEY, JSON.stringify(payload));

        const note = document.getElementById('inc-autosave-note');
        if (note) note.textContent = 'Saved locally at ' + new Date().toLocaleTimeString();
    } catch (e) {
        // Storage being unavailable is not worth interrupting a report over.
    }
}

function clearIncidentDraft() {
    try { localStorage.removeItem(DRAFT_KEY); } catch (e) {}
}

function restoreIncidentDraft() {
    let saved;
    try { saved = JSON.parse(localStorage.getItem(DRAFT_KEY) || 'null'); } catch (e) { return; }
    if (!saved || (!saved.title && !saved.narrative)) return;

    const note = document.getElementById('inc-autosave-note');
    if (!note) return;

    // Offered rather than applied. Silently refilling a form is alarming when
    // you meant to start a new report.
    note.innerHTML = `Unsent report from ${new Date(saved.at).toLocaleString()}.
        <button class="btn btn-ghost btn-xs" onclick="applyStoredDraft()">Restore it</button> ·
        <button class="btn btn-ghost btn-xs" onclick="clearIncidentDraft();document.getElementById('inc-autosave-note').textContent='Discarded.'">Discard</button>`;
}

function applyStoredDraft() {
    let saved;
    try { saved = JSON.parse(localStorage.getItem(DRAFT_KEY) || 'null'); } catch (e) { return; }
    if (!saved) return;
    const set = (id, v) => { const el = document.getElementById(id); if (el && v) el.value = v; };
    set('inc-title', saved.title);
    set('inc-narrative', saved.narrative);
    set('inc-location', saved.location);
    set('inc-severity', saved.severity);
    const note = document.getElementById('inc-autosave-note');
    if (note) note.textContent = 'Restored.';
}

// Files the report as a draft: saved server-side, visible only to its author.
async function saveIncidentDraft() {
    const title = document.getElementById('inc-title')?.value.trim();
    const narrative = document.getElementById('inc-narrative')?.value.trim();
    if (!title) { showToast('Title needed', 'A draft still needs something to find it by.', 'error'); return; }

    const result = await nuiFetch('createIncident', {
        title,
        narrative: narrative || '(draft)',
        severity: document.getElementById('inc-severity')?.value || '',
        location: document.getElementById('inc-location')?.value.trim() || '',
        status: 'draft',
        involved_civilians: window._linkedCivilians || [],
        involved_officers:  window._linkedOfficers || [],
        linked_arrests:     (window._linkedArrests || []).map(r => r.id),
        linked_citations:   (window._linkedCitations || []).map(r => r.id),
    });

    if (result) {
        clearIncidentDraft();
        showToast('Draft saved', 'Only you can see it until you file it.', 'success');
        document.querySelectorAll('.modal-overlay').forEach(m => m.remove());
        loadIncidents('drafts');
    } else {
        showToast('Error', 'Could not save the draft.', 'error');
    }
}

function openEditIncidentModal(id) {
    nuiFetch('getIncident', id).then(async incident => {
        if (!incident) return;
        window._linkedCivilians = [...(incident.involved_civilians || [])];
        window._linkedOfficers = [...(incident.involved_officers || [])];

        // Pre-fetch linked record labels so we can show them in the modal
        const linkedArrestIds   = incident.linked_arrests   || [];
        const linkedCitationIds = incident.linked_citations || [];
        let prefetchedRecords = { arrests: [], citations: [] };
        if (linkedArrestIds.length > 0 || linkedCitationIds.length > 0) {
            prefetchedRecords = await nuiFetch('getRecordsByIds', { arrests: linkedArrestIds, citations: linkedCitationIds }) || prefetchedRecords;
        }
        window._linkedArrests   = prefetchedRecords.arrests.map(a => ({ id: a.id, label: a.citizenid }));
        window._linkedCitations = prefetchedRecords.citations.map(c => ({ id: c.id, label: c.citizenid }));

        const modal = createModal('Edit Incident Report', `
            <div class="form-group">
                <label class="form-label">Title</label>
                <input class="input" id="inc-edit-title" value="${incident.title.replace(/"/g,'&quot;')}">
            </div>
            <div class="form-group">
                <label class="form-label">Narrative</label>
                <textarea class="textarea" id="inc-edit-narrative" style="min-height:260px;">${esc(incident.narrative)}</textarea>
            </div>
            <div class="form-row">
                <div class="form-group" style="flex:1;">
                    <label class="form-label">Link Civilians</label>
                    <div id="inc-edit-civ-linker"></div>
                </div>
                <div class="form-group" style="flex:1;">
                    <label class="form-label">Link Officers</label>
                    <div id="inc-edit-off-linker"></div>
                </div>
            </div>
            <div class="form-row">
                <div class="form-group" style="flex:1;">
                    <label class="form-label">Link Arrests</label>
                    <div id="inc-edit-arrest-linker"></div>
                </div>
                <div class="form-group" style="flex:1;">
                    <label class="form-label">Link Citations</label>
                    <div id="inc-edit-citation-linker"></div>
                </div>
            </div>`,
            async () => {
                const title = document.getElementById('inc-edit-title').value.trim();
                const narrative = document.getElementById('inc-edit-narrative').value.trim();
                if (!title || !narrative) { showToast('Missing Info', 'Title and narrative are required.', 'error'); return; }

                const result = await nuiFetch('updateIncident', {
                    id,
                    title,
                    narrative,
                    involved_civilians: window._linkedCivilians || [],
                    involved_officers:  window._linkedOfficers || [],
                    linked_arrests:     (window._linkedArrests || []).map(r => r.id),
                    linked_citations:   (window._linkedCitations || []).map(r => r.id),
                });
                if (result) {
                    showToast('Report Updated', '', 'success');
                    closeModal(modal);
                    openIncidentDetail(id);
                } else {
                    showToast('Error', 'Could not update report.', 'error');
                }
            }, 'Save Changes');

        setTimeout(() => {
            createPersonLinker('inc-edit-civ-linker', 'civilian');
            createPersonLinker('inc-edit-off-linker', 'officer');
            createRecordLinker('inc-edit-arrest-linker', 'arrest');
            createRecordLinker('inc-edit-citation-linker', 'citation');
            setTimeout(() => {
                refreshLinkedDisplay('inc-edit-civ-linker', 'civilian');
                refreshLinkedDisplay('inc-edit-off-linker', 'officer');
                refreshLinkedRecordsDisplay('inc-edit-arrest-linker', 'arrest');
                refreshLinkedRecordsDisplay('inc-edit-citation-linker', 'citation');
            }, 60);
        }, 50);
    });
}

async function deleteIncident(id) {
    const modal = createModal('Delete Incident Report', `
        <div class="alert alert-danger">
            <span>⚠</span>
            <div>
                <strong>Permanently delete Report #${id}?</strong><br>
                <span style="font-size:12px;">This cannot be undone. The report will be removed from the system entirely.</span>
            </div>
        </div>`,
        async () => {
            const ok = await nuiFetch('deleteIncident', id);
            if (ok) {
                showToast('Report Deleted', `Incident #${id} has been removed.`, 'success');
                closeModal(modal);
                loadIncidents();
            } else {
                showToast('Error', 'Could not delete report. Check your permissions.', 'error');
            }
        }, 'Delete Report', '🗑');
}

function openCaseNumberModal(incidentId, currentCase) {
    const modal = createModal('Link Case Number',
        `<div style="margin-bottom:12px;font-size:13px;color:var(--text-muted)">
            Assign a case number to group related incidents together.
            All incidents with the same case number can be viewed together.
        </div>
        <div class="form-group">
            <label>Case Number</label>
            <input class="input" id="case-num-input" placeholder="e.g. CASE-2025-001" value="${currentCase || ''}">
        </div>
        ${currentCase ? `<div style="margin-top:8px">
            <button class="btn btn-ghost btn-xs" onclick="viewLinkedIncidents('${currentCase}')">View all incidents in Case ${currentCase}</button>
        </div>` : ''}`,
        async () => {
            const cn = (document.getElementById('case-num-input') || {}).value || '';
            const ok = await nuiFetch('setCaseNumber', { incidentId, caseNumber: cn.trim() });
            if (ok) {
                showToast('Case Linked', cn.trim() ? 'Case number set to ' + cn.trim() : 'Case number removed', 'success');
                closeModal(modal);
                openIncidentDetail(incidentId);
            } else {
                showToast('Error', 'Could not update case number', 'error');
            }
        }, 'Save', '◈');
}

async function viewLinkedIncidents(caseNumber) {
    const panel = document.getElementById('tab-incidents');
    panel.innerHTML = `<div class="panel-header">
        <div class="panel-title">Case: ${caseNumber}</div>
        <div class="panel-actions"><button class="btn btn-ghost btn-sm" onclick="loadIncidents()">← Back</button></div>
    </div>
    <div class="panel-body" id="case-incidents-list"><div class="empty-state"><div class="empty-icon">◈</div><div class="empty-text">Loading...</div></div></div>`;

    const incidents = await nuiFetch('getIncidentsByCase', caseNumber);
    const el = document.getElementById('case-incidents-list');
    if (!el) return;
    if (!incidents || !incidents.length) {
        el.innerHTML = '<div class="empty-state"><div class="empty-icon">◈</div><div class="empty-text">No incidents found for this case</div></div>';
        return;
    }
    el.innerHTML = incidents.map(function(i) {
        return `<div class="card mb-2" onclick="openIncidentDetail(${i.id})" style="cursor:pointer;padding:12px 16px">
            <div style="font-size:14px;font-weight:600;margin-bottom:4px">${esc(i.title)}</div>
            <div style="font-size:12px;color:var(--text-muted)">Report #${i.id} · By ${esc(i.created_by_name)} · ${timeAgo(i.created_at)}</div>
        </div>`;
    }).join('');
}

window.loadIncidents                = loadIncidents;
window.openIncidentDetail           = openIncidentDetail;
window.openNewIncidentModal         = openNewIncidentModal;
window.openEditIncidentModal        = openEditIncidentModal;
window.deleteIncident               = deleteIncident;
window.openCaseNumberModal          = openCaseNumberModal;
window.viewLinkedIncidents          = viewLinkedIncidents;
window.printIncidentReport          = printIncidentReport;
window.createPersonLinker           = createPersonLinker;
window.linkPerson                   = linkPerson;
window.unlinkPerson                 = unlinkPerson;
window.refreshLinkedDisplay         = refreshLinkedDisplay;
window.createRecordLinker           = createRecordLinker;
window.linkRecord                   = linkRecord;
window.unlinkRecord                 = unlinkRecord;
window.refreshLinkedRecordsDisplay  = refreshLinkedRecordsDisplay;

const EVIDENCE_LOOK = {
    photo: ['📷', 'Photo'],
    item:  ['📦', 'Item'],
    note:  ['📝', 'Note'],
};

function renderEvidenceList(list, incidentId) {
    if (!list.length) return '<div class="text-muted text-sm">Nothing logged yet.</div>';

    return list.map(e => {
        const [icon, kindLabel] = EVIDENCE_LOOK[e.kind] || ['🗃', e.kind];
        return `
        <div style="padding:9px 0;border-bottom:1px solid var(--border);display:flex;gap:12px;align-items:flex-start;">
            ${e.kind === 'photo' && e.photo
                ? `<img src="${esc(e.photo)}" alt="" style="width:84px;height:56px;object-fit:cover;border-radius:6px;flex-shrink:0;"
                       onerror="this.style.display='none'">`
                : `<div style="font-size:20px;flex-shrink:0;width:36px;text-align:center;">${icon}</div>`}
            <div style="flex:1;min-width:0;">
                <div style="font-weight:600;font-size:13px;">
                    ${esc(e.label)}
                    <span class="tag tag-gray" style="margin-left:6px;font-size:9.5px;">${esc(kindLabel)}</span>
                </div>
                ${e.detail ? `<div class="text-muted text-sm" style="white-space:pre-wrap;">${esc(e.detail)}</div>` : ''}
                <div class="text-muted" style="font-size:10.5px;margin-top:3px;">
                    Logged by ${esc(e.logged_by_name)} · ${fmtDate(e.created_at)}
                </div>
            </div>
            <button class="btn btn-ghost btn-sm" title="Remove — your own within 15 minutes, or supervisor"
                    onclick="removeEvidence(${e.id}, ${incidentId})">✕</button>
        </div>`;
    }).join('');
}

function openEvidenceModal(incidentId) {
    const modal = createModal('Log Evidence', `
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Type</label>
                <select class="select" id="ev-kind" onchange="document.getElementById('ev-photo-row').style.display = this.value === 'photo' ? '' : 'none'">
                    <option value="item">📦 Item</option>
                    <option value="photo">📷 Photo</option>
                    <option value="note">📝 Note</option>
                </select>
            </div>
            <div class="form-group" style="flex:2;">
                <label class="form-label">Label</label>
                <input class="input" id="ev-label" placeholder="e.g. 9mm casing, kerb outside the bank">
            </div>
        </div>
        <div class="form-group" id="ev-photo-row" style="display:none;">
            <label class="form-label">Photo URL</label>
            <input class="input" id="ev-photo" placeholder="Direct image link (Discord CDN, Imgur…)">
        </div>
        <div class="form-group">
            <label class="form-label">Details</label>
            <textarea class="textarea" id="ev-detail" style="min-height:90px;"
                      placeholder="Where it was found, condition, anything a court would ask."></textarea>
        </div>`,
        async () => {
            const kind = document.getElementById('ev-kind').value;
            const label = document.getElementById('ev-label').value.trim();
            if (!label) { showToast('Label needed', 'Say what the evidence is.', 'error'); return; }

            const res = await nuiFetch('addEvidence', {
                incidentId, kind, label,
                detail: document.getElementById('ev-detail').value.trim(),
                photo: document.getElementById('ev-photo')?.value.trim() || null,
            });

            if (res && res.ok) {
                showToast('Evidence logged', label, 'success');
                closeModal(modal);
                openIncidentDetail(incidentId);
            } else {
                showToast('Not logged', (res && res.error) || 'The server refused it.', 'error');
            }
        }, 'Log It');
}

async function removeEvidence(id, incidentId) {
    const res = await nuiFetch('deleteEvidence', { id });
    if (res && res.ok) {
        showToast('Evidence removed', '', 'success');
        openIncidentDetail(incidentId);
    } else {
        showToast('Not removed', (res && res.error) || 'The server refused it.', 'error');
    }
}

window.incidentCards          = incidentCards;
window.queueIncidentSearch    = queueIncidentSearch;
window.runIncidentSearch      = runIncidentSearch;
window.renderEvidenceList     = renderEvidenceList;
window.openEvidenceModal      = openEvidenceModal;
window.removeEvidence         = removeEvidence;
window.statusTag              = statusTag;
window.statusControl          = statusControl;
window.changeIncidentStatus   = changeIncidentStatus;
window.applyIncidentTemplate  = applyIncidentTemplate;
window.queueDraftAutosave     = queueDraftAutosave;
window.saveIncidentDraft      = saveIncidentDraft;
window.clearIncidentDraft     = clearIncidentDraft;
window.restoreIncidentDraft   = restoreIncidentDraft;
window.applyStoredDraft       = applyStoredDraft;
