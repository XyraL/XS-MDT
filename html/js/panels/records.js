// Prompts for the arrest report. The hard part of writing one is remembering
// what to put in it, not typing it. Edit these freely.
const ARREST_TEMPLATES = {
    'Standard arrest': [
        'Date/time of arrest:',
        'Location:',
        'Reason for contact:',
        'Probable cause for the arrest:',
        'Suspect behaviour (cooperative / resisted / fled):',
        'Search on arrest (items found):',
        'Rights read (by who, when):',
        'Injuries and medical attention:',
        'Transport and booking:',
    ],
    'Warrant arrest': [
        'Date/time of arrest:',
        'Location:',
        'Warrant confirmed (number, charges):',
        'How the suspect was found:',
        'Suspect behaviour:',
        'Search on arrest (items found):',
        'Rights read:',
        'Transport and booking:',
    ],
    'DUI arrest': [
        'Date/time of stop:',
        'Location:',
        'Vehicle (plate, make, colour):',
        'Reason for the stop:',
        'Signs of impairment:',
        'Field sobriety / breath test result:',
        'Rights read:',
        'Vehicle towed or released to:',
    ],
    'Pursuit arrest': [
        'Date/time pursuit started:',
        'Start location and direction:',
        'Reason for the pursuit:',
        'Units involved:',
        'How the pursuit ended:',
        'Suspect behaviour at the end:',
        'Damage or injuries:',
        'Rights read:',
    ],
    'Drug arrest': [
        'Date/time:',
        'Location:',
        'How the drugs were found:',
        'Type and amount seized:',
        'Cash or other items seized:',
        'Evidence booked (numbers):',
        'Rights read:',
    ],
    'Weapons arrest': [
        'Date/time:',
        'Location:',
        'Weapon (type, serial if known):',
        'How the weapon was found:',
        'Owner and licence checked:',
        'Evidence booked (numbers):',
        'Rights read:',
    ],
};

function parseCharges(raw) {
    if (!raw) return [];
    if (Array.isArray(raw)) return raw;
    try { const list = JSON.parse(raw); return Array.isArray(list) ? list : []; } catch (e) { return []; }
}

function chargeSums(charges) {
    return {
        fine: charges.reduce((s, c) => s + (Number(c.fine_amount) || 0), 0),
        jail: charges.reduce((s, c) => s + (Number(c.jail_time) || 0), 0),
    };
}

function applyArrestTemplate(selectId, boxId) {
    const name = document.getElementById(selectId)?.value;
    const box = document.getElementById(boxId);
    if (!name || !box) return;
    const skeleton = (ARREST_TEMPLATES[name] || []).join('\n\n');
    box.value = box.value.trim() ? box.value.trimEnd() + '\n\n' + skeleton : skeleton;
    box.focus();
    queueArrestAutosave();
}

// ── Log Arrest ────────────────────────────────────────────────────────────
// The unsent form is kept on this machine as it is typed, the same as an
// incident report, so a misclick or a crash does not cost the officer it.
const ARREST_DRAFT_KEY = 'XS-MDT:arrest-draft';
let _arrestDraftTimer = null;
let _arrestForm = null;

function openNewArrestModal(prefillPerson = null) {
    const prefill = typeof prefillPerson === 'string' ? { citizenid: prefillPerson } : prefillPerson;
    const form = { suspect: null, reports: null, ns: null };
    _arrestForm = form;

    const modal = createModal('Log Arrest', `
        <div class="form-row">
            <div class="form-group" style="flex:3;">
                <label class="form-label">Suspect</label>
                <div id="arrest-person-search"></div>
            </div>
            <div class="form-group" style="flex:2;">
                <label class="form-label">Location of arrest</label>
                <input class="input" id="arrest-location" placeholder="e.g. Vinewood Blvd" oninput="queueArrestAutosave()">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Charges</label>
            <div id="arrest-charge-picker"></div>
            <div class="selected-charges" id="arrest-selected-charges">
                <span class="text-muted text-sm" style="padding:4px;">No charges selected</span>
            </div>
        </div>
        <div id="charge-total-display" class="charge-total" style="display:none;"></div>
        <div class="form-row" style="margin-top:12px;">
            <div class="form-group">
                <label class="form-label">Fine ($)</label>
                <input class="input font-mono" id="arrest-fine" type="number" min="0" placeholder="From charges"
                       oninput="this.dataset.manual=this.value;queueArrestAutosave()">
            </div>
            <div class="form-group">
                <label class="form-label">Jail time (minutes)</label>
                <input class="input font-mono" id="arrest-jail" type="number" min="0" placeholder="From charges"
                       oninput="this.dataset.manual=this.value;queueArrestAutosave()">
            </div>
            <div class="form-group">
                <label class="form-label">Start from a template</label>
                <select class="select" id="arrest-template" onchange="applyArrestTemplate('arrest-template','arrest-narrative')">
                    <option value="">— Blank —</option>
                    ${Object.keys(ARREST_TEMPLATES).map(t => `<option value="${esc(t)}">${esc(t)}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Arrest report</label>
            <textarea class="textarea" id="arrest-narrative" style="min-height:200px;"
                placeholder="What happened, in order. Pick a template above for the usual prompts."
                oninput="queueArrestAutosave()"></textarea>
            <div class="form-hint" id="arrest-autosave-note">Saved to this machine as you type, so a misclick cannot lose it.</div>
        </div>
        <div class="form-group">
            <label class="form-label">Incident reports <span class="text-muted">(optional)</span></label>
            <div id="arrest-report-linker"></div>
        </div>
        <label class="check-row" style="margin-bottom:12px;">
            <input type="checkbox" id="arrest-clear-warrants" checked style="accent-color:var(--accent);width:14px;height:14px;">
            <span>Clear this person's active warrants</span>
        </label>
        <div class="alert alert-warn">
            <span><i class="i i-alert"></i></span>
            <span>The arrest goes on the person's record as soon as it is logged. The report can be finished afterwards.</span>
        </div>`,
        async () => {
            if (!form.suspect || !form.suspect.citizenid) { showToast('Missing', 'Search and select a suspect first.', 'error'); return; }
            const charges = window._selectedCharges || [];
            if (!charges.length) { showToast('Missing', 'Select at least one charge.', 'error'); return; }

            const sums = chargeSums(charges);
            const fineInput = document.getElementById('arrest-fine').value;
            const jailInput = document.getElementById('arrest-jail').value;

            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Logging...'; btn.disabled = true;

            const res = await nuiFetch('logArrest', {
                citizenid: form.suspect.citizenid,
                charges,
                fine: fineInput === '' ? sums.fine : (parseInt(fineInput) || 0),
                jailTime: jailInput === '' ? sums.jail : (parseInt(jailInput) || 0),
                location: document.getElementById('arrest-location').value.trim(),
                narrative: document.getElementById('arrest-narrative').value.trim(),
                clearWarrants: document.getElementById('arrest-clear-warrants').checked,
                linkedIncidents: form.reports ? form.reports.refs() : [],
            });

            if (res && res.id) {
                clearArrestDraft();
                _arrestForm = null;
                showToast('Arrest logged', `Arrest #${res.id} for ${esc(form.suspect.name || form.suspect.citizenid)}.`, 'success');
                closeModal(modal);
                if (MDT.activeTab === 'arrests') openArrestDetail(res.id);
                else if (MDT.activeTab === 'civilians') openCivilianProfile(form.suspect.citizenid);
            } else {
                btn.textContent = 'Log Arrest'; btn.disabled = false;
            }
        }, 'Log Arrest', '<i class="i i-lock"></i>');

    modal.querySelector('.modal').classList.add('modal-lg');

    form.ns = new NameSearch({
        container: '#arrest-person-search',
        placeholder: 'Search suspect by name...',
        onSelect: (p) => { form.suspect = p; queueArrestAutosave(); },
    });
    if (prefill) form.ns.setValue(prefill);

    form.reports = new RecordPicker({
        container: '#arrest-report-linker',
        kind: 'incident',
        multiple: true,
        placeholder: 'Search reports by number or title...',
        onChange: () => queueArrestAutosave(),
    });

    renderChargePicker('arrest-charge-picker', 'arrest-selected-charges');
    const totals = document.getElementById('charge-total-display');
    if (totals) { totals.style.display = 'flex'; updateChargeTotals(); }

    offerArrestDraft(prefill);
}

