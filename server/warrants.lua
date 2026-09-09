local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

lib.callback.register('XS-MDT:server:getWarrants', function(source, data)
    if not HasPanel(source, 'warrants') then return nil end
    local filter = (type(data) == 'table' and data.filter) or (type(data) == 'string' and data) or 'active'
    local results = MySQL.query.await([[
        SELECT w.*, CONCAT(c.firstname, ' ', c.lastname) as subject_name, c.dob
        FROM mdt_warrants w
        LEFT JOIN mdt_civilians c ON w.citizenid = c.citizenid
        WHERE w.status = ?
        ORDER BY w.created_at DESC
        LIMIT 100
    ]], { filter })

    for _, w in ipairs(results) do
        w.charges = json.decode(w.charges)
    end
    return results
end)

lib.callback.register('XS-MDT:server:issueWarrant', function(source, data)
    if not HasPanel(source, 'warrants') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not officer then return false end
    if not data.citizenid or not data.charges or #data.charges == 0 then return false end

    -- Build expires_at from optional expiryDays field
    local expiresAt = nil
    if data.expiryDays and data.expiryDays > 0 then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + data.expiryDays * 86400)
    end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_warrants (citizenid, charges, description, issued_by, issued_by_name, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { data.citizenid, json.encode(data.charges), data.description, officer.citizenid, officer.name, expiresAt })

    -- Notify all on-duty officers
    local civName = MySQL.scalar.await("SELECT CONCAT(firstname, ' ', lastname) FROM mdt_civilians WHERE citizenid = ?", { data.citizenid })
    TriggerClientEvent('XS-MDT:client:warrantAlert', -1, {
        subject = civName or data.citizenid,
        charges = data.charges,
        issuedBy = officer.name,
    })

    exports['XS-MDT']:AuditLog('Warrant Issued', officer.name, 'Subject: ' .. (civName or data.citizenid))

    if Config.BodyCam.Enabled then
        MySQL.insert.await('INSERT INTO mdt_bodycam (citizenid, officer_name, action, details) VALUES (?,?,?,?)', {
            officer.citizenid, officer.name, 'WARRANT_ISSUED',
            'Subject: ' .. (civName or data.citizenid) .. ' | Charges: ' .. #data.charges
        })
    end
    return id
end)

lib.callback.register('XS-MDT:server:clearWarrant', function(source, warrantId)
    if not HasPanel(source, 'warrants') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    MySQL.update.await("UPDATE mdt_warrants SET status = 'cleared', cleared_by = ?, cleared_at = NOW() WHERE id = ?", {
        officer.citizenid, warrantId
    })
    exports['XS-MDT']:AuditLog('Warrant Cleared', officer.name, 'Warrant ID: ' .. warrantId)
    exports['XS-MDT']:LogBodyCam(source, 'WARRANT_CLEARED', 'Warrant ID: ' .. warrantId)
    return true
end)

lib.callback.register('XS-MDT:server:getWarrantsForCivilian', function(source, citizenid)
    if not HasPanel(source, 'warrants') then return nil end
    local results = MySQL.query.await('SELECT * FROM mdt_warrants WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    for _, w in ipairs(results) do w.charges = json.decode(w.charges) end
    return results
end)

-- Auto-expire warrants that have passed their expires_at date
-- Also alert on-duty officers about warrants expiring within 24 hours
CreateThread(function()
    while true do
        Wait(300000) -- check every 5 minutes

        -- Expire overdue warrants
        local expired = MySQL.query.await([[
            SELECT id FROM mdt_warrants
            WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at <= NOW()
        ]], {})
        if expired and #expired > 0 then
            local ids = {}
            for _, r in ipairs(expired) do ids[#ids+1] = r.id end
            MySQL.update.await(
                'UPDATE mdt_warrants SET status = "expired" WHERE id IN (' .. table.concat(ids, ',') .. ')',
                {}
            )
            print('[XS-MDT] Auto-expired ' .. #expired .. ' warrant(s)')
        end

        -- Alert about warrants expiring in the next 24 hours (send once per warrant)
        local expiring = MySQL.query.await([[
            SELECT w.id, w.expires_at,
                   CONCAT(c.firstname, ' ', c.lastname) as subject_name
            FROM mdt_warrants w
            LEFT JOIN mdt_civilians c ON w.citizenid = c.citizenid
            WHERE w.status = 'active'
              AND w.expires_at IS NOT NULL
              AND w.expires_at > NOW()
              AND w.expires_at <= DATE_ADD(NOW(), INTERVAL 24 HOUR)
              AND (w.expiry_alert_sent IS NULL OR w.expiry_alert_sent = 0)
        ]], {})

        if expiring and #expiring > 0 then
            local alertIds = {}
            for _, w in ipairs(expiring) do
                alertIds[#alertIds+1] = w.id
                -- Calculate hours remaining
                local expiryTime = w.expires_at
                local hoursLeft  = math.max(1, math.floor(
                    (os.time() - os.time()) + 1  -- approximate; server sends the data
                ))

                local players = exports['qbx_core']:GetQBPlayers()
                for psrc, p in pairs(players) do
                    local job = p.PlayerData.job
                    if Config.AuthorizedJobs[job.name] and (not Config.OnDutyOnly or job.onduty) then
                        TriggerClientEvent('XS-MDT:client:expiringWarrantAlert', psrc, {
                            subject   = w.subject_name or 'Unknown',
                            expiresAt = w.expires_at,
                            hoursLeft = 'less than 24',
                            warrantId = w.id,
                        })
                    end
                end
            end

            -- Mark alerts as sent
            MySQL.update.await(
                'UPDATE mdt_warrants SET expiry_alert_sent = 1 WHERE id IN (' .. table.concat(alertIds, ',') .. ')',
                {}
            )
            print('[XS-MDT] Sent expiry alerts for ' .. #expiring .. ' warrant(s)')
        end
    end
end)
