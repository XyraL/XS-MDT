function initVehiclePanel() {
    const panel = document.getElementById('tab-vehicles');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Vehicle Lookup</div>
                <div class="panel-subtitle">Search registration and owner info by plate</div>
            </div>
        </div>
        <div class="search-wrap">
            <div class="search-bar">
                <span class="search-icon"><i class="i i-car"></i></span>
                <input type="text" id="plate-search" placeholder="Enter license plate number..."
                       autocomplete="off" maxlength="8" style="text-transform:uppercase;font-family:var(--font-mono);font-size:15px;font-weight:700;letter-spacing:.08em;">
            </div>
            <button class="btn btn-primary" onclick="lookupPlate()">Search Plate</button>
        </div>
        <div class="panel-body" id="vehicle-results">
            <div class="empty-state">
                <div class="empty-icon"><i class="i i-car"></i></div>
                <div class="empty-title">Enter a plate number above</div>
                <div class="empty-subtitle">Press Enter or click Search</div>
            </div>
        </div>`;

    const inp = document.getElementById('plate-search');
    inp.addEventListener('keydown', e => { if (e.key === 'Enter') lookupPlate(); });
    inp.addEventListener('input', e => { e.target.value = e.target.value.toUpperCase(); });
    inp.focus();
}

async function lookupPlate() {
    const plate = document.getElementById('plate-search')?.value.trim().toUpperCase();
    if (!plate) return;
    const el = document.getElementById('vehicle-results');
    el.innerHTML = `<div>${Array(3).fill(0).map(() => `<div class="card mb-2">${skeletonLines(3)}</div>`).join('')}</div>`;

    addSearchHistory('plate', plate);
    const data = await nuiFetch('lookupPlate', plate);

    if (!data || !data.found) {
        const matches = (data && data.matches) || [];
        const bolo = data && data.bolo;

        // A BOLO can sit on a plate nobody has registered, and that is exactly
        // the plate an officer most wants flagged.
        const boloBanner = bolo ? `
            <div class="alert alert-danger" style="margin-bottom:12px;">
                <span><i class="i i-siren"></i></span>
                <div>
                    <strong>ACTIVE BOLO — ${esc(plate)}</strong><br>
                    ${esc(bolo.reason || 'No reason recorded')}
                    ${bolo.issued_by_name ? ` · issued by ${esc(bolo.issued_by_name)}` : ''}
                </div>
            </div>` : '';

        if (!matches.length) {
            el.innerHTML = boloBanner + `
                <div class="empty-state">
                    <div class="empty-icon"><i class="i i-x"></i></div>
                    <div class="empty-title">No vehicle found</div>
                    <div class="empty-subtitle">Plate <span class="font-mono" style="color:var(--accent-2);">${esc(plate)}</span> is not registered</div>
                </div>`;
            return;
        }

        const stateNames = { 0: ['Out', 'tag-yellow'], 1: ['Garaged', 'tag-green'], 2: ['Impounded', 'tag-red'] };

        el.innerHTML = boloBanner + `
            <div class="card">
                <div class="card-header">
                    <div class="card-title">${matches.length} plate${matches.length === 1 ? '' : 's'} containing "${esc(plate)}"</div>
                </div>
                <div class="form-hint" style="margin-bottom:10px;">No exact match. Pick the one you saw.</div>
                <div class="data-table-wrap">
                    <table class="data-table">
                        <thead><tr><th>Plate</th><th>Vehicle</th><th>Owner</th><th>Status</th></tr></thead>
                        <tbody>
                            ${matches.map(m => {
                                const [label, tag] = stateNames[m.state] || ['Unknown', 'tag-gray'];
                                // Plates are alphanumeric in game; stripping to
                                // that set means this is safe to drop into the
                                // handler, which no amount of HTML escaping
                                // would achieve inside an attribute.
                                const safe = String(m.plate || '').replace(/[^A-Za-z0-9 ]/g, '');
                                return `
                                    <tr style="cursor:pointer;" onclick="lookupPlateExact('${safe}')">
                                        <td class="font-mono" style="font-weight:700;letter-spacing:.08em;">${esc(m.plate)}</td>
                                        <td>${esc(m.label || '—')}</td>
                                        <td>${esc(m.owner_name || 'Unregistered')}</td>
                                        <td><span class="tag ${tag}">${label}</span></td>
                                    </tr>`;
                            }).join('')}
                        </tbody>
                    </table>
                </div>
            </div>`;
        return;
    }

    const stateMap = { 0: ['OUT', 'tag-yellow'], 1: ['GARAGED', 'tag-green'], 2: ['IMPOUNDED', 'tag-red'] };
    const [stateLabel, stateTag] = stateMap[data.vehicle.state] || ['UNKNOWN', 'tag-gray'];

    el.innerHTML = `
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">

            <!-- Vehicle Info -->
            <div>
                <div class="card accent-border">
                    <div class="card-header">
                        <div class="card-title">
                            <div class="card-title-icon"><i class="i i-car"></i></div>
                            Vehicle Record
                        </div>
                        <div style="display:flex;gap:6px;flex-wrap:wrap;">
                            ${data.bolo ? '<span class="tag tag-red"><i class="i i-alert"></i> BOLO</span>' : ''}
                            ${data.active_warrants > 0 ? `<span class="tag tag-red"><i class="i i-alert"></i> ${data.active_warrants} Warrant(s)</span>` : ''}
                            <span class="tag ${stateTag}">${stateLabel}</span>
                        </div>
                    </div>
                    <div style="font-size:28px;font-weight:900;font-family:var(--font-mono);letter-spacing:.12em;
                                color:var(--text-primary);margin-bottom:14px;
                                background:var(--bg-input);padding:12px 16px;border-radius:var(--radius);
                                border:1px solid var(--border-light);text-align:center;">
                        ${esc(data.plate)}
                    </div>
                    <div class="info-grid">
                        <div class="info-row">
                            <div class="info-key">Model</div>
                            <div class="info-val">${esc(data.vehicle.label || data.vehicle.model || '—')}</div>
                        </div>
                        <div class="info-row">
                            <div class="info-key">Status</div>
                            <div class="info-val">${stateLabel}</div>
                        </div>
                        <div class="info-row">
                            <div class="info-key">Garage</div>
                            <div class="info-val">${esc(data.vehicle.garage || '—')}</div>
                        </div>
                        <div class="info-row">
                            <div class="info-key">Fuel Level</div>
                            <div class="info-val">${data.vehicle.fuel ? Math.round(data.vehicle.fuel) + '%' : '—'}</div>
                        </div>
                    </div>
                    <div style="display:flex;gap:8px;margin-top:14px;flex-wrap:wrap;">
                        <button class="btn btn-danger btn-sm" onclick="flagStolen('${data.plate}')"><i class="i i-siren"></i> Flag Stolen</button>
                        <button class="btn btn-ghost btn-sm" onclick="openIssueBolo('vehicle','${data.plate}')"><i class="i i-signal"></i> Issue BOLO</button>
                        <button class="btn btn-success btn-sm" onclick="openTrafficStop(${JSON.stringify(data.owner).replace(/"/g,'&quot;')})"><i class="i i-traffic"></i> Traffic Stop</button>
                    </div>
                </div>

                ${data.bolo ? `
                    <div class="alert alert-danger">
                        <span><i class="i i-signal"></i></span>
                        <div>
                            <strong>Active BOLO on this vehicle</strong><br>
                            <span style="font-size:12px;">${esc(data.bolo.description)}</span><br>
                            <span style="font-size:11px;opacity:.7;">Issued by ${data.bolo.issued_by_name}</span>
                        </div>
                    </div>` : ''}
            </div>

            <!-- Owner Info -->
            <div>
                <div class="card">
                    <div class="card-header">
                        <div class="card-title">
                            <div class="card-title-icon"><i class="i i-user"></i></div>
                            Registered Owner
                        </div>
                        <button class="btn btn-ghost btn-sm"
                                onclick="openCivilianProfile('${data.owner.citizenid}');switchTab('civilians');">
                            View Full Profile →
                        </button>
                    </div>
                    <div class="info-grid">
                        <div class="info-row">
                            <div class="info-key">Name</div>
                            <div class="info-val font-bold">${esc(data.owner.name)}</div>
                        </div>
                        <div class="info-row">
                            <div class="info-key">Date of Birth</div>
                            <div class="info-val">${data.owner.dob || '—'}</div>
                        </div>
                        <div class="info-row">
                            <div class="info-key">Phone</div>
                            <div class="info-val font-mono">${data.owner.phone || '—'}</div>
                        </div>
                        <div class="info-row">
                            <div class="info-key">Citizen ID</div>
                            <div class="info-val font-mono text-sm text-muted">${data.owner.citizenid}</div>
                        </div>
                    </div>
                    ${data.active_warrants > 0 ? `
                        <div class="alert alert-danger mt-3">
                            <span><i class="i i-scale"></i></span>
                            <div>Owner has <strong>${data.active_warrants} active warrant(s)</strong> on file.</div>
                        </div>` : `
                        <div class="alert alert-info mt-3">
                            <span>✓</span>
                            <div>Owner has no active warrants on file.</div>
                        </div>`}
                </div>
            </div>
        </div>`;
}

async function flagStolen(plate) {
    const modal = createModal('Flag Vehicle as Stolen', `
        <div class="form-group">
            <label class="form-label">License Plate</label>
            <input class="input font-mono" value="${plate}" disabled style="font-size:16px;font-weight:700;letter-spacing:.1em;">
        </div>
        <div class="form-group">
            <label class="form-label">Additional Description</label>
            <input class="input" id="stolen-desc" placeholder="Color, make, model, last seen location, etc.">
        </div>
        <div class="alert alert-warn">
            <span><i class="i i-alert"></i></span>
            <span>This will create an automatic BOLO and notify all on-duty officers.</span>
        </div>`,
        async () => {
            const desc = document.getElementById('stolen-desc').value.trim();
            const btn = modal.querySelector('#modal-confirm');
            btn.textContent = 'Flagging...'; btn.disabled = true;
            const result = await nuiFetch('flagVehicleStolen', { plate, description: desc });
            if (result) {
                showToast('Vehicle Flagged', `Plate ${plate} flagged as stolen. BOLO issued.`, 'success');
                closeModal(modal);
                lookupPlate();
            } else {
                showToast('Error', 'Could not flag vehicle.', 'error');
                btn.textContent = 'Flag Stolen'; btn.disabled = false;
            }
        }, 'Flag as Stolen', '<i class="i i-siren"></i>');
}

function openTrafficStop(owner) {
    // Pre-fill citation modal with this vehicle owner — one click flow
    openNewCitationModal({ citizenid: owner.citizenid, name: owner.name, dob: owner.dob });
}

// Picking a partial-match row runs the real lookup for that exact plate.
function lookupPlateExact(plate) {
    const input = document.getElementById('plate-search');
    if (!input) return;
    input.value = plate;
    lookupPlate();
}

window.lookupPlateExact = lookupPlateExact;
window.initVehiclePanel = initVehiclePanel;
window.lookupPlate      = lookupPlate;
window.flagStolen       = flagStolen;
window.openTrafficStop  = openTrafficStop;