function queueArrestAutosave() {
    clearTimeout(_arrestDraftTimer);
    _arrestDraftTimer = setTimeout(saveArrestDraftLocal, 700);
}

function saveArrestDraftLocal() {
    const box = document.getElementById('arrest-narrative');
    if (!box || !_arrestForm) return;
    try {
        const suspect = _arrestForm.suspect;
        const payload = {
            suspect: suspect ? { citizenid: suspect.citizenid, name: suspect.name, dob: suspect.dob } : null,
            location: document.getElementById('arrest-location')?.value || '',
            fine: document.getElementById('arrest-fine')?.dataset.manual ? document.getElementById('arrest-fine').value : '',
            jail: document.getElementById('arrest-jail')?.dataset.manual ? document.getElementById('arrest-jail').value : '',
            narrative: box.value,
            charges: window._selectedCharges || [],
            reports: _arrestForm.reports ? _arrestForm.reports.value() : [],
            at: Date.now(),
        };
        if (!payload.narrative.trim() && !payload.charges.length && !payload.suspect) return;
        localStorage.setItem(ARREST_DRAFT_KEY, JSON.stringify(payload));
        const note = document.getElementById('arrest-autosave-note');
        if (note) note.textContent = 'Saved on this machine at ' + new Date().toLocaleTimeString();
    } catch (e) { /* storage unavailable */ }
}

function clearArrestDraft() {
    try { localStorage.removeItem(ARREST_DRAFT_KEY); } catch (e) {}
}

function readArrestDraft() {
    try { return JSON.parse(localStorage.getItem(ARREST_DRAFT_KEY) || 'null'); } catch (e) { return null; }
}

// Offered, never applied silently: starting a new arrest and finding someone
// else's half-written one filled in is worse than retyping.
function offerArrestDraft(prefill) {
    const saved = readArrestDraft();
    if (!saved || (!saved.narrative && !(saved.charges || []).length)) return;
    if (prefill && saved.suspect && prefill.citizenid && saved.suspect.citizenid !== prefill.citizenid) return;

    const note = document.getElementById('arrest-autosave-note');
    if (!note) return;
    const who = saved.suspect ? ` for ${esc(saved.suspect.name || saved.suspect.citizenid)}` : '';
    note.innerHTML = `Unsent arrest${who} from ${new Date(saved.at).toLocaleString()}.
        <button class="btn btn-ghost btn-xs" onclick="restoreArrestDraft()">Restore it</button> ·
        <button class="btn btn-ghost btn-xs" onclick="clearArrestDraft();document.getElementById('arrest-autosave-note').textContent='Discarded.'">Discard</button>`;
}

function restoreArrestDraft() {
    const saved = readArrestDraft();
    if (!saved || !_arrestForm) return;

    if (saved.suspect && _arrestForm.ns) _arrestForm.ns.setValue(saved.suspect);
    const set = (id, v) => { const el = document.getElementById(id); if (el && v !== undefined && v !== null && v !== '') el.value = v; };
    set('arrest-location', saved.location);
    set('arrest-narrative', saved.narrative);
    if (saved.fine !== '') { set('arrest-fine', saved.fine); document.getElementById('arrest-fine').dataset.manual = saved.fine; }
    if (saved.jail !== '') { set('arrest-jail', saved.jail); document.getElementById('arrest-jail').dataset.manual = saved.jail; }
    if (_arrestForm.reports) _arrestForm.reports.set(saved.reports || []);
    renderChargePicker('arrest-charge-picker', 'arrest-selected-charges', saved.charges || []);

    const note = document.getElementById('arrest-autosave-note');
    if (note) note.textContent = 'Restored.';
}

