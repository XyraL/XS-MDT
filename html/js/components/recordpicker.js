const RECORD_KINDS = {
    incident: { label: 'Report',   icon: 'clipboard', tab: 'incidents' },
    arrest:   { label: 'Arrest',   icon: 'lock',      tab: 'arrests' },
    citation: { label: 'Citation', icon: 'file',      tab: 'citations' },
    warrant:  { label: 'Warrant',  icon: 'scale',     tab: 'warrants' },
    bolo:     { label: 'BOLO',     icon: 'eye',       tab: 'bolos' },
    evidence: { label: 'Evidence', icon: 'box',       tab: 'evidence' },
    person:   { label: 'Person',   icon: 'user',      tab: 'civilians' },
    vehicle:  { label: 'Vehicle',  icon: 'car',       tab: 'vehicles' },
    weapon:   { label: 'Firearm',  icon: 'alert',     tab: 'weapons' },
    case:     { label: 'Case',     icon: 'folder',    tab: 'cases' },
};

function canOpenKind(kind) {
    const k = RECORD_KINDS[kind];
    if (!k) return false;
    return !MDT.panels || !MDT.panels.length || MDT.panels.includes(k.tab);
}

class RecordPicker {
    constructor({ container, kind, multiple = false, placeholder = '', value = [], onChange = null, onPick = null }) {
        this.kind = kind;
        this.multiple = multiple;
        this.onChange = onChange;
        this.onPick = onPick;
        this.selected = (value || []).slice();
        this.results = [];
        this.timer = null;

        this.el = typeof container === 'string' ? document.querySelector(container) : container;
        if (!this.el) return;
        this.el._picker = this;

        const word = ((RECORD_KINDS[kind] || {}).label || 'record').toLowerCase();
        this.el.innerHTML = `
            <div class="person-linker">
                <div class="person-linker-input-row">
                    <input class="input rp-input" autocomplete="off" placeholder="${esc(placeholder || 'Search ' + word + 's...')}">
                </div>
                <div class="person-linker-dropdown hidden rp-drop"></div>
            </div>
            ${onPick ? '' : '<div class="linked-persons rp-chips"></div>'}`;

        this.input = this.el.querySelector('.rp-input');
        this.drop = this.el.querySelector('.rp-drop');
        this.chips = this.el.querySelector('.rp-chips');

        this.input.addEventListener('input', () => this._queue());
        this.input.addEventListener('focus', () => { if (this.results.length) this.drop.classList.remove('hidden'); });
        this.input.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') this._close();
            if (e.key === 'Enter' && this.results.length) { e.preventDefault(); this._choose(0); }
        });

        this._outside = (e) => {
            if (!document.body.contains(this.el)) {
                document.removeEventListener('mousedown', this._outside, true);
                return;
            }
            if (!this.el.contains(e.target)) this._close();
        };
        document.addEventListener('mousedown', this._outside, true);

        this._renderChips();
    }

    _queue() {
        clearTimeout(this.timer);
        const q = this.input.value.trim();
        if (!q) { this._close(); return; }
        this.drop.innerHTML = '<div class="ns-loading"><span class="ns-spinner"></span> Searching...</div>';
        this.drop.classList.remove('hidden');
        this.timer = setTimeout(() => this._search(q), 250);
    }

    async _search(q) {
        const rows = await nuiFetch('searchLinkable', { kind: this.kind, query: q });
        if (this.input.value.trim() !== q) return;
        this.results = Array.isArray(rows) ? rows : [];

        if (!this.results.length) {
            this.drop.innerHTML = '<div class="ns-empty">Nothing found</div>';
            return;
        }

        const icon = (RECORD_KINDS[this.kind] || {}).icon || 'file';
        this.drop.innerHTML = this.results.map((r, i) => {
            const taken = this.selected.some(s => String(s.ref) === String(r.ref));
            return `
            <div class="person-linker-result ${taken ? 'added' : ''}" data-i="${i}">
                <span class="rp-icon"><i class="i i-${icon}"></i></span>
                <div class="rp-text">
                    <div class="person-linker-result-name">${esc(r.label)}</div>
                    <div class="person-linker-result-meta">${esc(r.meta || '')}${r.at ? ' · ' + fmtDateShort(r.at) : ''}</div>
                </div>
                ${taken ? '<span class="tag tag-gray">Added</span>' : ''}
            </div>`;
        }).join('');

        this.drop.querySelectorAll('.person-linker-result').forEach(row => {
            row.addEventListener('mousedown', (e) => {
                e.preventDefault();
                this._choose(Number(row.dataset.i));
            });
        });
    }

    _choose(i) {
        const item = this.results[i];
        if (!item) return;
        this.input.value = '';
        this._close();

        if (this.onPick) { this.onPick(item); return; }

        if (this.multiple) {
            if (!this.selected.some(s => String(s.ref) === String(item.ref))) this.selected.push(item);
        } else {
            this.selected = [item];
        }
        this._renderChips();
        if (this.onChange) this.onChange(this.selected);
    }

    _close() {
        this.drop.classList.add('hidden');
        this.results = [];
    }

    _renderChips() {
        if (!this.chips) return;
        if (!this.multiple && this.selected.length) this.input.parentElement.style.display = 'none';
        else this.input.parentElement.style.display = '';

        this.chips.innerHTML = this.selected.map((s, i) => `
            <span class="linked-person-tag">
                ${esc(s.label)}
                <button type="button" data-i="${i}" title="Remove">×</button>
            </span>`).join('');

        this.chips.querySelectorAll('button[data-i]').forEach(btn => {
            btn.addEventListener('click', () => {
                this.selected.splice(Number(btn.dataset.i), 1);
                this._renderChips();
                if (this.onChange) this.onChange(this.selected);
            });
        });
    }

    value() { return this.selected.slice(); }
    refs() { return this.selected.map(s => s.ref); }
    set(list) { this.selected = (list || []).slice(); this._renderChips(); }
}

