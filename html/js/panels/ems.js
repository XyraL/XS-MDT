// XSMDT — EMS panels: Patient Care Reports, Medical Records, Narcotics Log.

const PCR_DISPOSITIONS = [
    { value: 'treated_released', label: 'Treated & Released' },
    { value: 'transported',      label: 'Transported' },
    { value: 'refused',          label: 'Refused Care (AMA)' },
    { value: 'deceased',         label: 'Deceased on Scene' },
    { value: 'no_patient',       label: 'No Patient Found' },
];

const PCR_PRIORITY = {
    1: { label: 'Critical', tag: 'tag-red',    color: 'var(--red)' },
    2: { label: 'Urgent',   tag: 'tag-orange', color: 'var(--orange)' },
    3: { label: 'Standard', tag: 'tag-blue',   color: 'var(--accent)' },
    4: { label: 'Minor',    tag: 'tag-green',  color: 'var(--green)' },
};

const dispositionLabel = v => (PCR_DISPOSITIONS.find(d => d.value === v) || {}).label || v;
const priorityOf = p => PCR_PRIORITY[p] || PCR_PRIORITY[3];

// Comma-separated text <-> array, used for injuries / treatments / allergies etc.
const listToText = a => (a || []).join(', ');
const textToList = t => (t || '').split(',').map(s => s.trim()).filter(Boolean);

// ═══════════════════════════════════════════════════════════════════════════
//  PATIENT CARE REPORTS
// ═══════════════════════════════════════════════════════════════════════════

let _pcrFilter = 'all';

