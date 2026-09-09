local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetOfficerInfo = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end

lib.callback.register('XS-MDT:server:getBulletins', function(source)
    if not HasPanel(source, 'bulletins') then return nil end
    return MySQL.query.await([[
        SELECT * FROM mdt_bulletins
        WHERE is_archived = 0 AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY pinned DESC, created_at DESC
        LIMIT 50
    ]], {})
end)

lib.callback.register('XS-MDT:server:createBulletin', function(source, data)
    if not HasPanel(source, 'bulletins') then return false end
    local officer = GetOfficerInfo(source)
    if not officer or officer.grade < Dept.SupervisorGrade(officer.job) then return false end
    if not data.title or not data.body then return false end

    local expiresAt = nil
    if data.expiryHours and tonumber(data.expiryHours) and tonumber(data.expiryHours) > 0 then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + math.floor(tonumber(data.expiryHours)) * 3600)
    end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_bulletins (title, body, priority, pinned, created_by, created_by_name, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.title, data.body, data.priority or 'normal',
        data.pinned and 1 or 0,
        officer.citizenid, officer.name, expiresAt
    })

    exports['XS-MDT']:AuditLog('Bulletin Posted', officer.name, 'Bulletin #' .. id .. ': ' .. data.title)
    return id
end)

lib.callback.register('XS-MDT:server:deleteBulletin', function(source, bulletinId)
    if not HasPanel(source, 'bulletins') then return false end
    local officer = GetOfficerInfo(source)
    if not officer or officer.grade < Dept.SupervisorGrade(officer.job) then return false end
    MySQL.update.await('UPDATE mdt_bulletins SET is_archived = 1 WHERE id = ?', { bulletinId })
    return true
end)

lib.callback.register('XS-MDT:server:pinBulletin', function(source, data)
    if not HasPanel(source, 'bulletins') then return false end
    local officer = GetOfficerInfo(source)
    if not officer or officer.grade < Dept.SupervisorGrade(officer.job) then return false end
    MySQL.update.await('UPDATE mdt_bulletins SET pinned = ? WHERE id = ?', { data.pinned and 1 or 0, data.id })
    return true
end)
