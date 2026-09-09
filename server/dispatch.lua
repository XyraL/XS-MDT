local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
-- XSMDT Server Dispatch — receives auto-dispatch events and creates CAD calls
if Config.DisableInternalDispatchDetection then return end

-- ── Suppression & Filter Registry ────────────────────────────────────────
-- _suppressed[callType] = true  → globally blocked
-- _filters[callType]    = fn(data, src) → return false to block this specific event
local _suppressed = {}
local _filters    = {}

--[[
    SuppressDispatch(callType, suppressed)
    Globally enable or disable a dispatch call type server-wide.

    Example — suppress shots fired (e.g. during a paintball event):
        exports['XS-MDT']:SuppressDispatch('SHOTS_FIRED', true)

    Re-enable it when the event ends:
        exports['XS-MDT']:SuppressDispatch('SHOTS_FIRED', false)

    Pass nil as callType to suppress ALL auto-dispatch:
        exports['XS-MDT']:SuppressDispatch(nil, true)
]]
exports('SuppressDispatch', function(callType, suppressed)
    if callType == nil then
        -- Suppress/unsuppress every type at once
        _suppressed['__all__'] = suppressed == true
    else
        _suppressed[callType] = suppressed == true
    end
end)

--[[
    RegisterDispatchFilter(callType, fn)
    Register a conditional filter for a specific call type.
    fn receives (data, src) and must return true to ALLOW the call through,
    or false/nil to block it.

    Multiple filters can be registered per callType; ALL must pass.

    Example — only allow SHOTS_FIRED outside a specific zone:
        exports['XS-MDT']:RegisterDispatchFilter('SHOTS_FIRED', function(data, src)
            local coords = data.coords
            local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(200.0, -900.0, 30.0))
            return dist > 100.0  -- block if within 100u of paintball arena center
        end)
]]
exports('RegisterDispatchFilter', function(callType, fn)
    if type(fn) ~= 'function' then return end
    _filters[callType] = _filters[callType] or {}
    table.insert(_filters[callType], fn)
end)

-- Remove all filters for a call type (e.g. when paintball resource stops)
exports('ClearDispatchFilters', function(callType)
    _filters[callType] = nil
end)

local function IsAllowed(callType, data, src)
    if _suppressed['__all__'] then return false end
    if _suppressed[callType]  then return false end
    local fns = _filters[callType]
    if fns then
        for _, fn in ipairs(fns) do
            local ok, result = pcall(fn, data, src)
            if not ok or result == false then return false end
        end
    end
    return true
end

