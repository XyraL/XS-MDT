local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local IsSupervisor = function(src) return exports['XS-MDT']:IsSupervisor(src) end
local GetOfficer = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end

-- Fine deduction handler — replaceable via exports
local _fineHandler = function(targetSrc, amount, reason)
    if not Config.FineDeduction.Enabled then return end
    local target = Framework.GetPlayer(targetSrc)
    if target then
        target.Functions.RemoveMoney('bank', amount, reason)
    end
end

-- Allow other resources to override the deduction logic (e.g. custom economy)
exports('SetFineHandler', function(fn) _fineHandler = fn end)
exports('DeductFine', function(targetSrc, amount, reason) _fineHandler(targetSrc, amount, reason) end)

local function Decode(value)
    if type(value) ~= 'string' then return value or {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or {}
end

-- The server finds the suspect itself. The panel used to be trusted to say
-- which player to jail and fine, and never did, so neither ever happened.
local function OnlineSource(citizenid)
    local ok, player = pcall(function() return Framework.GetPlayerByCitizenId(citizenid) end)
    if ok and player and player.PlayerData then return player.PlayerData.source end
    return nil
end

local function CleanCharges(list)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for _, c in ipairs(list) do
        if type(c) == 'table' then
            out[#out + 1] = {
                id = tonumber(c.id),
                code = c.code and tostring(c.code):sub(1, 20) or nil,
                name = tostring(c.name or c.title or ''):sub(1, 150),
                type = c.type and tostring(c.type):sub(1, 20) or nil,
                category = c.category and tostring(c.category):sub(1, 60) or nil,
                fine_amount = math.max(0, math.floor(tonumber(c.fine_amount) or 0)),
                jail_time = math.max(0, math.floor(tonumber(c.jail_time) or 0)),
            }
            if #out >= 40 then break end
        end
    end
    return out
end

local function Amount(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function Text(value, max)
    if value == nil then return nil end
    local s = tostring(value)
    if s == '' then return nil end
    return s:sub(1, max)
end

-- ─── Arrests ───────────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:logArrest', function(source, data)
    if not HasPanel(source, 'arrests') then return false end
    local officer = GetOfficer(source)
    if not officer then return false, 'Not on duty' end
    if type(data) ~= 'table' or not data.citizenid then return false, 'Pick a suspect' end

    local charges = CleanCharges(data.charges)
    if #charges == 0 then return false, 'Add at least one charge' end

    local fine, jail = Amount(data.fine), Amount(data.jailTime)
    local narrative, location = Text(data.narrative, 20000), Text(data.location, 255)

    local id = MySQL.insert.await([[
        INSERT INTO mdt_arrests (citizenid, officer_citizenid, officer_name, charges, fine, jail_time, narrative, location)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.citizenid, officer.citizenid, officer.name,
        json.encode(charges), fine, jail, narrative, location,
    })
    if not id then return false, 'Could not save the arrest' end

    if data.clearWarrants then
        MySQL.update.await("UPDATE mdt_warrants SET status = 'cleared', cleared_by = ?, cleared_at = NOW() WHERE citizenid = ? AND status = 'active'", {
            officer.citizenid, data.citizenid
        })
    end

    if type(data.linkedIncidents) == 'table' and MdtSetIncidentLink then
        for _, incidentId in ipairs(data.linkedIncidents) do
            MdtSetIncidentLink('arrest', id, incidentId, true, officer.citizenid)
        end
    end

    local target = OnlineSource(data.citizenid)

    if target and jail > 0 then
        local jailResource = Config.JailResource
        if jailResource == 'qb-prison' then
            TriggerEvent('qb-prison:server:sendToJail', target, jail)
        elseif jailResource == 'ps-prison' then
            TriggerEvent('prison:server:SendToJail', target, jail)
        else
            TriggerClientEvent('XS-MDT:client:jailPlayer', target, jail)
        end
    end

    if target and fine > 0 and Config.FineDeduction.AutoDeductArrests then
        _fineHandler(target, fine, 'XS-MDT-arrest')
    end

    exports['XS-MDT']:AuditLog('Arrest Logged', officer.name, 'Arrest ID: ' .. id .. ' | Citizenid: ' .. data.citizenid)
    exports['XS-MDT']:LogBodyCam(source, 'ARREST_LOGGED',
        'Subject: ' .. data.citizenid .. ' | Charges: ' .. #charges .. ' | Fine: $' .. fine .. ' | Jail: ' .. jail .. 'min')
    return { id = id }
end)

lib.callback.register('XS-MDT:server:getArrest', function(source, id)
    if not HasPanel(source, 'arrests') then return nil end
    local officer = GetOfficer(source)
    if not officer then return nil end

    local a = MySQL.single.await([[
        SELECT a.*, c.firstname, c.lastname, c.dob, c.gender, c.image
        FROM mdt_arrests a LEFT JOIN mdt_civilians c ON c.citizenid = a.citizenid
        WHERE a.id = ?
    ]], { tonumber(id) })
    if not a then return nil end

    a.civilian_name = a.firstname and (a.firstname .. ' ' .. (a.lastname or '')) or a.citizenid
    a.charges = Decode(a.charges)
    a.tags = Decode(a.tags)
    a.reports = MdtIncidentsLinkedTo and MdtIncidentsLinkedTo('arrest', a.id, officer.citizenid) or {}
    a.evidence = MySQL.query.await([[
        SELECT id, evidence_number, kind, label, status, location, logged_by_name, created_at
        FROM mdt_evidence WHERE arrest_id = ? ORDER BY created_at
    ]], { a.id }) or {}
    a.cases = MdtCasesFor and MdtCasesFor('arrest', a.id) or {}
    a.canEdit = a.officer_citizenid == officer.citizenid or IsSupervisor(source)
    a.canDelete = IsSupervisor(source)
    a.canCases = HasPanel(source, 'cases')
    return a
end)

lib.callback.register('XS-MDT:server:updateArrest', function(source, data)
    if not HasPanel(source, 'arrests') then return false end
    local officer = GetOfficer(source)
    if not officer then return false, 'Not on duty' end
    if type(data) ~= 'table' or not data.id then return false, 'No arrest' end

    local existing = MySQL.single.await('SELECT id, officer_citizenid, citizenid FROM mdt_arrests WHERE id = ?', { data.id })
    if not existing then return false, 'That arrest no longer exists' end
    if existing.officer_citizenid ~= officer.citizenid and not IsSupervisor(source) then
        return false, 'Only the arresting officer or a supervisor can edit this'
    end

    local charges = CleanCharges(data.charges)
    if #charges == 0 then return false, 'Keep at least one charge' end

    MySQL.update.await([[
        UPDATE mdt_arrests SET charges = ?, fine = ?, jail_time = ?, narrative = ?, location = ?, updated_at = NOW()
        WHERE id = ?
    ]], { json.encode(charges), Amount(data.fine), Amount(data.jailTime),
          Text(data.narrative, 20000), Text(data.location, 255), existing.id })

    exports['XS-MDT']:AuditLog('Arrest Edited', officer.name, 'Arrest ID: ' .. existing.id .. ' | Citizenid: ' .. existing.citizenid)
    return true
end)

lib.callback.register('XS-MDT:server:deleteArrest', function(source, id)
    if not HasPanel(source, 'arrests') then return false end
    if not IsSupervisor(source) then return false, 'Supervisors only' end
    local officer = GetOfficer(source)
    local existing = MySQL.single.await('SELECT id, citizenid FROM mdt_arrests WHERE id = ?', { tonumber(id) })
    if not existing then return false, 'Already gone' end

    if MdtIncidentsLinkedTo and MdtSetIncidentLink then
        for _, report in ipairs(MdtIncidentsLinkedTo('arrest', existing.id)) do
            MdtSetIncidentLink('arrest', existing.id, report.id, false)
        end
    end
    MySQL.update.await('UPDATE mdt_evidence SET arrest_id = NULL WHERE arrest_id = ?', { existing.id })
    MySQL.update.await("DELETE FROM mdt_case_links WHERE kind = 'arrest' AND ref_id = ?", { tostring(existing.id) })
    MySQL.update.await('DELETE FROM mdt_arrests WHERE id = ?', { existing.id })

    exports['XS-MDT']:AuditLog('Arrest Deleted', officer and officer.name or 'Supervisor',
        'Arrest ID: ' .. existing.id .. ' | Citizenid: ' .. existing.citizenid)
    return true
end)

lib.callback.register('XS-MDT:server:getArrests', function(source, citizenid)
    if not HasPanel(source, 'arrests') then return nil end
    local results = MySQL.query.await('SELECT * FROM mdt_arrests WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    for _, a in ipairs(results) do a.charges = Decode(a.charges) end
    return results
end)

-- ─── Citations ─────────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:issueCitation', function(source, data)
    if not HasPanel(source, 'citations') then return false end
    local officer = GetOfficer(source)
    if not officer then return false, 'Not on duty' end
    if type(data) ~= 'table' or not data.citizenid then return false, 'Pick who the citation is for' end

    local charges = CleanCharges(data.charges)
    if #charges == 0 then return false, 'Add at least one charge' end
    local fine = Amount(data.fine)

    local id = MySQL.insert.await([[
        INSERT INTO mdt_citations (citizenid, officer_citizenid, officer_name, charges, fine, location, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.citizenid, officer.citizenid, officer.name,
        json.encode(charges), fine, Text(data.location, 255), Text(data.notes, 2000)
    })
    if not id then return false, 'Could not save the citation' end

    local target = OnlineSource(data.citizenid)
    if target and fine > 0 and (data.autoPay or Config.FineDeduction.AutoDeductCitations) and Config.FineDeduction.Enabled then
        _fineHandler(target, fine, 'XS-MDT-citation')
        MySQL.update.await('UPDATE mdt_citations SET paid = 1 WHERE id = ?', { id })
    end

    exports['XS-MDT']:AuditLog('Citation Issued', officer.name, 'Citation ID: ' .. id .. ' | Fine: $' .. fine)
    exports['XS-MDT']:LogBodyCam(source, 'CITATION_ISSUED',
        'Subject: ' .. data.citizenid .. ' | Fine: $' .. fine .. ' | Charges: ' .. #charges)
    return { id = id }
end)

lib.callback.register('XS-MDT:server:getCitation', function(source, id)
    if not HasPanel(source, 'citations') then return nil end
    local officer = GetOfficer(source)
    if not officer then return nil end

    local c = MySQL.single.await([[
        SELECT ci.*, c.firstname, c.lastname, c.dob, c.image
        FROM mdt_citations ci LEFT JOIN mdt_civilians c ON c.citizenid = ci.citizenid
        WHERE ci.id = ?
    ]], { tonumber(id) })
    if not c then return nil end

    c.civilian_name = c.firstname and (c.firstname .. ' ' .. (c.lastname or '')) or c.citizenid
    c.charges = Decode(c.charges)
    c.tags = Decode(c.tags)
    c.reports = MdtIncidentsLinkedTo and MdtIncidentsLinkedTo('citation', c.id, officer.citizenid) or {}
    c.cases = MdtCasesFor and MdtCasesFor('citation', c.id) or {}
    c.canMarkPaid = IsSupervisor(source)
    c.canCases = HasPanel(source, 'cases')
    return c
end)

lib.callback.register('XS-MDT:server:getCitations', function(source, citizenid)
    if not HasPanel(source, 'citations') then return nil end
    local results = MySQL.query.await('SELECT * FROM mdt_citations WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    for _, c in ipairs(results) do c.charges = Decode(c.charges) end
    return results
end)

-- Recent arrests (default load when tab opens — no search required)
lib.callback.register('XS-MDT:server:getRecentArrests', function(source)
    if not HasPanel(source, 'arrests') then return nil end
    local results = MySQL.query.await([[
        SELECT a.*, COALESCE(CONCAT(c.firstname,' ',c.lastname), a.citizenid) as civilian_name
        FROM mdt_arrests a
        LEFT JOIN mdt_civilians c ON c.citizenid = a.citizenid
        ORDER BY a.created_at DESC LIMIT 25
    ]], {})
    for _, a in ipairs(results) do
        a.charges = Decode(a.charges)
    end
    return results
end)

-- Unified search for arrests: civilian name/ID + officer name + date range
lib.callback.register('XS-MDT:server:searchArrests', function(source, data)
    if not HasPanel(source, 'arrests') then return nil end
    data = data or {}
    local where, params = {}, {}

    if data.query and #data.query >= 2 then
        local like = '%' .. data.query .. '%'
        where[#where+1] = "(CONCAT(COALESCE(c.firstname,''),' ',COALESCE(c.lastname,'')) LIKE ? OR a.citizenid LIKE ?)"
        params[#params+1] = like; params[#params+1] = like
    end
    if data.officer and #data.officer >= 2 then
        where[#where+1] = 'a.officer_name LIKE ?'
        params[#params+1] = '%' .. data.officer .. '%'
    end
    if data.dateFrom and #data.dateFrom > 0 then
        where[#where+1] = 'DATE(a.created_at) >= ?'
        params[#params+1] = data.dateFrom
    end
    if data.dateTo and #data.dateTo > 0 then
        where[#where+1] = 'DATE(a.created_at) <= ?'
        params[#params+1] = data.dateTo
    end

    local sql = [[
        SELECT a.*, COALESCE(CONCAT(c.firstname,' ',c.lastname), a.citizenid) as civilian_name
        FROM mdt_arrests a LEFT JOIN mdt_civilians c ON c.citizenid = a.citizenid
    ]]
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY a.created_at DESC LIMIT 100'

    local results = MySQL.query.await(sql, params)
    for _, a in ipairs(results) do a.charges = Decode(a.charges) end
    return results
end)

-- Legacy alias kept for backward compat
lib.callback.register('XS-MDT:server:getArrestsByName', function(source, query)
    if not HasPanel(source, 'arrests') then return nil end
    if not query or #query < 2 then return {} end
    local like = '%'..query..'%'
    local results = MySQL.query.await([[
        SELECT a.*, COALESCE(CONCAT(c.firstname,' ',c.lastname), a.citizenid) as civilian_name
        FROM mdt_arrests a LEFT JOIN mdt_civilians c ON c.citizenid = a.citizenid
        WHERE CONCAT(COALESCE(c.firstname,''),' ',COALESCE(c.lastname,'')) LIKE ? OR a.citizenid LIKE ?
        ORDER BY a.created_at DESC LIMIT 50
    ]], { like, like })
    for _, a in ipairs(results) do a.charges = Decode(a.charges) end
    return results
end)

-- Recent citations (default load)
lib.callback.register('XS-MDT:server:getRecentCitations', function(source)
    if not HasPanel(source, 'citations') then return nil end
    local results = MySQL.query.await([[
        SELECT ci.*, COALESCE(CONCAT(c.firstname,' ',c.lastname), ci.citizenid) as civilian_name
        FROM mdt_citations ci
        LEFT JOIN mdt_civilians c ON c.citizenid = ci.citizenid
        ORDER BY ci.created_at DESC LIMIT 25
    ]], {})
    for _, ci in ipairs(results) do
        ci.charges = Decode(ci.charges)
    end
    return results
end)

-- Unified search for citations: civilian name/ID + officer name + date range
lib.callback.register('XS-MDT:server:searchCitations', function(source, data)
    if not HasPanel(source, 'citations') then return nil end
    data = data or {}
    local where, params = {}, {}

    if data.query and #data.query >= 2 then
        local like = '%' .. data.query .. '%'
        where[#where+1] = "(CONCAT(COALESCE(c.firstname,''),' ',COALESCE(c.lastname,'')) LIKE ? OR ci.citizenid LIKE ?)"
        params[#params+1] = like; params[#params+1] = like
    end
    if data.officer and #data.officer >= 2 then
        where[#where+1] = 'ci.officer_name LIKE ?'
        params[#params+1] = '%' .. data.officer .. '%'
    end
    if data.dateFrom and #data.dateFrom > 0 then
        where[#where+1] = 'DATE(ci.created_at) >= ?'
        params[#params+1] = data.dateFrom
    end
    if data.dateTo and #data.dateTo > 0 then
        where[#where+1] = 'DATE(ci.created_at) <= ?'
        params[#params+1] = data.dateTo
    end

    local sql = [[
        SELECT ci.*, COALESCE(CONCAT(c.firstname,' ',c.lastname), ci.citizenid) as civilian_name
        FROM mdt_citations ci LEFT JOIN mdt_civilians c ON c.citizenid = ci.citizenid
    ]]
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY ci.created_at DESC LIMIT 100'

    local results = MySQL.query.await(sql, params)
    for _, ci in ipairs(results) do ci.charges = Decode(ci.charges) end
    return results
end)

-- Legacy alias
lib.callback.register('XS-MDT:server:getCitationsByName', function(source, query)
    if not HasPanel(source, 'citations') then return nil end
    if not query or #query < 2 then return {} end
    local like = '%'..query..'%'
    local results = MySQL.query.await([[
        SELECT ci.*, COALESCE(CONCAT(c.firstname,' ',c.lastname), ci.citizenid) as civilian_name
        FROM mdt_citations ci LEFT JOIN mdt_civilians c ON c.citizenid = ci.citizenid
        WHERE CONCAT(COALESCE(c.firstname,''),' ',COALESCE(c.lastname,'')) LIKE ? OR ci.citizenid LIKE ?
        ORDER BY ci.created_at DESC LIMIT 50
    ]], { like, like })
    for _, ci in ipairs(results) do ci.charges = Decode(ci.charges) end
    return results
end)

-- ─── Record Tags ───────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:updateRecordTags', function(source, data)
    if not HasPanel(source, 'arrests') then return false end
    if not data or not data.type or not data.id or not data.tags then return false end
    local tableMap = { arrest = 'mdt_arrests', citation = 'mdt_citations', incident = 'mdt_incidents' }
    local tbl = tableMap[data.type]
    if not tbl then return false end
    MySQL.update.await('UPDATE `' .. tbl .. '` SET tags = ? WHERE id = ?', { json.encode(data.tags), data.id })
    return true
end)

-- ─── Fetch records by ID lists (for incident linked records display) ──────────

lib.callback.register('XS-MDT:server:getRecordsByIds', function(source, data)
    if not HasPanel(source, 'arrests') and not HasPanel(source, 'incidents') then return nil end
    local result = { arrests = {}, citations = {} }
    if type(data) ~= 'table' then return result end

    if type(data.arrests) == 'table' and #data.arrests > 0 then
        local rows = MySQL.query.await([[
            SELECT a.id, a.citizenid, a.officer_name, a.charges, a.fine, a.jail_time, a.created_at,
                   COALESCE(CONCAT(c.firstname, ' ', c.lastname), a.citizenid) AS civilian_name
            FROM mdt_arrests a LEFT JOIN mdt_civilians c ON c.citizenid = a.citizenid
            WHERE a.id IN (?)
        ]], { data.arrests })
        for _, a in ipairs(rows or {}) do a.charges = Decode(a.charges) end
        result.arrests = rows or {}
    end

    if type(data.citations) == 'table' and #data.citations > 0 then
        local rows = MySQL.query.await([[
            SELECT ci.id, ci.citizenid, ci.officer_name, ci.charges, ci.fine, ci.paid, ci.created_at,
                   COALESCE(CONCAT(c.firstname, ' ', c.lastname), ci.citizenid) AS civilian_name
            FROM mdt_citations ci LEFT JOIN mdt_civilians c ON c.citizenid = ci.citizenid
            WHERE ci.id IN (?)
        ]], { data.citations })
        for _, c in ipairs(rows or {}) do c.charges = Decode(c.charges) end
        result.citations = rows or {}
    end

    return result
end)

-- ─── Citations (mark paid) ──────────────────────────────────────────────────

-- Mark a citation as paid and optionally deduct the fine from the civilian's bank
lib.callback.register('XS-MDT:server:markCitationPaid', function(source, citationId)
    if not HasPanel(source, 'citations') then return false end
    local officer = GetOfficer(source)
    local citation = MySQL.single.await('SELECT citizenid, fine FROM mdt_citations WHERE id = ? AND paid = 0', { citationId })
    if not citation then return false end

    MySQL.update.await('UPDATE mdt_citations SET paid = 1 WHERE id = ?', { citationId })

    if Config.FineDeduction.AutoDeductOnMarkPaid and citation.fine and citation.fine > 0 then
        local target = OnlineSource(citation.citizenid)
        if target then _fineHandler(target, citation.fine, 'XS-MDT-citation-paid') end
    end

    exports['XS-MDT']:AuditLog('Citation Paid', officer.name, 'Citation #' .. citationId .. ' marked as paid')
    return true
end)
