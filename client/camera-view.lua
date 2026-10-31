--[[  Camera views

      Looking through a fixed camera. The officer stays exactly where they are,
      visible and as vulnerable as anyone else looking at a screen: the view is
      a scripted camera at the camera's position, and the game is told to load
      the world there instead of around the officer.

      It pans, tilts and zooms, because a camera you cannot move is a
      screenshot. The stored heading is where it rests, not where it is stuck.

      Aiming is done in-world rather than by typing numbers: stand where the
      camera should be, look at what it should see, and the panel saves your
      position and your view.
]]

local viewing = nil     -- { id, code, label, area, heading, pitch, fov, cam, health, armour, frozen, at }

local PITCH_MIN, PITCH_MAX = -70.0, 25.0
local FOV_MIN, FOV_MAX = 22.0, 85.0

local function StopViewing(reason)
    if not viewing then return end

    local v = viewing
    viewing = nil

    RenderScriptCams(false, false, 0, true, true)
    if v.cam and DoesCamExist(v.cam) then DestroyCam(v.cam, true) end
    ClearFocus()
    if v.frozen then FreezeEntityPosition(PlayerPedId(), false) end

    SendNUIMessage({ action = 'bodycamClose' })
    SetNuiFocus(false, false)

    lib.callback.await('XS-MDT:server:stopCameraView', false)

    if reason then
        lib.notify({ title = 'Camera', description = reason, type = 'error' })
    end
end

exports('StopCameraView', function() StopViewing() end)

--[[ Point the view somewhere. Called on open and on every pan. ]]
local function Aim()
    if not viewing or not DoesCamExist(viewing.cam) then return end
    SetCamRot(viewing.cam, viewing.pitch, 0.0, viewing.heading, 2)
    SetCamFov(viewing.cam, viewing.fov)
end

local function StartViewing(cam)
    if not cam or not cam.coords then return false end

    local me = PlayerPedId()
    if IsEntityDead(me) then return false end

    local vehicle = GetVehiclePedIsIn(me, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == me and GetEntitySpeed(vehicle) > 1.0 then
        lib.notify({ title = 'Camera', description = 'Stop the vehicle first', type = 'error' })
        return false
    end

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end

    -- On foot the officer is held still, so the ground cannot unload from
    -- under them while the game streams the camera's area instead.
    local frozen = vehicle == 0
    if frozen then FreezeEntityPosition(me, true) end

    local c = cam.coords
    local x, y, z = c.x + 0.0, c.y + 0.0, c.z + 0.0
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(x, y, z)

    viewing = {
        id = cam.id, code = cam.camera_code, label = cam.label, area = cam.area,
        heading = tonumber(cam.heading) or 0.0,
        pitch = tonumber(cam.pitch) or -12.0,
        fov = 60.0,
        health = GetEntityHealth(me),
        armour = GetPedArmour(me),
        frozen = frozen,
        at = GetEntityCoords(me),
    }

    viewing.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', x, y, z, 0.0, 0.0, 0.0, viewing.fov, false, 2)
    SetCamActive(viewing.cam, true)
    RenderScriptCams(true, false, 0, true, true)
    Aim()

    -- Give the world around the camera a moment to load, or the first second
    -- of every feed is grey fog.
    NewLoadSceneStartSphere(x, y, z, 80.0, 0)
    local deadline = GetGameTimer() + 3000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
    NewLoadSceneStop()

    if not viewing then
        DoScreenFadeIn(250)
        return false
    end

    SendNUIMessage({
        action = 'bodycamOpen',
        mode = 'camera',
        unit = { callsign = cam.camera_code, name = cam.label, rank = cam.area },
    })
    SetNuiFocus(false, false)

    DoScreenFadeIn(350)
    return true
end

-- The view ends the moment the officer is hurt, so it can never be somewhere
-- to hide.
local function Harmed(v)
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) then return true end
    if GetEntityHealth(ped) < v.health or GetPedArmour(ped) < v.armour then return true end
    return false