// ── Arrest report page ────────────────────────────────────────────────────

let _openArrest = null;

async function openArrestDetail(id) {
    const panel = document.getElementById('tab-arrests');
    if (!panel) return;
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Arrest Report</div>
                <div class="panel-subtitle" id="arrest-detail-sub">Arrest #${Number(id)}</div>
            </div>
            <div class="panel-actions" id="arrest-detail-actions">${recordBackButton('initArrestsPanel()')}</div>
        </div>
        <div class="panel-body" id="arrest-detail">
            ${Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    const a = await nuiFetch('getArrest', id);
    const body = document.getElementById('arrest-detail');
    if (!body) return;
    if (!a || !a.id) {
        body.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="i i-alert"></i></div><div class="empty-title">Arrest not found</div></div>';
        return;
    }
    _openArrest = a;

    const charges = parseCharges(a.charges);
    const name = a.civilian_name || a.citizenid;
    const unwritten = !a.narrative;
    const offerWrite = a.canEdit && unwritten;

    const actions = document.getElementById('arrest-detail-actions');
    if (actions) {
        actions.innerHTML = `
            ${recordBackButton('initArrestsPanel()')}
            ${a.canEdit ? `<button class="btn btn-ghost btn-sm" onclick="openEditArrestModal(${a.id})"><i class="i i-edit"></i> Edit</button>` : ''}
            ${a.canDelete ? `<button class="btn btn-danger btn-sm" onclick="deleteArrest(${a.id})"><i class="i i-trash"></i> Delete</button>` : ''}`;
    }
    const sub = document.getElementById('arrest-detail-sub');
    if (sub) sub.textContent = `Arrest #${a.id} · ${fmtDate(a.created_at)}`;

    body.innerHTML = `
        <div class="profile-banner">
            <div class="mugshot-wrap">
                ${a.image ? `<img src="${esc(a.image)}" class="mugshot-img" alt="">` : '<span class="mugshot-placeholder"><i class="i i-user"></i></span>'}
            </div>
            <div class="profile-info">
                <div class="profile-name">${esc(name)}</div>
                <div class="profile-meta">
                    <span class="mono">${esc(a.citizenid)}</span> ${copyBtn(a.citizenid)}
                    ${a.dob ? ` · DOB ${esc(a.dob)}` : ''}
                </div>
                <div class="report-facts">
                    <span><i class="i i-badge"></i> ${esc(a.officer_name)}</span>
                    <span><i class="i i-clock"></i> ${fmtDate(a.created_at)}</span>
                    ${a.location ? `<span><i class="i i-map-pin"></i> ${esc(a.location)}</span>` : ''}
                    ${a.updated_at ? `<span class="text-accent">Edited ${timeAgo(a.updated_at)}</span>` : ''}
                </div>
                ${recordCases('arrest', a.id, `Arrest #${a.id} — ${name}`, a.cases, a.canCases, () => openArrestDetail(a.id))}
            </div>
            <div class="report-totals">
                <div class="report-total"><div class="stat-label">Fine</div><div class="report-total-val fine">${dollarFmt(a.fine)}</div></div>
                <div class="report-total"><div class="stat-label">Jail</div><div class="report-total-val jail">${Number(a.jail_time) || 0} min</div></div>
                <button class="btn btn-ghost btn-sm" onclick="showCivilian('${esc(a.citizenid)}')">View profile</button>
            </div>
        </div>

        <div class="card mb-2">
            <div class="card-header"><div class="card-title">
                <div class="card-title-icon"><i class="i i-scale"></i></div>Charges (${charges.length})
            </div></div>
            ${chargeTable(charges)}
        </div>

        <div class="card mb-2">
            <div class="card-header">
                <div class="card-title"><div class="card-title-icon"><i class="i i-clipboard"></i></div>Arrest report</div>
                ${offerWrite ? `<button class="btn btn-ghost btn-sm" onclick="openEditArrestModal(${a.id})">Write it</button>` : ''}
            </div>
            <div class="card-body">
                ${unwritten
                    ? '<div class="text-muted text-sm">No report written yet.</div>'
                    : `<div class="report-text">${esc(a.narrative)}</div>`}
                ${renderRecordTags('arrest', a.id, a.tags)}
            </div>
        </div>

        <div class="report-grid">
            <div class="card">
                <div class="card-header">
                    <div class="card-title"><div class="card-title-icon"><i class="i i-link"></i></div>Incident reports (${(a.reports || []).length})</div>
                    ${canOpenKind('incident') ? `<button class="btn btn-ghost btn-sm" onclick="linkReportTo('arrest', ${a.id})">+ Link report</button>` : ''}
                </div>
                ${reportRows(a.reports || [], 'arrest', a.id)}
            </div>
            <div class="card">
                <div class="card-header">
                    <div class="card-title"><div class="card-title-icon"><i class="i i-box"></i></div>Evidence (${(a.evidence || []).length})</div>
                    <div style="display:flex;gap:6px;">
                        <button class="btn btn-ghost btn-sm" onclick="bookEvidenceFor('arrest', ${a.id})">+ Book</button>
                        ${canOpenKind('evidence') ? `<button class="btn btn-ghost btn-sm" onclick="attachEvidenceTo('arrest', ${a.id})">Attach</button>` : ''}
                    </div>
                </div>
                ${evidenceRows(a.evidence || [], 'arrest', a.id)}
            </div>
        </div>`;
}

function chargeTable(charges) {
    if (!charges.length) return '<div class="text-muted text-sm">No charges.</div>';
    const sums = chargeSums(charges);
    return `
        <div class="data-table-wrap">
            <table class="data-table static">
                <thead><tr><th>Code</th><th>Charge</th><th>Class</th><th class="ta-right">Fine</th><th class="ta-right">Time</th></tr></thead>
                <tbody>
                    ${charges.map(c => `
                        <tr>
                            <td class="mono">${esc(c.code || '—')}</td>
                            <td>${esc(c.name || c.title || '')}</td>
                            <td>${chargeTypeTag(c.type || 'misdemeanor')}</td>
                            <td class="mono ta-right">${c.fine_amount ? dollarFmt(c.fine_amount) : '—'}</td>
                            <td class="mono ta-right">${c.jail_time ? c.jail_time + ' min' : '—'}</td>
                        </tr>`).join('')}
                    <tr class="charge-sum-row">
                        <td></td><td class="text-muted">From the charge book</td><td></td>
                        <td class="mono ta-right">${dollarFmt(sums.fine)}</td>
                        <td class="mono ta-right">${sums.jail} min</td>
                    </tr>
                </tbody>
            </table>
        </div>`;
}

function reportRows(reports, kind, id) {
    if (!reports.length) return '<div class="text-muted text-sm">No reports linked.</div>';
    return `<div class="link-list">${reports.map(r => `
        <div class="link-row" onclick="openRecord('incident', ${Number(r.id)})">
            <span class="link-row-icon"><i class="i i-clipboard"></i></span>
            <span class="mono link-row-no">${esc(r.case_number || '#' + r.id)}</span>
            <span class="link-row-label">${esc(r.title)}</span>
            <span class="record-meta">${esc(r.created_by_name)}</span>
            <button class="btn btn-ghost btn-xs" title="Unlink" onclick="event.stopPropagation();unlinkReportFrom('${kind}', ${Number(id)}, ${Number(r.id)})"><i class="i i-x"></i></button>
        </div>`).join('')}</div>`;
}

function evidenceRows(items, kind, id) {
    if (!items.length) return '<div class="text-muted text-sm">Nothing attached.</div>';
    const look = (typeof EV_STATUS !== 'undefined') ? EV_STATUS : {};
    return `<div class="link-list">${items.map(e => {
        const st = look[e.status] || { label: e.status || 'booked', tag: 'tag-gray' };
        return `
        <div class="link-row" onclick="openRecord('evidence', ${Number(e.id)})">
            <span class="link-row-icon"><i class="i i-box"></i></span>
            <span class="mono link-row-no">${esc(e.evidence_number || '#' + e.id)}</span>
            <span class="link-row-label">${esc(e.label)}</span>
            <span class="tag ${st.tag}">${esc(st.label)}</span>
            <button class="btn btn-ghost btn-xs" title="Take off" onclick="event.stopPropagation();detachEvidence(${Number(e.id)}, '${kind}', ${Number(id)})"><i class="i i-x"></i></button>
        </div>`;
    }).join('')}</div>`;
}

function reopenRecord(kind, id) {
    if (kind === 'arrest') openArrestDetail(id);
    else if (kind === 'citation') openCitationDetail(id);
    else if (kind === 'incident') openIncidentDetail(id);
}

function linkReportTo(kind, id) {
    pickRecord('Link Incident Report', 'incident', 'Search reports by number or title...', async (r) => {
        const ok = await nuiFetch('setIncidentLink', { kind, recordId: id, incidentId: r.ref, add: true });
        if (!ok) return false;
        showToast('Report linked', r.label, 'success', 2500);
        reopenRecord(kind, id);
    });
}

async function unlinkReportFrom(kind, id, incidentId) {
    const ok = await nuiFetch('setIncidentLink', { kind, recordId: id, incidentId, add: false });
    if (ok) reopenRecord(kind, id);
}

function bookEvidenceFor(kind, id) {
    const opts = { after: () => reopenRecord(kind, id) };
    if (kind === 'arrest') {
        const a = _openArrest && _openArrest.id === id ? _openArrest : null;
        opts.arrest = { ref: id, label: `Arrest #${id}` + (a ? ` — ${a.civilian_name || a.citizenid}` : '') };
    }
    if (kind === 'incident') {
        const r = typeof _openIncident !== 'undefined' && _openIncident && _openIncident.id === id ? _openIncident : null;
        opts.report = { ref: id, label: r ? (r.case_number || '#' + r.id) + ' — ' + r.title : 'Report #' + id };
    }
    openBookEvidence(opts);
}

