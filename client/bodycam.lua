--[[  Live body cam

      Watching another officer's camera without going anywhere. The server
      widens how far the watcher receives entities so the officer being watched
      streams in wherever they are, the game loads the world around them
      instead of around the watcher, and a scripted camera hangs off their
      chest.

      The watcher's own character stays where it was, visible and hittable,
      and the feed drops the moment they are hurt.

      The camera takes the ped's body rotation, so it looks where their chest
      faces rather than where their head turns. That is what a real body cam
      does, and it is also the only rotation you can read off a remote ped
      reliably.
]]

local watching = nil     -- { serverId, ped, cam, name, rank, department, health, armour, frozen, at }
local lastSeen = 0       -- os.time() the target ped was last valid

local function LiveCfg()
    return (Config.BodyCam and Config.BodyCam.Live) or {}
end

local function LiveEnabled()
    return Config.BodyCam and Config.BodyCam.Enabled and LiveCfg().Enabled
end

-- The server asks this of the officer being watched when it cannot read the
-- position itself.
lib.callback.register('XS-MDT:client:whereAmI', function()
    local c = GetEntityCoords(PlayerPedId())
    return { x = c.x, y = c.y, z = c.z }
end)

local function TargetPed()
    if not watching then return nil end
    local player = GetPlayerFromServerId(watching.serverId)
    if player == -1 or not NetworkIsPlayerActive(player) then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

-- ── Camera ────────────────────────────────────────────────────────────────

local function BuildCam(ped)
    local cfg = LiveCfg()
    local offset = cfg.Offset or { x = 0.0, y = 0.22, z = 0.0 }

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, cfg.Fov or 80.0, false, 2)

    AttachCamToPedBone(cam, ped, cfg.Bone or 24818,
        offset.x + 0.0, offset.y + 0.0, offset.z + 0.0, true)

    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    return cam
end

-- ── Stop ──────────────────────────────────────────────────────────────────

local function StopWatching(reason)
    if not watching then return end

    local w = watching
    watching = nil

    RenderScriptCams(false, false, 0, true, true)
    if w.cam and DoesCamExist(w.cam) then DestroyCam(w.cam, true) end
    ClearFocus()
    if w.frozen then FreezeEntityPosition(PlayerPedId(), false) end

    SendNUIMessage({ action = 'bodycamClose' })
    SetNuiFocus(false, false)

    lib.callback.await('XS-MDT:server:stopBodyCam', false)

    if reason then
        lib.notify({ title = 'Body cam', description = reason, type = 'error' })
    end
end

exports('StopBodyCam', function() StopWatching() end)

-- ── Start ─────────────────────────────────────────────────────────────────

local function StartWatching(info)
    local me = PlayerPedId()
    if IsEntityDead(me) then return false end

    local vehicle = GetVehiclePedIsIn(me, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == me and GetEntitySpeed(vehicle) > 1.0 then
        lib.notify({ title = 'Body cam', description = 'Stop the vehicle first', type = 'error' })
        return false
    end

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(0) end

    local frozen = vehicle == 0
    if frozen then FreezeEntityPosition(me, true) end

    local at = info.coords
    if at then SetFocusPosAndVel(at.x + 0.0, at.y + 0.0, at.z + 0.0, 0.0, 0.0, 0.0) end

    -- The server has widened what this client receives; wait for them to
    -- arrive rather than going to them.
    local ped
    for _ = 1, 100 do
        local player = GetPlayerFromServerId(info.serverId)
        if player ~= -1 then
            local candidate = GetPlayerPed(player)
            if candidate and candidate ~= 0 and DoesEntityExist(candidate) then
                ped = candidate
                break
            end
        end
        Wait(50)
    end

    if not ped then
        ClearFocus()
        if frozen then FreezeEntityPosition(me, false) end
        DoScreenFadeIn(300)
        lib.callback.await('XS-MDT:server:stopBodyCam', false)
        lib.notify({ title = 'Body cam', description = 'Could not reach that unit', type = 'error' })
        return false
    end

    SetFocusEntity(ped)

    watching = {
        serverId = info.serverId, ped = ped,
        name = info.name, rank = info.rank, department = info.department,
        callsign = info.callsign, badge = info.badge,
        health = GetEntityHealth(me), armour = GetPedArmour(me),
        frozen = frozen, at = GetEntityCoords(me),
    }
    watching.cam = BuildCam(ped)
    lastSeen = os.time()

    SendNUIMessage({ action = 'bodycamOpen', unit = {
        name = watching.name, rank = watching.rank, department = watching.department,
        callsign = watching.callsign, badge = watching.badge,
    } })
    SetNuiFocus(false, false)

    Wait(200)
    DoScreenFadeIn(400)
    return true
end

local function Harmed(w)
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) then return true end
    if GetEntityHealth(ped) < w.health or GetPedArmour(ped) < w.armour then return true end
    return false
