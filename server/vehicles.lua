local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

local function Truthy(v)
    return v == true or v == 1 or v == '1' or v == 'true'
end

local function ParkingColumn(row)
    local from = Config.VehicleStateFrom or 'auto'
    if from ~= 'auto' then return from end
    if row.in_garage ~= nil then return 'in_garage' end
    if row.stored ~= nil then return 'stored' end
    return 'state'
end

function MdtVehicleState(row)
    if Truthy(row.impound) or Truthy(row.impounded) then return 2 end
    local column = ParkingColumn(row)
    if column == 'in_garage' then return Truthy(row.in_garage) and 1 or 0 end
    if column == 'stored' then return Truthy(row.stored) and 1 or 0 end
    local s = row.state
    if s == true then return 1 end
    s = tonumber(s)
    if s == 1 or s == 2 then return s end
    return 0
end

function MdtVehicleLabel(model)
    return Framework.VehicleLabel(model) or model or 'Unknown'
end

local function Props(row)
    local ok, props = pcall(json.decode, row.mods or '{}')
    return ok and type(props) == 'table' and props or {}
end

local function OwnerName(charinfo)
    local ok, ci = pcall(json.decode, charinfo or '')
    if not ok or type(ci) ~= 'table' or not ci.firstname then return nil, {} end
    return ci.firstname .. ' ' .. (ci.lastname or ''), ci
end

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
            local rows = MySQL.query.await([[
                SELECT pv.*, p.charinfo
                FROM player_vehicles pv
                LEFT JOIN players p ON pv.citizenid = p.citizenid
                WHERE UPPER(REPLACE(pv.plate, ' ', '')) LIKE ?
                LIMIT 15
            ]], { '%' .. plate .. '%' }) or {}

            for i, row in ipairs(rows) do
                matches[i] = {
                    plate = row.plate,
                    citizenid = row.citizenid,
                    owner_name = OwnerName(row.charinfo) or 'Unregistered',
                    label = MdtVehicleLabel(row.vehicle),
                    state = MdtVehicleState(row),
                }
            end
        end

        -- A BOLO can exist on a plate nobody has registered.
        local bolo = MySQL.single.await('SELECT * FROM mdt_bolos WHERE plate = ? AND active = 1', { plate })
        local flag = not bolo and MdtPolice.PlateFlag(plate)
        if flag then bolo = { type = 'vehicle', plate = plate, description = 'Flagged plate ' .. plate, reason = flag.reason, issued_by_name = flag.officer } end

        return {
            found   = false,
            plate   = plate,
            bolo    = bolo,
            partial = #matches > 0 or nil,
            matches = matches,
        }
    end

    local ownerName, charinfo = OwnerName(vehicle.charinfo)
    local props = Props(vehicle)

    local bolo = MySQL.single.await("SELECT * FROM mdt_bolos WHERE plate = ? AND active = 1", { plate })
    local flag = not bolo and MdtPolice.PlateFlag(plate)
    if flag then bolo = { type = 'vehicle', plate = plate, description = 'Flagged plate ' .. plate, reason = flag.reason, issued_by_name = flag.officer } end
    local warrants = MySQL.query.await("SELECT COUNT(*) as count FROM mdt_warrants WHERE citizenid = ? AND status = 'active'", { vehicle.citizenid })
    local civilian = MySQL.single.await('SELECT * FROM mdt_civilians WHERE citizenid = ?', { vehicle.citizenid })

    return {
        found = true,
        plate = plate,
        owner = {
            citizenid = vehicle.citizenid,
            name = ownerName or 'Unknown',
            dob = charinfo.birthdate,
            phone = charinfo.phone,
        },
        vehicle = {
            model = vehicle.vehicle or vehicle.hash,
            label = MdtVehicleLabel(vehicle.vehicle),
            color1 = props.color1,
            color2 = props.color2,
            fuel = tonumber(vehicle.fuel) or tonumber(props.fuelLevel),
            garage = vehicle.garage or vehicle.garage_id,
            state = MdtVehicleState(vehicle),
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

    MdtPolice.FlagPlate(data.plate, 'Reported stolen')
    exports['XS-MDT']:AuditLog('Vehicle Flagged Stolen', officer.name, 'Plate: ' .. data.plate)
    return true
end)