function attachEvidenceTo(kind, id) {
    pickRecord('Attach Evidence', 'evidence', 'Search by evidence number or item...', async (e) => {
        const ok = await nuiFetch('linkEvidence', { id: e.ref, kind, ref: id });
        if (!ok) return false;
        showToast('Evidence attached', e.label, 'success', 2500);
        reopenRecord(kind, id);
    });
}

async function detachEvidence(evidenceId, kind, id) {
    const ok = await nuiFetch('linkEvidence', { id: evidenceId, kind, ref: 0 });
    if (ok) reopenRecord(kind, id);
}

function openEditArrestModal(id) {
    const a = _openArrest && _openArrest.id === id ? _openArrest : null;
    if (!a) { openArrestDetail(id); return; }

    const modal = createModal(`Edit Arrest #${a.id}`, `
        <div class="form-row">
            <div class="form-group" style="flex:2;">
                <label class="form-label">Location of arrest</label>
                <input class="input" id="arrest-edit-location" value="${esc(a.location || '')}">
            </div>
            <div class="form-group">
                <label class="form-label">Fine ($)</label>
                <input class="input font-mono" id="arrest-edit-fine" type="number" min="0" value="${Number(a.fine) || 0}" data-manual="1"
                       oninput="this.dataset.manual=this.value">
            </div>
            <div class="form-group">
                <label class="form-label">Jail (minutes)</label>
                <input class="input font-mono" id="arrest-edit-jail" type="number" min="0" value="${Number(a.jail_time) || 0}" data-manual="1"
                       oninput="this.dataset.manual=this.value">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Charges</label>
            <div id="arrest-edit-charge-picker"></div>
            <div class="selected-charges" id="arrest-edit-selected-charges"></div>
        </div>
        <div class="form-row">
            <div class="form-group" style="flex:1;">
                <label class="form-label">Add a template</label>
                <select class="select" id="arrest-edit-template" onchange="applyArrestTemplate('arrest-edit-template','arrest-edit-narrative')">
                    <option value="">— None —</option>
                    ${Object.keys(ARREST_TEMPLATES).map(t => `<option value="${esc(t)}">${esc(t)}</option>`).join('')}
                </select>
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Arrest report</label>
            <textarea class="textarea" id="arrest-edit-narrative" style="min-height:240px;">${esc(a.narrative || '')}</textarea>
        </div>
        <div class="form-hint">Changing the charges here corrects the record. It does not jail or fine anyone again.</div>`,
        async () => {
            const charges = window._selectedCharges || [];
            if (!charges.length) { showToast('Missing', 'Keep at least one charge.', 'error'); return; }
            const ok = await nuiFetch('updateArrest', {
                id: a.id,
                charges,
                fine: parseInt(document.getElementById('arrest-edit-fine').value) || 0,
                jailTime: parseInt(document.getElementById('arrest-edit-jail').value) || 0,
                location: document.getElementById('arrest-edit-location').value.trim(),
                narrative: document.getElementById('arrest-edit-narrative').value.trim(),
            });
            if (ok) {
                showToast('Arrest updated', '', 'success', 2500);
                closeModal(modal);
                openArrestDetail(a.id);
            }
        }, 'Save Changes', '<i class="i i-edit"></i>');

    modal.querySelector('.modal').classList.add('modal-lg');
    renderChargePicker('arrest-edit-charge-picker', 'arrest-edit-selected-charges', parseCharges(a.charges));
}