// Open any record from wherever a link to it is shown. Reports, arrests and
// citations open on their own page; evidence and cases open over what is
// already on screen, so closing them lands back where the officer was.
async function openRecord(kind, ref, fromCase) {
    const k = RECORD_KINDS[kind];
    if (!k) return;
    if (!canOpenKind(kind)) {
        showToast('Not available', `Your department cannot open ${k.label.toLowerCase()} records.`, 'warning');
        return;
    }

    const t = await nuiFetch('getLinkTarget', { kind, ref });
    if (!t || !t.found) {
        showToast('Not found', `That ${k.label.toLowerCase()} is no longer on file.`, 'warning');
        return;
    }

    if (kind === 'evidence') { openEvidenceItem(t.id); return; }
    if (kind === 'case') { openCase(t.id); return; }

    const context = fromCase === undefined ? MDT.fromCase : fromCase;
    document.querySelectorAll('.modal-backdrop').forEach(m => m.remove());

    switch (kind) {
        case 'incident': switchTab('incidents', true); MDT.fromCase = context; openIncidentDetail(t.id); break;
        case 'arrest':   switchTab('arrests', true);   MDT.fromCase = context; openArrestDetail(t.id); break;
        case 'citation': switchTab('citations', true); MDT.fromCase = context; openCitationDetail(t.id); break;
        case 'warrant':
        case 'person':   showCivilian(t.citizenid); break;
        case 'bolo':     switchTab('bolos', true); loadBolos(t.id); break;
        case 'vehicle':  switchTab('vehicles'); lookupPlateExact(t.plate); break;
        case 'weapon':   showWeapon(t.serial); break;
    }
}

