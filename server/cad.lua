local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local activeCalls = {} -- in-memory cache for live calls

local function UsesExternalDispatch()
    return MdtDispatchBridge.IsExternal()
end

local function ExternalCall(call)
    local units = {}
    for _, unit in pairs(call.units or {}) do units[#units + 1] = unit end
    return {
        id = call.id, call_number = call.id, call_type = call.title or call.type,
        type = call.type, description = call.description, location = call.street,
        coords = call.coords, priority = call.priority, units = units, notes = call.notes or {},
        status = call.status == 'active' and 'active' or call.status,
        caller_name = call.caller, created_by_name = call.caller,
        created_at = os.date('!%Y-%m-%dT%H:%M:%SZ', call.createdAt or os.time()),
        operation = call.operation, external = true,
    }
end

AddEventHandler('XS-Dispatch:provider:mdt:callCreated', function(call)
    if not UsesExternalDispatch() then return end
    TriggerClientEvent('XS-MDT:client:newCall', -1, ExternalCall(call))
end)

AddEventHandler('XS-Dispatch:provider:mdt:callClosed', function(call)
    if not UsesExternalDispatch() then return end
    TriggerClientEvent('XS-MDT:client:callClosed', -1, call.id)
end)

AddEventHandler('XS-Dispatch:provider:mdt:callUpdated', function(call)
    if not UsesExternalDispatch() then return end
    TriggerClientEvent('XS-MDT:client:callUpdated', -1, ExternalCall(call))
end)

-- Generate a unique call number: e.g. CAD-20240615-001
local function GenerateCallNumber()
    local date  = os.date('%Y%m%d')
    local count = MySQL.scalar.await(
        "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
    return string.format('CAD-%s-%03d', date, count)
end

lib.callback.register('XS-MDT:server:getActiveCalls', function(source)
    if not HasPanel(source, 'cad') then return nil end
    if UsesExternalDispatch() then
        local result = {}
        local calls = MdtDispatchBridge.Call('getActiveCalls')
        for _, call in pairs(type(calls) == 'table' and calls or {}) do
            if call.status == 'active' then result[#result + 1] = ExternalCall(call) end
        end
        table.sort(result, function(a, b) return a.created_at > b.created_at end)
        return result
    end
    local calls = MySQL.query.await([[
        SELECT * FROM mdt_cad_calls
        WHERE status NOT IN ('completed', 'cancelled')
        ORDER BY created_at DESC
    ]], {})
    for _, c in ipairs(calls) do
        c.units = c.units and json.decode(c.units) or {}
        c.notes = c.notes and json.decode(c.notes) or {}
        c.coords = c.coords and json.decode(c.coords) or nil
    end
    return calls
end)

lib.callback.register('XS-MDT:server:createCall', function(source, data)
    if not HasPanel(source, 'cad') then return false end
    if UsesExternalDispatch() then
        local coords = data.coords or GetEntityCoords(GetPlayerPed(source))
        local id, call = MdtDispatchBridge.Call('createCall', source, { type = 'custom', title = data.type, description = data.description, street = data.location, coords = coords, priority = data.priority, caller = GetPlayerName(source) })
        return call and ExternalCall(call) or false
    end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not data.type or not data.description or not data.location then return false end

    local callNumber = GenerateCallNumber()
    local priority = math.max(1, math.min(3, tonumber(data.priority) or 2))
    local id = MySQL.insert.await([[
        INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, units, caller_id, caller_name, status, priority)
        VALUES (?, ?, ?, ?, ?, '[]', ?, ?, 'pending', ?)
    ]], {
        callNumber, data.type, data.description, data.location,
        data.coords and json.encode(data.coords) or nil,
        officer.citizenid, officer.name, priority
    })

    local call = {
        id = id,
        call_number = callNumber,
        call_type = data.type,
        type = data.type,
        description = data.description,
        location = data.location,
        coords = data.coords,
        priority = priority,
        units = {},
        notes = {},
        status = 'pending',
        caller_id = officer.citizenid,
        caller_name = officer.name,
        created_at = os.date('%Y-%m-%d %H:%M:%S'),
    }
    activeCalls[id] = call

    -- Push new call to all on-duty officers
    TriggerClientEvent('XS-MDT:client:newCall', -1, call)
    exports['XS-MDT']:AuditLog('CAD Call Created', officer.name, callNumber .. ': ' .. data.type .. ' @ ' .. data.location)
    return call
end)

lib.callback.register('XS-MDT:server:respondToCall', function(source, callId)
    if not HasPanel(source, 'cad') then return false end
    if UsesExternalDispatch() then return MdtDispatchBridge.Call('respond', source, callId) end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)

    local call = MySQL.single.await('SELECT units FROM mdt_cad_calls WHERE id = ?', { callId })
    if not call then return false end

    local units = json.decode(call.units) or {}
    -- Check if officer already on this call
    for _, u in ipairs(units) do
        if u.citizenid == officer.citizenid then return true end
    end

    units[#units + 1] = {
        citizenid = officer.citizenid,
        name = officer.name,
        respondedAt = os.date('%H:%M'),
    }

    MySQL.update.await("UPDATE mdt_cad_calls SET units = ?, status = 'enroute' WHERE id = ? AND status = 'pending'", {
        json.encode(units), callId
    })
    MySQL.update.await('UPDATE mdt_cad_calls SET units = ? WHERE id = ?', { json.encode(units), callId })

    -- Notify all clients of unit update
    TriggerClientEvent('XS-MDT:client:callUpdated', -1, {
        id = callId,
        units = units,
        status = 'enroute',
    })
    exports['XS-MDT']:LogBodyCam(source, 'CALL_RESPONDED', 'Call ID: ' .. callId)
    return true
end)

lib.callback.register('XS-MDT:server:updateCallStatus', function(source, data)
    if not HasPanel(source, 'cad') then return false end
    if UsesExternalDispatch() then return MdtDispatchBridge.Call('setCallStatus', source, data.callId, data.status) end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)

    MySQL.update.await('UPDATE mdt_cad_calls SET status = ?, updated_at = NOW() WHERE id = ?', {
        data.status, data.callId
    })

    TriggerClientEvent('XS-MDT:client:callUpdated', -1, {
        id = data.callId,
        status = data.status,
    })

    if data.status == 'completed' or data.status == 'cancelled' then
        TriggerClientEvent('XS-MDT:client:callClosed', -1, data.callId)
        activeCalls[data.callId] = nil
    end

    exports['XS-MDT']:AuditLog('Call Status Updated', officer.name, 'Call #' .. data.callId .. ' → ' .. data.status)
    return true
end)