function deleteArrest(id) {
    const modal = createModal('Delete Arrest', `
        <div class="alert alert-danger">
            <span><i class="i i-alert"></i></span>
            <div>
                <strong>Delete arrest #${Number(id)}?</strong><br>
                <span style="font-size:12px;">It comes off the person's record, and any reports, evidence and cases stop pointing at it. This cannot be undone.</span>
            </div>
        </div>`,
        async () => {
            const ok = await nuiFetch('deleteArrest', id);
            if (ok) {
                showToast('Arrest deleted', `Arrest #${Number(id)} removed.`, 'success');
                closeModal(modal);
                MDT.fromCase = null;
                initArrestsPanel();
            }
        }, 'Delete', '<i class="i i-trash"></i>');
}

// ── Citation Modal ────────────────────────────────────────────────────────
function openNewCitationModal(prefillPerson = null) {
    const prefill = typeof prefillPerson === 'string' ? { citizenid: prefillPerson } : prefillPerson;
    let _citePerson = null;

    const modal = createModal('Issue Citation', `
        <div class="form-group">
            <label class="form-label">Civilian</label>
            <div id="cite-person-search"></div>
        </div>
        <div class="form-group">
            <label class="form-label">Select Charges</label>
            <div id="cite-charge-picker"></div>
        </div>
        <div class="form-group">
            <label class="form-label">Selected Charges</label>
            <div class="selected-charges" id="cite-selected-charges">
                <span class="text-muted text-sm" style="padding:4px;">No charges selected</span>
            </div>
        </div>
        <div id="charge-total-display" class="charge-total" style="display:none;"></div>
        <div class="form-row" style="margin-top:12px;">
            <div class="form-group">
                <label class="form-label">Fine Amount ($)</label>
                <input class="input font-mono" id="cite-fine" type="number" min="0" placeholder="Auto-calculated"
                       oninput="this.dataset.manual=this.value">
            </div>
            <div class="form-group">
                <label class="form-label">Location</label>
                <input class="input" id="cite-location" placeholder="Where was this citation issued?">
            </div>
        </div>
        <div class="form-group">
            <label class="form-label">Notes (optional)</label>
            <input class="input" id="cite-notes" placeholder="Additional notes about this citation">
        </div>
        <div class="form-group">
            <label class="form-label" style="display:flex;align-items:center;gap:8px;cursor:pointer;font-weight:400;">
                <input type="checkbox" id="cite-autopay" style="accent-color:var(--accent);width:14px;height:14px;">
                <span>Take the fine from their bank now (they must be in the city)</span>
            </label>
        </div>`,
        async () => {
            if (!_citePerson || !_citePerson.citizenid) { showToast('Missing', 'Search and select a civilian first.', 'error'); return; }
            const charges = window._selectedCharges || [];
            if (!charges.length) { showToast('Missing', 'Select at least one charge.', 'error'); return; }
            const fineInput = document.getElementById('cite-fine').value;
            const fine = fineInput === '' ? chargeSums(charges).fine : (parseInt(fineInput) || 0);

            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Issuing...'; btn.disabled = true;
            const res = await nuiFetch('issueCitation', {
                citizenid: _citePerson.citizenid, charges, fine,
                location: document.getElementById('cite-location').value.trim(),
                notes: document.getElementById('cite-notes').value.trim(),
                autoPay: document.getElementById('cite-autopay').checked,
            });
            if (res && res.id) {
                showToast('Citation issued', `Citation #${res.id} — ${dollarFmt(fine)} for ${esc(_citePerson.name || _citePerson.citizenid)}`, 'success');
                closeModal(modal);
                if (MDT.activeTab === 'citations') openCitationDetail(res.id);
                else if (MDT.activeTab === 'civilians') openCivilianProfile(_citePerson.citizenid);
            } else {
                btn.textContent = 'Issue Citation'; btn.disabled = false;
            }
        }, 'Issue Citation', '<i class="i i-file"></i>');

    const ns = new NameSearch({
        container: '#cite-person-search',
        placeholder: 'Search civilian by name...',
        onSelect: (p) => { _citePerson = p; },
    });
    if (prefill) ns.setValue(prefill);

    renderChargePicker('cite-charge-picker', 'cite-selected-charges');
    const totals = document.getElementById('charge-total-display');
    if (totals) { totals.style.display = 'flex'; updateChargeTotals(); }
}