--[[
    CreateDispatchCall(data) — Server Export
    Create a CAD dispatch call directly from any other server-side resource.
    No client event needed. Bypasses suppression/filters (it's an intentional call).

    Required fields:
        callType    (string)  — e.g. 'ROBBERY', 'SHOOTING', 'PURSUIT'
        description (string)  — human-readable description shown in CAD
        coords      (table)   — { x, y, z }

    Optional fields:
        street      (string)  — street name (auto-generated from coords if omitted)
        callerName  (string)  — displayed as caller in CAD (defaults to 'Dispatch')
        icon        (string)  — emoji shown on alert notification

    Returns: callId (number) or nil on failure

    Example — from a robbery resource:
        local callId = exports['XS-MDT']:CreateDispatchCall({
            callType    = 'STORE_ROBBERY',
            description = 'Armed robbery at Discount Store.',
            coords      = { x = 24.8, y = -1347.3, z = 29.5 },
            street      = 'Olympic Freeway',
            callerName  = '911 Caller',
        })
]]
exports('CreateDispatchCall', function(data)
    if not data or not data.callType or not data.description or not data.coords then
        return nil
    end
    if MdtDispatchBridge.IsExternal() then
        local id = MdtDispatchBridge.Call('createCall', -1, {
            type=string.lower(data.callType), title=data.label or data.callType,
            description=data.description, coords=data.coords, street=data.street,
            caller=data.callerName or 'Dispatch', priority=data.priority,
        })
        return id
    end

    -- Check suppression (intentional calls still respect global suppression)
    if not IsAllowed(data.callType, data, -1) then return nil end

    local icon  = data.icon or CALL_ICONS[data.callType]  or '📡'
    local label = data.label or CALL_LABELS[data.callType] or data.callType

    local dateStr = os.date('%Y%m%d')
    local count = MySQL.scalar.await(
        "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
    local callNumber = string.format('CAD-%s-%03d', dateStr, count)

    local callId = MySQL.insert.await([[
        INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, status, caller_name, created_at)
        VALUES (?, ?, ?, ?, ?, 'active', ?, NOW())
    ]], {
        callNumber,
        label,
        data.description,
        data.street or 'Unknown Location',
        json.encode(data.coords),
        data.callerName or 'Dispatch',
    })

    if not callId then return nil end

    local callData = {
        id          = callId,
        call_number = callNumber,
        call_type   = label,
        icon        = icon,
        description = data.description,
        location    = data.street or 'Unknown Location',
        coords      = data.coords,
        status      = 'active',
        caller_name = data.callerName or 'Dispatch',
        units       = {},
        created_at  = os.date('%Y-%m-%dT%H:%M:%SZ'),
    }

    -- Only the departments Config.CallRouting assigns to this call type.
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        local job = p.PlayerData.job
        if Dept.ReceivesCall(job.name, data.callType) and (not Config.OnDutyOnly or job.onduty) then
            TriggerClientEvent('XS-MDT:client:newCall', psrc, callData)
            TriggerClientEvent('XS-MDT:client:dispatchAlert', psrc, {
                icon        = icon,
                title       = label,
                description = data.description,
                location    = data.street or 'Unknown Location',
                coords      = data.coords,
                callNumber  = callNumber,
                callId      = callId,
            })
        end
    end

    return callId
end)

-- ── Call Type Config ──────────────────────────────────────────────────────
local CALL_ICONS = {
    SHOTS_FIRED  = '🔫',
    FIGHT        = '👊',
    VEHICLE_CRASH= '💥',
    ROBBERY      = '🏪',
    BANK_ROBBERY = '🏦',
    STORE_ROBBERY= '🏪',
    TRAFFIC_STOP = '🚦',
    MEDICAL      = '🚑',
    FIRE         = '🔥',
    SUSPICIOUS   = '👁',
    CUSTOM       = '📡',
}

local CALL_LABELS = {
    SHOTS_FIRED  = 'Shots Fired',
    FIGHT        = 'Fight / Assault',
    VEHICLE_CRASH= 'Vehicle Crash',
    ROBBERY      = 'Robbery in Progress',
    BANK_ROBBERY = 'Bank Robbery',
    STORE_ROBBERY= 'Store Robbery',
    TRAFFIC_STOP = 'Traffic Stop',
    MEDICAL      = 'Medical Emergency',
    FIRE         = 'Structure Fire',
    SUSPICIOUS   = 'Suspicious Activity',
    CUSTOM       = 'Dispatch Call',
}

-- Rate limit: don't spam identical calls from same player
local _recentCalls = {}

RegisterNetEvent('XS-MDT:server:autoDispatch')
AddEventHandler('XS-MDT:server:autoDispatch', function(data)
    local src = source
    if MdtDispatchBridge.IsExternal() then
        MdtDispatchBridge.Call('createCall', src, {
            type = data and string.lower(data.callType or 'custom') or 'custom',
            title = data and data.callType or 'Dispatch Call', description = data and data.description,
            street = data and data.street, coords = data and data.coords, caller = GetPlayerName(src),
        })
        return
    end
    local player = exports['qbx_core']:GetPlayer(src)
    if not player then return end

    local callType = data.callType or 'CUSTOM'

    -- Check suppression and filters before doing anything
    if not IsAllowed(callType, data, src) then return end

    local key = tostring(src) .. '_' .. callType

    if _recentCalls[key] and (os.time() - _recentCalls[key]) < 60 then return end
    _recentCalls[key] = os.time()

    local pd = player.PlayerData
    local callerName = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
    local icon  = CALL_ICONS[callType]  or '📡'
    local label = CALL_LABELS[callType] or 'Dispatch Call'

    -- Generate call number
    local dateStr = os.date('%Y%m%d')
    local count = MySQL.scalar.await(
        "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
    local callNumber = string.format('CAD-%s-%03d', dateStr, count)

    local callId = MySQL.insert.await([[
        INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, status, caller_name, caller_id, created_at)
        VALUES (?, ?, ?, ?, ?, 'active', ?, ?, NOW())
    ]], {
        callNumber,
        label,
        data.description or label,
        data.street or 'Unknown Location',
        json.encode(data.coords or {}),
        callerName,
        pd.citizenid,
    })

    if not callId then return end

    local callData = {
        id          = callId,
        call_number = callNumber,
        call_type   = label,
        icon        = icon,
        description = data.description or label,
        location    = data.street or 'Unknown Location',
        coords      = data.coords,
        status      = 'active',
        caller_name = callerName,
        units       = {},
        created_at  = os.date('%Y-%m-%dT%H:%M:%SZ'),
    }

    -- Broadcast to the departments this call type is routed to.
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        local job = p.PlayerData.job
        if Dept.ReceivesCall(job.name, callType) and (not Config.OnDutyOnly or job.onduty) then
            TriggerClientEvent('XS-MDT:client:newCall', psrc, callData)
            TriggerClientEvent('XS-MDT:client:dispatchAlert', psrc, {
                icon        = icon,
                title       = label,
                description = data.description or label,
                location    = data.street or 'Unknown Location',
                coords      = data.coords,
                callNumber  = callNumber,
                callId      = callId,
            })
        end
    end

    -- Audit log
    exports['XS-MDT']:AuditLog('AUTO_DISPATCH', callerName, label .. ' at ' .. (data.street or '?'))
end)

-- Manual dispatch from CAD panel
RegisterNetEvent('XS-MDT:server:manualDispatch')
AddEventHandler('XS-MDT:server:manualDispatch', function(data)
    local src = source
    if not exports['XS-MDT']:HasPanel(src, 'cad') then return end
    local officer = exports['XS-MDT']:GetOfficerInfo(src)
    if not officer then return end
    if MdtDispatchBridge.IsExternal() then
        MdtDispatchBridge.Call('createCall', src, {
            type='custom', title=data.callType or 'Dispatch Call', description=data.description or '',
            street=data.location or 'Unknown', coords=data.coords, caller=officer.name,
        })
        return
    end

    local dateStr = os.date('%Y%m%d')
    local count = MySQL.scalar.await(
        "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
    local callNumber = string.format('CAD-%s-%03d', dateStr, count)

    local callId = MySQL.insert.await([[
        INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, status, caller_name, caller_id, created_at)
        VALUES (?, ?, ?, ?, ?, 'active', ?, ?, NOW())
    ]], {
        callNumber,
        data.callType or 'Dispatch Call',
        data.description or '',
        data.location or 'Unknown',
        json.encode(data.coords or {}),
        officer.name,
        officer.citizenid,
    })

    if not callId then return end

    local callData = {
        id          = callId,
        call_number = callNumber,
        call_type   = data.callType or 'Dispatch Call',
        description = data.description or '',
        location    = data.location or 'Unknown',
        coords      = data.coords,
        status      = 'active',
        caller_name = officer.name,
        units       = {},
        created_at  = os.date('%Y-%m-%dT%H:%M:%SZ'),
    }

    -- Manually created calls carry a free-text type, so they route as CUSTOM.
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        local job = p.PlayerData.job
        if Dept.ReceivesCall(job.name, 'CUSTOM') and (not Config.OnDutyOnly or job.onduty) then
            TriggerClientEvent('XS-MDT:client:newCall', psrc, callData)
        end
    end
end)

-- Panic button handler
RegisterNetEvent('XS-MDT:server:panicButton')
AddEventHandler('XS-MDT:server:panicButton', function(data)
    local src    = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player then return end
    local pd = player.PlayerData
    if not Config.AuthorizedJobs[pd.job.name] then return end

    local name   = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
    local badge  = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { pd.citizenid }) or '???'
    local street = data.street or 'Unknown Location'
    if MdtDispatchBridge.IsExternal() then
        MdtDispatchBridge.Call('createCall', src, {
            type='officer_backup', title=name .. ' activated PANIC',
            description='OFFICER NEEDS ASSISTANCE — ' .. name .. ' (Badge #' .. badge .. ')',
            priority=1, street=street, coords=data, caller=name,
        })
        exports['XS-MDT']:AuditLog('PANIC BUTTON', name, 'Badge #' .. badge .. ' at ' .. street)
        exports['XS-MDT']:LogBodyCam(src, 'PANIC_BUTTON', 'Location: ' .. street)
        return
    end

    -- Create a priority CAD call
    local dateStr = os.date('%Y%m%d')
    local count   = MySQL.scalar.await(
        "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
    local callNumber = string.format('CAD-%s-%03d', dateStr, count)

    local callId = MySQL.insert.await([[
        INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, status, caller_name, caller_id, created_at)
        VALUES (?, 'PANIC', ?, ?, ?, 'active', ?, ?, NOW())
    ]], {
        callNumber,
        'OFFICER NEEDS ASSISTANCE — ' .. name .. ' (Badge #' .. badge .. ')',
        street,
        json.encode(data),
        name,
        pd.citizenid,
    })

    local callData = {
        id          = callId,
        call_number = callNumber,
        call_type   = 'OFFICER NEEDS ASSISTANCE',
        description = 'OFFICER NEEDS ASSISTANCE — ' .. name .. ' (Badge #' .. badge .. ')',
        location    = street,
        coords      = data,
        status      = 'active',
        caller_name = name,
        units       = {},
        created_at  = os.date('%Y-%m-%dT%H:%M:%SZ'),
    }

    -- Broadcast to ALL authorized players with high-priority alert
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        if Dept.ReceivesCall(p.PlayerData.job.name, nil) then   -- safety alert: all departments
            TriggerClientEvent('XS-MDT:client:panicAlert', psrc, {
                officerName = name,
                badge       = badge,
                location    = street,
                coords      = data,
                callNumber  = callNumber,
            })
            TriggerClientEvent('XS-MDT:client:newCall', psrc, callData)
        end
    end

    exports['XS-MDT']:AuditLog('PANIC BUTTON', name, 'Badge #' .. badge .. ' at ' .. street)
    exports['XS-MDT']:LogBodyCam(src, 'PANIC_BUTTON', 'Location: ' .. street)
end)