lib.callback.register('XS-MDT:server:addCallNote', function(source, data)
    if not HasPanel(source, 'cad') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if UsesExternalDispatch() then return MdtDispatchBridge.Call('addCallNote', source, data.callId, { author = officer.name, text = data.text }) end

    local call = MySQL.single.await('SELECT notes FROM mdt_cad_calls WHERE id = ?', { data.callId })
    if not call then return false end

    local notes = call.notes and json.decode(call.notes) or {}
    notes[#notes + 1] = {
        author = officer.name,
        text = data.text,
        time = os.date('%H:%M'),
    }

    MySQL.update.await('UPDATE mdt_cad_calls SET notes = ? WHERE id = ?', { json.encode(notes), data.callId })
    TriggerClientEvent('XS-MDT:client:callNoteAdded', -1, { callId = data.callId, notes = notes })
    return true
end)

-- Quick Dispatch: mark officer as responding to a call
RegisterNetEvent('XS-MDT:server:respondToCall')
AddEventHandler('XS-MDT:server:respondToCall', function(data)
    local src = source
    if not HasPanel(src, 'cad') then return end
    if UsesExternalDispatch() then
        MdtDispatchBridge.Call('respond', src, data and data.callId)
        return
    end
    local officer = exports['XS-MDT']:GetOfficerInfo(src)
    if not officer or not data.callId then return end

    local call = MySQL.single.await('SELECT units FROM mdt_cad_calls WHERE id = ?', { data.callId })
    if not call then return end

    local units = call.units and json.decode(call.units) or {}

    -- Add officer if not already on this call
    local already = false
    for _, u in ipairs(units) do
        if u.citizenid == officer.citizenid then already = true break end
    end
    if not already then
        units[#units+1] = {
            citizenid  = officer.citizenid,
            name       = officer.name,
            status     = 'enroute',
        }
        MySQL.update.await('UPDATE mdt_cad_calls SET units = ?, status = IF(status = "pending","active",status) WHERE id = ?', {
            json.encode(units), data.callId
        })
    end

    -- Broadcast updated units list to all officers with MDT open
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        if Config.AuthorizedJobs[p.PlayerData.job.name] then
            TriggerClientEvent('XS-MDT:client:callUpdated', psrc, { id = data.callId, units = units })
        end
    end

    exports['XS-MDT']:AuditLog('RESPOND_TO_CALL', officer.name, 'Call ID: ' .. data.callId)
end)

-- Pull historical calls (last 50 completed)
lib.callback.register('XS-MDT:server:getCallHistory', function(source)
    if not HasPanel(source, 'callhistory') then return nil end
    local calls = MySQL.query.await([[
        SELECT * FROM mdt_cad_calls
        WHERE status IN ('completed', 'cancelled')
        ORDER BY updated_at DESC LIMIT 50
    ]], {})
    for _, c in ipairs(calls) do
        c.units = c.units and json.decode(c.units) or {}
        c.notes = c.notes and json.decode(c.notes) or {}
    end
    return calls
end)

-- Searchable callout history (all statuses, with filters)
lib.callback.register('XS-MDT:server:searchCallHistory', function(source, data)
    if not HasPanel(source, 'callhistory') then return nil end
    data = data or {}
    local where, params = {}, {}

    if data.callType and #data.callType >= 2 then
        where[#where+1] = 'call_type LIKE ?'
        params[#params+1] = '%' .. data.callType .. '%'
    end
    if data.unit and #data.unit >= 2 then
        where[#where+1] = 'JSON_SEARCH(LOWER(units), "one", LOWER(?)) IS NOT NULL'
        params[#params+1] = '%' .. data.unit .. '%'
    end
    if data.status and #data.status > 0 then
        where[#where+1] = 'status = ?'
        params[#params+1] = data.status
    end
    if data.dateFrom and #data.dateFrom > 0 then
        where[#where+1] = 'DATE(created_at) >= ?'
        params[#params+1] = data.dateFrom
    end
    if data.dateTo and #data.dateTo > 0 then
        where[#where+1] = 'DATE(created_at) <= ?'
        params[#params+1] = data.dateTo
    end

    local sql = 'SELECT id, call_number, call_type, description, location, status, caller_name, priority, created_at, updated_at FROM mdt_cad_calls'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY created_at DESC LIMIT 100'

    return MySQL.query.await(sql, params)
end)
