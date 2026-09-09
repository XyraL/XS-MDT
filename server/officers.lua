local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetOfficerInfo = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end

-- Public identity adapter for dispatch resources. Keeps MDT table ownership
-- inside XS-MDT instead of requiring integrations to query it directly.
exports('GetDispatchIdentity', function(src)
    local officer = GetOfficerInfo(tonumber(src))
    if not officer then return nil end
    local profile = MySQL.single.await('SELECT badge, callsign, department FROM mdt_officers WHERE citizenid = ?', { officer.citizenid })
    if not profile then return nil end
    return {
        callsign = profile.callsign,
        badge = profile.badge,
        department = profile.department,
        unitType = 'field',
    }
end)

exports('SetDispatchStatus', function(src, status)
    local officer = GetOfficerInfo(tonumber(src))
    if not officer then return false end
    local aliases = {
        ['10-8 Available'] = '10-8', ['10-6 Busy'] = '10-6',
        ['10-7 Out of Service'] = '10-7', ['On Scene'] = 'Code 4',
    }
    local mdtStatus = aliases[status] or status
    MySQL.update.await('UPDATE mdt_officers SET status = ? WHERE citizenid = ?', { mdtStatus, officer.citizenid })
    return true
end)

-- Get all currently on-duty officers (live, from connected players)
lib.callback.register('XS-MDT:server:getRoster', function(source)
    if not IsAuthorized(source) then return nil end
    local roster = {}
    local players = exports['qbx_core']:GetQBPlayers()
    for src, player in pairs(players) do
        local pd = player.PlayerData
        if Config.AuthorizedJobs[pd.job.name] and pd.job.onduty then
            local profile = MySQL.single.await('SELECT badge, callsign, status FROM mdt_officers WHERE citizenid = ?', { pd.citizenid })
            roster[#roster + 1] = {
                source    = src,
                citizenid = pd.citizenid,
                name      = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
                job       = pd.job.name,
                grade     = pd.job.grade.name,
                badge     = (profile and profile.badge) or 'N/A',
                callsign  = (profile and profile.callsign) or 'N/A',
                status    = (profile and profile.status) or '10-8',
            }
        end
    end
    return roster
end)

-- Get or create the MDT officer profile for the requesting player
lib.callback.register('XS-MDT:server:getMyOfficerProfile', function(source)
    if not IsAuthorized(source) then return nil end
    local officer = GetOfficerInfo(source)
    local profile = MySQL.single.await('SELECT * FROM mdt_officers WHERE citizenid = ?', { officer.citizenid })
    if not profile then
        -- Auto-create a basic profile on first open
        local badge = tostring(math.random(1000, 9999))
        MySQL.insert.await('INSERT INTO mdt_officers (citizenid, badge, rank, department) VALUES (?, ?, ?, ?)', {
            officer.citizenid, badge, officer.gradeLabel, officer.job
        })
        profile = MySQL.single.await('SELECT * FROM mdt_officers WHERE citizenid = ?', { officer.citizenid })
    end
    profile.name        = officer.name
    profile.onduty      = officer.onduty
    profile.grade       = officer.gradeLabel    -- human-readable rank label
    profile.gradeLevel  = officer.grade         -- numeric grade for permission checks
    profile.isSupervisor = officer.grade >= Dept.SupervisorGrade(officer.job)
    return profile
end)

-- Search on-duty officers by name (for incident linking)
lib.callback.register('XS-MDT:server:searchOfficers', function(source, query)
    if not IsAuthorized(source) then return nil end
    if not query or #query < 2 then return {} end
    local search = '%' .. query:lower() .. '%'
    local results = {}
    local players = exports['qbx_core']:GetQBPlayers()
    for src, player in pairs(players) do
        local pd = player.PlayerData
        if Config.AuthorizedJobs[pd.job.name] then
            local fullname = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
            if fullname:lower():find(search, 1, true) then
                local badge = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { pd.citizenid })
                results[#results + 1] = {
                    citizenid = pd.citizenid,
                    name = fullname,
                    grade = pd.job.grade.name,
                    badge = badge or 'N/A',
                    onduty = pd.job.onduty,
                }
            end
        end
    end
    return results
end)

