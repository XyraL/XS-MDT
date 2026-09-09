-- XSMDT Server — Shift Log

local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetOfficerInfo = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end

-- Track open shift IDs per citizenid
local _openShifts = {}  -- citizenid -> shift db id

lib.callback.register('XS-MDT:server:clockIn', function(source)
    if not HasPanel(source, 'shiftlog') then return { ok = false, error = 'Unauthorized' } end
    local officer = GetOfficerInfo(source)
    if not officer then return { ok = false, error = 'No officer data' } end

    if _openShifts[officer.citizenid] then
        return { ok = false, error = 'Already clocked in' }
    end

    local badge = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { officer.citizenid }) or '???'

    local id = MySQL.insert.await([[
        INSERT INTO mdt_shift_log (citizenid, officer_name, badge, clock_in)
        VALUES (?, ?, ?, NOW())
    ]], { officer.citizenid, officer.name, badge })

    _openShifts[officer.citizenid] = id
    exports['XS-MDT']:AuditLog('CLOCK IN', officer.name, 'Shift started')
    return { ok = true, shiftId = id }
end)

lib.callback.register('XS-MDT:server:clockOut', function(source)
    if not HasPanel(source, 'shiftlog') then return { ok = false, error = 'Unauthorized' } end
    local officer = GetOfficerInfo(source)
    if not officer then return { ok = false, error = 'No officer data' } end

    local shiftId = _openShifts[officer.citizenid]
    if not shiftId then return { ok = false, error = 'Not clocked in' } end

    local shift = MySQL.single.await('SELECT clock_in FROM mdt_shift_log WHERE id = ?', { shiftId })
    local duration = 0
    if shift and shift.clock_in then
        local clockInTs = os.time() -- approximate; we use DB NOW() below
        duration = math.floor((clockInTs - clockInTs) + 1) -- placeholder; DB computes it
    end

    MySQL.update.await([[
        UPDATE mdt_shift_log
        SET clock_out = NOW(),
            duration_minutes = ROUND(TIMESTAMPDIFF(SECOND, clock_in, NOW()) / 60)
        WHERE id = ?
    ]], { shiftId })

    _openShifts[officer.citizenid] = nil
    exports['XS-MDT']:AuditLog('CLOCK OUT', officer.name, 'Shift ended')

    local updated = MySQL.single.await('SELECT duration_minutes FROM mdt_shift_log WHERE id = ?', { shiftId })
    return { ok = true, durationMinutes = updated and updated.duration_minutes or 0 }
end)

lib.callback.register('XS-MDT:server:getShiftStatus', function(source)
    if not HasPanel(source, 'shiftlog') then return nil end
    local officer = GetOfficerInfo(source)
    if not officer then return nil end
    return {
        clockedIn = _openShifts[officer.citizenid] ~= nil,
        shiftId   = _openShifts[officer.citizenid],
    }
end)

lib.callback.register('XS-MDT:server:getShiftHistory', function(source, data)
    if not HasPanel(source, 'shiftlog') then return nil end
    data = data or {}
    local where, params = {}, {}

    if data.citizenid and #data.citizenid > 0 then
        where[#where+1] = 'citizenid = ?'
        params[#params+1] = data.citizenid
    end
    if data.officerName and #data.officerName >= 2 then
        where[#where+1] = 'officer_name LIKE ?'
        params[#params+1] = '%' .. data.officerName .. '%'
    end
    if data.dateFrom and #data.dateFrom > 0 then
        where[#where+1] = 'DATE(clock_in) >= ?'
        params[#params+1] = data.dateFrom
    end
    if data.dateTo and #data.dateTo > 0 then
        where[#where+1] = 'DATE(clock_in) <= ?'
        params[#params+1] = data.dateTo
    end

    local sql = 'SELECT * FROM mdt_shift_log'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY clock_in DESC LIMIT 200'

    return MySQL.query.await(sql, params)
end)

lib.callback.register('XS-MDT:server:getWeeklyHours', function(source)
    if not HasPanel(source, 'shiftlog') then return nil end
    local officer = GetOfficerInfo(source)
    if not officer then return nil end

    local rows = MySQL.query.await([[
        SELECT citizenid, officer_name,
               SUM(duration_minutes) as total_minutes
        FROM mdt_shift_log
        WHERE YEARWEEK(clock_in, 1) = YEARWEEK(NOW(), 1)
          AND clock_out IS NOT NULL
        GROUP BY citizenid, officer_name
        ORDER BY total_minutes DESC
        LIMIT 50
    ]], {})
    return rows
end)

-- Auto clock-out if officer disconnects while clocked in
AddEventHandler('playerDropped', function()
    local src = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player then return end
    local cid = player.PlayerData.citizenid
    if _openShifts[cid] then
        MySQL.update.await([[
            UPDATE mdt_shift_log
            SET clock_out = NOW(),
                duration_minutes = ROUND(TIMESTAMPDIFF(SECOND, clock_in, NOW()) / 60)
            WHERE id = ?
        ]], { _openShifts[cid] })
        _openShifts[cid] = nil
    end
end)
