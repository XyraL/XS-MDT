local mdtOpen = false

-- Open the MDT NUI
local function OpenMDT()
    if mdtOpen then return end
    local officer = lib.callback.await('XS-MDT:server:open', false)
    if not officer then
        lib.notify({ title = 'XSMDT', description = 'Access Denied', type = 'error' })
        return
    end
    mdtOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', officer = officer })
    TriggerEvent('XS-MDT:client:mdtStateChanged', true)
    if Config.Sounds.Enabled then
        SendNUIMessage({ action = 'playSound', sound = 'open' })
    end
end

-- Close the MDT NUI
local function CloseMDT()
    if not mdtOpen then return end
    mdtOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerEvent('XS-MDT:client:mdtStateChanged', false)
    if Config.Sounds.Enabled then
        SendNUIMessage({ action = 'playSound', sound = 'close' })
    end
end

-- Register keybind
RegisterKeyMapping('xs_mdt_open', 'Open XSMDT', 'keyboard', Config.OpenKey)
RegisterCommand('xs_mdt_open', function()
    if mdtOpen then CloseMDT() else OpenMDT() end
end, false)

-- Panic button — broadcasts priority alert with officer location to all units
RegisterKeyMapping('xs_mdt_panic', 'XSMDT: Panic Button', 'keyboard', 'F11')
RegisterCommand('xs_mdt_panic', function()
    local pd = exports['qbx_core']:GetPlayerData()
    if not pd or not Config.AuthorizedJobs[pd.job.name] then return end
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, _ = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    TriggerServerEvent('XS-MDT:server:panicButton', {
        x = coords.x, y = coords.y, z = coords.z,
        street = street,
    })
    -- Flash screen red briefly
    StartScreenEffect('RampQuickSepia', 0, false)
    Wait(400)
    StopScreenEffect('RampQuickSepia')
end, false)

-- Auto-close MDT on death
CreateThread(function()
    while true do
        Wait(2000)
        if mdtOpen and IsEntityDead(PlayerPedId()) then
            CloseMDT()
        end
    end
end)

-- Auto-close MDT when going off-duty (if OnDutyOnly is enabled)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    if Config.OnDutyOnly and not job.onduty and mdtOpen then
        CloseMDT()
        lib.notify({ title = 'XSMDT', description = 'MDT closed — you went off duty.', type = 'inform' })
    end
    -- Tell server to drop this unit's blip position if off-duty
    if not job.onduty then
        TriggerServerEvent('XS-MDT:server:clearPosition')
    end
end)

-- NUI close callback
RegisterNUICallback('close', function(_, cb)
    CloseMDT()
    cb('ok')
end)

-- Map click / "Route" button → drop a GPS waypoint at that world position.
RegisterNUICallback('setWaypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then
        SetNewWaypoint(x + 0.0, y + 0.0)
    end
    cb({ ok = x ~= nil and y ~= nil })
end)

-- Forward all data requests from NUI to server callbacks.
--
-- `false` is passed straight through instead of being folded into `{}`.
--
-- It used to send `result or {}`, and an empty object is truthy in JS, so every
-- `if (result)` in the panel read a refusal as a success. A denied action gave
-- a green toast; creating a CAD call you had no permission for reported
-- "undefined dispatched".
--
-- nil still becomes `{}` — plenty of callbacks return nothing on purpose and
-- the panel expects an object from those.
RegisterNUICallback('request', function(data, cb)
    local result = lib.callback.await('XS-MDT:server:' .. data.endpoint, false, data.payload)

    if result == false then
        cb(false)
    else
        cb(result or {})
    end
end)