-- Update officer callsign/badge
lib.callback.register('XS-MDT:server:updateOfficerProfile', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = GetOfficerInfo(source)
    if not officer then return false end

    -- Ensure badge is unique
    if data.badge then
        local existing = MySQL.scalar.await('SELECT citizenid FROM mdt_officers WHERE badge = ? AND citizenid != ?', { data.badge, officer.citizenid })
        if existing then return false, 'Badge number already in use' end
    end

    MySQL.update.await('UPDATE mdt_officers SET badge = ?, callsign = ? WHERE citizenid = ?', {
        data.badge, data.callsign, officer.citizenid
    })
    -- Drop the cached badge so live blip labels pick the new one up.
    exports['XS-MDT']:InvalidateBadgeCache(officer.citizenid)
    return true
end)


-- ═══════════════════════════════════════════════════════════════════════════
--  LIVE UNIT TRACKING
--  One in-memory store of every tracked unit's position, rebroadcast to
--  everyone allowed to see them. Which jobs take part and whether departments
--  see each other is decided by Dept.IsTracked / Dept.CanSeeUnit.
-- ═══════════════════════════════════════════════════════════════════════════

local _unitPositions = {}   -- [citizenid] = unit record
local _badgeCache    = {}   -- [citizenid] = badge; avoids a query every tick

local function GetBadge(citizenid)
    local cached = _badgeCache[citizenid]
    if cached ~= nil then return cached end
    local badge = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { citizenid })
    _badgeCache[citizenid] = badge or 'N/A'
    return _badgeCache[citizenid]
end

-- Called after a profile edit so the blip label picks up the new badge.
local function InvalidateBadge(citizenid) _badgeCache[citizenid] = nil end

