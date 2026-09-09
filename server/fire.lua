-- XSMDT — Fire backend.
-- Fire incident reports (NFIRS-flavoured), hazmat entries, and the apparatus
-- roster with its inspection log. Panel-gated the same way as EMS.

local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetInfo  = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end
local IsSuper  = function(src) return exports['XS-MDT']:IsSupervisor(src) end
local AuditLog = function(...) return exports['XS-MDT']:AuditLog(...) end

-- ═══════════════════════════════════════════════════════════════════════════
--  FIRE INCIDENT REPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local function decodeIncident(r)
    if not r then return nil end
    r.units_responded = r.units_responded and json.decode(r.units_responded) or {}
    r.personnel       = r.personnel       and json.decode(r.personnel)       or {}
    r.casualties      = r.casualties      and json.decode(r.casualties)      or {}
    return r
end

lib.callback.register('XS-MDT:server:getFireIncidents', function(source, data)
    if not HasPanel(source, 'fireincidents') then return nil end
    local ff     = GetInfo(source)
    local filter = (type(data) == 'table' and data.filter) or 'all'
    local search = (type(data) == 'table' and data.search) or nil

    local where, params = {}, {}
    if filter == 'mine' then
        where[#where + 1] = 'created_by = ?'
        params[#params + 1] = ff.citizenid
    elseif filter == 'open' then
        where[#where + 1] = "status = 'open'"
    end
    if search and #search >= 2 then
        where[#where + 1] = '(address LIKE ? OR incident_type LIKE ? OR narrative LIKE ?)'
        for _ = 1, 3 do params[#params + 1] = '%' .. search .. '%' end
    end

    local sql = 'SELECT * FROM mdt_fire_incidents'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY created_at DESC LIMIT 100'

    local rows = MySQL.query.await(sql, params) or {}
    for _, r in ipairs(rows) do decodeIncident(r) end
    return rows
end)

lib.callback.register('XS-MDT:server:getFireIncident', function(source, id)
    if not HasPanel(source, 'fireincidents') then return nil end
    return decodeIncident(MySQL.single.await('SELECT * FROM mdt_fire_incidents WHERE id = ?', { id }))
end)

lib.callback.register('XS-MDT:server:createFireIncident', function(source, data)
    if not HasPanel(source, 'fireincidents') then return false end
    local ff = GetInfo(source)
    if not data or not data.incident_type or not data.address then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_fire_incidents
            (incident_type, address, alarm_level, cause, structure_type, narrative,
             units_responded, personnel, casualties, damage_estimate, acres_burned,
             water_used, status, created_by, created_by_name)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        data.incident_type, data.address,
        tonumber(data.alarm_level) or 1,
        data.cause or 'undetermined',
        data.structure_type or nil,
        data.narrative or '',
        json.encode(data.units_responded or {}),
        json.encode(data.personnel or {}),
        json.encode(data.casualties or {}),
        tonumber(data.damage_estimate) or 0,
        tonumber(data.acres_burned) or 0,
        tonumber(data.water_used) or 0,
        data.status or 'open',
        ff.citizenid, ff.name,
    })

    AuditLog('Fire Incident Created', ff.name, ('Incident #%d — %s at %s'):format(id, data.incident_type, data.address))
    return id
end)

lib.callback.register('XS-MDT:server:updateFireIncident', function(source, data)
    if not HasPanel(source, 'fireincidents') then return false end
    local ff = GetInfo(source)
    if not data or not data.id then return false end

    local owner = MySQL.scalar.await('SELECT created_by FROM mdt_fire_incidents WHERE id = ?', { data.id })
    if not owner then return false end
    if owner ~= ff.citizenid and not IsSuper(source) then return false, 'Not your report' end

    MySQL.update.await([[
        UPDATE mdt_fire_incidents SET
            incident_type = ?, address = ?, alarm_level = ?, cause = ?, structure_type = ?,
            narrative = ?, units_responded = ?, personnel = ?, casualties = ?,
            damage_estimate = ?, acres_burned = ?, water_used = ?, status = ?
        WHERE id = ?
    ]], {
        data.incident_type, data.address,
        tonumber(data.alarm_level) or 1,
        data.cause or 'undetermined',
        data.structure_type or nil,
        data.narrative or '',
        json.encode(data.units_responded or {}),
        json.encode(data.personnel or {}),
        json.encode(data.casualties or {}),
        tonumber(data.damage_estimate) or 0,
        tonumber(data.acres_burned) or 0,
        tonumber(data.water_used) or 0,
        data.status or 'open',
        data.id,
    })

    AuditLog('Fire Incident Updated', ff.name, 'Incident #' .. data.id)
    return true
end)

lib.callback.register('XS-MDT:server:deleteFireIncident', function(source, id)
    if not HasPanel(source, 'fireincidents') then return false end
    if not IsSuper(source) then return false, 'Supervisor only' end
    local ff = GetInfo(source)
    MySQL.query.await('DELETE FROM mdt_fire_incidents WHERE id = ?', { id })
    AuditLog('Fire Incident Deleted', ff.name, 'Incident #' .. tostring(id))
    return true
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  HAZMAT
-- ═══════════════════════════════════════════════════════════════════════════

lib.callback.register('XS-MDT:server:getHazmat', function(source, data)
    if not HasPanel(source, 'hazmat') then return nil end
    local filter = (type(data) == 'table' and data.filter) or 'active'

    local sql = 'SELECT * FROM mdt_hazmat'
    local params = {}
    if filter == 'active' then
        sql = sql .. " WHERE status <> 'closed'"
    end
    sql = sql .. ' ORDER BY created_at DESC LIMIT 100'
    return MySQL.query.await(sql, params) or {}
end)

lib.callback.register('XS-MDT:server:createHazmat', function(source, data)
    if not HasPanel(source, 'hazmat') then return false end
    local ff = GetInfo(source)
    if not data or not data.substance or not data.location then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_hazmat
            (substance, un_number, hazard_class, location, quantity, containment,
             evacuation_radius, injuries, narrative, status, incident_id, created_by, created_by_name)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        data.substance, data.un_number or nil, data.hazard_class or nil,
        data.location, data.quantity or nil,
        data.containment or 'ongoing',
        tonumber(data.evacuation_radius) or 0,
        tonumber(data.injuries) or 0,
        data.narrative or '',
        data.status or 'active',
        data.incident_id or nil,
        ff.citizenid, ff.name,
    })

    AuditLog('Hazmat Logged', ff.name, ('%s at %s'):format(data.substance, data.location))
    return id
end)

lib.callback.register('XS-MDT:server:updateHazmatStatus', function(source, data)
    if not HasPanel(source, 'hazmat') then return false end
    local ff = GetInfo(source)
    if not data or not data.id or not data.status then return false end
    MySQL.update.await('UPDATE mdt_hazmat SET status = ?, containment = ? WHERE id = ?', {
        data.status, data.containment or 'ongoing', data.id })
    AuditLog('Hazmat Updated', ff.name, 'Hazmat #' .. data.id .. ' → ' .. data.status)
    return true
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  APPARATUS + INSPECTIONS
-- ═══════════════════════════════════════════════════════════════════════════

lib.callback.register('XS-MDT:server:getApparatus', function(source)
    if not HasPanel(source, 'apparatus') then return nil end
    local rows = MySQL.query.await('SELECT * FROM mdt_apparatus ORDER BY unit_id ASC') or {}
    for _, a in ipairs(rows) do
        a.last_inspection = MySQL.single.await(
            'SELECT * FROM mdt_apparatus_log WHERE apparatus_id = ? ORDER BY created_at DESC LIMIT 1',
            { a.id })
    end
    return { apparatus = rows, isSupervisor = IsSuper(source) }
end)

lib.callback.register('XS-MDT:server:saveApparatus', function(source, data)
    if not HasPanel(source, 'apparatus') then return false end
    if not IsSuper(source) then return false, 'Supervisor only' end
    local ff = GetInfo(source)
    if not data or not data.unit_id then return false end

    if data.id then
        MySQL.update.await([[
            UPDATE mdt_apparatus SET unit_id = ?, type = ?, station = ?, status = ?, notes = ?
            WHERE id = ?
        ]], { data.unit_id, data.type or 'engine', data.station or '', data.status or 'in_service',
              data.notes or '', data.id })
        AuditLog('Apparatus Updated', ff.name, data.unit_id)
        return data.id
    end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_apparatus (unit_id, type, station, status, notes) VALUES (?,?,?,?,?)
    ]], { data.unit_id, data.type or 'engine', data.station or '', data.status or 'in_service',
          data.notes or '' })
    AuditLog('Apparatus Added', ff.name, data.unit_id)
    return id
end)