-- Alert: warrant issued
RegisterNetEvent('XS-MDT:client:warrantAlert', function(data)
    lib.notify({
        title = 'WARRANT ISSUED',
        description = string.format('%s — %d charge(s) | By: %s', data.subject, #data.charges, data.issuedBy),
        type = 'error',
        duration = 8000,
    })
    if mdtOpen then
        SendNUIMessage({ action = 'warrantAlert', data = data })
    end
end)

-- Alert: BOLO issued or cleared
RegisterNetEvent('XS-MDT:client:boloAlert', function(data)
    lib.notify({
        title = 'BOLO — ' .. (data.type == 'vehicle' and 'VEHICLE' or 'PERSON'),
        description = data.description .. (data.plate and (' | Plate: ' .. data.plate) or '') .. ' | By: ' .. data.issuedBy,
        type = 'warning',
        duration = 10000,
    })
    if mdtOpen then
        SendNUIMessage({ action = 'boloAlert', data = data })
    end
end)

RegisterNetEvent('XS-MDT:client:boloCleared', function(boloId)
    if mdtOpen then
        SendNUIMessage({ action = 'boloCleared', id = boloId })
    end
end)

-- Alert: new CAD call
RegisterNetEvent('XS-MDT:client:newCall', function(call)
    lib.notify({
        title = '📡 NEW CALL — ' .. call.call_number,
        description = (call.call_type or call.type or 'Unknown') .. ' @ ' .. (call.location or ''),
        type = 'inform',
        duration = 10000,
    })
    if mdtOpen then
        SendNUIMessage({ action = 'newCall', call = call })
    end
end)

RegisterNetEvent('XS-MDT:client:callUpdated', function(data)
    if mdtOpen then
        SendNUIMessage({ action = 'callUpdated', data = data })
    end
end)

RegisterNetEvent('XS-MDT:client:callClosed', function(callId)
    if mdtOpen then
        SendNUIMessage({ action = 'callClosed', id = callId })
    end
end)

RegisterNetEvent('XS-MDT:client:callNoteAdded', function(data)
    if mdtOpen then
        SendNUIMessage({ action = 'callNoteAdded', data = data })
    end
end)

-- Panic alert received (high-priority in-game + NUI notification)
RegisterNetEvent('XS-MDT:client:panicAlert', function(data)
    lib.notify({
        title       = '🚨 OFFICER NEEDS ASSISTANCE',
        description = data.officerName .. ' (Badge #' .. data.badge .. ')\n📍 ' .. data.location,
        type        = 'error',
        duration    = 20000,
        position    = 'top',
    })
    SendNUIMessage({ action = 'panicAlert', data = data })
    -- NUI sound (plays regardless of MDT open state via postMessage)
    if Config.Sounds.Enabled then
        SendNUIMessage({ action = 'playSound', sound = 'panic' })
    end
end)

-- Auto-dispatch alert (shown to all on-duty officers in-game)
RegisterNetEvent('XS-MDT:client:dispatchAlert', function(data)
    lib.notify({
        title = data.icon .. ' DISPATCH — ' .. data.title,
        description = data.description .. '\n📍 ' .. data.location,
        type = 'error',
        duration = 12000,
        position = 'top-right',
    })
    if mdtOpen then
        SendNUIMessage({ action = 'newCall', call = {
            id          = data.callId,
            call_number = data.callNumber,
            call_type   = data.title,
            description = data.description,
            location    = data.location,
            coords      = data.coords,
            status      = 'active',
        }})
    end
end)

-- Jail player event (triggered by server after arrest)
RegisterNetEvent('XS-MDT:client:jailPlayer', function(minutes)
    -- Hook into your server's jail system here
    -- Example: TriggerEvent('your-jail-resource:jail', minutes)
    print('[XSMDT] Jail trigger: ' .. minutes .. ' minutes')
end)

-- ── Quick Dispatch Responder ──────────────────────────────────────────────
local qdOpen = false

local function OpenQuickDispatch()
    if mdtOpen or qdOpen then return end
    local pd = exports['qbx_core']:GetPlayerData()
    if not pd or not Config.AuthorizedJobs[pd.job.name] then return end
    if Config.OnDutyOnly and not pd.job.onduty then return end

    local calls = lib.callback.await('XS-MDT:server:getActiveCalls', false)
    if not calls or #calls == 0 then
        lib.notify({ title = 'Quick Dispatch', description = 'No active calls.', type = 'inform', duration = 3000 })
        return
    end

    qdOpen = true
    SetNuiFocus(true, false)  -- cursor only, no keyboard capture (we handle keys in JS)
    SendNUIMessage({ type = 'openQuickDispatch', calls = calls })
end

RegisterKeyMapping('xs_mdt_quickdispatch', 'XSMDT: Quick Dispatch', 'keyboard', 'F10')
RegisterCommand('xs_mdt_quickdispatch', function()
    OpenQuickDispatch()
end, false)

-- Backup request — sends an urgent dispatch call with officer's location
RegisterKeyMapping('xs_mdt_backup', 'XSMDT: Request Backup', 'keyboard', 'F12')
RegisterCommand('xs_mdt_backup', function()
    local pd = exports['qbx_core']:GetPlayerData()
    if not pd or not Config.AuthorizedJobs[pd.job.name] then return end
    if Config.OnDutyOnly and not pd.job.onduty then return end
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, _ = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    TriggerServerEvent('XS-MDT:server:backupRequest', {
        x = coords.x, y = coords.y, z = coords.z,
        street = street,
    })
    lib.notify({ title = 'Backup Requested', description = 'Broadcast sent to all units.', type = 'success', duration = 5000 })
end, false)

-- Expiring warrant alert receiver
RegisterNetEvent('XS-MDT:client:expiringWarrantAlert', function(data)
    lib.notify({
        title       = '⚖ WARRANT EXPIRING SOON',
        description = (data.subject or 'Unknown') .. ' — expires in ' .. (data.hoursLeft or '?') .. 'h',
        type        = 'warning',
        duration    = 12000,
    })
    if mdtOpen then
        SendNUIMessage({ action = 'expiringWarrant', data = data })
    end
end)

-- NUI: player pressed Esc or responded
RegisterNUICallback('qdClosed', function(_, cb)
    qdOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

-- NUI: player selected a call to respond to
RegisterNUICallback('qdRespond', function(data, cb)
    qdOpen = false
    SetNuiFocus(false, false)

    -- Set GPS waypoint
    if data.coords then
        SetNewWaypoint(data.coords.x, data.coords.y)
    end

    -- Mark responding on the call server-side
    TriggerServerEvent('XS-MDT:server:respondToCall', {
        callId = data.callId,
    })

    lib.notify({
        title       = '📡 Responding',
        description = (data.callType or 'Call') .. ' — ' .. (data.location or '') .. '\nGPS set · ' .. (data.callNumber or ''),
        type        = 'success',
        duration    = 6000,
    })

    cb('ok')
end)
