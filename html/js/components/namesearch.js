/**
 * XSMDT Name Search Component
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
    constructor({ container, placeholder = 'Search by name…', onSelect, allowClear = true, label = null }) {
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
                    <div class="ns-search-icon">🔍</div>
                    <input class="ns-input" type="text" autocomplete="off" placeholder="${placeholder}">
                    ${allowClear ? '<button class="ns-clear" title="Clear" style="display:none;">✕</button>' : ''}
                </div>
                <div class="ns-dropdown" style="display:none;"></div>
                <div class="ns-selected" style="display:none;"></div>
            </div>`;

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
        const data = await nuiFetch('searchPlayersByName', q);
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
                    <div class="ns-item-meta">DOB ${p.dob || '—'} · ${p.gender === 'male' || p.gender === 'm' ? '♂' : '♀'}</div>
                </div>
                <div class="ns-item-right">
                    ${p.online ? '<span class="ns-badge ns-badge-green">● ONLINE</span>' : '<span class="ns-badge ns-badge-gray">OFFLINE</span>'}
                    ${p.warrants > 0 ? `<span class="ns-badge ns-badge-red">⚠ ${p.warrants}W</span>` : ''}
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

    _select(person) {
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
            ? `<span class="ns-badge ns-badge-red" style="margin-left:auto;">⚠ ${person.warrants} Active Warrant${person.warrants > 1 ? 's' : ''}</span>`
            : '';
        this._selBox.innerHTML = `
            <div class="ns-selected-card">
                <div class="ns-selected-avatar">${person.name.charAt(0).toUpperCase()}</div>
                <div class="ns-selected-info">
                    <div class="ns-selected-name">${esc(person.name)}</div>
                    <div class="ns-selected-meta">DOB ${person.dob || '—'} · ${person.citizenid}</div>
                </div>
                ${warnHtml}
                <button class="ns-deselect" title="Change">✕</button>
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

// Inject styles into the document
(function injectNameSearchStyles() {
    if (document.getElementById('ns-styles')) return;
    const s = document.createElement('style');
    s.id = 'ns-styles';
    s.textContent = `
.ns-wrap { position: relative; }
.ns-input-row {
    display: flex; align-items: center; gap: 0;
    background: var(--bg-input); border: 1px solid var(--border);
    border-radius: var(--radius); transition: border-color .15s;
}
.ns-input-row:focus-within { border-color: var(--accent); box-shadow: 0 0 0 2px var(--accent-glow); }
.ns-search-icon { padding: 0 10px; font-size: 14px; opacity: .55; pointer-events: none; }
.ns-input {
    flex: 1; padding: 10px 8px 10px 0; background: transparent;
    border: none; outline: none; color: var(--text-primary);
    font-size: 14px; font-family: var(--font-sans);
}
.ns-clear {
    background: none; border: none; color: var(--text-muted); cursor: pointer;
    padding: 0 12px; font-size: 14px; opacity: .7;
}
.ns-clear:hover { opacity: 1; color: var(--text-primary); }
.ns-dropdown {
    position: absolute; top: calc(100% + 6px); left: 0; right: 0;
    background: var(--bg-panel); border: 1px solid var(--border-light);
    border-radius: var(--radius); z-index: 9999;
    box-shadow: 0 12px 40px rgba(0,0,0,.6);
    max-height: 280px; overflow-y: auto;
}
.ns-item {
    display: flex; align-items: center; gap: 12px;
    padding: 10px 14px; cursor: pointer; border-bottom: 1px solid var(--border);
    transition: background .1s;
}
.ns-item:last-child { border-bottom: none; }
.ns-item:hover, .ns-item-focused { background: var(--bg-hover); }
.ns-item-left { flex: 1; min-width: 0; }
.ns-item-name { font-weight: 600; font-size: 14px; color: var(--text-primary); }
.ns-item-meta { font-size: 11px; color: var(--text-muted); margin-top: 2px; }
.ns-item-right { display: flex; gap: 6px; align-items: center; flex-shrink: 0; }
.ns-badge {
    font-size: 10px; font-weight: 700; padding: 2px 7px;
    border-radius: 20px; text-transform: uppercase; letter-spacing: .04em;
}
.ns-badge-green { background: rgba(34,197,94,.15); color: #4ade80; }
.ns-badge-gray  { background: rgba(148,163,184,.1); color: var(--text-muted); }
.ns-badge-red   { background: rgba(239,68,68,.15); color: #f87171; }
.ns-empty, .ns-loading {
    padding: 14px 16px; font-size: 13px; color: var(--text-muted); text-align: center;
}
.ns-loading { display: flex; align-items: center; justify-content: center; gap: 8px; }
.ns-spinner {
    width: 14px; height: 14px; border: 2px solid var(--border-light);
    border-top-color: var(--accent); border-radius: 50%;
    animation: ns-spin .7s linear infinite; display: inline-block;
}
@keyframes ns-spin { to { transform: rotate(360deg); } }
.ns-selected { }
.ns-selected-card {
    display: flex; align-items: center; gap: 12px;
    background: var(--bg-input); border: 1px solid var(--accent);
    border-radius: var(--radius); padding: 10px 14px;
    box-shadow: 0 0 0 2px var(--accent-glow);
}
.ns-selected-avatar {
    width: 36px; height: 36px; border-radius: 50%; flex-shrink: 0;
    background: var(--accent-glow); color: var(--accent-2);
    display: flex; align-items: center; justify-content: center;
    font-size: 16px; font-weight: 800;
}
.ns-selected-info { flex: 1; min-width: 0; }
.ns-selected-name { font-weight: 700; font-size: 14px; color: var(--text-primary); }
.ns-selected-meta { font-size: 11px; color: var(--text-muted); margin-top: 2px; font-family: var(--font-mono); }
.ns-deselect {
    background: none; border: none; color: var(--text-muted); cursor: pointer;
    padding: 4px 8px; font-size: 14px; opacity: .6; flex-shrink: 0;
}
.ns-deselect:hover { opacity: 1; color: var(--text-danger); }
`;
    document.head.appendChild(s);
}());

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
