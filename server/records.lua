local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

-- Fine deduction handler — replaceable via exports
local _fineHandler = function(targetSrc, amount, reason)
    if not Config.FineDeduction.Enabled then return end
    local target = exports['qbx_core']:GetPlayer(targetSrc)
    if target then
        target.Functions.RemoveMoney('bank', amount, reason)
    end
end

-- Allow other resources to override the deduction logic (e.g. custom economy)
exports('SetFineHandler', function(fn) _fineHandler = fn end)
exports('DeductFine', function(targetSrc, amount, reason) _fineHandler(targetSrc, amount, reason) end)

-- ─── Arrests ───────────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:logArrest', function(source, data)
    if not HasPanel(source, 'arrests') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not data.citizenid or not data.charges or #data.charges == 0 then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_arrests (citizenid, officer_citizenid, officer_name, charges, fine, jail_time, narrative, location)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.citizenid, officer.citizenid, officer.name,
        json.encode(data.charges), data.fine or 0, data.jailTime or 0,
        data.narrative, data.location
    })

    -- Clear any active warrants for this civilian automatically
    if data.clearWarrants then
        MySQL.update.await("UPDATE mdt_warrants SET status = 'cleared', cleared_by = ?, cleared_at = NOW() WHERE citizenid = ? AND status = 'active'", {
            officer.citizenid, data.citizenid
        })
    end

    -- Jail time trigger
    if data.targetSource and data.jailTime and data.jailTime > 0 then
        local jailResource = Config.JailResource
        if jailResource == 'qb-prison' then
            TriggerEvent('qb-prison:server:sendToJail', data.targetSource, data.jailTime)
        elseif jailResource == 'ps-prison' then
            TriggerEvent('prison:server:SendToJail', data.targetSource, data.jailTime)
        else
            TriggerClientEvent('XS-MDT:client:jailPlayer', data.targetSource, data.jailTime)
        end
    end
    -- Fine deduction
    if data.targetSource and data.fine and data.fine > 0 and Config.FineDeduction.AutoDeductArrests then
        _fineHandler(data.targetSource, data.fine, 'XS-MDT-arrest')
    end

    exports['XS-MDT']:AuditLog('Arrest Logged', officer.name, 'Arrest ID: ' .. id .. ' | Citizenid: ' .. data.citizenid)
    exports['XS-MDT']:LogBodyCam(source, 'ARREST_LOGGED',
        'Subject: ' .. data.citizenid .. ' | Charges: ' .. #data.charges .. ' | Fine: $' .. (data.fine or 0) .. ' | Jail: ' .. (data.jailTime or 0) .. 'min')
    return id
end)

lib.callback.register('XS-MDT:server:getArrests', function(source, citizenid)
    if not HasPanel(source, 'arrests') then return nil end
    local results = MySQL.query.await('SELECT * FROM mdt_arrests WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    for _, a in ipairs(results) do a.charges = json.decode(a.charges) end
    return results
end)

-- ─── Citations ─────────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:issueCitation', function(source, data)
    if not HasPanel(source, 'citations') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not data.citizenid or not data.charges or #data.charges == 0 then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_citations (citizenid, officer_citizenid, officer_name, charges, fine, location, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.citizenid, officer.citizenid, officer.name,
        json.encode(data.charges), data.fine or 0, data.location, data.notes
    })

    -- Fine deduction on immediate cite
    if data.targetSource and data.fine and data.fine > 0 and Config.FineDeduction.AutoDeductCitations then
        _fineHandler(data.targetSource, data.fine, 'XS-MDT-citation')
    end

    exports['XS-MDT']:AuditLog('Citation Issued', officer.name, 'Citation ID: ' .. id .. ' | Fine: $' .. (data.fine or 0))
    exports['XS-MDT']:LogBodyCam(source, 'CITATION_ISSUED',
        'Subject: ' .. data.citizenid .. ' | Fine: $' .. (data.fine or 0) .. ' | Charges: ' .. #data.charges)
    return id
end)

lib.callback.register('XS-MDT:server:getCitations', function(source, citizenid)
    if not HasPanel(source, 'citations') then return nil end
    local results = MySQL.query.await('SELECT * FROM mdt_citations WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    for _, c in ipairs(results) do c.charges = json.decode(c.charges) end
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
        if a.charges then a.charges = json.decode(a.charges) end
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
    for _, a in ipairs(results) do if a.charges then a.charges = json.decode(a.charges) end end
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
    for _, a in ipairs(results) do if a.charges then a.charges = json.decode(a.charges) end end
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
        if ci.charges then ci.charges = json.decode(ci.charges) end
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
    for _, ci in ipairs(results) do if ci.charges then ci.charges = json.decode(ci.charges) end end
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
    for _, ci in ipairs(results) do if ci.charges then ci.charges = json.decode(ci.charges) end end
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
    if not HasPanel(source, 'arrests') then return nil end
    local result = { arrests = {}, citations = {} }

    if data.arrests and #data.arrests > 0 then
        local ph = string.rep('?,', #data.arrests):sub(1, -2)
        local rows = MySQL.query.await(
            'SELECT id, citizenid, officer_name, charges, fine, jail_time, created_at FROM mdt_arrests WHERE id IN (' .. ph .. ')',
            data.arrests
        )
        for _, a in ipairs(rows) do if a.charges then a.charges = json.decode(a.charges) end end
        result.arrests = rows
    end

    if data.citations and #data.citations > 0 then
        local ph = string.rep('?,', #data.citations):sub(1, -2)
        local rows = MySQL.query.await(
            'SELECT id, citizenid, officer_name, charges, fine, paid, created_at FROM mdt_citations WHERE id IN (' .. ph .. ')',
            data.citations
        )
        for _, c in ipairs(rows) do if c.charges then c.charges = json.decode(c.charges) end end
        result.citations = rows
    end

    return result
end)

-- ─── Citations (mark paid) ──────────────────────────────────────────────────

-- Mark a citation as paid and optionally deduct the fine from the civilian's bank
lib.callback.register('XS-MDT:server:markCitationPaid', function(source, citationId)
    if not HasPanel(source, 'citations') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    local citation = MySQL.single.await('SELECT citizenid, fine FROM mdt_citations WHERE id = ? AND paid = 0', { citationId })
    if not citation then return false end

    MySQL.update.await('UPDATE mdt_citations SET paid = 1 WHERE id = ?', { citationId })

    -- Deduct from bank if target civilian is online
    if Config.FineDeduction.AutoDeductOnMarkPaid and citation.fine and citation.fine > 0 then
        local players = exports['qbx_core']:GetQBPlayers()
        for src, player in pairs(players) do
            if player.PlayerData.citizenid == citation.citizenid then
                _fineHandler(src, citation.fine, 'XS-MDT-citation-paid')
                break
            end
        end
    end

    exports['XS-MDT']:AuditLog('Citation Paid', officer.name, 'Citation #' .. citationId .. ' marked as paid')
    return true
end)
