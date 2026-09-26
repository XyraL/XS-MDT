// ── Live body cam overlay ─────────────────────────────────────────────────
//
// The game renders behind this. The page background is transparent, so all
// this draws is the chrome a body cam stamps onto its own footage: a recording
// light, a clock, who is wearing it, and where they are.
//
// Nothing here is clickable — the watcher has no NUI focus, and Lua owns the
// exit key. A panel that took focus would take their mouse with it.

const BodyCam = (() => {
    let el = null;
    let clock = null;
    let unit = null;
    let startedAt = 0;
    let signal = true;

    function build() {
        if (el) return el;

        el = document.createElement('div');
        el.id = 'bodycam';
        el.innerHTML = `
            <div class="bc-grain"></div>
            <div class="bc-vignette"></div>

            <div class="bc-top">
                <div class="bc-rec"><span class="bc-rec-dot"></span>REC</div>
                <div class="bc-unit">
                    <span class="bc-callsign" id="bc-callsign"></span>
                    <span class="bc-name" id="bc-name"></span>
                </div>
                <div class="bc-right">
                    <div class="bc-signal" id="bc-signal">SIGNAL <span class="bc-bars"><i></i><i></i><i></i><i></i></span></div>
                    <div class="bc-batt"><span class="bc-batt-fill"></span></div>
                </div>
            </div>

            <div class="bc-bottom">
                <div class="bc-stamp" id="bc-stamp"></div>
                <div class="bc-where" id="bc-where"></div>
                <div class="bc-elapsed" id="bc-elapsed">00:00</div>
            </div>

            <div class="bc-lost" id="bc-lost">
                <div class="bc-lost-title">SIGNAL LOST</div>
                <div class="bc-lost-sub">Reacquiring</div>
            </div>

            <div class="bc-exit">ESC to close</div>`;

        document.body.appendChild(el);
        return el;
    }

    function pad(n) { return String(n).padStart(2, '0'); }

    function tick() {
        const now = new Date();
        const stamp = document.getElementById('bc-stamp');
        if (stamp) {
            stamp.textContent = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
                + `  ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
        }

        const elapsed = document.getElementById('bc-elapsed');
        if (elapsed) {
            const s = Math.floor((Date.now() - startedAt) / 1000);
            elapsed.textContent = `${pad(Math.floor(s / 60))}:${pad(s % 60)}`;
        }
    }

    function open(u) {
        unit = u || {};
        startedAt = Date.now();
        signal = true;

        build();
        el.classList.add('live');
        el.classList.remove('nosignal');

        document.getElementById('bc-callsign').textContent = unit.callsign || unit.badge || '';
        document.getElementById('bc-name').textContent =
            [unit.rank, unit.name].filter(Boolean).join(' ');
        document.getElementById('bc-where').textContent = '';

        tick();
        clearInterval(clock);
        clock = setInterval(tick, 1000);
    }

    function close() {
        clearInterval(clock);
        clock = null;
        if (el) el.classList.remove('live', 'nosignal');
    }

    // Street, speed and whether they are driving. Sent on a slow tick from Lua
    // because none of it changes at frame rate.
    function update(data) {
        if (!el || !el.classList.contains('live')) return;

        if (data.ok !== undefined) setSignal(data.ok);

        const where = document.getElementById('bc-where');
        if (!where) return;

        const bits = [];
        if (data.street) bits.push(data.street);
        if (data.inVehicle) bits.push(`${data.speed || 0} MPH`);
        where.textContent = bits.join('  ·  ');
    }

    function setSignal(ok) {
        if (signal === ok || !el) return;
        signal = ok;
        el.classList.toggle('nosignal', !ok);
    }

    return { open, close, update, setSignal };
})();