end

-- ── Per-frame ─────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        local wait = 300

        if watching then
            wait = 0

            DisableAllControlActions(0)
            EnableControlAction(0, 200, true)   -- ESC
            EnableControlAction(0, 177, true)   -- BACKSPACE
            EnableControlAction(0, 249, true)   -- push to talk

            local ped = TargetPed()

            if Harmed(watching) then
                StopWatching('You were hurt')
            elseif IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 177)
               or IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
                StopWatching()
            elseif ped and ped ~= 0 then
                lastSeen = os.time()

                -- Re-attach if they streamed out and back in as a new entity.
                if ped ~= watching.ped then
                    watching.ped = ped
                    if watching.cam and DoesCamExist(watching.cam) then DestroyCam(watching.cam, true) end
                    watching.cam = BuildCam(ped)
                    SetFocusEntity(ped)
                end

                -- Body rotation, not head. Set every frame, because attaching
                -- to a bone gives position only.
                local rot = GetEntityRotation(ped, 2)
                SetCamRot(watching.cam, rot.x + (LiveCfg().Pitch or -4.0), 0.0, rot.z, 2)
            elseif os.time() - lastSeen > (LiveCfg().SignalLossSeconds or 8) then
                StopWatching('Lost the feed')
            else
                SendNUIMessage({ action = 'bodycamSignal', ok = false })
            end
        end

        Wait(wait)
    end
end)

-- The overlay wants the street and speed, which change far more slowly than
-- the frame rate. The ground under the watcher is kept loaded meanwhile.
CreateThread(function()
    while true do
        Wait(1500)
        if watching then
            if watching.at then RequestCollisionAtCoord(watching.at.x, watching.at.y, watching.at.z) end
            local ped = TargetPed()
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                local hash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                SendNUIMessage({
                    action = 'bodycamTick',
                    ok = true,
                    street = GetStreetNameFromHashKey(hash),
                    inVehicle = IsPedInAnyVehicle(ped, false),
                    speed = math.floor(GetEntitySpeed(ped) * 2.236936),
                })
            end
        end
    end
end)

-- ── NUI and events ────────────────────────────────────────────────────────

RegisterNUICallback('startBodyCam', function(data, cb)
    if not LiveEnabled() or watching then cb(false) return end

    local ok, info = lib.callback.await('XS-MDT:server:startBodyCam', false, data and data.serverId)
    if not ok or type(info) ~= 'table' then cb(false) return end

    info.callsign = data.callsign
    info.badge = data.badge

    -- The MDT closes first: the overlay is a different thing wearing the same
    -- page, and leaving the tablet up behind it looks like a bug.
    TriggerEvent('XS-MDT:client:closeForBodyCam')

    cb(StartWatching(info) and { ok = true } or false)
end)

RegisterNUICallback('stopBodyCam', function(_, cb)
    StopWatching()
    cb('ok')
end)

RegisterNetEvent('XS-MDT:client:bodyCamLost', function(reason)
    StopWatching(reason or 'Lost the feed')
end)

--[[ Told to the officer being watched, not the watcher. A recording light you
     cannot see is not a recording light. ]]
RegisterNetEvent('XS-MDT:client:bodyCamNotice', function(data)
    if data and data.active then
        lib.notify({
            title = 'Body cam',
            description = ('%s is viewing your camera'):format(data.watcher or 'Command'),
            type = 'inform',
            duration = 6000,
        })
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() or not watching then return end
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    if watching.frozen then FreezeEntityPosition(PlayerPedId(), false) end
    watching = nil
end)
