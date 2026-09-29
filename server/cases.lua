--[[  Cases, evidence and the weapons registry

      A case is the folder. Incidents, arrests, citations, warrants, BOLOs,
      people, vehicles and evidence all attach to one, which is the difference
      between "there was a robbery report somewhere" and being able to open the
      whole thing at once.

      Before 3.0 a case was a free-text string typed onto an incident, so
      CASE-2025-1 and CASE-2025-01 were two different cases and neither of them
      knew about the other.
]]

local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetOfficerInfo = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end
local IsSupervisor = function(src) return exports['XS-MDT']:IsSupervisor(src) end
local Audit = function(src, action, details, target) return exports['XS-MDT']:AuditLog(action, src, details, target) end

-- ── Numbering ─────────────────────────────────────────────────────────────

--[[ Next number in a series, as PREFIX-YY-NNNN.

     Read from the highest existing number rather than a counter table: a
     server that imports old records keeps counting from where they left off,
     and there is nothing to get out of step. ]]
local function NextNumber(table_, column, prefix)
    local year = os.date('%y')
    local like = ('%s-%s-%%'):format(prefix, year)
    local last = MySQL.scalar.await(
        ('SELECT %s FROM %s WHERE %s LIKE ? ORDER BY %s DESC LIMIT 1'):format(column, table_, column, column),
        { like })
    local n = last and tonumber(last:match('(%d+)$')) or 0
    return ('%s-%s-%04d'):format(prefix, year, n + 1)
end

-- ── Cases ─────────────────────────────────────────────────────────────────

local LINK_KINDS = {
    incident = true, arrest = true, citation = true, warrant = true,
    bolo = true, evidence = true, person = true, vehicle = true, weapon = true,
}

-- The cases one record is filed under, for the record's own page.
function MdtCasesFor(kind, refId)
    if not refId then return {} end
    return MySQL.query.await([[
        SELECT l.id AS link_id, c.id, c.case_number, c.title, c.status
        FROM mdt_case_links l
        JOIN mdt_cases c ON c.id = l.case_id
        WHERE l.kind = ? AND l.ref_id = ?
        ORDER BY c.updated_at DESC
    ]], { kind, tostring(refId) }) or {}
end

