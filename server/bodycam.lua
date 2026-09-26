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
        print('[XS-MDT] Purged ' .. deleted .. ' old body cam log entries')
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

--[[  Live body cam

      A supervisor picks an on-duty officer and watches what their chest camera
      sees. The server's job is to decide whether that is allowed, hand the
      watcher a server id, and make sure it is on the record: every viewing is
      audited, and by default the officer is told it is happening.

      Nothing about the camera itself lives here. The server never knows where
      the watcher is looking — it only says yes.
]]

local _watching = {}   -- [watcherSrc] = { target = src, citizenid, startedAt }

local function LiveEnabled()
    return Config.BodyCam.Enabled and Config.BodyCam.Live and Config.BodyCam.Live.Enabled
end

--[[ Who is on duty and can be watched.

     Same shape as the roster, plus the server id the watcher's client needs to
     resolve the ped. Restricted to the watcher's own department unless the
     config says otherwise. ]]
lib.callback.register('XS-MDT:server:getLiveCams', function(source)
    if not LiveEnabled() then return nil end
    if not exports['XS-MDT']:HasPanel(source, 'cameras') then return nil end

    local me = exports['XS-MDT']:GetOfficerInfo(source)
    if not me then return nil end

    local live = Config.BodyCam.Live
    if live.SupervisorOnly and not exports['XS-MDT']:IsSupervisor(source) then
        return { units = {}, canWatch = false }
    end

    local units = {}
    for src, player in pairs(Framework.GetPlayers()) do
        local pd = player.PlayerData
        local dept = pd and Config.AuthorizedJobs[pd.job.name]

        if dept and pd.job.onduty and src ~= source then
            if not live.SameDepartment or dept == me.department then
                local profile = MySQL.single.await(
                    'SELECT badge, callsign, status FROM mdt_officers WHERE citizenid = ?', { pd.citizenid })
                units[#units + 1] = {
                    serverId  = src,
                    citizenid = pd.citizenid,
                    name      = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
                    rank      = pd.job.grade.name,
                    department = dept,
                    badge     = profile and profile.badge or '—',
                    callsign  = profile and profile.callsign or nil,
                    status    = profile and profile.status or '10-8',
                }
            end
        end
    end

    table.sort(units, function(a, b) return (a.callsign or a.badge) < (b.callsign or b.badge) end)
    return { units = units, canWatch = true }
end)

--[[ Start watching. Returns the server id the client spectates.

     The checks are repeated here rather than trusted from getLiveCams,
     because the panel is just a UI and the payload it sends is whatever the
     client felt like sending. ]]
lib.callback.register('XS-MDT:server:startBodyCam', function(source, targetSrc)
    if not LiveEnabled() then return false, 'Live body cams are off' end
    if not exports['XS-MDT']:HasPanel(source, 'cameras') then return false, 'No access' end

    local live = Config.BodyCam.Live
    if live.SupervisorOnly and not exports['XS-MDT']:IsSupervisor(source) then
        return false, 'Supervisors only'
    end

    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == source then return false, 'Pick a unit' end

    local me = exports['XS-MDT']:GetOfficerInfo(source)
    local them = exports['XS-MDT']:GetOfficerInfo(targetSrc)
    if not me or not them then return false, 'That unit is not on duty' end
    if not them.onduty then return false, 'That unit is off duty' end
    if live.SameDepartment and them.department ~= me.department then
        return false, 'Different department'
    end

    _watching[source] = { target = targetSrc, citizenid = them.citizenid, startedAt = os.time() }

    exports['XS-MDT']:AuditLog('BODYCAM_VIEWED', source,
        ('Opened %s\'s body cam'):format(them.name), { citizenid = them.citizenid, name = them.name })
    exports['XS-MDT']:LogBodyCam(targetSrc, 'BODYCAM_VIEWED', ('Viewed by %s'):format(me.name))

    if live.NotifyOfficer then
        TriggerClientEvent('XS-MDT:client:bodyCamNotice', targetSrc, { watcher = me.name, active = true })
    end

    local coords = lib.callback.await('XS-MDT:client:whereAmI', targetSrc)

    return true, {
        serverId = targetSrc,
        coords = coords,
        name = them.name,
        rank = them.gradeLabel,
        department = them.departmentShort,
    }
end)

lib.callback.register('XS-MDT:server:stopBodyCam', function(source)
    local session = _watching[source]
    _watching[source] = nil
    if not session then return true end

    local seconds = os.time() - session.startedAt
    exports['XS-MDT']:AuditLog('BODYCAM_CLOSED', source,
        ('Watched for %dm %02ds'):format(seconds // 60, seconds % 60), session.citizenid)

    if Config.BodyCam.Live and Config.BodyCam.Live.NotifyOfficer then
        TriggerClientEvent('XS-MDT:client:bodyCamNotice', session.target, { active = false })
    end
    return true
end)

--[[ A watcher who drops mid-session leaves the officer thinking they are still
     being watched, so the same tidy-up runs on disconnect. ]]
AddEventHandler('playerDropped', function()
    local src = source
    local session = _watching[src]
    if session then
        _watching[src] = nil
        if Config.BodyCam.Live and Config.BodyCam.Live.NotifyOfficer then
            TriggerClientEvent('XS-MDT:client:bodyCamNotice', session.target, { active = false })
        end
    end

    -- And anyone watching the player who just left loses the feed.
    for watcher, s in pairs(_watching) do
        if s.target == src then
            _watching[watcher] = nil
            TriggerClientEvent('XS-MDT:client:bodyCamLost', watcher, 'That unit disconnected')
        end
    end
end)