function loadPCRs(filter) {
    if (filter) _pcrFilter = filter;
    const panel = document.getElementById('tab-pcr');
    if (!panel) return;

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Patient Care Reports</div>
                <div class="panel-subtitle">Field reports — one per patient contact</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadPCRs()">↻ Refresh</button>
                <button class="btn btn-primary btn-sm" onclick="openNewPCR()">+ New PCR</button>
            </div>
        </div>
        <div class="panel-toolbar">
            <input type="text" class="input" id="pcr-search" placeholder="Search patient or complaint..." autocomplete="off">
            <div class="panel-actions">
                ${['all', 'mine', 'open'].map(f => `
                    <button class="btn btn-sm ${_pcrFilter === f ? 'btn-primary' : 'btn-ghost'}"
                            onclick="loadPCRs('${f}')">${f === 'all' ? 'All' : f === 'mine' ? 'Mine' : 'Open'}</button>`).join('')}
            </div>
        </div>
        <div class="panel-body" id="pcr-body">
            ${Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    const search = document.getElementById('pcr-search');
    let debounce;
    search.addEventListener('input', () => {
        clearTimeout(debounce);
        debounce = setTimeout(() => fetchPCRs(search.value), 300);
    });

    fetchPCRs('');
}

function fetchPCRs(search) {
    nuiFetch('getPCRs', { filter: _pcrFilter, search }).then(rows => {
        const body = document.getElementById('pcr-body');
        if (!body) return;
        if (!rows || rows.length === 0) {
            body.innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon">✚</div>
                    <div class="empty-title">No patient care reports</div>
                    <div class="empty-subtitle">File one after your next call</div>
                </div>`;
            return;
        }
        body.innerHTML = rows.map(pcrCard).join('');
    });
}

function pcrCard(r) {
    const pri = priorityOf(r.priority);
    return `
        <div class="card" style="border-left:3px solid ${pri.color};margin-bottom:10px;cursor:pointer;"
             onclick="openPCR(${r.id})">
            <div class="card-header" style="margin-bottom:8px;">
                <div style="display:flex;align-items:center;gap:8px;flex:1;flex-wrap:wrap;">
                    <span class="tag ${esc(pri.tag)}">${esc(pri.label)}</span>
                    <span class="font-bold" style="font-size:14px;">${esc(r.patient_name)}</span>
                    ${r.status === 'open' ? '<span class="tag tag-yellow">OPEN</span>' : ''}
                    <span class="text-xs text-muted font-mono">${timeAgo(r.created_at)}</span>
                </div>
                <span class="text-xs text-muted font-mono">PCR #${r.id}</span>
            </div>
            <div style="font-size:13.5px;font-weight:600;color:var(--text-primary);margin-bottom:5px;">
                ${r.chief_complaint}
            </div>
            <div style="font-size:11px;color:var(--text-muted);display:flex;gap:12px;flex-wrap:wrap;">
                <span>${dispositionLabel(r.disposition)}</span>
                ${r.transported_to ? `<span>→ ${r.transported_to}</span>` : ''}
                <span>Medic: <strong class="text-secondary">${r.medic_name}</strong></span>
            </div>
        </div>`;
}

function pcrFormHTML(r = {}) {
    return `
        <div class="form-group">
            <label class="form-label">Patient</label>
            <div id="pcr-patient-search"></div>
            <input type="hidden" id="pcr-cid" value="${r.patient_citizenid || ''}">
            <input type="hidden" id="pcr-pname" value="${esc(r.patient_name || '')}">
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Chief Complaint</label>
                <input type="text" class="input" id="pcr-complaint" value="${r.chief_complaint || ''}"
                       placeholder="e.g. GSW to left thigh">
            </div>
            <div class="form-group">
                <label class="form-label">Priority</label>
                <select class="input" id="pcr-priority">
                    ${[1, 2, 3, 4].map(p => `<option value="${p}" ${String(r.priority || 3) === String(p) ? 'selected' : ''}>${p} — ${PCR_PRIORITY[p].label}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Injuries <span class="form-hint">comma separated</span></label>
            <input type="text" class="input" id="pcr-injuries" value="${listToText(r.injuries)}"
                   placeholder="Gunshot wound, Blood loss, Shock">
        </div>
        <div class="form-group">
            <label class="form-label">Treatments Given <span class="form-hint">comma separated</span></label>
            <input type="text" class="input" id="pcr-treatments" value="${listToText(r.treatments)}"
                   placeholder="Tourniquet, IV fluids, Morphine 4mg">
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">BP</label>
                <input type="text" class="input" id="pcr-bp" value="${(r.vitals || {}).bp || ''}" placeholder="120/80">
            </div>
            <div class="form-group">
                <label class="form-label">Pulse</label>
                <input type="text" class="input" id="pcr-pulse" value="${(r.vitals || {}).pulse || ''}" placeholder="72">
            </div>
            <div class="form-group">
                <label class="form-label">SpO₂</label>
                <input type="text" class="input" id="pcr-spo2" value="${(r.vitals || {}).spo2 || ''}" placeholder="98%">
            </div>
            <div class="form-group">
                <label class="form-label">GCS</label>
                <input type="text" class="input" id="pcr-gcs" value="${(r.vitals || {}).gcs || ''}" placeholder="15">
            </div>
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Disposition</label>
                <select class="input" id="pcr-disposition">
                    ${PCR_DISPOSITIONS.map(d => `<option value="${d.value}" ${r.disposition === d.value ? 'selected' : ''}>${esc(d.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Transported To</label>
                <input type="text" class="input" id="pcr-transport" value="${r.transported_to || ''}"
                       placeholder="Pillbox Hill Medical">
            </div>
            <div class="form-group">
                <label class="form-label">Status</label>
                <select class="input" id="pcr-status">
                    <option value="open"   ${r.status === 'open' ? 'selected' : ''}>Open</option>
                    <option value="closed" ${r.status === 'closed' ? 'selected' : ''}>Closed</option>
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Narrative</label>
            <textarea class="input" id="pcr-narrative" rows="5"
                      placeholder="Arrived on scene to find...">${esc(r.narrative || '')}</textarea>
        </div>`;
}

function readPCRForm() {
    const val = id => (document.getElementById(id) || {}).value || '';
    return {
        patient_citizenid: val('pcr-cid'),
        patient_name     : val('pcr-pname'),
        chief_complaint  : val('pcr-complaint'),
        narrative        : val('pcr-narrative'),
        injuries         : textToList(val('pcr-injuries')),
        treatments       : textToList(val('pcr-treatments')),
        vitals           : { bp: val('pcr-bp'), pulse: val('pcr-pulse'), spo2: val('pcr-spo2'), gcs: val('pcr-gcs') },
        disposition      : val('pcr-disposition'),
        transported_to   : val('pcr-transport'),
        priority         : parseInt(val('pcr-priority')) || 3,
        status           : val('pcr-status') || 'open',
    };
}

function openNewPCR() {
    createModal('New Patient Care Report', pcrFormHTML(), async () => {
        const data = readPCRForm();
        if (!data.patient_citizenid) return showToast('Missing patient', 'Search and pick a patient first.', 'error'), false;
        if (!data.chief_complaint)   return showToast('Missing complaint', 'A chief complaint is required.', 'error'), false;

        const id = await nuiFetch('createPCR', data);
        if (id) { showToast('PCR Filed', `Report #${id} created`, 'success'); loadPCRs(); }
        else showToast('Error', 'Could not file the report.', 'error');
    }, 'File Report', '✚');

    // Reuse the shared name-search component to attach a patient.
    mountNameSearch('pcr-patient-search', (person) => {
        document.getElementById('pcr-cid').value   = person.citizenid;
        document.getElementById('pcr-pname').value = person.name;
    });
}

async function openPCR(id) {
    const r = await nuiFetch('getPCR', id);
    if (!r) return showToast('Error', 'Report not found.', 'error');

    createModal(`PCR #${r.id} — ${esc(r.patient_name)}`, pcrFormHTML(r), async () => {
        const data = readPCRForm();
        data.id = r.id;
        const ok = await nuiFetch('updatePCR', data);
        if (ok) { showToast('PCR Updated', `Report #${r.id} saved`, 'success'); loadPCRs(); }
        else showToast('Error', 'Could not save — you may not be the author.', 'error');
    }, 'Save Changes', '✚');

    mountNameSearch('pcr-patient-search', (person) => {
        document.getElementById('pcr-cid').value   = person.citizenid;
        document.getElementById('pcr-pname').value = person.name;
    }, r.patient_name);
}

// ═══════════════════════════════════════════════════════════════════════════
//  MEDICAL RECORDS
// ═══════════════════════════════════════════════════════════════════════════

function loadMedicalRecords() {
    const panel = document.getElementById('tab-medhistory');
    if (!panel) return;

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Medical Records</div>
                <div class="panel-subtitle">Allergies, conditions, medications and patient history</div>
            </div>
        </div>
        <div class="panel-toolbar">
            <input type="text" class="input" id="med-search" placeholder="Search a patient by name..." autocomplete="off">
        </div>
        <div class="panel-body" id="med-body">
            <div class="empty-state">
                <div class="empty-icon">❤</div>
                <div class="empty-title">Search for a patient</div>
                <div class="empty-subtitle">Type at least two letters of their name</div>
            </div>
        </div>`;

    const search = document.getElementById('med-search');
    let debounce;
    search.addEventListener('input', () => {
        clearTimeout(debounce);
        const q = search.value;
        if (q.length < 2) return;
        debounce = setTimeout(async () => {
            const results = await nuiFetch('searchCivilians', q);
            const body = document.getElementById('med-body');
            if (!body) return;
            if (!results || !results.length) {
                body.innerHTML = `<div class="empty-state"><div class="empty-icon">◎</div>
                    <div class="empty-title">No match</div></div>`;
                return;
            }
            body.innerHTML = results.map(c => `
                <div class="card mb-2" style="cursor:pointer;" onclick="openMedicalRecord('${c.citizenid}')">
                    <div class="font-bold">${esc(c.firstname)} ${esc(c.lastname)}</div>
                    <div class="text-xs text-muted font-mono">DOB ${c.dob || '—'} · ${c.citizenid}</div>
                </div>`).join('');
        }, 300);
    });
}

async function openMedicalRecord(citizenid) {
    const d = await nuiFetch('getMedicalRecord', citizenid);
    const body = document.getElementById('med-body');
    if (!d || !body) return showToast('Error', 'No record found.', 'error');

    const rec = d.record || {};
    const civ = d.civilian || {};

    body.innerHTML = `
        <div class="card mb-2">
            <div class="card-header">
                <div class="card-title">${esc(civ.firstname)} ${esc(civ.lastname)}</div>
                <button class="btn btn-primary btn-sm" onclick="editMedicalRecord('${citizenid}')">Edit Record</button>
            </div>
            <div class="text-xs text-muted font-mono mb-2">
                DOB ${civ.dob || '—'} · ${civ.gender || '—'} · ${civ.phone || 'no phone'}
            </div>
            <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px;">
                ${rec.blood_type ? `<span class="tag tag-red">🩸 ${rec.blood_type}</span>` : ''}
                ${Number(rec.dnr) ? '<span class="tag tag-orange">⚠ DNR</span>' : ''}
                ${Number(rec.organ_donor) ? '<span class="tag tag-green">ORGAN DONOR</span>' : ''}
            </div>
            ${medListBlock('Allergies', rec.allergies, 'tag-red')}
            ${medListBlock('Conditions', rec.conditions, 'tag-orange')}
            ${medListBlock('Medications', rec.medications, 'tag-blue')}
            ${rec.notes ? `<div class="mt-2"><div class="form-label">Notes</div>
                <div style="font-size:12.5px;color:var(--text-secondary);">${esc(rec.notes)}</div></div>` : ''}
        </div>

        <div class="card mb-2">
            <div class="card-header">
                <div class="card-title">History</div>
                <button class="btn btn-ghost btn-sm" onclick="addMedicalEntry('${citizenid}')">+ Add Entry</button>
            </div>
            ${(d.history || []).length ? d.history.map(h => `
                <div style="padding:8px 0;border-bottom:1px solid var(--border);">
                    <div style="display:flex;gap:8px;align-items:center;">
                        <span class="tag tag-gray">${h.entry_type}</span>
                        <span class="text-xs text-muted font-mono">${fmtDateShort(h.created_at)}</span>
                        <span class="text-xs text-muted">— ${h.author_name}</span>
                    </div>
                    <div style="font-size:12.5px;color:var(--text-secondary);margin-top:4px;">${h.entry}</div>
                </div>`).join('')
              : '<div class="text-xs text-muted">No history entries.</div>'}
        </div>

        <div class="card">
            <div class="card-header"><div class="card-title">Prior Patient Care Reports</div></div>
            ${(d.pcrs || []).length ? d.pcrs.map(p => `
                <div style="padding:7px 0;border-bottom:1px solid var(--border);display:flex;gap:10px;align-items:center;cursor:pointer;"
                     onclick="switchTab('pcr');setTimeout(()=>openPCR(${p.id}),120)">
                    <span class="tag ${priorityOf(p.priority).tag}">${priorityOf(p.priority).label}</span>
                    <span style="flex:1;font-size:12.5px;">${p.chief_complaint}</span>
                    <span class="text-xs text-muted font-mono">${fmtDateShort(p.created_at)}</span>
                </div>`).join('')
              : '<div class="text-xs text-muted">No prior reports.</div>'}
        </div>`;
}

function medListBlock(title, items, tagClass) {
    if (!items || !items.length) return '';
    return `<div class="mb-2">
        <div class="form-label">${title}</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;">
            ${items.map(i => `<span class="tag ${tagClass}">${i}</span>`).join('')}
        </div>
    </div>`;
}

async function editMedicalRecord(citizenid) {
    const d = await nuiFetch('getMedicalRecord', citizenid);
    if (!d) return;
    const r = d.record || {};

    createModal('Edit Medical Record', `
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Blood Type</label>
                <select class="input" id="med-blood">
                    <option value="">Unknown</option>
                    ${['A+','A-','B+','B-','AB+','AB-','O+','O-'].map(b =>
                        `<option value="${b}" ${r.blood_type === b ? 'selected' : ''}>${b}</option>`).join('')}
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">DNR</label>
                <select class="input" id="med-dnr">
                    <option value="0" ${!Number(r.dnr) ? 'selected' : ''}>No</option>
                    <option value="1" ${Number(r.dnr) ? 'selected' : ''}>Yes</option>
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Organ Donor</label>
                <select class="input" id="med-organ">
                    <option value="0" ${!Number(r.organ_donor) ? 'selected' : ''}>No</option>
                    <option value="1" ${Number(r.organ_donor) ? 'selected' : ''}>Yes</option>
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Allergies <span class="form-hint">comma separated</span></label>
            <input type="text" class="input" id="med-allergies" value="${listToText(r.allergies)}">
        </div>
        <div class="form-group">
            <label class="form-label">Conditions <span class="form-hint">comma separated</span></label>
            <input type="text" class="input" id="med-conditions" value="${listToText(r.conditions)}">
        </div>
        <div class="form-group">
            <label class="form-label">Medications <span class="form-hint">comma separated</span></label>
            <input type="text" class="input" id="med-medications" value="${listToText(r.medications)}">
        </div>
        <div class="form-group">
            <label class="form-label">Notes</label>
            <textarea class="input" id="med-notes" rows="3">${esc(r.notes || '')}</textarea>
        </div>`, async () => {
        const val = id => (document.getElementById(id) || {}).value || '';
        const ok = await nuiFetch('updateMedicalRecord', {
            citizenid,
            blood_type : val('med-blood'),
            allergies  : textToList(val('med-allergies')),
            conditions : textToList(val('med-conditions')),
            medications: textToList(val('med-medications')),
            dnr        : val('med-dnr') === '1',
            organ_donor: val('med-organ') === '1',
            notes      : val('med-notes'),
        });
        if (ok) { showToast('Record Updated', '', 'success'); openMedicalRecord(citizenid); }
        else showToast('Error', 'Could not save the record.', 'error');
    }, 'Save Record', '❤');
}

function addMedicalEntry(citizenid) {
    createModal('Add History Entry', `
        <div class="form-group">
            <label class="form-label">Type</label>
            <select class="input" id="mhe-type">
                <option value="note">Note</option>
                <option value="diagnosis">Diagnosis</option>
                <option value="procedure">Procedure</option>
                <option value="prescription">Prescription</option>
                <option value="admission">Hospital Admission</option>
            </select>
        </div>
        <div class="form-group">
            <label class="form-label">Entry</label>
            <textarea class="input" id="mhe-text" rows="4" placeholder="Details..."></textarea>
        </div>`, async () => {
        const entry = (document.getElementById('mhe-text') || {}).value || '';
        if (!entry.trim()) return showToast('Empty entry', 'Write something first.', 'error'), false;
        const ok = await nuiFetch('addMedicalEntry', {
            citizenid,
            entry_type: (document.getElementById('mhe-type') || {}).value || 'note',
            entry,
        });
        if (ok) { showToast('Entry Added', '', 'success'); openMedicalRecord(citizenid); }
        else showToast('Error', 'Could not add the entry.', 'error');
    }, 'Add Entry', '❤');
}

// ═══════════════════════════════════════════════════════════════════════════
//  NARCOTICS LOG
// ═══════════════════════════════════════════════════════════════════════════

let _narcFilter = 'mine';

function loadNarcLog(filter) {
    if (filter) _narcFilter = filter;
    const panel = document.getElementById('tab-narclog');
    if (!panel) return;

    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Controlled Substance Log</div>
                <div class="panel-subtitle">Every draw, administration and waste — witnessed</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-ghost btn-sm" onclick="loadNarcLog()">↻ Refresh</button>
                <button class="btn btn-primary btn-sm" onclick="openNarcEntry()">+ Log Entry</button>
            </div>
        </div>
        <div class="panel-toolbar">
            <div class="panel-actions">
                <button class="btn btn-sm ${_narcFilter === 'mine' ? 'btn-primary' : 'btn-ghost'}"
                        onclick="loadNarcLog('mine')">My Entries</button>
                <button class="btn btn-sm ${_narcFilter === 'all' ? 'btn-primary' : 'btn-ghost'}"
                        onclick="loadNarcLog('all')">All (Supervisor)</button>
            </div>
        </div>
        <div class="panel-body" id="narc-body">${skeletonLines(4)}</div>`;

    nuiFetch('getNarcLog', { filter: _narcFilter }).then(d => {
        const body = document.getElementById('narc-body');
        if (!body) return;
        if (!d) {
            body.innerHTML = `<div class="empty-state"><div class="empty-icon">🔒</div>
                <div class="empty-title">Supervisor access required</div>
                <div class="empty-subtitle">The full log is restricted</div></div>`;
            return;
        }
        if (!d.entries.length) {
            body.innerHTML = `<div class="empty-state"><div class="empty-icon">💊</div>
                <div class="empty-title">No entries logged</div></div>`;
            return;
        }

        const totalRows = Object.entries(d.totals).map(([drug, t]) => `
            <div style="display:flex;gap:12px;align-items:center;padding:6px 0;border-bottom:1px solid var(--border);">
                <span class="font-bold" style="flex:1;font-size:12.5px;">${drug}</span>
                <span class="text-xs text-muted">drawn <strong class="text-secondary">${t.drawn || 0}</strong></span>
                <span class="text-xs text-muted">given <strong class="text-secondary">${t.administered || 0}</strong></span>
                <span class="text-xs text-muted">wasted <strong class="text-secondary">${t.wasted || 0}</strong></span>
                ${(t.drawn || 0) !== ((t.administered || 0) + (t.wasted || 0))
                    ? '<span class="tag tag-red">DISCREPANCY</span>' : '<span class="tag tag-green">BALANCED</span>'}
            </div>`).join('');

        const ACTION_TAG = { drawn: 'tag-blue', administered: 'tag-green', wasted: 'tag-orange' };

        body.innerHTML = `
            <div class="card mb-2">
                <div class="card-header"><div class="card-title">Reconciliation</div></div>
                ${totalRows || '<div class="text-xs text-muted">Nothing to reconcile.</div>'}
            </div>
            ${d.entries.map(e => `
                <div class="card mb-2">
                    <div class="card-header" style="margin-bottom:6px;">
                        <div style="display:flex;gap:8px;align-items:center;flex:1;flex-wrap:wrap;">
                            <span class="tag ${ACTION_TAG[e.action] || 'tag-gray'}">${e.action.toUpperCase()}</span>
                            <span class="font-bold">${e.drug}</span>
                            <span class="font-mono text-secondary">${e.amount}${e.unit}</span>
                        </div>
                        <span class="text-xs text-muted font-mono">${timeAgo(e.created_at)}</span>
                    </div>
                    <div style="font-size:11px;color:var(--text-muted);display:flex;gap:12px;flex-wrap:wrap;">
                        ${e.patient_name ? `<span>Patient: <strong class="text-secondary">${esc(e.patient_name)}</strong></span>` : ''}
                        <span>Medic: <strong class="text-secondary">${e.medic_name}</strong></span>
                        ${e.witness_name ? `<span>Witness: <strong class="text-secondary">${e.witness_name}</strong></span>` : '<span class="tag tag-yellow">NO WITNESS</span>'}
                    </div>
                    ${e.notes ? `<div style="font-size:12px;color:var(--text-secondary);margin-top:5px;">${esc(e.notes)}</div>` : ''}
                </div>`).join('')}`;
    });
}

function openNarcEntry() {
    createModal('Log Controlled Substance', `
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Drug</label>
                <input type="text" class="input" id="narc-drug" placeholder="Morphine">
            </div>
            <div class="form-group">
                <label class="form-label">Amount</label>
                <input type="number" class="input" id="narc-amount" value="0" step="0.1" min="0">
            </div>
            <div class="form-group">
                <label class="form-label">Unit</label>
                <select class="input" id="narc-unit">
                    ${['mg', 'mcg', 'mL', 'g'].map(u => `<option value="${u}">${u}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-row">
            <div class="form-group">
                <label class="form-label">Action</label>
                <select class="input" id="narc-action">
                    <option value="drawn">Drawn</option>
                    <option value="administered">Administered</option>
                    <option value="wasted">Wasted</option>
                </select>
            </div>
            <div class="form-group">
                <label class="form-label">Witness</label>
                <input type="text" class="input" id="narc-witness" placeholder="Second medic's name">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Patient <span class="form-hint">optional</span></label>
            <div id="narc-patient-search"></div>
            <input type="hidden" id="narc-cid">
            <input type="hidden" id="narc-pname">
        </div>
        <div class="form-group">
            <label class="form-label">Notes</label>
            <textarea class="input" id="narc-notes" rows="2"></textarea>
        </div>`, async () => {
        const val = id => (document.getElementById(id) || {}).value || '';
        if (!val('narc-drug').trim()) return showToast('Missing drug', 'Name the substance.', 'error'), false;

        const id = await nuiFetch('addNarcEntry', {
            drug: val('narc-drug'), amount: parseFloat(val('narc-amount')) || 0,
            unit: val('narc-unit'), action: val('narc-action'),
            patient_citizenid: val('narc-cid') || null,
            patient_name: val('narc-pname') || null,
            witness_name: val('narc-witness') || null,
            notes: val('narc-notes'),
        });
        if (id) { showToast('Entry Logged', '', 'success'); loadNarcLog(); }
        else showToast('Error', 'Could not log the entry.', 'error');
    }, 'Log Entry', '💊');

    mountNameSearch('narc-patient-search', (person) => {
        document.getElementById('narc-cid').value   = person.citizenid;
        document.getElementById('narc-pname').value = person.name;
    });
}