lib.callback.register('XS-MDT:server:getCases', function(source, filter)
    if not HasPanel(source, 'cases') then return nil end
    local me = GetOfficerInfo(source)
    if not me then return nil end

    filter = filter or {}
    local where, args = { 'c.department = ?' }, { me.department }

    if filter.status and filter.status ~= 'all' then
        where[#where + 1] = 'c.status = ?'
        args[#args + 1] = filter.status
    end
    if filter.mine then
        where[#where + 1] = 'c.lead_citizenid = ?'
        args[#args + 1] = me.citizenid
    end
    if filter.search and filter.search ~= '' then
        where[#where + 1] = '(c.title LIKE ? OR c.case_number LIKE ? OR c.summary LIKE ?)'
        local q = '%' .. filter.search .. '%'
        args[#args + 1] = q; args[#args + 1] = q; args[#args + 1] = q
    end

    local cases = MySQL.query.await(([[
        SELECT c.*,
               (SELECT COUNT(*) FROM mdt_case_links l WHERE l.case_id = c.id) AS links,
               (SELECT COUNT(*) FROM mdt_case_notes n WHERE n.case_id = c.id) AS notes
        FROM mdt_cases c
        WHERE %s
        ORDER BY FIELD(c.status, 'active', 'open', 'cold', 'closed'), c.updated_at DESC
        LIMIT 200
    ]]):format(table.concat(where, ' AND ')), args)

    return { cases = cases, canManage = true }
end)

lib.callback.register('XS-MDT:server:getCase', function(source, id)
    if not HasPanel(source, 'cases') then return nil end
    local me = GetOfficerInfo(source)
    if not me then return nil end

    local case = MySQL.single.await('SELECT * FROM mdt_cases WHERE id = ?', { id })
    if not case then return nil end

    case.links = MySQL.query.await('SELECT * FROM mdt_case_links WHERE case_id = ? ORDER BY kind, created_at', { id })
    case.notes = MySQL.query.await('SELECT * FROM mdt_case_notes WHERE case_id = ? ORDER BY created_at DESC', { id })
    case.evidence = MySQL.query.await('SELECT * FROM mdt_evidence WHERE case_id = ? ORDER BY created_at', { id })
    case.canManage = true
    case.isSupervisor = IsSupervisor(source)
    return case
end)

lib.callback.register('XS-MDT:server:saveCase', function(source, data)
    if not HasPanel(source, 'cases') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.title or data.title == '' then return false, 'A case needs a title' end

    if data.id then
        MySQL.update.await([[
            UPDATE mdt_cases
            SET title = ?, summary = ?, status = ?, lead_citizenid = ?, lead_name = ?,
                closed_at = CASE WHEN ? = 'closed' THEN NOW() ELSE NULL END
            WHERE id = ? AND department = ?
        ]], { data.title, data.summary, data.status or 'open', data.lead_citizenid, data.lead_name,
              data.status or 'open', data.id, me.department })
        Audit(source, 'CASE_UPDATED', data.title)
        return true
    end

    local number = NextNumber('mdt_cases', 'case_number', 'CASE')
    local id = MySQL.insert.await([[
        INSERT INTO mdt_cases (case_number, title, summary, status, lead_citizenid, lead_name,
                               department, created_by, created_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { number, data.title, data.summary, data.status or 'open',
          data.lead_citizenid or me.citizenid, data.lead_name or me.name,
          me.department, me.citizenid, me.name })

    Audit(source, 'CASE_OPENED', ('%s — %s'):format(number, data.title))
    return { id = id, case_number = number }
end)

local function LinkToCase(caseId, kind, refId, label, me)
    MySQL.insert.await([[
        INSERT IGNORE INTO mdt_case_links (case_id, kind, ref_id, label, added_by, added_by_name)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { caseId, kind, tostring(refId), label, me.citizenid, me.name })

    -- Evidence carries the case on its own row too, so the locker can filter
    -- by case without joining through the link table.
    if kind == 'evidence' then
        MySQL.update.await('UPDATE mdt_evidence SET case_id = ? WHERE id = ?', { caseId, tonumber(refId) })
    end

    MySQL.update.await('UPDATE mdt_cases SET updated_at = NOW() WHERE id = ?', { caseId })
end

lib.callback.register('XS-MDT:server:linkToCase', function(source, data)
    if not HasPanel(source, 'cases') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.caseId then return false, 'No case' end
    if not LINK_KINDS[data.kind] then return false, 'Not something a case can hold' end
    if not data.refId or data.refId == '' then return false, 'Nothing to link' end

    local case = MySQL.single.await('SELECT id, case_number FROM mdt_cases WHERE id = ?', { data.caseId })
    if not case then return false, 'That case no longer exists' end

    LinkToCase(case.id, data.kind, data.refId, data.label, me)
    Audit(source, 'CASE_LINKED', ('%s #%s to %s'):format(data.kind, data.refId, case.case_number))
    return true
end)

lib.callback.register('XS-MDT:server:unlinkFromCase', function(source, id)
    if not HasPanel(source, 'cases') then return false, 'No access' end
    local link = MySQL.single.await('SELECT * FROM mdt_case_links WHERE id = ?', { id })
    if not link then return false, 'Already gone' end

    MySQL.update.await('DELETE FROM mdt_case_links WHERE id = ?', { id })
    if link.kind == 'evidence' then
        MySQL.update.await('UPDATE mdt_evidence SET case_id = NULL WHERE id = ? AND case_id = ?',
            { tonumber(link.ref_id), link.case_id })
    end

    Audit(source, 'CASE_UNLINKED', ('%s #%s'):format(link.kind, link.ref_id))
    return true
end)

lib.callback.register('XS-MDT:server:addCaseNote', function(source, data)
    if not HasPanel(source, 'cases') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.body or data.body == '' then return false, 'Nothing to add' end

    MySQL.insert.await([[
        INSERT INTO mdt_case_notes (case_id, body, author, author_name) VALUES (?, ?, ?, ?)
    ]], { data.caseId, data.body, me.citizenid, me.name })

    MySQL.update.await('UPDATE mdt_cases SET updated_at = NOW() WHERE id = ?', { data.caseId })
    return true
end)

-- ── Evidence locker ───────────────────────────────────────────────────────

local EVIDENCE_STATUS = {
    booked = true, checked_out = true, released = true, destroyed = true, lost = true,
}

local EVIDENCE_KINDS = {
    item = true, weapon = true, drug = true, photo = true, print = true, dna = true, doc = true, note = true,
}

local function Custody(evidenceId, action, detail, me)
    MySQL.insert.await([[
        INSERT INTO mdt_evidence_custody (evidence_id, action, detail, officer_citizenid, officer_name)
        VALUES (?, ?, ?, ?, ?)
    ]], { evidenceId, action, detail, me.citizenid, me.name })
end

-- A report someone else is still drafting cannot have things hung off it.
local function ReportFor(id, viewerCid)
    id = tonumber(id)
    if not id then return nil end
    local row = MySQL.single.await(
        'SELECT id, case_number, title, status, created_by FROM mdt_incidents WHERE id = ?', { id })
    if not row then return nil end
    if row.status == 'draft' and row.created_by ~= viewerCid then return nil end
    return row
end

local function ArrestFor(id)
    id = tonumber(id)
    if not id then return nil end
    return MySQL.single.await([[
        SELECT a.id, a.citizenid, COALESCE(CONCAT(c.firstname, ' ', c.lastname), a.citizenid) AS civilian_name
        FROM mdt_arrests a LEFT JOIN mdt_civilians c ON c.citizenid = a.citizenid
        WHERE a.id = ?
    ]], { id })
end

--[[ Every piece of evidence is booked the same way, wherever it was logged
     from: a number, a custody entry, and whatever it was attached to. ]]
function MdtBookEvidence(actor, data)
    local kind = EVIDENCE_KINDS[data.kind] and data.kind or 'item'
    local label = tostring(data.label or ''):sub(1, 120)
    if label == '' then return nil end

    local location = data.location and tostring(data.location):sub(1, 120) or nil
    if location == '' then location = nil end

    local number = NextNumber('mdt_evidence', 'evidence_number', 'EV')
    local id = MySQL.insert.await([[
        INSERT INTO mdt_evidence (evidence_number, case_id, incident_id, arrest_id, kind, label, detail,
                                  photo, location, status, logged_by, logged_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'booked', ?, ?)
    ]], { number, data.caseId, data.incidentId, data.arrestId, kind, label,
          data.detail and tostring(data.detail):sub(1, 1000) or nil,
          kind == 'photo' and data.photo and tostring(data.photo):sub(1, 500) or nil,
          location, actor.citizenid, actor.name })
    if not id then return nil end

    Custody(id, 'booked', location and ('Into ' .. location) or nil, actor)

    if data.caseId then
        LinkToCase(data.caseId, 'evidence', id, number .. ' — ' .. label, actor)
    end

    return id, number
end

lib.callback.register('XS-MDT:server:getEvidence', function(source, filter)
    if not HasPanel(source, 'evidence') then return nil end

    filter = filter or {}
    local where, args = { '1=1' }, {}

    if filter.status and filter.status ~= 'all' then
        where[#where + 1] = 'e.status = ?'
        args[#args + 1] = filter.status
    end
    if filter.search and filter.search ~= '' then
        where[#where + 1] = '(e.label LIKE ? OR e.evidence_number LIKE ? OR e.detail LIKE ? OR e.location LIKE ?)'
        local q = '%' .. filter.search .. '%'
        for _ = 1, 4 do args[#args + 1] = q end
    end

    local rows = MySQL.query.await(([[
        SELECT e.*, c.case_number, i.case_number AS report_number
        FROM mdt_evidence e
        LEFT JOIN mdt_cases c ON c.id = e.case_id
        LEFT JOIN mdt_incidents i ON i.id = e.incident_id
        WHERE %s
        ORDER BY e.created_at DESC
        LIMIT 200
    ]]):format(table.concat(where, ' AND ')), args)

    return { items = rows, canManage = true }
end)

lib.callback.register('XS-MDT:server:getEvidenceItem', function(source, id)
    if not HasPanel(source, 'evidence') then return nil end
    local me = GetOfficerInfo(source)
    local item = MySQL.single.await([[
        SELECT e.*, c.case_number, c.title AS case_title FROM mdt_evidence e
        LEFT JOIN mdt_cases c ON c.id = e.case_id
        WHERE e.id = ?
    ]], { id })
    if not item then return nil end
    item.custody = MySQL.query.await(
        'SELECT * FROM mdt_evidence_custody WHERE evidence_id = ? ORDER BY created_at DESC', { id })
    item.report = item.incident_id and ReportFor(item.incident_id, me and me.citizenid) or nil
    item.arrest = item.arrest_id and ArrestFor(item.arrest_id) or nil
    return item
end)

lib.callback.register('XS-MDT:server:bookEvidence', function(source, data)
    if not HasPanel(source, 'evidence') and not HasPanel(source, 'incidents') and not HasPanel(source, 'arrests') then
        return false, 'No access'
    end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if type(data) ~= 'table' or not data.label or data.label == '' then return false, 'Describe what it is' end

    local links = { kind = data.kind, label = data.label, detail = data.detail, location = data.location, photo = data.photo }

    if data.incidentId then
        local report = ReportFor(data.incidentId, me.citizenid)
        if not report then return false, 'That report does not exist' end
        links.incidentId = report.id
    end
    if data.arrestId then
        local arrest = ArrestFor(data.arrestId)
        if not arrest then return false, 'That arrest does not exist' end
        links.arrestId = arrest.id
    end
    if data.caseId then
        local case = MySQL.scalar.await('SELECT id FROM mdt_cases WHERE id = ?', { tonumber(data.caseId) })
        if not case then return false, 'That case does not exist' end
        links.caseId = case
    end

    local id, number = MdtBookEvidence(me, links)
    if not id then return false, 'Could not book it in' end

    Audit(source, 'EVIDENCE_BOOKED', ('%s — %s'):format(number, links.label))
    return { id = id, number = number }
end)

lib.callback.register('XS-MDT:server:updateEvidence', function(source, data)
    if not HasPanel(source, 'evidence') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.id then return false, 'No item' end

    local item = MySQL.single.await('SELECT * FROM mdt_evidence WHERE id = ?', { data.id })
    if not item then return false, 'No such item' end

    local status = data.status or item.status
    if not EVIDENCE_STATUS[status] then return false, 'Not a status' end

    -- Destroying or releasing evidence is a supervisor's call. Everything else
    -- an officer handling the item can do.
    if (status == 'destroyed' or status == 'released') and status ~= item.status and not IsSupervisor(source) then
        return false, 'A supervisor releases or destroys evidence'
    end

    MySQL.update.await([[
        UPDATE mdt_evidence SET status = ?, location = ?, detail = ? WHERE id = ?
    ]], { status, data.location, data.detail, data.id })

    if status ~= item.status then
        Custody(data.id, status, data.note, me)
        Audit(source, 'EVIDENCE_' .. status:upper(), ('%s — %s'):format(item.evidence_number or item.id, item.label))
    elseif data.note and data.note ~= '' then
        Custody(data.id, 'note', data.note, me)
    end

    return true
end)

-- Attach evidence to a report, an arrest or a case, or take it off one. A ref
-- of 0 detaches.
lib.callback.register('XS-MDT:server:linkEvidence', function(source, data)
    if not HasPanel(source, 'evidence') and not HasPanel(source, 'incidents') and not HasPanel(source, 'arrests') then
        return false, 'No access'
    end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if type(data) ~= 'table' or not data.id then return false, 'No item' end

    local item = MySQL.single.await('SELECT id, evidence_number, label, incident_id, arrest_id, case_id FROM mdt_evidence WHERE id = ?', { data.id })
    if not item then return false, 'No such item' end

    local ref = tonumber(data.ref) or 0
    local name = item.evidence_number or ('#' .. item.id)

    if data.kind == 'incident' then
        if ref == 0 then
            MySQL.update.await('UPDATE mdt_evidence SET incident_id = NULL WHERE id = ?', { item.id })
            Custody(item.id, 'note', 'Taken off report', me)
        else
            local report = ReportFor(ref, me.citizenid)
            if not report then return false, 'That report does not exist' end
            MySQL.update.await('UPDATE mdt_evidence SET incident_id = ? WHERE id = ?', { report.id, item.id })
            Custody(item.id, 'note', 'Attached to report ' .. (report.case_number or ('#' .. report.id)), me)
        end
    elseif data.kind == 'arrest' then
        if ref == 0 then
            MySQL.update.await('UPDATE mdt_evidence SET arrest_id = NULL WHERE id = ?', { item.id })
            Custody(item.id, 'note', 'Taken off arrest', me)
        else
            local arrest = ArrestFor(ref)
            if not arrest then return false, 'That arrest does not exist' end
            MySQL.update.await('UPDATE mdt_evidence SET arrest_id = ? WHERE id = ?', { arrest.id, item.id })
            Custody(item.id, 'note', ('Attached to arrest #%d (%s)'):format(arrest.id, arrest.civilian_name), me)
        end
    elseif data.kind == 'case' then
        if not HasPanel(source, 'cases') then return false, 'No access to cases' end
        if item.case_id then
            MySQL.update.await("DELETE FROM mdt_case_links WHERE case_id = ? AND kind = 'evidence' AND ref_id = ?",
                { item.case_id, tostring(item.id) })
            MySQL.update.await('UPDATE mdt_evidence SET case_id = NULL WHERE id = ?', { item.id })
        end
        if ref ~= 0 then
            local case = MySQL.single.await('SELECT id, case_number FROM mdt_cases WHERE id = ?', { ref })
            if not case then return false, 'That case does not exist' end
            LinkToCase(case.id, 'evidence', item.id, name .. ' — ' .. item.label, me)
            Custody(item.id, 'note', 'Filed under ' .. case.case_number, me)
        end
    else
        return false, 'Not something evidence can be attached to'
    end

    Audit(source, 'EVIDENCE_LINKED', ('%s %s %s #%s'):format(name, ref == 0 and 'taken off' or 'attached to', data.kind, ref))
    return true
end)

-- ── Finding things to attach ──────────────────────────────────────────────

local SEARCH_PANEL = {
    incident = 'incidents', arrest = 'arrests', citation = 'citations', warrant = 'warrants',
    bolo = 'bolos', evidence = 'evidence', person = 'civilians', vehicle = 'vehicles',
    weapon = 'weapons', case = 'cases',
}

local function Short(s, n)
    s = tostring(s or '')
    return #s > n and (s:sub(1, n - 1) .. '…') or s
end

--[[ One search for every kind of record, in one shape: ref is what a link
     stores, label is what a person reads, meta is the line under it. ]]
lib.callback.register('XS-MDT:server:searchLinkable', function(source, data)
    if type(data) ~= 'table' then return {} end
    local panel = SEARCH_PANEL[data.kind]
    if not panel or not HasPanel(source, panel) then return {} end
    local me = GetOfficerInfo(source)
    if not me then return {} end

    local q = tostring(data.query or ''):sub(1, 60)
    if #q < 1 then return {} end
    local like = '%' .. q .. '%'
    local asId = tonumber((q:gsub('^#', '')))
    local out = {}

    if data.kind == 'incident' then
        local rows = MySQL.query.await([[
            SELECT id, case_number, title, created_by_name, created_at FROM mdt_incidents
            WHERE (status != 'draft' OR created_by = ?)
              AND (id = ? OR case_number LIKE ? OR title LIKE ?)
            ORDER BY created_at DESC LIMIT 12
        ]], { me.citizenid, asId or -1, like, like }) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { ref = r.id, label = ('%s — %s'):format(r.case_number or ('#' .. r.id), Short(r.title, 60)),
                              meta = ('By %s'):format(r.created_by_name or '?'), at = r.created_at }
        end

    elseif data.kind == 'arrest' or data.kind == 'citation' or data.kind == 'warrant' then
        local tbl = ({ arrest = 'mdt_arrests', citation = 'mdt_citations', warrant = 'mdt_warrants' })[data.kind]
        local by = data.kind == 'warrant' and 'r.issued_by_name' or 'r.officer_name'
        local rows = MySQL.query.await(([[
            SELECT r.id, r.citizenid, %s AS officer, r.created_at,
                   COALESCE(CONCAT(c.firstname, ' ', c.lastname), r.citizenid) AS civilian_name
            FROM %s r LEFT JOIN mdt_civilians c ON c.citizenid = r.citizenid
            WHERE r.id = ? OR r.citizenid LIKE ?
               OR CONCAT(COALESCE(c.firstname, ''), ' ', COALESCE(c.lastname, '')) LIKE ?
            ORDER BY r.created_at DESC LIMIT 12
        ]]):format(by, tbl), { asId or -1, like, like }) or {}
        local word = ({ arrest = 'Arrest', citation = 'Citation', warrant = 'Warrant' })[data.kind]
        for _, r in ipairs(rows) do
            out[#out + 1] = { ref = r.id, label = ('%s #%d — %s'):format(word, r.id, r.civilian_name),
                              meta = ('By %s'):format(r.officer or '?'), at = r.created_at }
        end

    elseif data.kind == 'bolo' then
        local rows = MySQL.query.await([[
            SELECT id, type, description, plate, active, created_at FROM mdt_bolos
            WHERE id = ? OR description LIKE ? OR plate LIKE ?
            ORDER BY active DESC, created_at DESC LIMIT 12
        ]], { asId or -1, like, like }) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { ref = r.id, label = ('BOLO #%d — %s'):format(r.id, Short(r.description, 60)),
                              meta = (r.plate and (r.plate .. ' · ') or '') .. (tonumber(r.active) == 1 and 'Active' or 'Cleared'),
                              at = r.created_at }
        end

    elseif data.kind == 'evidence' then
        local rows = MySQL.query.await([[
            SELECT id, evidence_number, label, status, location, created_at FROM mdt_evidence
            WHERE id = ? OR evidence_number LIKE ? OR label LIKE ?
            ORDER BY created_at DESC LIMIT 12
        ]], { asId or -1, like, like }) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { ref = r.id, label = ('%s — %s'):format(r.evidence_number or ('#' .. r.id), Short(r.label, 60)),
                              meta = (r.status or 'booked'):gsub('_', ' ') .. (r.location and (' · ' .. r.location) or ''),
                              at = r.created_at }
        end

    elseif data.kind == 'person' then
        local rows = MySQL.query.await([[
            SELECT citizenid, firstname, lastname, dob FROM mdt_civilians
            WHERE citizenid LIKE ? OR CONCAT(firstname, ' ', lastname) LIKE ?
            ORDER BY lastname, firstname LIMIT 12
        ]], { like, like }) or {}
        if #rows == 0 then
            local found = MySQL.query.await([[
                SELECT citizenid, charinfo FROM players
                WHERE citizenid LIKE ?
                   OR CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ',
                             JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?
                LIMIT 12
            ]], { like, like }) or {}
            for _, r in ipairs(found) do
                local ok, info = pcall(json.decode, r.charinfo or '{}')
                info = ok and info or {}
                rows[#rows + 1] = { citizenid = r.citizenid, firstname = info.firstname, lastname = info.lastname, dob = info.birthdate }
            end
        end
        for _, r in ipairs(rows) do
            local name = ('%s %s'):format(r.firstname or '', r.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
            out[#out + 1] = { ref = r.citizenid, label = name ~= '' and name or r.citizenid,
                              meta = ('%s · DOB %s'):format(r.citizenid, r.dob or '—') }
        end

    elseif data.kind == 'vehicle' then
        local rows = MySQL.query.await([[
            SELECT plate, vehicle, citizenid FROM player_vehicles WHERE plate LIKE ? LIMIT 12
        ]], { like }) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { ref = (r.plate or ''):gsub('^%s+', ''):gsub('%s+$', ''),
                              label = ('%s — %s'):format(r.plate, r.vehicle or 'Vehicle'),
                              meta = r.citizenid and ('Owner ' .. r.citizenid) or '' }
        end

    elseif data.kind == 'weapon' then
        local rows = MySQL.query.await([[
            SELECT serial, model, owner_name, status FROM mdt_weapons
            WHERE serial LIKE ? OR model LIKE ? OR owner_name LIKE ?
            ORDER BY updated_at DESC LIMIT 12
        ]], { like, like, like }) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { ref = r.serial, label = ('%s — %s'):format(r.serial, r.model),
                              meta = ('%s · %s'):format(r.owner_name or 'No owner on file', r.status or 'registered') }
        end

    elseif data.kind == 'case' then
        local rows = MySQL.query.await([[
            SELECT id, case_number, title, status FROM mdt_cases
            WHERE department = ? AND (case_number LIKE ? OR title LIKE ?)
            ORDER BY FIELD(status, 'active', 'open', 'cold', 'closed'), updated_at DESC LIMIT 12
        ]], { me.department, like, like }) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { ref = r.id, label = ('%s — %s'):format(r.case_number, Short(r.title, 60)), meta = r.status }
        end
    end

    return out
end)

--[[ Where an attachment actually points.

     Links made from the search above store ids, but links typed by hand
     before it existed hold whatever the officer wrote: a report number, an
     evidence number, a plate. This resolves either. ]]
lib.callback.register('XS-MDT:server:getLinkTarget', function(source, data)
    if type(data) ~= 'table' then return { found = false } end
    local panel = SEARCH_PANEL[data.kind]
    if not panel or not HasPanel(source, panel) then return { found = false, error = 'No access' } end
    local me = GetOfficerInfo(source)
    if not me then return { found = false } end

    local ref = tostring(data.ref or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if ref == '' then return { found = false } end
    local asId = tonumber((ref:gsub('^#', '')))

    if data.kind == 'incident' then
        local row = MySQL.single.await([[
            SELECT id FROM mdt_incidents
            WHERE (id = ? OR case_number = ?) AND (status != 'draft' OR created_by = ?)
            LIMIT 1
        ]], { asId or -1, ref, me.citizenid })
        return row and { found = true, id = row.id } or { found = false }

    elseif data.kind == 'arrest' or data.kind == 'citation' or data.kind == 'bolo' then
        local tbl = ({ arrest = 'mdt_arrests', citation = 'mdt_citations', bolo = 'mdt_bolos' })[data.kind]
        local id = asId and MySQL.scalar.await(('SELECT id FROM %s WHERE id = ?'):format(tbl), { asId })
        return id and { found = true, id = id } or { found = false }

    elseif data.kind == 'warrant' then
        local row = asId and MySQL.single.await('SELECT id, citizenid FROM mdt_warrants WHERE id = ?', { asId })
        return row and { found = true, id = row.id, citizenid = row.citizenid } or { found = false }

    elseif data.kind == 'evidence' then
        local id = MySQL.scalar.await('SELECT id FROM mdt_evidence WHERE id = ? OR evidence_number = ? LIMIT 1',
            { asId or -1, ref })
        return id and { found = true, id = id } or { found = false }

    elseif data.kind == 'person' then
        local cid = MySQL.scalar.await('SELECT citizenid FROM mdt_civilians WHERE citizenid = ?', { ref })
            or MySQL.scalar.await('SELECT citizenid FROM players WHERE citizenid = ?', { ref })
        return cid and { found = true, citizenid = cid } or { found = false }

    elseif data.kind == 'vehicle' then
        return { found = true, plate = ref:upper() }

    elseif data.kind == 'weapon' then
        local serial = MySQL.scalar.await('SELECT serial FROM mdt_weapons WHERE serial = ? OR id = ? LIMIT 1',
            { ref:upper(), asId or -1 })
        return serial and { found = true, serial = serial } or { found = false }

    elseif data.kind == 'case' then
        local id = MySQL.scalar.await('SELECT id FROM mdt_cases WHERE id = ? OR case_number = ? LIMIT 1',
            { asId or -1, ref })
        return id and { found = true, id = id } or { found = false }
    end

    return { found = false }
end)

-- ── Weapons registry ──────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:getWeapons', function(source, filter)
    if not HasPanel(source, 'weapons') then return nil end

    filter = filter or {}
    local where, args = { '1=1' }, {}

    if filter.status and filter.status ~= 'all' then
        where[#where + 1] = 'status = ?'
        args[#args + 1] = filter.status
    end
    if filter.search and filter.search ~= '' then
        where[#where + 1] = '(serial LIKE ? OR model LIKE ? OR owner_name LIKE ?)'
        local q = '%' .. filter.search .. '%'
        for _ = 1, 3 do args[#args + 1] = q end
    end

    return {
        weapons = MySQL.query.await(
            ('SELECT * FROM mdt_weapons WHERE %s ORDER BY updated_at DESC LIMIT 200'):format(table.concat(where, ' AND ')),
            args),
        canManage = true,
    }
end)

--[[ Every firearm registered to one person.

     The civilian profile calls this, so a lookup shows what somebody is
     licensed to carry without opening the registry separately. ]]
lib.callback.register('XS-MDT:server:getWeaponsFor', function(source, citizenid)
    if not IsAuthorized(source) then return nil end
    if not citizenid then return {} end
    return MySQL.query.await(
        'SELECT * FROM mdt_weapons WHERE owner_citizenid = ? ORDER BY status, model', { citizenid }) or {}
end)

-- Same list, for another resource. A weapon shop checking whether somebody is
-- registered should not have to query our tables itself.
exports('GetWeaponsFor', function(citizenid)
    if not citizenid then return {} end
    return MySQL.query.await(
        'SELECT * FROM mdt_weapons WHERE owner_citizenid = ? ORDER BY status, model', { citizenid }) or {}
end)

lib.callback.register('XS-MDT:server:saveWeapon', function(source, data)
    if not HasPanel(source, 'weapons') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.serial or data.serial == '' then return false, 'A firearm needs a serial' end
    if not data.model or data.model == '' then return false, 'A firearm needs a model' end

    local serial = data.serial:upper():sub(1, 30)

    if data.id then
        MySQL.update.await([[
            UPDATE mdt_weapons SET serial = ?, model = ?, class = ?, owner_citizenid = ?, owner_name = ?,
                   status = ?, registered_at = ?, notes = ?
            WHERE id = ?
        ]], { serial, data.model, data.class, data.owner_citizenid, data.owner_name,
              data.status or 'registered', data.registered_at, data.notes, data.id })
        Audit(source, 'WEAPON_UPDATED', ('%s — %s'):format(serial, data.model), data.owner_citizenid)
        return true
    end

    local taken = MySQL.scalar.await('SELECT id FROM mdt_weapons WHERE serial = ?', { serial })
    if taken then return false, 'That serial is already on the registry' end

    MySQL.insert.await([[
        INSERT INTO mdt_weapons (serial, model, class, owner_citizenid, owner_name, status,
                                 registered_at, notes, added_by, added_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { serial, data.model, data.class, data.owner_citizenid, data.owner_name,
          data.status or 'registered', data.registered_at, data.notes, me.citizenid, me.name })

    Audit(source, 'WEAPON_REGISTERED', ('%s — %s'):format(serial, data.model), data.owner_citizenid)
    return true, serial
end)

lib.callback.register('XS-MDT:server:deleteWeapon', function(source, id)
    if not HasPanel(source, 'weapons') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors only' end

    local w = MySQL.single.await('SELECT serial, model FROM mdt_weapons WHERE id = ?', { id })
    if not w then return false, 'Already gone' end

    MySQL.update.await('DELETE FROM mdt_weapons WHERE id = ?', { id })
    Audit(source, 'WEAPON_REMOVED', ('%s — %s'):format(w.serial, w.model))
    return true
end)
