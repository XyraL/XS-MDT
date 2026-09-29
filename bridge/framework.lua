--[[ Framework bridge.

     The MDT was written against qbx_core directly — 40 call sites across the
     server, which is why it was the only script in the line that would not run
     on QBCore. The two frameworks agree on the shape that matters here
     (PlayerData.citizenid, .charinfo, .job.name, .job.grade.level, .job.onduty),
     so the bridge is thin: it is the entry points that differ, not the data.

     Everything above returns plain values rather than a player object wherever
     it can. A caller that only wants a citizenid should not have to know which
     framework it came from, or handle the object being nil. ]]

Framework = { name = nil, core = nil }

local function detect()
    local forced = Config.Framework

    if forced == 'qbox' or forced == 'qbcore' then return forced end

    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end

    return nil
end

Framework.name = detect()

if Framework.name == 'qbcore' then
    -- QBCore hands its whole API over in one object; qbx exposes exports.
    Framework.core = exports['qb-core']:GetCoreObject()
elseif not Framework.name then
    print('^1[XS-MDT]^0 No supported framework found. Start qbx_core or qb-core before XS-MDT.')
end

-- ── Server ──────────────────────────────────────────────────────────────────

if IsDuplicityVersion() then
    function Framework.GetPlayer(src)
        if Framework.name == 'qbox' then return exports.qbx_core:GetPlayer(src) end
        if Framework.name == 'qbcore' then return Framework.core.Functions.GetPlayer(src) end
        return nil
    end

    function Framework.GetPlayerByCitizenId(cid)
        if not cid then return nil end
        if Framework.name == 'qbox' then return exports.qbx_core:GetPlayerByCitizenId(cid) end
        if Framework.name == 'qbcore' then return Framework.core.Functions.GetPlayerByCitizenId(cid) end
        return nil
    end

    --[[ Every loaded player.

         qbx returns a table keyed by source; qb-core's GetQBPlayers does the
         same on current builds but older forks only have GetPlayers, which
         returns a list of ids. Both are normalised to { [src] = player } so
         callers can pairs() over it without caring. ]]
    function Framework.GetPlayers()
        if Framework.name == 'qbox' then
            return exports.qbx_core:GetQBPlayers() or {}
        end

        if Framework.name == 'qbcore' then
            local fn = Framework.core.Functions

            if fn.GetQBPlayers then return fn.GetQBPlayers() or {} end

            local out = {}
            for _, id in pairs(fn.GetPlayers() or {}) do
                local player = fn.GetPlayer(tonumber(id))
                if player then out[tonumber(id)] = player end
            end
            return out
        end

        return {}
    end

    function Framework.GetCitizenId(src)
        local player = Framework.GetPlayer(src)
        return player and player.PlayerData and player.PlayerData.citizenid or nil
    end

    function Framework.GetName(src)
        local player = Framework.GetPlayer(src)
        local ci = player and player.PlayerData and player.PlayerData.charinfo
        if not ci then return 'Unknown' end
        return ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    end

    --[[ The job, flattened.

         Callers want name / grade / grade label / on duty, and reaching into
         PlayerData.job.grade.level at 40 sites is how a framework leaks back
         into the resource. Returns nil rather than a blank table when there is
         no player, because "no player" and "unemployed" are different answers. ]]
    function Framework.GetJob(src)
        local player = Framework.GetPlayer(src)
        local job = player and player.PlayerData and player.PlayerData.job
        if not job then return nil end

        return {
            name       = job.name,
            label      = job.label,
            grade      = (job.grade and job.grade.level) or 0,
            gradeLabel = (job.grade and job.grade.name) or '',
            onduty     = job.onduty and true or false,
            isboss     = (job.isboss or (job.grade and job.grade.isboss)) and true or false,
        }
    end

    --[[ Set somebody's job grade. This is what the roster's rank change writes.

         Both frameworks refuse silently for an offline player — the object
         simply is not there — which is why the panel says the officer has to be
         online rather than letting somebody promote into the void. ]]
    function Framework.SetJob(src, name, grade)
        grade = tonumber(grade) or 0

        if Framework.name == 'qbox' then
            local ok = pcall(function() exports.qbx_core:SetJob(src, name, grade) end)
            return ok
        end

        if Framework.name == 'qbcore' then
            local player = Framework.GetPlayer(src)
            if not player then return false end

            local ok = pcall(function() player.Functions.SetJob(name, grade) end)
            return ok
        end

        return false
    end

    --[[ The grades a job defines, as an ordered list.

         The rank picker is built from this rather than from a list in our own
         config: a server that renamed its ranks should see its own names, and
         a grade that does not exist should not be offerable. Shapes differ —
         qbx keys grades by number with a `name`, qb-core uses `label` — so both
         are read defensively. ]]
    function Framework.GetJobGrades(name)
        if not name then return {} end

        local shared
        if Framework.name == 'qbox' then
            shared = (exports.qbx_core:GetJobs() or {})[name]
        elseif Framework.name == 'qbcore' then
            shared = (Framework.core.Shared.Jobs or {})[name]
        end

        local grades = shared and shared.grades
        if not grades then return {} end

        local out = {}
        for level, grade in pairs(grades) do
            out[#out + 1] = {
                grade  = tonumber(level) or 0,
                label  = grade.name or grade.label or ('Grade %s'):format(level),
                isboss = grade.isboss and true or false,
            }
        end

        table.sort(out, function(a, b) return a.grade < b.grade end)
        return out
    end

    function Framework.Notify(src, message, kind)
        if Framework.name == 'qbox' then
            TriggerClientEvent('ox_lib:notify', src, { description = message, type = kind or 'inform' })
            return
        end

        if Framework.name == 'qbcore' then
            TriggerClientEvent('QBCore:Notify', src, message, kind == 'error' and 'error' or kind == 'success' and 'success' or 'primary')
        end
    end

    local vehicleNames

    function Framework.VehicleLabel(model)
        if type(model) ~= 'string' or model == '' then return nil end
        if not vehicleNames then
            local ok, list = pcall(function()
                if Framework.name == 'qbox' then return exports.qbx_core:GetVehiclesByName() end
                if Framework.name == 'qbcore' then return Framework.core.Shared.Vehicles end
            end)
            if not ok or type(list) ~= 'table' then return nil end
            vehicleNames = list
        end
        local v = vehicleNames[model] or vehicleNames[model:lower()]
        if type(v) ~= 'table' or type(v.name) ~= 'string' then return nil end
        if type(v.brand) == 'string' and v.brand ~= '' then return v.brand .. ' ' .. v.name end
        return v.name
    end

    return
end

-- ── Client ──────────────────────────────────────────────────────────────────

function Framework.GetPlayerData()
    if Framework.name == 'qbox' then return exports.qbx_core:GetPlayerData() end
    if Framework.name == 'qbcore' then return Framework.core.Functions.GetPlayerData() end
    return nil
end

function Framework.GetJob()
    local data = Framework.GetPlayerData()
    local job = data and data.job
    if not job then return nil end

    return {
        name       = job.name,
        label      = job.label,
        grade      = (job.grade and job.grade.level) or 0,
        gradeLabel = (job.grade and job.grade.name) or '',
        onduty     = job.onduty and true or false,
    }
end

function Framework.Notify(message, kind)
    if Framework.name == 'qbox' then
        lib.notify({ description = message, type = kind or 'inform' })
        return
    end

    if Framework.name == 'qbcore' then
        TriggerEvent('QBCore:Notify', message, kind == 'error' and 'error' or kind == 'success' and 'success' or 'primary')
    end
end
