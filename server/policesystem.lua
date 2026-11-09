MdtPolice = {}

local RESOURCE = 'XS-PoliceSystem'
local MAX_IMAGE = 60000

local function linked()
    return GetResourceState(RESOURCE) == 'started'
end

function MdtPolice.Plate(plate)
    return (tostring(plate or ''):upper():gsub('%s+', ''))
end

function MdtPolice.FlagPlate(plate, reason)
    plate = MdtPolice.Plate(plate)
    if plate == '' or not linked() then return false end
    local ok = pcall(function() exports['XS-PoliceSystem']:FlagPlate(plate, tostring(reason or ''):sub(1, 160), 0) end)
    return ok
end

function MdtPolice.UnflagPlate(plate)
    plate = MdtPolice.Plate(plate)
    if plate == '' or not linked() then return false end
    local active = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_bolos WHERE active = 1 AND UPPER(REPLACE(plate, ' ', '')) = ?", { plate })
    if (tonumber(active) or 0) > 0 then return false end
    local ok = pcall(function() exports['XS-PoliceSystem']:UnflagPlate(plate) end)
    return ok
end

function MdtPolice.PlateFlag(plate)
    if not linked() then return nil end
    local ok, flag = pcall(function() return exports['XS-PoliceSystem']:GetPlateFlag(MdtPolice.Plate(plate)) end)
    return ok and type(flag) == 'table' and flag or nil
end

function MdtPolice.Profile(citizenid)
    if not linked() then return nil end
    local ok, profile = pcall(function() return exports['XS-PoliceSystem']:GetProfile(citizenid) end)
    return ok and type(profile) == 'table' and profile or nil
end

function MdtPolice.Mugshot(citizenid)
    if not linked() then return nil end
    local ok, image = pcall(function() return exports['XS-PoliceSystem']:GetMugshot(citizenid) end)
    if not ok or type(image) ~= 'string' or #image > MAX_IMAGE then return nil end
    return image
end

function MdtPolice.SaveImage(citizenid, image)
    if type(image) ~= 'string' or image == '' or #image > MAX_IMAGE then return false end
    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_civilians WHERE citizenid = ?', { citizenid })
    if (tonumber(exists) or 0) == 0 and MdtSyncCivilian then MdtSyncCivilian(citizenid) end
    MySQL.update.await('UPDATE mdt_civilians SET image = ? WHERE citizenid = ?', { image, citizenid })
    return true
end

AddEventHandler('XS-PoliceSystem:server:mugshot', function(_, citizenid, image)
    if not citizenid then return end
    if MdtPolice.SaveImage(citizenid, image) then
        exports['XS-MDT']:AuditLog('Mugshot Taken', 'XS-PoliceSystem', citizenid)
    end
end)

AddEventHandler('XS-PoliceSystem:server:plateFlagged', function(plate, reason, officer)
    plate = MdtPolice.Plate(plate)
    if plate == '' then return end
    local active = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_bolos WHERE active = 1 AND UPPER(REPLACE(plate, ' ', '')) = ?", { plate })
    if (tonumber(active) or 0) > 0 then return end
    local by = tostring(officer or ''):sub(1, 100)
    if by == '' then by = 'XS-PoliceSystem' end
    local id = MySQL.insert.await([[
        INSERT INTO mdt_bolos (type, description, reason, plate, issued_by, issued_by_name)
        VALUES ('vehicle', ?, ?, ?, 'XS-PoliceSystem', ?)
    ]], { 'Flagged plate ' .. plate, tostring(reason or ''):sub(1, 255), plate, by })
    TriggerClientEvent('XS-MDT:client:boloAlert', -1, {
        id = id, type = 'vehicle', description = 'Flagged plate ' .. plate, reason = reason, plate = plate, issuedBy = by,
    })
    exports['XS-MDT']:AuditLog('BOLO Issued', by, 'vehicle: Flagged plate ' .. plate)
end)

AddEventHandler('XS-PoliceSystem:server:plateUnflagged', function(plate)
    plate = MdtPolice.Plate(plate)
    if plate == '' then return end
    local rows = MySQL.query.await("SELECT id FROM mdt_bolos WHERE active = 1 AND UPPER(REPLACE(plate, ' ', '')) = ?", { plate }) or {}
    for _, row in ipairs(rows) do
        MySQL.update.await("UPDATE mdt_bolos SET active = 0, cleared_by = 'XS-PoliceSystem', cleared_at = NOW() WHERE id = ?", { row.id })
        TriggerClientEvent('XS-MDT:client:boloCleared', -1, row.id)
    end
    if #rows > 0 then exports['XS-MDT']:AuditLog('BOLO Cleared', 'XS-PoliceSystem', 'Plate ' .. plate) end
end)

exports('GetActiveWarrants', function(citizenid)
    if not citizenid then return 0 end
    local count = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_warrants WHERE citizenid = ? AND status = 'active'", { citizenid })
    return tonumber(count) or 0
end)