-- Units seen recently enough to still be considered live.
local function LiveUnits()
    local staleAfter = (Config.Blips or {}).StaleAfter or 15
    local now, units = os.time(), {}
    for _, u in pairs(_unitPositions) do
        if now - u.ts < staleAfter then units[#units + 1] = u end
    end
    return units
end

-- Push the unit list to every connected player, filtered to what that
-- player's department is allowed to see.
function BroadcastUnits()
    if not (Config.Blips or {}).Enabled then return end
    local units = LiveUnits()
    for psrc, p in pairs(exports['qbx_core']:GetQBPlayers()) do
        local viewerJob = p.PlayerData.job and p.PlayerData.job.name
        if Dept.IsTracked(viewerJob) then
            local visible = {}
            for _, u in ipairs(units) do
                if Dept.CanSeeUnit(viewerJob, u.job) then visible[#visible + 1] = u end
            end
            TriggerClientEvent('XS-MDT:client:updateBlips', psrc, visible)
        end
    end
end

RegisterNetEvent('XS-MDT:server:broadcastPosition')
AddEventHandler('XS-MDT:server:broadcastPosition', function(data)
    if not (Config.Blips or {}).Enabled then return end
    local src    = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player or type(data) ~= 'table' then return end

    local pd = player.PlayerData
    if not Dept.IsTracked(pd.job.name) then return end
    if (Config.Blips or {}).OnDutyOnly ~= false and not pd.job.onduty then
        _unitPositions[pd.citizenid] = nil
        return BroadcastUnits()
    end

    local prev = _unitPositions[pd.citizenid]
    _unitPositions[pd.citizenid] = {
        citizenid  = pd.citizenid,
        name       = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
        job        = pd.job.name,
        department = Dept.OfJob(pd.job.name),
        badge      = GetBadge(pd.citizenid),
        coords     = { x = data.x or 0, y = data.y or 0, z = data.z or 0 },
        sprite     = data.sprite or 1,
        heading    = data.heading or 0,
        status     = prev and prev.status or nil,
        ts         = os.time(),
    }

    BroadcastUnits()
end)

-- Callback for the NUI map to pull the current picture on demand.
lib.callback.register('XS-MDT:server:getUnits', function(source)
    if not IsAuthorized(source) then return {} end
    local player = exports['qbx_core']:GetPlayer(source)
    local viewerJob = player and player.PlayerData.job and player.PlayerData.job.name
    local out = {}
    for _, u in ipairs(LiveUnits()) do
        if Dept.CanSeeUnit(viewerJob, u.job) then out[#out + 1] = u end
    end
    return out
end)

-- Clear a unit's position (going off duty or disconnecting)
RegisterNetEvent('XS-MDT:server:clearPosition')
AddEventHandler('XS-MDT:server:clearPosition', function()
    local player = exports['qbx_core']:GetPlayer(source)
    if not player then return end
    _unitPositions[player.PlayerData.citizenid] = nil
    BroadcastUnits()
end)

AddEventHandler('playerDropped', function()
    local player = exports['qbx_core']:GetPlayer(source)
    if not player then return end
    local cid = player.PlayerData.citizenid
    _unitPositions[cid] = nil
    _badgeCache[cid]    = nil
    BroadcastUnits()
end)

exports('InvalidateBadgeCache', InvalidateBadge)

-- Unit status update (10-8, 10-6, Code 4, etc.)
lib.callback.register('XS-MDT:server:setUnitStatus', function(source, status)
    if not IsAuthorized(source) then return false end
    local officer = exports['XS-MDT']:GetOfficerInfo(source)
    if not officer then return false end
    if _unitPositions[officer.citizenid] then
        _unitPositions[officer.citizenid].status = status
    end
    MySQL.update.await('UPDATE mdt_officers SET status = ? WHERE citizenid = ?', { status, officer.citizenid })
    if MdtDispatchBridge and MdtDispatchBridge.IsExternal() then
        MdtDispatchBridge.Call('setUnitStatus', source, status)
    end
    BroadcastUnits()   -- rebroadcast so the roster/map update live
    return true
end)

-- ─── Department Statistics ───────────────────────────────────────────────────
-- Totals and a per-day series go to every officer; the per-officer leaderboard
-- stays with supervisors, because "who arrested the least this week" pinned on
-- everyone's dashboard is a drama machine.

lib.callback.register('XS-MDT:server:getDepartmentStats', function(source, data)
    if not HasPanel(source, 'arrests') then return nil end
    local officer = GetOfficerInfo(source)
    if not officer then return nil end

    local isSupervisor = officer.grade >= Dept.SupervisorGrade(officer.job)

    -- 7 or 30 days; anything else falls back to 7.
    local days = (type(data) == 'table' and tonumber(data.range) == 30) and 30 or 7

    local function countSince(tbl)
        return MySQL.scalar.await(
            ('SELECT COUNT(*) FROM %s WHERE created_at >= DATE_SUB(NOW(), INTERVAL %d DAY)'):format(tbl, days)) or 0
    end

    local fine_arrests = MySQL.scalar.await(
        ('SELECT COALESCE(SUM(fine),0) FROM mdt_arrests WHERE created_at >= DATE_SUB(NOW(), INTERVAL %d DAY)'):format(days)) or 0
    local fine_citations = MySQL.scalar.await(
        ('SELECT COALESCE(SUM(fine),0) FROM mdt_citations WHERE created_at >= DATE_SUB(NOW(), INTERVAL %d DAY)'):format(days)) or 0

    -- One row per day per table, merged into a dense series here — a day with
    -- nothing still appears, because a gap in a bar chart IS the information.
    local function daily(tbl)
        local rows = MySQL.query.await(
            ('SELECT DATE(created_at) AS d, COUNT(*) AS n FROM %s WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL %d DAY) GROUP BY DATE(created_at)'):format(tbl, days - 1)) or {}
        local byDay = {}
        for _, r in ipairs(rows) do byDay[tostring(r.d):sub(1, 10)] = r.n end
        return byDay
    end

    local arrestsBy = daily('mdt_arrests')
    local citationsBy = daily('mdt_citations')

    local series = {}
    for i = days - 1, 0, -1 do
        local day = os.date('%Y-%m-%d', os.time() - i * 86400)
        series[#series + 1] = {
            day = day,
            arrests = arrestsBy[day] or 0,
            citations = citationsBy[day] or 0,
        }
    end

    local stats = {
        range           = days,
        arrests         = countSince('mdt_arrests'),
        citations       = countSince('mdt_citations'),
        incidents       = countSince('mdt_incidents'),
        arrests_today   = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_arrests   WHERE DATE(created_at) = CURDATE()") or 0,
        citations_today = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_citations WHERE DATE(created_at) = CURDATE()") or 0,
        warrants_active = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_warrants WHERE status = 'active'") or 0,
        bolos_active    = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_bolos WHERE active = 1") or 0,
        fines           = fine_arrests + fine_citations,
        series          = series,
        isSupervisor    = isSupervisor,
    }

    if isSupervisor then
        stats.top_officers = MySQL.query.await(([[
            SELECT officer_name, COUNT(*) as arrest_count
            FROM mdt_arrests
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL %d DAY)
            GROUP BY officer_citizenid, officer_name
            ORDER BY arrest_count DESC
            LIMIT 5
        ]]):format(days), {})
    end

    return stats
end)
