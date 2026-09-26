--[[  Camera views

      Looking through a fixed camera is the body cam without the hard part —
      there is no ped to stream in and no rotation to track. The watcher is
      moved to the camera's position, hidden and frozen, and a static camera is
      created there pointing at the stored heading and pitch.

      It pans, tilts and zooms, because a camera you cannot move is a
      screenshot. The stored heading is where it rests, not where it is stuck.

      Aiming is done in-world rather than by typing numbers: stand where the
      camera should be, look at what it should see, and the panel saves your
      position and your view.
]]

local viewing = nil     -- { id, code, label, area, heading, pitch, fov, cam }
local restore = nil

local PITCH_MIN, PITCH_MAX = -70.0, 25.0
local FOV_MIN, FOV_MAX = 22.0, 85.0

local function Hide()
    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetLocalPlayerVisibleLocally(false)
end

local function Show()
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

local function StopViewing()
    if not viewing then return end

    local cam = viewing.cam
    viewing = nil

    RenderScriptCams(false, false, 0, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, true) end
    Show()

    SendNUIMessage({ action = 'bodycamClose' })
    SetNuiFocus(false, false)
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
    local here = GetEntityCoords(me)
    restore = { x = here.x, y = here.y, z = here.z, h = GetEntityHeading(me) }

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end

    Hide()

    local c = cam.coords
    RequestCollisionAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    SetEntityCoords(me, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false, false)

    -- Give the world around the camera a moment to load, or the first second
    -- of every feed is grey fog.
    local deadline = GetGameTimer() + 4000
    while not HasCollisionLoadedAroundEntity(me) and GetGameTimer() < deadline do Wait(50) end

    viewing = {
        id = cam.id, code = cam.camera_code, label = cam.label, area = cam.area,
        heading = tonumber(cam.heading) or 0.0,
        pitch = tonumber(cam.pitch) or -12.0,
        fov = 60.0,
    }

    viewing.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        c.x + 0.0, c.y + 0.0, c.z + 0.0, 0.0, 0.0, 0.0, viewing.fov, false, 2)
    SetCamActive(viewing.cam, true)
    RenderScriptCams(true, false, 0, true, true)
    Aim()

    SendNUIMessage({
        action = 'bodycamOpen',
        mode = 'camera',
        unit = { callsign = cam.camera_code, name = cam.label, rank = cam.area },
    })
    SetNuiFocus(false, false)

    Wait(150)
    DoScreenFadeIn(350)
    return true
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

            if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 177)
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

-- The overlay shows where the camera is pointing and how far it is zoomed in.
CreateThread(function()
    while true do
        Wait(500)
        if viewing then
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
    if not data or not data.coords then cb(false) return end

    TriggerEvent('XS-MDT:client:closeForBodyCam')
    cb(StartViewing(data) and { ok = true } or false)
end)

RegisterNUICallback('stopCameraView', function(_, cb)
    StopViewing()
    cb('ok')
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
    if name == GetCurrentResourceName() then StopViewing() end
end)