// ── Citation page ─────────────────────────────────────────────────────────

async function openCitationDetail(id) {
    const panel = document.getElementById('tab-citations');
    if (!panel) return;
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Citation</div>
                <div class="panel-subtitle" id="citation-detail-sub">Citation #${Number(id)}</div>
            </div>
            <div class="panel-actions" id="citation-detail-actions">${recordBackButton('initCitationsPanel()')}</div>
        </div>
        <div class="panel-body" id="citation-detail">
            ${Array(2).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    const c = await nuiFetch('getCitation', id);
    const body = document.getElementById('citation-detail');
    if (!body) return;
    if (!c || !c.id) {
        body.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="i i-alert"></i></div><div class="empty-title">Citation not found</div></div>';
        return;
    }

    const paid = c.paid == 1 || c.paid === true;
    const name = c.civilian_name || c.citizenid;
    const charges = parseCharges(c.charges);

    const actions = document.getElementById('citation-detail-actions');
    if (actions) {
        actions.innerHTML = `
            ${recordBackButton('initCitationsPanel()')}
            ${!paid && c.canMarkPaid ? `<button class="btn btn-success btn-sm" onclick="markCitationPaid(${c.id}, true)">Mark paid</button>` : ''}`;
    }
    const sub = document.getElementById('citation-detail-sub');
    if (sub) sub.textContent = `Citation #${c.id} · ${fmtDate(c.created_at)}`;

    body.innerHTML = `
        <div class="profile-banner">
            <div class="mugshot-wrap">
                ${c.image ? `<img src="${esc(c.image)}" class="mugshot-img" alt="">` : '<span class="mugshot-placeholder"><i class="i i-user"></i></span>'}
            </div>
            <div class="profile-info">
                <div class="profile-name">${esc(name)} <span class="tag ${paid ? 'tag-green' : 'tag-red'}">${paid ? 'PAID' : 'UNPAID'}</span></div>
                <div class="profile-meta"><span class="mono">${esc(c.citizenid)}</span> ${copyBtn(c.citizenid)}${c.dob ? ` · DOB ${esc(c.dob)}` : ''}</div>
                <div class="report-facts">
                    <span><i class="i i-badge"></i> ${esc(c.officer_name)}</span>
                    <span><i class="i i-clock"></i> ${fmtDate(c.created_at)}</span>
                    ${c.location ? `<span><i class="i i-map-pin"></i> ${esc(c.location)}</span>` : ''}
                </div>
                ${recordCases('citation', c.id, `Citation #${c.id} — ${name}`, c.cases, c.canCases, () => openCitationDetail(c.id))}
            </div>
            <div class="report-totals">
                <div class="report-total"><div class="stat-label">Fine</div><div class="report-total-val fine">${dollarFmt(c.fine)}</div></div>
                <button class="btn btn-ghost btn-sm" onclick="showCivilian('${esc(c.citizenid)}')">View profile</button>
            </div>
        </div>

        <div class="card mb-2">
            <div class="card-header"><div class="card-title">
                <div class="card-title-icon"><i class="i i-scale"></i></div>Charges (${charges.length})
            </div></div>
            ${chargeTable(charges)}
            <div class="card-body">
                ${c.notes ? `<div class="report-section-label">Notes</div><div class="report-text">${esc(c.notes)}</div>` : ''}
                ${renderRecordTags('citation', c.id, c.tags)}
            </div>
        </div>

        <div class="card">
            <div class="card-header">
                <div class="card-title"><div class="card-title-icon"><i class="i i-link"></i></div>Incident reports (${(c.reports || []).length})</div>
                ${canOpenKind('incident') ? `<button class="btn btn-ghost btn-sm" onclick="linkReportTo('citation', ${c.id})">+ Link report</button>` : ''}
            </div>
            ${reportRows(c.reports || [], 'citation', c.id)}
        </div>`;
}

// ── Shared filter row builder ─────────────────────────────────────────────
function _filterRow(type) {
    const isA = type === 'arrest';
    const pfx = isA ? 'arrest' : 'cite';
    return `
        <div class="records-filter-row">
            <div class="search-bar" style="flex:1.4;min-width:160px;">
                <span class="search-icon"><i class="i i-user"></i></span>
                <input type="text" id="${pfx}-search-input" placeholder="Civilian name or Citizen ID..." autocomplete="off">
            </div>
            <div class="search-bar" style="flex:1;min-width:140px;">
                <span class="search-icon"><i class="i i-badge"></i></span>
                <input type="text" id="${pfx}-officer-input" placeholder="Officer name..." autocomplete="off">
            </div>
            <span class="filter-label">From</span>
            <input type="date" class="input input-sm date-input" id="${pfx}-date-from">
            <span class="filter-label">To</span>
            <input type="date" class="input input-sm date-input" id="${pfx}-date-to">
            <button class="btn btn-primary btn-sm" onclick="${isA ? 'searchArrests' : 'searchCitations'}()">Search</button>
            <button class="btn btn-ghost btn-sm" onclick="${isA ? 'clearArrestFilters' : 'clearCitationFilters'}()">Clear</button>
        </div>`;
}

function _getFilters(pfx) {
    return {
        query:    document.getElementById(`${pfx}-search-input`)?.value.trim() || '',
        officer:  document.getElementById(`${pfx}-officer-input`)?.value.trim() || '',
        dateFrom: document.getElementById(`${pfx}-date-from`)?.value || '',
        dateTo:   document.getElementById(`${pfx}-date-to`)?.value || '',
    };
}

function _hasActiveFilters(pfx) {
    const f = _getFilters(pfx);
    return f.query || f.officer || f.dateFrom || f.dateTo;
}

function _bindFilterKeys(pfx, searchFn) {
    [`${pfx}-search-input`, `${pfx}-officer-input`].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.addEventListener('keydown', e => { if (e.key === 'Enter') searchFn(); });
    });
}

// ── Arrests Tab ───────────────────────────────────────────────────────────
function initArrestsPanel() {
    MDT.fromCase = null;
    const panel = document.getElementById('tab-arrests');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Arrest Records</div>
                <div class="panel-subtitle">Latest 25. Click one to open the full report.</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-danger btn-sm" onclick="openNewArrestModal()"><i class="i i-lock"></i> Log Arrest</button>
            </div>
        </div>
        ${_filterRow('arrest')}
        <div class="panel-body" id="arrests-body">
            ${Array(4).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;
    _bindFilterKeys('arrest', searchArrests);
    loadRecentArrests();
}

async function loadRecentArrests() {
    const results = await nuiFetch('getRecentArrests');
    renderRecordBody(document.getElementById('arrests-body'), results, renderArrestsList, '<i class="i i-lock"></i>', 'No arrest records yet');
}

async function searchArrests() {
    const filters = _getFilters('arrest');
    if (!_hasActiveFilters('arrest')) { loadRecentArrests(); return; }
    const body = document.getElementById('arrests-body');
    if (!body) return;
    body.innerHTML = Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('');
    const results = await nuiFetch('searchArrests', filters);
    renderRecordBody(document.getElementById('arrests-body'), results, renderArrestsList, '<i class="i i-lock"></i>', 'No arrest records found');
}

function clearArrestFilters() {
    ['arrest-search-input','arrest-officer-input','arrest-date-from','arrest-date-to']
        .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
    loadRecentArrests();
}

// ── Citations Tab ─────────────────────────────────────────────────────────
function initCitationsPanel() {
    MDT.fromCase = null;
    const panel = document.getElementById('tab-citations');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Citations</div>
                <div class="panel-subtitle">Latest 25. Click one to open it.</div>
            </div>
            <div class="panel-actions">
                <button class="btn btn-success btn-sm" onclick="openNewCitationModal()"><i class="i i-file"></i> Issue Citation</button>
            </div>
        </div>
        ${_filterRow('citation')}
        <div class="panel-body" id="citations-body">
            ${Array(4).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}
        </div>`;
    _bindFilterKeys('cite', searchCitations);
    loadRecentCitations();
}

async function loadRecentCitations() {
    const results = await nuiFetch('getRecentCitations');
    renderRecordBody(document.getElementById('citations-body'), results, renderCitationsList, '<i class="i i-file"></i>', 'No citations yet');
}

async function searchCitations() {
    const filters = _getFilters('cite');
    if (!_hasActiveFilters('cite')) { loadRecentCitations(); return; }
    const body = document.getElementById('citations-body');
    if (!body) return;
    body.innerHTML = Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('');
    const results = await nuiFetch('searchCitations', filters);
    renderRecordBody(document.getElementById('citations-body'), results, renderCitationsList, '<i class="i i-file"></i>', 'No citations found');
}

function clearCitationFilters() {
    ['cite-search-input','cite-officer-input','cite-date-from','cite-date-to']
        .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
    loadRecentCitations();
}

function renderRecordBody(body, results, renderFn, icon, emptyMsg) {
    if (!body) return;
    if (!Array.isArray(results) || !results.length) {
        body.innerHTML = `<div class="empty-state"><div class="empty-icon">${icon}</div><div class="empty-title">${emptyMsg}</div></div>`;
        return;
    }
    body.innerHTML = renderFn(results);
}

// ── Tag System ────────────────────────────────────────────────────────────
const TAG_PRESETS = [
    'Gang Related','Drug Related','Weapon Involved','Repeat Offender',
    'Fleeing','Court Date Set','High Profile','ATL','Domestic','DUI','Warrant Issued',
];

function parseTags(raw) {
    if (!raw) return [];
    try { return typeof raw === 'string' ? JSON.parse(raw) : raw; } catch(e) { return []; }
}

function renderRecordTags(type, id, tags) {
    const list = parseTags(tags);
    return `
        <div class="record-tags-row" id="tags-row-${type}-${id}" onclick="event.stopPropagation()">
            ${list.map((t, i) => `
                <span class="record-user-tag">
                    ${esc(t)}<button class="tag-remove" title="Remove" onclick="event.stopPropagation();removeRecordTag('${type}',${id},${i})">×</button>
                </span>`).join('')}
            <button class="btn-add-tag" onclick="openTagPicker(event,'${type}',${id})">+ Tag</button>
        </div>`;
}

function openTagPicker(e, type, id) {
    e.stopPropagation();
    document.querySelectorAll('.tag-picker-popup').forEach(el => el.remove());
    const row = document.getElementById(`tags-row-${type}-${id}`);
    const existing = parseTags(_getRecordTagsFromRow(row));
    const popup = document.createElement('div');
    popup.className = 'tag-picker-popup';
    popup.innerHTML = `
        <input type="text" id="tag-custom-input" placeholder="Type a tag or pick below...">
        <div class="tag-preset-grid">
            ${TAG_PRESETS.filter(t => !existing.includes(t)).map(t =>
                `<button class="tag-preset-btn" onclick="addRecordTagDirect('${type}',${id},'${t}')">${t}</button>`
            ).join('')}
        </div>`;
    const rect = e.target.getBoundingClientRect();
    popup.style.top  = (rect.bottom + 6) + 'px';
    popup.style.left = rect.left + 'px';
    document.body.appendChild(popup);
    const inp = popup.querySelector('#tag-custom-input');
    inp.focus();
    inp.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') {
            const val = inp.value.trim();
            if (val) addRecordTagDirect(type, id, val);
        }
        if (ev.key === 'Escape') popup.remove();
    });
    setTimeout(() => {
        document.addEventListener('click', function closeIt(ev) {
            if (!popup.contains(ev.target)) { popup.remove(); document.removeEventListener('click', closeIt); }
        }, { capture: true });
    }, 100);
}

