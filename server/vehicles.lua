local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

-- Plate lookup.
--
-- Exact match first, then a partial sweep. Officers rarely get a whole plate —
-- they catch three or four characters as a car goes past, and an exact-only
-- query turns that into nothing at all. A partial hit returns candidates for
-- the officer to pick from rather than guessing on their behalf.
--
-- A plate with no registration is still worth answering: it may well be the
-- one with a stolen BOLO on it, so BOLOs are checked either way.
lib.callback.register('XS-MDT:server:lookupPlate', function(source, plate)
    if not HasPanel(source, 'vehicles') then return nil end
    if not plate or #plate < 1 then return nil end

    plate = plate:upper():gsub('%s+', '')

    local vehicle = MySQL.single.await([[
        SELECT pv.*, p.charinfo, p.citizenid
        FROM player_vehicles pv
        LEFT JOIN players p ON pv.citizenid = p.citizenid
        WHERE UPPER(REPLACE(pv.plate, ' ', '')) = ?
    ]], { plate })

    if not vehicle then
        -- Three characters is the shortest fragment worth searching; below
        -- that a LIKE returns most of the server and helps nobody.
        local matches = {}
        if #plate >= 3 then
            matches = MySQL.query.await([[
                SELECT pv.plate, pv.vehicle, pv.state, p.charinfo, pv.citizenid
                FROM player_vehicles pv
                LEFT JOIN players p ON pv.citizenid = p.citizenid
                WHERE UPPER(REPLACE(pv.plate, ' ', '')) LIKE ?
                LIMIT 15
            ]], { '%' .. plate .. '%' }) or {}

            for _, row in ipairs(matches) do
                local ci = row.charinfo and json.decode(row.charinfo) or nil
                local props = row.vehicle and json.decode(row.vehicle) or {}
                row.owner_name = ci and (ci.firstname .. ' ' .. ci.lastname) or 'Unregistered'
                row.label = props.modelName or 'Unknown'
                row.charinfo, row.vehicle = nil, nil
            end
        end

        -- A BOLO can exist on a plate nobody has registered.
        local bolo = MySQL.single.await('SELECT * FROM mdt_bolos WHERE plate = ? AND active = 1', { plate })

        return {
            found   = false,
            plate   = plate,
            bolo    = bolo,
            partial = #matches > 0 or nil,
            matches = matches,
        }
    end

    local charinfo = json.decode(vehicle.charinfo)
    local props = vehicle.vehicle and json.decode(vehicle.vehicle) or {}

    local bolo = MySQL.single.await("SELECT * FROM mdt_bolos WHERE plate = ? AND active = 1", { plate })
    local warrants = MySQL.query.await("SELECT COUNT(*) as count FROM mdt_warrants WHERE citizenid = ? AND status = 'active'", { vehicle.citizenid })
    local civilian = MySQL.single.await('SELECT * FROM mdt_civilians WHERE citizenid = ?', { vehicle.citizenid })

    return {
        found = true,
        plate = plate,
        owner = {
            citizenid = vehicle.citizenid,
            name = charinfo.firstname .. ' ' .. charinfo.lastname,
            dob = charinfo.birthdate,
            phone = charinfo.phone,
        },
        vehicle = {
            model = props.model or vehicle.hash,
            label = props.modelName or 'Unknown',
            color1 = props.color1,
            color2 = props.color2,
            fuel = props.fuelLevel,
            mods = props.mods,
            garage = vehicle.garage,
            state = vehicle.state, -- 0=out, 1=garaged, 2=impounded
        },
        bolo = bolo,
        active_warrants = warrants[1] and warrants[1].count or 0,
        flags = civilian and civilian.flags and json.decode(civilian.flags) or {},
    }
end)

-- Mark vehicle as stolen
lib.callback.register('XS-MDT:server:flagVehicleStolen', function(source, data)
    if not HasPanel(source, 'vehicles') then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)

    -- Create a BOLO for the vehicle
    MySQL.insert.await([[
        INSERT INTO mdt_bolos (type, description, reason, plate, issued_by, issued_by_name)
        VALUES ('vehicle', ?, 'Reported Stolen', ?, ?, ?)
    ]], {
        'Stolen Vehicle — Plate: ' .. data.plate .. (data.description and (' — ' .. data.description) or ''),
        data.plate,
        officer.citizenid,
        officer.name
    })

    -- Notify all on-duty officers
    TriggerClientEvent('XS-MDT:client:boloAlert', -1, {
        type = 'vehicle',
        plate = data.plate,
        description = data.description or 'No additional description',
        issuedBy = officer.name,
    })

    exports['XS-MDT']:AuditLog('Vehicle Flagged Stolen', officer.name, 'Plate: ' .. data.plate)
    return true
end)