-- Backup request — lower urgency than panic, creates a BACKUP_REQUEST call
RegisterNetEvent('XS-MDT:server:backupRequest')
AddEventHandler('XS-MDT:server:backupRequest', function(data)
    local src    = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player then return end
    local pd = player.PlayerData
    if not Config.AuthorizedJobs[pd.job.name] then return end

    local name   = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
    local badge  = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { pd.citizenid }) or '???'
    local street = data.street or 'Unknown Location'
    if MdtDispatchBridge.IsExternal() then
        MdtDispatchBridge.Call('createCall', src, {
            type='officer_backup', title='Backup Requested — ' .. name,
            description='BACKUP REQUESTED — ' .. name .. ' (Badge #' .. badge .. ')',
            priority=2, street=street, coords=data, caller=name,
        })
        exports['XS-MDT']:AuditLog('BACKUP REQUEST', name, 'Badge #' .. badge .. ' at ' .. street)
        return
    end

    local dateStr = os.date('%Y%m%d')
    local count   = MySQL.scalar.await(
        "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
    local callNumber = string.format('CAD-%s-%03d', dateStr, count)

    local callId = MySQL.insert.await([[
        INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, status, caller_name, caller_id, created_at)
        VALUES (?, 'BACKUP_REQUEST', ?, ?, ?, 'active', ?, ?, NOW())
    ]], {
        callNumber,
        'BACKUP REQUESTED — ' .. name .. ' (Badge #' .. badge .. ')',
        street,
        json.encode(data),
        name,
        pd.citizenid,
    })

    local callData = {
        id          = callId,
        call_number = callNumber,
        call_type   = 'BACKUP REQUEST',
        icon        = '🆘',
        description = 'BACKUP REQUESTED — ' .. name .. ' (Badge #' .. badge .. ')',
        location    = street,
        coords      = data,
        status      = 'active',
        caller_name = name,
        units       = {},
        created_at  = os.date('%Y-%m-%dT%H:%M:%SZ'),
    }

    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        if Dept.ReceivesCall(p.PlayerData.job.name, nil) then   -- safety alert: all departments
            TriggerClientEvent('XS-MDT:client:newCall', psrc, callData)
            TriggerClientEvent('XS-MDT:client:dispatchAlert', psrc, {
                icon        = '🆘',
                title       = 'BACKUP REQUEST',
                description = 'BACKUP REQUESTED — ' .. name .. ' (Badge #' .. badge .. ')',
                location    = street,
                coords      = data,
                callNumber  = callNumber,
                callId      = callId,
            })
        end
    end

    exports['XS-MDT']:AuditLog('BACKUP REQUEST', name, 'Badge #' .. badge .. ' at ' .. street)
end)