lib.callback.register('XS-MDT:server:deleteApparatus', function(source, id)
    if not HasPanel(source, 'apparatus') then return false end
    if not IsSuper(source) then return false, 'Supervisor only' end
    MySQL.query.await('DELETE FROM mdt_apparatus_log WHERE apparatus_id = ?', { id })
    MySQL.query.await('DELETE FROM mdt_apparatus WHERE id = ?', { id })
    return true
end)

lib.callback.register('XS-MDT:server:getApparatusLog', function(source, apparatusId)
    if not HasPanel(source, 'apparatus') then return nil end
    return MySQL.query.await(
        'SELECT * FROM mdt_apparatus_log WHERE apparatus_id = ? ORDER BY created_at DESC LIMIT 50',
        { apparatusId }) or {}
end)

-- Any firefighter can file an inspection; only supervisors edit the roster itself.
lib.callback.register('XS-MDT:server:logInspection', function(source, data)
    if not HasPanel(source, 'apparatus') then return false end
    local ff = GetInfo(source)
    if not data or not data.apparatus_id then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_apparatus_log
            (apparatus_id, check_type, result, mileage, notes, author_citizenid, author_name)
        VALUES (?,?,?,?,?,?,?)
    ]], {
        data.apparatus_id, data.check_type or 'daily',
        data.result or 'pass', tonumber(data.mileage) or 0,
        data.notes or '', ff.citizenid, ff.name,
    })

    -- A failed check pulls the unit out of service automatically.
    if data.result == 'fail' then
        MySQL.update.await("UPDATE mdt_apparatus SET status = 'out_of_service' WHERE id = ?",
            { data.apparatus_id })
    end

    AuditLog('Apparatus Inspection', ff.name,
        ('Unit #%s — %s'):format(tostring(data.apparatus_id), data.result or 'pass'))
    return id
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  FIRE DASHBOARD STATS
-- ═══════════════════════════════════════════════════════════════════════════

