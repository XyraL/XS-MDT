/**
 * XS-MDT Name Search Component
 * Replaces all CID/ID inputs with live player-name lookups.
 *
 * Usage:
 *   const ns = new NameSearch({
 *     container : '#my-container',   // selector or element
 *     placeholder: 'Search player…',
 *     onSelect  : (person) => { ... },
 *   });
 *
 * person object: { citizenid, name, firstname, lastname, dob, gender, phone, online, warrants }
 */
class NameSearch {
    constructor({ container, placeholder = 'Search by name…', onSelect, allowClear = true, label = null, endpoint = 'searchPlayersByName' }) {
        this.endpoint    = endpoint;
        this.onSelect    = onSelect;
        this.selected    = null;
        this.debounce    = null;
        this.results     = [];
        this.focusIndex  = -1;

        const el = typeof container === 'string' ? document.querySelector(container) : container;
        if (!el) { console.error('[NameSearch] container not found:', container); return; }

        el.innerHTML = `
            <div class="ns-wrap" tabindex="-1">
                ${label ? `<label class="form-label">${label}</label>` : ''}
                <div class="ns-input-row">
                    <div class="ns-search-icon"><i class="i i-search"></i></div>
                    <input class="ns-input" type="text" autocomplete="off" placeholder="${placeholder}">
                    ${allowClear ? '<button class="ns-clear" title="Clear" style="display:none;"><i class="i i-x"></i></button>' : ''}
                </div>
                <div class="ns-dropdown" style="display:none;"></div>
                <div class="ns-selected" style="display:none;"></div>
            </div>`;

        // Forms reach the instance through the container to prefill it. This
        // was never set, so prefill from a civilian profile silently did nothing.
        el._ns = this;

        this._wrap     = el.querySelector('.ns-wrap');
        this._input    = el.querySelector('.ns-input');
        this._dropdown = el.querySelector('.ns-dropdown');
        this._selBox   = el.querySelector('.ns-selected');
        this._clearBtn = el.querySelector('.ns-clear');

        this._input.addEventListener('input', () => this._onInput());
        this._input.addEventListener('keydown', e => this._onKey(e));
        this._input.addEventListener('blur', () => setTimeout(() => this._closeDropdown(), 180));

        if (this._clearBtn) {
            this._clearBtn.addEventListener('click', () => this.clear());
        }

        document.addEventListener('click', e => {
            if (!el.contains(e.target)) this._closeDropdown();
        });
    }

    _onInput() {
        const q = this._input.value.trim();
        if (this._clearBtn) this._clearBtn.style.display = q ? '' : 'none';
        if (q.length < 2) { this._closeDropdown(); return; }
        clearTimeout(this.debounce);
        this.debounce = setTimeout(() => this._search(q), 280);
        this._showLoading();
    }

    async _search(q) {
        const data = await nuiFetch(this.endpoint, q);
        this.results = Array.isArray(data) ? data : [];
        this.focusIndex = -1;
        if (!this.results.length) {
            this._dropdown.style.display = 'block';
            this._dropdown.innerHTML = '<div class="ns-empty">No results found</div>';
            return;
        }
        this._renderDropdown();
    }

    _renderDropdown() {
        this._dropdown.style.display = 'block';
        this._dropdown.innerHTML = this.results.map((p, i) => `
            <div class="ns-item ${this.focusIndex === i ? 'ns-item-focused' : ''}" data-idx="${i}">
                <div class="ns-item-left">
                    <div class="ns-item-name">${esc(p.name)}</div>
                    <div class="ns-item-meta">${this._meta(p)}</div>
                </div>
                <div class="ns-item-right">
                    ${p.online === true ? '<span class="ns-badge ns-badge-green"><i class="dot"></i>ONLINE</span>'
                      : p.online === false ? '<span class="ns-badge ns-badge-gray">OFFLINE</span>' : ''}
                    ${p.onduty ? '<span class="ns-badge ns-badge-green"><i class="dot"></i>ON DUTY</span>' : ''}
                    ${p.warrants > 0 ? `<span class="ns-badge ns-badge-red"><i class="i i-alert"></i> ${p.warrants}W</span>` : ''}
                </div>
            </div>`).join('');

        this._dropdown.querySelectorAll('.ns-item').forEach(item => {
            item.addEventListener('mousedown', e => {
                e.preventDefault();
                this._select(this.results[parseInt(item.dataset.idx)]);
            });
        });
    }

