// ── Weapons registry ──────────────────────────────────────────────────────
//
// Serial numbers are the point. A seized firearm is looked up by serial, and a
// serial that is not in here is an unregistered one — which is a charge.

const WEAPON_STATUS = {
    registered:   { label: 'Registered',   tag: 'tag-green' },
    stolen:       { label: 'Stolen',       tag: 'tag-red' },
    seized:       { label: 'Seized',       tag: 'tag-yellow' },
    destroyed:    { label: 'Destroyed',    tag: 'tag-gray' },
    unregistered: { label: 'Unregistered', tag: 'tag-orange' },
};

const WEAPON_CLASSES = ['Handgun', 'Shotgun', 'Rifle', 'SMG', 'Heavy', 'Melee', 'Other'];

let _wFilter = { status: 'all', search: '' };
let _weapons = null;

function loadWeapons() {
    const panel = document.getElementById('tab-weapons');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Weapons Registry</div>
                <div class="panel-subtitle">Registered, stolen and seized firearms</div>
            </div>
            <div class="panel-actions">
                <div class="seg" id="w-status">
                    ${[['all', 'All'], ...Object.entries(WEAPON_STATUS).map(([k, v]) => [k, v.label])]
                        .map(([k, label]) => `<button class="seg-btn ${_wFilter.status === k ? 'active' : ''}" data-status="${k}">${label}</button>`).join('')}
                </div>
                <div class="search-bar" style="width:230px;">
                    <span class="search-icon"><i class="i i-search"></i></span>
                    <input type="text" id="w-search" placeholder="Serial, model or owner...">
                </div>
                <button class="btn btn-primary btn-sm" onclick="openWeaponEditor()">Add Firearm</button>
            </div>
        </div>
        <div class="panel-body" id="w-body">${skeletonLines(5)}</div>`;

    document.getElementById('w-status').onclick = (e) => {
        const btn = e.target.closest('.seg-btn');
        if (!btn) return;
        _wFilter.status = btn.dataset.status;
        btn.parentElement.querySelectorAll('.seg-btn').forEach(b => b.classList.toggle('active', b === btn));
        fetchWeapons();
    };

    let timer;
    document.getElementById('w-search').oninput = (e) => {
        clearTimeout(timer);
        _wFilter.search = e.target.value.trim();
        timer = setTimeout(fetchWeapons, 250);
    };

    fetchWeapons();
}

function fetchWeapons() {
    nuiFetch('getWeapons', _wFilter).then(data => {
        _weapons = data;
        const body = document.getElementById('w-body');
        if (!body) return;

        if (!data || !data.weapons || !data.weapons.length) {
            body.innerHTML = `<div class="empty-state">
                <div class="empty-icon"><i class="i i-alert"></i></div>
                <div class="empty-title">Nothing on the registry</div>
                <div class="empty-subtitle">Add a firearm when it is registered, seized or reported stolen.</div>
            </div>`;
            return;
        }

        body.innerHTML = `
            <div class="w-table">
                <div class="w-head">
                    <span>Serial</span><span>Model</span><span>Class</span>
                    <span>Owner</span><span>Status</span><span>Registered</span>
                </div>
                ${data.weapons.map(w => {
                    const st = WEAPON_STATUS[w.status] || WEAPON_STATUS.registered;
                    return `
                    <div class="w-row" onclick="openWeaponEditor(${w.id})">
                        <span class="mono w-serial">${esc(w.serial)}</span>
                        <span class="w-model">${esc(w.model)}</span>
                        <span>${esc(w.class || '—')}</span>
                        <span>${esc(w.owner_name || 'No owner on file')}</span>
                        <span><span class="tag ${st.tag}">${esc(st.label)}</span></span>
                        <span class="mono">${w.registered_at ? fmtDateShort(w.registered_at) : '—'}</span>
                    </div>`;
                }).join('')}
            </div>
            <div class="penal-count">${data.weapons.length} firearm${data.weapons.length === 1 ? '' : 's'}</div>`;
    });
}

function openWeaponEditor(id) {
    const w = id ? (_weapons.weapons || []).find(x => x.id === id) : null;

    const body = `
        <div class="form-row">
            <div class="form-group" style="width:190px;">
                <label class="form-label">Serial</label>
                <input class="input mono" id="w-serial" value="${w ? esc(w.serial) : ''}" placeholder="AB12CD34" maxlength="30">
            </div>
            <div class="form-group" style="flex:1;">
                <label class="form-label">Model</label>
                <input class="input" id="w-model" value="${w ? esc(w.model) : ''}" placeholder="Pistol .50">
            </div>
            <div class="form-group" style="width:150px;">
                <label class="form-label">Class</label>
                <select class="input select" id="w-class">
                    <option value="">—</option>
                    ${WEAPON_CLASSES.map(c => `<option value="${c}" ${w && w.class === c ? 'selected' : ''}>${c}</option>`).join('')}
                </select>
            </div>
        </div>

        <div class="form-group">
            <label class="form-label">Owner</label>
            <div id="w-owner"></div>
        </div>

        <div class="form-row">
            <div class="form-group" style="width:190px;">
                <label class="form-label">Status</label>
                <select class="input select" id="w-status-sel">
                    ${Object.entries(WEAPON_STATUS).map(([k, v]) =>
                        `<option value="${k}" ${w && w.status === k ? 'selected' : ''}>${esc(v.label)}</option>`).join('')}
                </select>
            </div>
            <div class="form-group" style="width:190px;">
                <label class="form-label">Registered on</label>
                <input class="input mono" id="w-date" type="date" value="${w && w.registered_at ? String(w.registered_at).slice(0, 10) : ''}">
            </div>
        </div>

        <div class="form-group">
            <label class="form-label">Notes</label>
            <textarea class="textarea" id="w-notes" style="min-height:80px;">${w ? esc(w.notes || '') : ''}</textarea>
        </div>

        ${w ? `<div class="modal-actions"><button class="btn btn-ghost btn-xs btn-danger" onclick="removeWeapon(${w.id})">Remove from registry</button></div>` : ''}`;

    const modal = createModal(w ? 'Firearm' : 'Add Firearm', body, () => {
        nuiFetch('saveWeapon', {
            id,
            serial: document.getElementById('w-serial').value.trim(),
            model: document.getElementById('w-model').value.trim(),
            class: document.getElementById('w-class').value,
            status: document.getElementById('w-status-sel').value,
            registered_at: document.getElementById('w-date').value || null,
            notes: document.getElementById('w-notes').value.trim(),
            owner_citizenid: modal.dataset.owner || (w && w.owner_citizenid),
            owner_name: modal.dataset.ownerName || (w && w.owner_name),
        }).then(res => {
            if (!res) return;
            closeModal(modal);
            showToast('Saved', '', 'success', 2000);
            fetchWeapons();
        });
    }, 'Save', '<i class="i i-alert"></i>');

    new NameSearch({
        container: modal.querySelector('#w-owner'),
        placeholder: w && w.owner_name ? `${w.owner_name} — search to change…` : 'Search by name…',
        onSelect: (p) => {
            modal.dataset.owner = p ? p.citizenid : '';
            modal.dataset.ownerName = p ? p.name : '';
        },
    });
}

function removeWeapon(id) {
    const open = document.querySelector('.modal-backdrop:last-of-type');
    nuiFetch('deleteWeapon', id).then(res => {
        if (!res) return;
        closeModal(open);
        showToast('Removed', '', 'success', 2000);
        fetchWeapons();
    });
}

function showWeapon(serial) {
    if (!switchTab('weapons', true)) return;
    _wFilter = { status: 'all', search: String(serial || '') };
    loadWeapons();
    const input = document.getElementById('w-search');
    if (input) input.value = _wFilter.search;
}

window.loadWeapons = loadWeapons;
window.openWeaponEditor = openWeaponEditor;
window.removeWeapon = removeWeapon;
window.showWeapon = showWeapon;
