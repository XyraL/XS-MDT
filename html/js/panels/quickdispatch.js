// Quick Dispatch Responder — keybind overlay (no MDT needed)
const QD = {
    visible: false,
    calls: [],
    selected: 0,
};

function qdOpen(calls) {
    QD.calls = (calls || []).filter(c => c.status === 'active' || c.status === 'enroute' || c.status === 'onscene');
    QD.selected = 0;
    QD.visible = true;
    document.getElementById('quick-dispatch').classList.remove('hidden');
    qdRender();
    document.addEventListener('keydown', qdKeyHandler);
}

function qdClose() {
    QD.visible = false;
    document.getElementById('quick-dispatch').classList.add('hidden');
    document.removeEventListener('keydown', qdKeyHandler);
    fetch(`https://${MDT_RESOURCE}/qdClosed`, { method: 'POST', body: JSON.stringify({}) });
}

function qdRender() {
    const list = document.getElementById('qd-list');
    if (!QD.calls.length) {
        list.innerHTML = '<div class="qd-empty">No active calls</div>';
        document.getElementById('qd-selected-info').textContent = '';
        return;
    }
    list.innerHTML = QD.calls.map((c, i) => {
        const age = qdAge(c.created_at);
        const units = Array.isArray(c.units) ? c.units.length : 0;
        const priorityClass = c.priority <= 1 ? 'qd-p1' : c.priority === 2 ? 'qd-p2' : 'qd-p3';
        return `<div class="qd-row ${i === QD.selected ? 'qd-selected' : ''} ${priorityClass}" onclick="qdSelect(${i})">
            <div class="qd-row-left">
                <span class="qd-icon">${c.icon || '📡'}</span>
                <div class="qd-row-info">
                    <div class="qd-row-type">${c.call_type || 'Call'}</div>
                    <div class="qd-row-loc">${esc(c.location || 'Unknown')}</div>
                </div>
            </div>
            <div class="qd-row-right">
                <span class="qd-num">${c.call_number || ''}</span>
                <span class="qd-meta">${units} unit${units !== 1 ? 's' : ''} · ${age}</span>
            </div>
        </div>`;
    }).join('');

    const sel = QD.calls[QD.selected];
    if (sel) {
        document.getElementById('qd-selected-info').textContent =
            `${esc(sel.description || '')} — Caller: ${sel.caller_name || 'Unknown'}`;
    }
}

function qdSelect(i) {
    QD.selected = i;
    qdRender();
}

function qdRespond() {
    const call = QD.calls[QD.selected];
    if (!call) return;
    fetch(`https://${MDT_RESOURCE}/qdRespond`, {
        method: 'POST',
        body: JSON.stringify({
            callId:      call.id,
            coords:      call.coords,
            location:    call.location,
            callNumber:  call.call_number,
            callType:    call.call_type,
        }),
    });
    qdClose();
}

function qdKeyHandler(e) {
    if (e.key === 'Escape') { qdClose(); return; }
    if (e.key === 'ArrowDown') {
        QD.selected = Math.min(QD.selected + 1, QD.calls.length - 1);
        qdRender(); return;
    }
    if (e.key === 'ArrowUp') {
        QD.selected = Math.max(QD.selected - 1, 0);
        qdRender(); return;
    }
    if (e.key === 'Enter') { qdRespond(); return; }
}

function qdAge(ts) {
    if (!ts) return '';
    const diff = Math.floor((Date.now() - new Date(ts).getTime()) / 1000);
    if (diff < 60) return diff + 's ago';
    if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
    return Math.floor(diff / 3600) + 'h ago';
}

// NUI message handler
window.addEventListener('message', function(e) {
    if (e.data.type === 'openQuickDispatch') {
        qdOpen(e.data.calls);
    }
});

window.qdOpen    = qdOpen;
window.qdClose   = qdClose;
window.qdSelect  = qdSelect;
window.qdRespond = qdRespond;