    _showLoading() {
        this._dropdown.style.display = 'block';
        this._dropdown.innerHTML = '<div class="ns-loading"><span class="ns-spinner"></span> Searching…</div>';
    }

    _onKey(e) {
        if (!this.results.length) return;
        if (e.key === 'ArrowDown') {
            e.preventDefault();
            this.focusIndex = Math.min(this.focusIndex + 1, this.results.length - 1);
            this._renderDropdown();
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            this.focusIndex = Math.max(this.focusIndex - 1, 0);
            this._renderDropdown();
        } else if (e.key === 'Enter' && this.focusIndex >= 0) {
            e.preventDefault();
            this._select(this.results[this.focusIndex]);
        } else if (e.key === 'Escape') {
            this._closeDropdown();
        }
    }

    // One shape, whatever the source. A profile prefill carries firstname and
    // lastname but no name, and _renderSelected read person.name.charAt() —
    // the crash that took the charge picker down with it.
    _normalise(person) {
        const name = person.name
            || [person.firstname, person.lastname].filter(Boolean).join(' ')
            || person.citizenid || 'Unknown';
        return { ...person, name };
    }

    _meta(p) {
        if (p.badge) return [`#${esc(p.badge)}`, esc(p.grade || p.rank || '')].filter(Boolean).join(' · ');
        const g = String(p.gender || '').toLowerCase();
        const gender = g === 'male' || g === 'm' || g === '0' ? 'M'
                     : g === 'female' || g === 'f' || g === '1' ? 'F' : '';
        return [`DOB ${esc(p.dob || '—')}`, gender].filter(Boolean).join(' · ');
    }

    _select(person) {
        person = this._normalise(person);
        this.selected = person;
        this._input.value = '';
        if (this._clearBtn) this._clearBtn.style.display = 'none';
        this._closeDropdown();
        this._renderSelected(person);
        if (this.onSelect) this.onSelect(person);
    }

    _renderSelected(person) {
        this._selBox.style.display = 'block';
        this._input.style.display = 'none';
        if (this._clearBtn) this._clearBtn.style.display = 'none';
        const warnHtml = person.warrants > 0
            ? `<span class="ns-badge ns-badge-red" style="margin-left:auto;"><i class="i i-alert"></i> ${person.warrants} Active Warrant${person.warrants > 1 ? 's' : ''}</span>`
            : '';
        this._selBox.innerHTML = `
            <div class="ns-selected-card">
                <div class="ns-selected-avatar">${person.name.charAt(0).toUpperCase()}</div>
                <div class="ns-selected-info">
                    <div class="ns-selected-name">${esc(person.name)}</div>
                    <div class="ns-selected-meta">${this._meta(person)} · ${esc(person.citizenid || '')}</div>
                </div>
                ${warnHtml}
                <button class="ns-deselect" title="Change"><i class="i i-x"></i></button>
            </div>`;
        this._selBox.querySelector('.ns-deselect').addEventListener('click', () => this.clear());
    }

    _closeDropdown() {
        this._dropdown.style.display = 'none';
        this.results = [];
        this.focusIndex = -1;
    }

    clear() {
        this.selected = null;
        this._input.value = '';
        this._input.style.display = '';
        if (this._clearBtn) this._clearBtn.style.display = 'none';
        this._selBox.style.display = 'none';
        this._selBox.innerHTML = '';
        this._closeDropdown();
        this._input.focus();
    }

    getValue() { return this.selected; }
    setValue(person) { if (person) this._select(person); }
}

window.NameSearch = NameSearch;

/**
 * Shorthand for the common case: attach a picker to a container id and hand
 * the chosen person to a callback. Returns the NameSearch instance.
 *   mountNameSearch('pcr-patient-search', p => { ... }, 'Existing Name')
 */
function mountNameSearch(containerId, onSelect, placeholderName) {
    const el = document.getElementById(containerId);
    if (!el) return null;
    return new NameSearch({
        container: el,
        placeholder: placeholderName ? `${placeholderName} — search to change…` : 'Search by name…',
        onSelect,
    });
}
window.mountNameSearch = mountNameSearch;