lib.callback.register('XS-MDT:server:getFireStats', function(source)
    if not HasPanel(source, 'fireincidents') then return nil end
    local ff = GetInfo(source)

    return {
        incidents_today = MySQL.scalar.await(
            'SELECT COUNT(*) FROM mdt_fire_incidents WHERE DATE(created_at) = CURDATE()') or 0,
        incidents_week = MySQL.scalar.await(
            'SELECT COUNT(*) FROM mdt_fire_incidents WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)') or 0,
        my_incidents = MySQL.scalar.await(
            'SELECT COUNT(*) FROM mdt_fire_incidents WHERE created_by = ?', { ff.citizenid }) or 0,
        open_incidents = MySQL.scalar.await(
            "SELECT COUNT(*) FROM mdt_fire_incidents WHERE status = 'open'") or 0,
        -- SUM() comes back as a string through oxmysql — coerce before use.
        damage_week = tonumber(MySQL.scalar.await(
            'SELECT COALESCE(SUM(damage_estimate),0) FROM mdt_fire_incidents WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)')) or 0,
        active_hazmat = MySQL.scalar.await(
            "SELECT COUNT(*) FROM mdt_hazmat WHERE status <> 'closed'") or 0,
        oos_apparatus = MySQL.scalar.await(
            "SELECT COUNT(*) FROM mdt_apparatus WHERE status = 'out_of_service'") or 0,
        top_types = MySQL.query.await([[
            SELECT incident_type, COUNT(*) AS cnt FROM mdt_fire_incidents
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
            GROUP BY incident_type ORDER BY cnt DESC LIMIT 5
        ]]) or {},
    }
end)
