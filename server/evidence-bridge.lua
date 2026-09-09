-- Server-to-server hooks for cipher-evidence (or any resource) to create an
-- incident and attach evidence to it without a player behind the request.
--
-- The normal incident/evidence paths are lib.callbacks that need a source and a
-- panel check — right for the UI, wrong for another resource acting on the
-- server's behalf. These exports are the resource-facing door: no source, a
-- fixed system actor, and the same validation the callbacks apply.

local EVIDENCE_KINDS = { photo = true, item = true, note = true }
local VALID_STATUS = { open = true, closed = true, draft = true, cold = true }

-- Create an incident on behalf of another resource. `data` mirrors the fields
-- the createIncident callback accepts. Returns { id, caseNumber } or nil.
exports('CreateIncidentExternal', function(data)
    if type(data) ~= 'table' or not data.title then return nil end

    local status = VALID_STATUS[data.status] and data.status or 'open'
    local actorName = tostring(data.actorName or 'Evidence System'):sub(1, 120)
    local actorCid  = data.actorCid and tostring(data.actorCid):sub(1, 64) or 'system'

    local id = MySQL.insert.await([[
        INSERT INTO mdt_incidents (title, narrative, involved_civilians, involved_officers, linked_arrests, linked_citations, severity, status, location, occurred_at, tags, created_by, created_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        tostring(data.title):sub(1, 160),
        tostring(data.narrative or ''):sub(1, 5000),
        json.encode(data.involved_civilians or {}),
        json.encode(data.involved_officers or {}),
        json.encode({}), json.encode({}),
        data.severity or nil,
        status,
        data.location and tostring(data.location):sub(1, 255) or nil,
        data.occurred_at or nil,
        json.encode({}),
        actorCid, actorName,
    })
    if not id then return nil end

    -- Honour a supplied case number (so the two systems share one), else derive.
    local caseNumber = data.caseNumber and tostring(data.caseNumber):gsub('[^%w%-]', ''):sub(1, 50) or nil
    if not caseNumber or caseNumber == '' then
        caseNumber = ('INC-%s-%05d'):format(os.date('%Y'), id)
    end
    MySQL.update.await('UPDATE mdt_incidents SET case_number = ? WHERE id = ?', { caseNumber, id })

    if exports['XS-MDT'] and exports['XS-MDT'].AuditLog then
        exports['XS-MDT']:AuditLog('Incident Created', actorName, caseNumber .. ': ' .. tostring(data.title))
    end
    return { id = id, caseNumber = caseNumber }
end)

-- Attach an evidence row to an existing incident. `ev.kind` is mapped to the
-- MDT's own kinds (photo|item|note); anything else falls back to 'item'.
exports('AttachEvidence', function(incidentId, ev)
    if not incidentId or type(ev) ~= 'table' then return false end
    incidentId = tonumber(incidentId)
    if not incidentId then return false end

    local incident = MySQL.single.await('SELECT id FROM mdt_incidents WHERE id = ?', { incidentId })
    if not incident then return false end

    local kind = EVIDENCE_KINDS[ev.kind] and ev.kind or 'item'
    local label = tostring(ev.label or 'Evidence'):sub(1, 120)

    MySQL.insert.await([[
        INSERT INTO mdt_evidence (incident_id, kind, label, detail, photo, logged_by, logged_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        incidentId, kind, label,
        ev.detail and tostring(ev.detail):sub(1, 1000) or nil,
        kind == 'photo' and ev.photo and tostring(ev.photo):sub(1, 500) or nil,
        'system', tostring(ev.actorName or 'Evidence System'):sub(1, 120),
    })
    return true
end)
