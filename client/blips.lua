-- XSMDT Blips — live on-duty Police / EMS / Fire blips on the game map.
-- Which jobs take part, whether departments see each other, and whether the
-- system runs at all are all controlled by Config.Blips.

local _blips = {}       -- [citizenid] = blip handle
local _blipData = {}    -- [citizenid] = last known state (for label refresh)

-- Blip sprite IDs
local SPRITE = {
    ON_FOOT     = 1,
    CAR         = 225,
    MOTORCYCLE  = 226,
    HELICOPTER  = 64,
    PLANE       = 307,
    BOAT        = 427,
    BICYCLE     = 348,
}

local function GetVehicleSprite(veh)
    if not veh or veh == 0 then return SPRITE.ON_FOOT end
    local vehClass = GetVehicleClass(veh)
    -- Vehicle class IDs: 8=motorcycle, 9=bicycle, 13=cycle, 14=boat, 15=helicopter, 16=plane
    if vehClass == 8  then return SPRITE.MOTORCYCLE end
    if vehClass == 9 or vehClass == 13 then return SPRITE.BICYCLE end
    if vehClass == 14 then return SPRITE.BOAT end
    if vehClass == 15 then return SPRITE.HELICOPTER end
    if vehClass == 16 then return SPRITE.PLANE end
    return SPRITE.CAR
end

-- "J. Doe [FD-12] [VEH]" — each part is individually toggleable in config.
local function MakeBlipLabel(name, badge, deptShort, sprite)
    local B = Config.Blips or {}
    local label = (B.ShowName == false) and (deptShort or 'UNIT') or (name or 'Unit')

    if B.ShowBadge ~= false and badge and badge ~= '' and badge ~= 'N/A' then
        label = label .. ' [' .. (deptShort and (deptShort .. '-') or '') .. badge .. ']'
    elseif deptShort and B.ShowName ~= false then
        label = label .. ' [' .. deptShort .. ']'
    end

    if B.ShowVehicle ~= false and sprite and sprite ~= SPRITE.ON_FOOT then
        if sprite == SPRITE.HELICOPTER or sprite == SPRITE.PLANE then label = label .. ' [AIR]'
        elseif sprite == SPRITE.BOAT then label = label .. ' [BOAT]'
        else label = label .. ' [VEH]' end
    end
    return label
end

local function ApplyLabel(blip, label)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
end

local function CreateBlip(unit, coords, sprite, color, deptShort)
    local B = Config.Blips or {}
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, B.Scale or 0.82)
    SetBlipAsShortRange(blip, B.ShortRange == true)
    ShowHeadingIndicatorOnBlip(blip, true)
    ApplyLabel(blip, MakeBlipLabel(unit.name, unit.badge, deptShort, sprite))

    _blips[unit.citizenid] = blip
    _blipData[unit.citizenid] = {
        name = unit.name, badge = unit.badge, job = unit.job,
        sprite = sprite, color = color,
    }
end

local function UpdateBlip(unit, coords, sprite, color, deptShort)
    local blip = _blips[unit.citizenid]
    if not blip or not DoesBlipExist(blip) then return end

    SetBlipCoords(blip, coords.x, coords.y, coords.z)

    -- Only touch sprite/colour/label when something actually changed (avoids flicker)
    local prev = _blipData[unit.citizenid] or {}
    if prev.color ~= color then
        SetBlipColour(blip, color)
        prev.color = color
    end
    if prev.sprite ~= sprite or prev.badge ~= unit.badge or prev.name ~= unit.name then
        SetBlipSprite(blip, sprite)
        ApplyLabel(blip, MakeBlipLabel(unit.name, unit.badge, deptShort, sprite))
        prev.sprite = sprite
        prev.badge  = unit.badge
        prev.name   = unit.name
    end
    _blipData[unit.citizenid] = prev
end

local function RemoveUnitBlip(citizenid)
    if _blips[citizenid] and DoesBlipExist(_blips[citizenid]) then
        RemoveBlip(_blips[citizenid])
    end
    _blips[citizenid]    = nil
    _blipData[citizenid] = nil
end

local function ClearAllBlips()
    for cid in pairs(_blips) do
        if DoesBlipExist(_blips[cid]) then RemoveBlip(_blips[cid]) end
    end
    _blips, _blipData = {}, {}
end

-- Receive full unit list from server every broadcast cycle
RegisterNetEvent('XS-MDT:client:updateBlips', function(units)
    if not (Config.Blips or {}).Enabled then return ClearAllBlips() end

    local myData = exports['qbx_core']:GetPlayerData()
    local myCid  = myData and myData.citizenid
    local myJob  = myData and myData.job and myData.job.name

    local seen = {}
    for _, unit in ipairs(units or {}) do
        -- Skip self, and anyone this department isn't allowed to see.
        if unit.citizenid ~= myCid and Dept.CanSeeUnit(myJob, unit.job) then
            seen[unit.citizenid] = true

            local coords    = unit.coords or { x = 0, y = 0, z = 0 }
            local color     = Dept.BlipColor(unit.job)
            local sprite    = unit.sprite or SPRITE.ON_FOOT
            local deptCfg   = Dept.ConfigOfJob(unit.job)
            local deptShort = deptCfg and deptCfg.short or nil

            if _blips[unit.citizenid] and DoesBlipExist(_blips[unit.citizenid]) then
                UpdateBlip(unit, coords, sprite, color, deptShort)
            else
                CreateBlip(unit, coords, sprite, color, deptShort)
            end
        end
    end

    -- Drop blips for units no longer in the list (off duty / disconnected)
    for cid in pairs(_blips) do
        if not seen[cid] then RemoveUnitBlip(cid) end
    end
end)

-- ── Position broadcast loop ───────────────────────────────────────────────
-- Sends coords + vehicle sprite so the server can forward the right icon.
-- Skipped entirely when blips are disabled, so a server running its own blip
-- script pays nothing for this.
CreateThread(function()
    if not (Config.Blips or {}).Enabled then return end
    local B = Config.Blips
    local interval = B.UpdateInterval or 2000

    while true do
        Wait(interval)
        local pd = exports['qbx_core']:GetPlayerData()
        if pd and pd.job and Dept.IsTracked(pd.job.name)
           and (B.OnDutyOnly == false or pd.job.onduty) then

            local ped    = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local veh    = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0

            TriggerServerEvent('XS-MDT:server:broadcastPosition', {
                x       = coords.x,
                y       = coords.y,
                z       = coords.z,
                sprite  = GetVehicleSprite(veh),
                heading = GetEntityHeading(ped),
            })
        end
    end
end)

-- Clean up all blips when resource stops
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearAllBlips()
end)
