local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

lib.callback.register('XS-MDT:server:getBolos', function(source)
    if not HasPanel(source, 'bolos') then return nil end
    return MySQL.query.await('SELECT * FROM mdt_bolos WHERE active = 1 ORDER BY created_at DESC', {})
end)

lib.callback.register('XS-MDT:server:issueBolo', function(source, data)
    if not HasPanel(source, 'bolos') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not officer then return false end
    if not data.description or not data.reason then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_bolos (type, description, reason, plate, image, issued_by, issued_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { data.type or 'person', data.description, data.reason, data.plate, data.image, officer.citizenid, officer.name })

    -- Broadcast to all on-duty officers
    TriggerClientEvent('XS-MDT:client:boloAlert', -1, {
        id = id,
        type = data.type or 'person',
        description = data.description,
        reason = data.reason,
        plate = data.plate,
        issuedBy = officer.name,
    })

    exports['XS-MDT']:AuditLog('BOLO Issued', officer.name, data.type .. ': ' .. data.description)
    return id
end)

lib.callback.register('XS-MDT:server:clearBolo', function(source, boloId)
    if not HasPanel(source, 'bolos') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    MySQL.update.await('UPDATE mdt_bolos SET active = 0, cleared_by = ?, cleared_at = NOW() WHERE id = ?', {
        officer.citizenid, boloId
    })
    -- Notify clients to remove the BOLO from their boards
    TriggerClientEvent('XS-MDT:client:boloCleared', -1, boloId)
    exports['XS-MDT']:AuditLog('BOLO Cleared', officer.name, 'BOLO ID: ' .. boloId)
    return true
end)
