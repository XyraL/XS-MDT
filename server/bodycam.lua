local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end

-- Internal logger — called by other server files
local function LogBodyCam(src, action, details)
    if not Config.BodyCam.Enabled then return end
    local officer = exports['XS-MDT']:GetOfficerInfo(src)
    if not officer then return end
    MySQL.insert.await('INSERT INTO mdt_bodycam (citizenid, officer_name, action, details) VALUES (?,?,?,?)', {
        officer.citizenid, officer.name, action, details or ''
    })
end

exports('LogBodyCam', LogBodyCam)

-- Get body cam log for an officer (supervisor sees any officer, others see own only)
lib.callback.register('XS-MDT:server:getBodyCamLog', function(source, targetCitizenid)
    if not IsAuthorized(source) then return nil end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not officer then return nil end

    -- Non-supervisors can only view their own log
    local cid = targetCitizenid
    local isSupervisor = officer.grade >= Dept.SupervisorGrade(officer.job)
    if not isSupervisor or not cid then
        cid = officer.citizenid
    end

    -- A supervisor oversees their own department only — an EMS captain has no
    -- business reading a police officer's action log.
    if cid ~= officer.citizenid then
        local targetJob = MySQL.scalar.await('SELECT department FROM mdt_officers WHERE citizenid = ?', { cid })
        if targetJob and Dept.OfJob(targetJob) ~= Dept.OfJob(officer.job) then return nil end
    end

    local results = MySQL.query.await([[
        SELECT id, officer_name, action, details, created_at
        FROM mdt_bodycam
        WHERE citizenid = ?
        ORDER BY created_at DESC
        LIMIT 200
    ]], { cid })
    return results
end)

-- Purge old body cam logs (called by resource start or scheduled)
local function PurgeOldLogs()
    if not Config.BodyCam.Enabled or Config.BodyCam.RetentionDays <= 0 then return end
    local deleted = MySQL.scalar.await([[
        DELETE FROM mdt_bodycam WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { Config.BodyCam.RetentionDays })
    if deleted and deleted > 0 then
        print('[XSMDT] Purged ' .. deleted .. ' old body cam log entries')
    end
end

-- Purge on resource start, then every 6 hours
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    PurgeOldLogs()
end)

CreateThread(function()
    while true do
        Wait(21600000) -- 6 hours
        PurgeOldLogs()
    end
end)
