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
    return true, { id = id, case_number = number }
end)

lib.callback.register('XS-MDT:server:linkToCase', function(source, data)
    if not HasPanel(source, 'cases') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.caseId then return false, 'No case' end
    if not LINK_KINDS[data.kind] then return false, 'Not something a case can hold' end
    if not data.refId or data.refId == '' then return false, 'Nothing to link' end

    MySQL.insert.await([[
        INSERT IGNORE INTO mdt_case_links (case_id, kind, ref_id, label, added_by, added_by_name)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { data.caseId, data.kind, tostring(data.refId), data.label, me.citizenid, me.name })

    -- Evidence carries the case on its own row too, so the locker can filter
    -- by case without joining through the link table.
    if data.kind == 'evidence' then
        MySQL.update.await('UPDATE mdt_evidence SET case_id = ? WHERE id = ?', { data.caseId, tonumber(data.refId) })
    end

    MySQL.update.await('UPDATE mdt_cases SET updated_at = NOW() WHERE id = ?', { data.caseId })
    Audit(source, 'CASE_LINKED', ('%s #%s'):format(data.kind, data.refId))
    return true
end)

lib.callback.register('XS-MDT:server:unlinkFromCase', function(source, id)
    if not HasPanel(source, 'cases') then return false, 'No access' end
    local link = MySQL.single.await('SELECT * FROM mdt_case_links WHERE id = ?', { id })
    if not link then return false, 'Already gone' end

    MySQL.update.await('DELETE FROM mdt_case_links WHERE id = ?', { id })
    if link.kind == 'evidence' then
        MySQL.update.await('UPDATE mdt_evidence SET case_id = NULL WHERE id = ?', { tonumber(link.ref_id) })
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

local function Custody(evidenceId, action, detail, me)
    MySQL.insert.await([[
        INSERT INTO mdt_evidence_custody (evidence_id, action, detail, officer_citizenid, officer_name)
        VALUES (?, ?, ?, ?, ?)
    ]], { evidenceId, action, detail, me.citizenid, me.name })
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
        SELECT e.*, c.case_number
        FROM mdt_evidence e
        LEFT JOIN mdt_cases c ON c.id = e.case_id
        WHERE %s
        ORDER BY e.created_at DESC
        LIMIT 200
    ]]):format(table.concat(where, ' AND ')), args)

    return { items = rows, canManage = true }
end)

lib.callback.register('XS-MDT:server:getEvidenceItem', function(source, id)
    if not HasPanel(source, 'evidence') then return nil end
    local item = MySQL.single.await([[
        SELECT e.*, c.case_number FROM mdt_evidence e
        LEFT JOIN mdt_cases c ON c.id = e.case_id
        WHERE e.id = ?
    ]], { id })
    if not item then return nil end
    item.custody = MySQL.query.await(
        'SELECT * FROM mdt_evidence_custody WHERE evidence_id = ? ORDER BY created_at DESC', { id })
    return item
end)

lib.callback.register('XS-MDT:server:bookEvidence', function(source, data)
    if not HasPanel(source, 'evidence') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.label or data.label == '' then return false, 'Describe what it is' end

    local number = NextNumber('mdt_evidence', 'evidence_number', 'EV')
    local id = MySQL.insert.await([[
        INSERT INTO mdt_evidence (evidence_number, case_id, kind, label, detail, location, status,
                                  logged_by, logged_by_name)
        VALUES (?, ?, ?, ?, ?, ?, 'booked', ?, ?)
    ]], { number, data.caseId, data.kind or 'item', data.label, data.detail, data.location,
          me.citizenid, me.name })

    Custody(id, 'booked', data.location and ('Into ' .. data.location) or nil, me)

    if data.caseId then
        MySQL.insert.await([[
            INSERT IGNORE INTO mdt_case_links (case_id, kind, ref_id, label, added_by, added_by_name)
            VALUES (?, 'evidence', ?, ?, ?, ?)
        ]], { data.caseId, tostring(id), number .. ' — ' .. data.label, me.citizenid, me.name })
    end

    Audit(source, 'EVIDENCE_BOOKED', ('%s — %s'):format(number, data.label))
    return true, number
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