function _getRecordTagsFromRow(row) {
    if (!row) return [];
    return [...row.querySelectorAll('.record-user-tag')].map(el => el.childNodes[0].textContent.trim());
}

function addRecordTagDirect(type, id, tag) {
    document.querySelectorAll('.tag-picker-popup').forEach(el => el.remove());
    const row = document.getElementById(`tags-row-${type}-${id}`);
    const tags = _getRecordTagsFromRow(row);
    if (!tags.includes(tag)) tags.push(tag);
    _saveAndRerenderTags(type, id, tags);
}

function removeRecordTag(type, id, idx) {
    const row = document.getElementById(`tags-row-${type}-${id}`);
    const tags = _getRecordTagsFromRow(row);
    tags.splice(idx, 1);
    _saveAndRerenderTags(type, id, tags);
}

function _saveAndRerenderTags(type, id, tags) {
    const row = document.getElementById(`tags-row-${type}-${id}`);
    if (!row) return;
    const dummy = document.createElement('div');
    dummy.innerHTML = renderRecordTags(type, id, tags);
    row.replaceWith(dummy.firstElementChild);
    nuiFetch('updateRecordTags', { type, id, tags });
}

// ── List cards ────────────────────────────────────────────────────────────
function chargeLine(charges, fallbackType) {
    const shown = charges.slice(0, 3).map(c =>
        `<span class="charge-inline">${chargeTypeTag(c.type || fallbackType)} ${esc(c.name || c.title || '')}</span>`).join('');
    const more = charges.length > 3 ? `<span class="text-muted text-sm">+${charges.length - 3} more</span>` : '';
    return shown + more;
}

