local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

-- draft   — being written, visible only to its author
-- open    — filed and active
-- review  — waiting on a supervisor
-- closed  — done
local VALID_STATUS = { draft = true, open = true, review = true, closed = true }

-- Tags come from the panel as free text and are stored as JSON, so they are
-- trimmed, lowercased for consistency, de-duplicated and capped here rather
-- than being cleaned at every place that reads them.
local function CleanTags(list)
    if type(list) ~= 'table' then return {} end
    local out, seen = {}, {}
    for _, raw in ipairs(list) do
        local tag = tostring(raw):lower():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 24)
        if tag ~= '' and not seen[tag] then
            seen[tag] = true
            out[#out + 1] = tag
            if #out >= 10 then break end
        end
    end
    return out
end

lib.callback.register('XS-MDT:server:getIncidents', function(source, data)
    if not HasPanel(source, 'incidents') then return nil end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local filter = (type(data) == 'table' and data.filter) or (type(data) == 'string' and data) or 'all'

    -- A draft is a half-written report. It belongs to whoever is writing it
    -- and to nobody else, so the scoping happens here rather than trusting the
    -- panel to leave other people's drafts out of what it shows.
    local where, params = { "(status != 'draft' OR created_by = ?)" }, { officer.citizenid }

    if filter == 'mine' then
        where[#where + 1] = 'created_by = ?'
        params[#params + 1] = officer.citizenid
    end

    local status = type(data) == 'table' and data.status or nil
    if status and status ~= 'all' then
        where[#where + 1] = 'status = ?'
        params[#params + 1] = status
    end

    local results = MySQL.query.await(
        'SELECT * FROM mdt_incidents WHERE ' .. table.concat(where, ' AND ')
        .. ' ORDER BY created_at DESC LIMIT 100', params)

    for _, i in ipairs(results) do
        i.involved_civilians = i.involved_civilians and json.decode(i.involved_civilians) or {}
        i.involved_officers = i.involved_officers and json.decode(i.involved_officers) or {}
        i.linked_arrests = i.linked_arrests and json.decode(i.linked_arrests) or {}
        i.linked_citations = i.linked_citations and json.decode(i.linked_citations) or {}
        i.tags = i.tags and json.decode(i.tags) or {}
    end
    return results
end)

lib.callback.register('XS-MDT:server:getIncident', function(source, id)
    if not HasPanel(source, 'incidents') then return nil end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local incident = MySQL.single.await('SELECT * FROM mdt_incidents WHERE id = ?', { id })
    if not incident then return nil end
    -- Someone else's unfinished draft is not readable by id either.
    if incident.status == 'draft' and incident.created_by ~= officer.citizenid then return nil end
    incident.involved_civilians = incident.involved_civilians and json.decode(incident.involved_civilians) or {}
    incident.involved_officers = incident.involved_officers and json.decode(incident.involved_officers) or {}
    incident.linked_arrests = incident.linked_arrests and json.decode(incident.linked_arrests) or {}
    incident.linked_citations = incident.linked_citations and json.decode(incident.linked_citations) or {}
    incident.tags = incident.tags and json.decode(incident.tags) or {}
    incident.evidence = MySQL.query.await(
        'SELECT * FROM mdt_evidence WHERE incident_id = ? ORDER BY created_at ASC', { id }) or {}
    return incident
end)

lib.callback.register('XS-MDT:server:createIncident', function(source, data)
    if not HasPanel(source, 'incidents') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not data.title or not data.narrative then return false end

    local status = VALID_STATUS[data.status] and data.status or 'open'

    local id = MySQL.insert.await([[
        INSERT INTO mdt_incidents (title, narrative, involved_civilians, involved_officers, linked_arrests, linked_citations, severity, status, location, occurred_at, tags, created_by, created_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.title, data.narrative,
        json.encode(data.involved_civilians or {}),
        json.encode(data.involved_officers or {}),
        json.encode(data.linked_arrests or {}),
        json.encode(data.linked_citations or {}),
        data.severity or nil,
        status,
        data.location and tostring(data.location):sub(1, 255) or nil,
        data.occurred_at or nil,
        json.encode(CleanTags(data.tags)),
        officer.citizenid, officer.name
    })

    -- Case numbers used to be typed by hand, so most reports had none and the
    -- ones that did could collide. Deriving it from the row id makes it unique
    -- without a counter to maintain anywhere.
    local caseNumber = data.caseNumber and tostring(data.caseNumber):gsub('[^%w%-]', ''):sub(1, 50) or nil
    if not caseNumber or caseNumber == '' then
        caseNumber = ('INC-%s-%05d'):format(os.date('%Y'), id)
    end
    MySQL.update.await('UPDATE mdt_incidents SET case_number = ? WHERE id = ?', { caseNumber, id })

    -- Starting to type is not an event worth auditing; filing one is.
    if status ~= 'draft' then
        exports['XS-MDT']:AuditLog('Incident Created', officer.name, caseNumber .. ': ' .. data.title)
    end
    -- A table, not two values: the NUI bridge keeps only the first return,
    -- so the case number would never reach the panel otherwise.
    return { id = id, caseNumber = caseNumber }
end)

-- Moving a report along its lifecycle. Separate from updateIncident so that
-- closing a report does not mean sending the whole narrative back to the
-- server just to change one word.
lib.callback.register('XS-MDT:server:setIncidentStatus', function(source, data)
    if not HasPanel(source, 'incidents') then return { ok = false, error = 'Not authorised' } end
    if type(data) ~= 'table' or not data.id then return { ok = false, error = 'Missing incident' } end
    if not VALID_STATUS[data.status] then return { ok = false, error = 'Unknown status' } end

    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local incident = MySQL.single.await('SELECT created_by, case_number, status FROM mdt_incidents WHERE id = ?', { data.id })
    if not incident then return { ok = false, error = 'No such incident' } end

    -- Authors move their own reports; supervisors move anyone's.
    local isOwner = incident.created_by == officer.citizenid
    if not isOwner and not exports['XS-MDT']:IsSupervisor(source) then
        return { ok = false, error = 'Only the author or a supervisor can change this' }
    end

    MySQL.update.await('UPDATE mdt_incidents SET status = ? WHERE id = ?', { data.status, data.id })
    exports['XS-MDT']:AuditLog('Incident ' .. data.status, officer.name,
        (incident.case_number or ('#' .. data.id)) .. ' was ' .. (incident.status or '?'))
    return { ok = true }
end)

lib.callback.register('XS-MDT:server:updateIncident', function(source, data)
    if not HasPanel(source, 'incidents') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)

    -- Only the author or a supervisor (grade 3+) can edit
    local existing = MySQL.single.await('SELECT created_by FROM mdt_incidents WHERE id = ?', { data.id })
    if not existing then return false end
    local player = exports['qbx_core']:GetPlayer(source)
    if existing.created_by ~= officer.citizenid and player.PlayerData.job.grade.level < 3 then
        return false
    end

    MySQL.update.await([[
        UPDATE mdt_incidents SET title=?, narrative=?, involved_civilians=?, involved_officers=?,
        linked_arrests=?, linked_citations=?, updated_at=NOW()
        WHERE id = ?
    ]], {
        data.title, data.narrative,
        json.encode(data.involved_civilians or {}),
        json.encode(data.involved_officers or {}),
        json.encode(data.linked_arrests or {}),
        json.encode(data.linked_citations or {}),
        data.id
    })
    return true
end)

lib.callback.register('XS-MDT:server:deleteIncident', function(source, id)
    if not HasPanel(source, 'incidents') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local existing = MySQL.single.await('SELECT created_by FROM mdt_incidents WHERE id = ?', { id })
    if not existing then return false end
    local player = exports['qbx_core']:GetPlayer(source)
    if existing.created_by ~= officer.citizenid and player.PlayerData.job.grade.level < 3 then
        return false
    end
    MySQL.query.await('DELETE FROM mdt_incidents WHERE id = ?', { id })
    exports['XS-MDT']:AuditLog('Incident Deleted', officer.name, 'Incident #' .. id)
    return true
end)

-- ── Case linking ───────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:setCaseNumber', function(source, data)
    if not HasPanel(source, 'incidents') then return false end
    if not data.incidentId or not data.caseNumber then return false end
    -- Trim and validate: alphanumeric + hyphens, max 50 chars
    local cn = tostring(data.caseNumber):gsub('[^%w%-]', ''):sub(1, 50)
    MySQL.update.await('UPDATE mdt_incidents SET case_number = ? WHERE id = ?', { cn ~= '' and cn or nil, data.incidentId })
    return true
end)

-- Search across every report an officer may see: case number, title, the
-- narrative itself, and who wrote it. Draft privacy holds here exactly as it
-- does in the list — someone else's unfinished report is not findable either.
lib.callback.register('XS-MDT:server:searchIncidents', function(source, query)
    if not HasPanel(source, 'incidents') then return nil end
    query = tostring(query or '')
    if #query < 2 then return {} end

    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local like = '%' .. query .. '%'

    local results = MySQL.query.await([[
        SELECT * FROM mdt_incidents
        WHERE (status != 'draft' OR created_by = ?)
          AND (case_number LIKE ? OR title LIKE ? OR narrative LIKE ? OR created_by_name LIKE ?)
        ORDER BY created_at DESC
        LIMIT 50
    ]], { officer.citizenid, like, like, like, like })

    for _, i in ipairs(results) do
        i.involved_civilians = i.involved_civilians and json.decode(i.involved_civilians) or {}
        i.involved_officers = i.involved_officers and json.decode(i.involved_officers) or {}
        i.linked_arrests = i.linked_arrests and json.decode(i.linked_arrests) or {}
        i.linked_citations = i.linked_citations and json.decode(i.linked_citations) or {}
        i.tags = i.tags and json.decode(i.tags) or {}
    end
    return results
end)

-- ── Evidence ─────────────────────────────────────────────────────────────────
-- Photos, items and notes attached to a report, each stamped with who logged
-- it and when. Entries are meant to be append-mostly: the logger gets a short
-- window to fix a typo, after that only a supervisor can remove one — an
-- evidence log everyone can quietly edit later is not worth keeping.

local EVIDENCE_KINDS = { photo = true, item = true, note = true }
local EVIDENCE_EDIT_WINDOW = 15 * 60

lib.callback.register('XS-MDT:server:addEvidence', function(source, data)
    if not HasPanel(source, 'incidents') then return { ok = false, error = 'Not authorised' } end
    if type(data) ~= 'table' or not data.incidentId then return { ok = false, error = 'Missing report' } end
    if not EVIDENCE_KINDS[data.kind] then return { ok = false, error = 'Unknown evidence type' } end

    local label = tostring(data.label or ''):sub(1, 120)
    if label == '' then return { ok = false, error = 'A label is required' } end

    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local incident = MySQL.single.await(
        'SELECT id, status, created_by, case_number FROM mdt_incidents WHERE id = ?', { data.incidentId })
    if not incident then return { ok = false, error = 'No such report' } end
    if incident.status == 'draft' and incident.created_by ~= officer.citizenid then
        return { ok = false, error = 'No such report' }
    end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_evidence (incident_id, kind, label, detail, photo, logged_by, logged_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.incidentId, data.kind, label,
        data.detail and tostring(data.detail):sub(1, 1000) or nil,
        data.kind == 'photo' and data.photo and tostring(data.photo):sub(1, 500) or nil,
        officer.citizenid, officer.name,
    })

    exports['XS-MDT']:AuditLog('Evidence Logged', officer.name,
        ('%s "%s" on %s'):format(data.kind, label, incident.case_number or ('#' .. incident.id)))
    return { ok = true, id = id }
end)

lib.callback.register('XS-MDT:server:deleteEvidence', function(source, data)
    if not HasPanel(source, 'incidents') then return { ok = false, error = 'Not authorised' } end
    if type(data) ~= 'table' or not data.id then return { ok = false, error = 'Missing entry' } end

    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local row = MySQL.single.await(
        'SELECT id, label, logged_by, UNIX_TIMESTAMP(created_at) AS at FROM mdt_evidence WHERE id = ?', { data.id })
    if not row then return { ok = false, error = 'Already gone' } end

    local own = row.logged_by == officer.citizenid
    local fresh = (os.time() - (row.at or 0)) <= EVIDENCE_EDIT_WINDOW
    if not ((own and fresh) or exports['XS-MDT']:IsSupervisor(source)) then
        return { ok = false, error = 'Only within 15 minutes of logging it, or a supervisor' }
    end

    MySQL.query.await('DELETE FROM mdt_evidence WHERE id = ?', { data.id })
    exports['XS-MDT']:AuditLog('Evidence Removed', officer.name, ('"%s" (#%d)'):format(row.label, row.id))
    return { ok = true }
end)

lib.callback.register('XS-MDT:server:getIncidentsByCase', function(source, caseNumber)
    if not HasPanel(source, 'incidents') then return nil end
    if not caseNumber or #caseNumber < 1 then return {} end
    local results = MySQL.query.await([[
        SELECT id, title, severity, created_by_name, created_at, case_number
        FROM mdt_incidents
        WHERE case_number = ?
        ORDER BY created_at ASC
    ]], { caseNumber })
    return results
end)