// The way back off a record page: to the case it was opened from, or to the
// list it belongs to.
function recordBackButton(listCall) {
    if (MDT.fromCase) {
        return `<button class="btn btn-ghost btn-sm" onclick="returnToCase()">← ${esc(MDT.fromCase.number)}</button>`;
    }
    return `<button class="btn btn-ghost btn-sm" onclick="${listCall}">← Back</button>`;
}

function returnToCase() {
    const c = MDT.fromCase;
    MDT.fromCase = null;
    if (!c) return;
    switchTab('cases');
    openCase(c.id);
}

// The strip on a record page showing which cases it is filed under.
function recordCases(kind, ref, label, cases, canCases, after) {
    MDT.caseTarget = { kind, ref, label, after };
    const chips = (cases || []).map(c => `
        <span class="case-chip" onclick="openRecord('case', ${Number(c.id)})" title="${esc(c.title)}">
            <i class="i i-folder"></i>
            <span class="mono">${esc(c.case_number)}</span>
            <span class="case-chip-title">${esc(c.title)}</span>
            ${canCases ? `<button class="case-chip-x" title="Take off this case" onclick="event.stopPropagation();removeFromCase(${Number(c.link_id)})"><i class="i i-x"></i></button>` : ''}
        </span>`).join('');

    return `
        <div class="record-cases">
            <span class="record-key">Cases</span>
            ${chips || '<span class="text-muted text-sm">Not filed under a case</span>'}
            ${canCases ? '<button class="btn btn-ghost btn-xs" onclick="openAddToCase()">+ Add to case</button>' : ''}
        </div>`;
}

function openAddToCase() {
    const target = MDT.caseTarget;
    if (!target) return;

    const modal = createModal('Add to Case', `
        <div class="form-hint" style="margin:0 0 10px;">${esc(target.label)}</div>
        <div id="atc-picker"></div>
        <div class="form-hint">Pick the case this belongs to. It shows up in the case straight away.</div>`,
        () => closeModal(modal), 'Close', '<i class="i i-folder"></i>');
    modal.querySelector('#modal-cancel').style.display = 'none';

    new RecordPicker({
        container: modal.querySelector('#atc-picker'),
        kind: 'case',
        placeholder: 'Search cases by number or title...',
        onPick: async (c) => {
            const ok = await nuiFetch('linkToCase', { caseId: c.ref, kind: target.kind, refId: target.ref, label: target.label });
            if (!ok) return;
            showToast('Added to case', c.label, 'success', 2500);
            closeModal(modal);
            if (target.after) target.after();
        },
    });
    setTimeout(() => modal.querySelector('.rp-input')?.focus(), 30);
}

async function removeFromCase(linkId) {
    const ok = await nuiFetch('unlinkFromCase', linkId);
    if (!ok) return;
    showToast('Taken off the case', '', 'success', 2000);
    if (MDT.caseTarget && MDT.caseTarget.after) MDT.caseTarget.after();
}

// Pick one record and hand it back. Used wherever a single link is added.
function pickRecord(title, kind, placeholder, onPick) {
    const modal = createModal(title, '<div id="pick-record"></div>', () => closeModal(modal), 'Close', `<i class="i i-${(RECORD_KINDS[kind] || {}).icon || 'link'}"></i>`);
    modal.querySelector('#modal-cancel').style.display = 'none';
    new RecordPicker({
        container: modal.querySelector('#pick-record'),
        kind, placeholder,
        onPick: async (item) => {
            const done = await onPick(item);
            if (done !== false) closeModal(modal);
        },
    });
    setTimeout(() => modal.querySelector('.rp-input')?.focus(), 30);
    return modal;
}

window.RecordPicker = RecordPicker;
window.canOpenKind = canOpenKind;
window.openRecord = openRecord;
window.recordBackButton = recordBackButton;
window.returnToCase = returnToCase;
window.recordCases = recordCases;
window.openAddToCase = openAddToCase;
window.removeFromCase = removeFromCase;
window.pickRecord = pickRecord;
