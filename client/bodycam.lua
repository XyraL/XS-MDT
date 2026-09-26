--[[  Live body cam

      Watching another player's camera in FiveM means three separate things,
      and skipping any of them gives you a black screen:

        1. you need their position, which you CANNOT read from their ped —
           GetPlayerPed returns 0 for anyone not streamed to you, and
           GetEntityCoords(0) is the origin. The server sends it instead.

        2. their ped has to stream in, which only happens once you are near
           them. So the watcher is moved there first, invisible and frozen,
           and NetworkSetInSpectatorMode does the rest — it is what the
           built-in spectate uses.

        3. a scripted camera attached to the ped, because spectator mode on its
           own gives you the ordinary third-person view.

      The camera hangs off SKEL_Spine3 and takes the ped's body rotation, so it
      looks where their chest faces rather than where their head turns. That is
      what a real body cam does, and it is also the only rotation you can read
      off a remote ped reliably.
]]

local watching = nil     -- { serverId, ped, cam, name, rank, department }
local restore = nil      -- where the watcher was standing before
local lastSeen = 0       -- os.time() the target ped was last valid

local function LiveCfg()
    return (Config.BodyCam and Config.BodyCam.Live) or {}
end

local function LiveEnabled()
    return Config.BodyCam and Config.BodyCam.Enabled and LiveCfg().Enabled
end

-- The server asks this of the officer being watched, because nobody else can
-- answer it until their ped has streamed in.
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

-- ── Watcher state ─────────────────────────────────────────────────────────

local function HideWatcher()
    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetLocalPlayerVisibleLocally(false)
end

local function ShowWatcher()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetLocalPlayerVisibleLocally(true)

    if restore then
        SetEntityCoords(ped, restore.x, restore.y, restore.z, false, false, false, false)
        SetEntityHeading(ped, restore.h)
        restore = nil
    end
end

local function StopWatching(reason)
    if not watching then return end

    local cam = watching.cam
    watching = nil

    RenderScriptCams(false, false, 0, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, true) end
    NetworkSetInSpectatorMode(false, PlayerPedId())
    ShowWatcher()

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
    local here = GetEntityCoords(me)
    restore = { x = here.x, y = here.y, z = here.z, h = GetEntityHeading(me) }

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(0) end

    HideWatcher()

    -- Go to the position the server gave us and wait for their ped to arrive.
    local at = info.coords
    if at then
        RequestCollisionAtCoord(at.x + 0.0, at.y + 0.0, at.z + 0.0)
        SetEntityCoords(me, at.x + 0.0, at.y + 0.0, at.z + 1.0, false, false, false, false)
    end

    local ped
    for _ = 1, 80 do
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
        ShowWatcher()
        DoScreenFadeIn(300)
        lib.notify({ title = 'Body cam', description = 'Could not reach that unit', type = 'error' })
        return false
    end

    NetworkSetInSpectatorMode(true, ped)
    FreezeEntityPosition(PlayerPedId(), true)

    watching = {
        serverId = info.serverId, ped = ped,
        name = info.name, rank = info.rank, department = info.department,
        callsign = info.callsign, badge = info.badge,
    }
    watching.cam = BuildCam(ped)
    lastSeen = os.time()

    SendNUIMessage({ action = 'bodycamOpen', unit = watching })
    SetNuiFocus(false, false)

    Wait(200)
    DoScreenFadeIn(400)
    return true
end

-- ── Per-frame ─────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        local wait = 300

        if watching then
            wait = 0
            local ped = TargetPed()

            if ped and ped ~= 0 then
                lastSeen = os.time()

                -- Re-attach if they streamed out and back in as a new entity.
                if ped ~= watching.ped then
                    watching.ped = ped
                    if watching.cam and DoesCamExist(watching.cam) then DestroyCam(watching.cam, true) end
                    watching.cam = BuildCam(ped)
                    NetworkSetInSpectatorMode(true, ped)
                end

                -- Body rotation, not head. Set every frame, because attaching
                -- to a bone gives position only.
                local rot = GetEntityRotation(ped, 2)
                SetCamRot(watching.cam, rot.x + (LiveCfg().Pitch or -4.0), 0.0, rot.z, 2)

                -- The watcher is a passenger, not a participant.
                DisableAllControlActions(0)
                EnableControlAction(0, 200, true)   -- ESC
                EnableControlAction(0, 177, true)   -- BACKSPACE

                if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 177)
                   or IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
                    StopWatching()
                end
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
-- the frame rate.
CreateThread(function()
    while true do
        Wait(1500)
        if watching then
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
    if not LiveEnabled() then cb(false) return end

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
    if name == GetCurrentResourceName() then StopWatching() end
end)