function renderArrestsList(list) {
    return list.map(a => {
        const charges = parseCharges(a.charges);
        const written = Boolean(a.narrative);
        return `
            <div class="record-card clickable arrest-card" onclick="openArrestDetail(${Number(a.id)})">
                <div class="record-head">
                    <span class="record-icon"><i class="i i-lock"></i></span>
                    <span class="record-title">${esc(a.civilian_name || a.citizenid)}</span>
                    ${copyBtn(a.citizenid)}
                    <span class="mono record-no">#${Number(a.id)}</span>
                    <span class="record-meta">${esc(a.officer_name)} · ${fmtDate(a.created_at)}</span>
                </div>
                <div class="record-line charge-line">${chargeLine(charges, 'misdemeanor')}</div>
                <div class="report-figures">
                    ${a.fine > 0 ? `<span><i class="i i-cash"></i> ${dollarFmt(a.fine)}</span>` : ''}
                    ${a.jail_time > 0 ? `<span><i class="i i-clock"></i> ${Number(a.jail_time)} min</span>` : ''}
                    ${a.location ? `<span><i class="i i-map-pin"></i> ${esc(a.location)}</span>` : ''}
                    ${written ? '' : '<span class="tag tag-yellow">No report written</span>'}
                </div>
                ${renderRecordTags('arrest', a.id, a.tags)}
            </div>`;
    }).join('');
}

function renderCitationsList(list) {
    return list.map(c => {
        const charges = parseCharges(c.charges);
        const paid = c.paid == 1 || c.paid === true;
        return `
            <div class="record-card clickable citation-card" id="citation-card-${Number(c.id)}" onclick="openCitationDetail(${Number(c.id)})">
                <div class="record-head">
                    <span class="record-icon"><i class="i i-file"></i></span>
                    <span class="record-title">${esc(c.civilian_name || c.citizenid)}</span>
                    ${copyBtn(c.citizenid)}
                    <span class="mono record-no">#${Number(c.id)}</span>
                    <span class="tag ${paid ? 'tag-green' : 'tag-red'}">${paid ? 'PAID' : 'UNPAID'}</span>
                    <span class="record-meta">${esc(c.officer_name)} · ${fmtDate(c.created_at)}</span>
                </div>
                <div class="record-line charge-line">${chargeLine(charges, 'infraction')}</div>
                <div class="report-figures">
                    ${c.fine > 0 ? `<span><i class="i i-cash"></i> ${dollarFmt(c.fine)}</span>` : ''}
                    ${c.location ? `<span><i class="i i-map-pin"></i> ${esc(c.location)}</span>` : ''}
                    ${c.notes ? `<span>${esc(c.notes)}</span>` : ''}
                </div>
                ${renderRecordTags('citation', c.id, c.tags)}
            </div>`;
    }).join('');
}

async function markCitationPaid(id, reopen) {
    const result = await nuiFetch('markCitationPaid', id);
    if (!result) { showToast('Error', 'Could not mark citation as paid.', 'error'); return; }
    showToast('Citation marked paid', '', 'success');
    if (reopen) openCitationDetail(id);
}

window.openNewArrestModal   = openNewArrestModal;
window.openArrestDetail     = openArrestDetail;
window.openEditArrestModal  = openEditArrestModal;
window.deleteArrest         = deleteArrest;
window.applyArrestTemplate  = applyArrestTemplate;
window.queueArrestAutosave  = queueArrestAutosave;
window.clearArrestDraft     = clearArrestDraft;
window.restoreArrestDraft   = restoreArrestDraft;
window.openNewCitationModal = openNewCitationModal;
window.openCitationDetail   = openCitationDetail;
window.linkReportTo         = linkReportTo;
window.unlinkReportFrom     = unlinkReportFrom;
window.bookEvidenceFor      = bookEvidenceFor;
window.attachEvidenceTo     = attachEvidenceTo;
window.detachEvidence       = detachEvidence;
window.initArrestsPanel     = initArrestsPanel;
window.initCitationsPanel   = initCitationsPanel;
window.searchArrests        = searchArrests;
window.searchCitations      = searchCitations;
window.clearArrestFilters   = clearArrestFilters;
window.clearCitationFilters = clearCitationFilters;
window.renderArrestsList    = renderArrestsList;
window.renderCitationsList  = renderCitationsList;
window.markCitationPaid     = markCitationPaid;
window.renderRecordTags     = renderRecordTags;
window.openTagPicker        = openTagPicker;
window.addRecordTagDirect   = addRecordTagDirect;
window.removeRecordTag      = removeRecordTag;