end

-- ── Controls ──────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        if not viewing then
            Wait(300)
        else
            DisableAllControlActions(0)
            EnableControlAction(0, 200, true)   -- ESC
            EnableControlAction(0, 177, true)   -- BACKSPACE
            EnableControlAction(0, 249, true)   -- push to talk

            if Harmed(viewing) then
                StopViewing('You were hurt')
            elseif IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 177)
               or IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
                StopViewing()
            else
                -- Pan and tilt scale with the zoom, so a tight shot does not
                -- swing wildly for the same key press.
                local step = 1.6 * (viewing.fov / 60.0)
                local moved = false

                if IsDisabledControlPressed(0, 174) then viewing.heading = viewing.heading + step; moved = true end
                if IsDisabledControlPressed(0, 175) then viewing.heading = viewing.heading - step; moved = true end
                if IsDisabledControlPressed(0, 172) then viewing.pitch = viewing.pitch + step * 0.7; moved = true end
                if IsDisabledControlPressed(0, 173) then viewing.pitch = viewing.pitch - step * 0.7; moved = true end

                if IsDisabledControlJustPressed(0, 241) then viewing.fov = viewing.fov - 6.0; moved = true end
                if IsDisabledControlJustPressed(0, 242) then viewing.fov = viewing.fov + 6.0; moved = true end

                if moved then
                    if viewing.heading > 360.0 then viewing.heading = viewing.heading - 360.0 end
                    if viewing.heading < 0.0 then viewing.heading = viewing.heading + 360.0 end
                    if viewing.pitch < PITCH_MIN then viewing.pitch = PITCH_MIN end
                    if viewing.pitch > PITCH_MAX then viewing.pitch = PITCH_MAX end
                    if viewing.fov < FOV_MIN then viewing.fov = FOV_MIN end
                    if viewing.fov > FOV_MAX then viewing.fov = FOV_MAX end
                    Aim()
                end
            end

            Wait(0)
        end
    end
end)

-- The overlay shows where the camera is pointing and how far it is zoomed in,
-- and the ground under the officer is kept loaded while the camera's area is.
CreateThread(function()
    while true do
        Wait(500)
        if viewing then
            if viewing.at then RequestCollisionAtCoord(viewing.at.x, viewing.at.y, viewing.at.z) end
            SendNUIMessage({
                action = 'bodycamTick',
                ok = true,
                street = viewing.area or '',
                bearing = math.floor(viewing.heading),
                zoom = math.floor((85.0 - viewing.fov) / 63.0 * 100.0),
            })
        end
    end
end)

-- ── NUI ───────────────────────────────────────────────────────────────────

RegisterNUICallback('viewCamera', function(data, cb)
    if viewing or not data or not data.id then cb(false) return end

    local cam = lib.callback.await('XS-MDT:server:startCameraView', false, data.id)
    if type(cam) ~= 'table' or not cam.coords then cb(false) return end

    TriggerEvent('XS-MDT:client:closeForBodyCam')
    local ok = StartViewing(cam)
    if not ok then lib.callback.await('XS-MDT:server:stopCameraView', false) end
    cb(ok and { ok = true } or false)
end)

RegisterNUICallback('stopCameraView', function(_, cb)
    StopViewing()
    cb('ok')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    StopViewing()
end)

--[[ Where the officer is standing and what they are looking at.

     Aiming a camera by typing coordinates and a heading is how you end up with
     thirty-five cameras pointing at the sky. ]]
RegisterNUICallback('myView', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local rot = GetGameplayCamRot(2)
    cb({
        x = c.x, y = c.y, z = c.z,
        heading = GetGameplayCamRelativeHeading() + GetEntityHeading(ped),
        pitch = rot.x,
    })
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        if viewing then
            RenderScriptCams(false, false, 0, true, true)
            ClearFocus()
            if viewing.frozen then FreezeEntityPosition(PlayerPedId(), false) end
            viewing = nil
        end
    end
end)
