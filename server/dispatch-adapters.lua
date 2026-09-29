local Adapters = {}

local JOB_TYPES = { police = 'leo', ems = 'ems', fire = 'fire' }

local function Vec(c)
    return vector3((tonumber(c.x) or 0.0) + 0.0, (tonumber(c.y) or 0.0) + 0.0, (tonumber(c.z) or 0.0) + 0.0)
end

local function Code(call)
    return call.code or '10-90'
end

local function Details(call)
    local text = call.description or call.label
    if call.street and call.street ~= '' then return ('%s — %s'):format(text, call.street) end
    return text
end

local function Colour(call)
    return call.priority == 1 and 1 or 5
end

local function OnDutyWithJobs(jobs)
    local wanted, out = {}, {}
    for _, j in ipairs(jobs or {}) do wanted[j] = true end
    for src, p in pairs(Framework.GetPlayers()) do
        local job = p.PlayerData and p.PlayerData.job
        if job and wanted[job.name] and (not Config.OnDutyOnly or job.onduty) then
            out[#out + 1] = tonumber(src)
        end
    end
    return out
end

Adapters['ps-dispatch'] = function(call, res)
    local jobs, seen = {}, {}
    for _, j in ipairs(call.jobs or {}) do
        jobs[#jobs + 1] = j
        local t = JOB_TYPES[Dept.OfJob(j) or '']
        if t and not seen[t] then seen[t] = true end
    end
    for t in pairs(seen) do jobs[#jobs + 1] = t end

    local alert = {
        message     = call.label,
        codeName    = 'mdt_call',
        code        = Code(call),
        icon        = 'fas fa-bullhorn',
        priority    = call.priority == 1 and 1 or 2,
        coords      = Vec(call.coords),
        street      = call.street,
        information = call.description,
        jobs        = jobs,
        addToList   = true,
        alert = {
            radius = 0, sprite = 60, color = Colour(call), scale = 1.0, length = 3,
            sound = 'Lose_1st', sound2 = 'GTAO_FM_Events_Soundset', offset = false, flash = call.priority == 1,
        },
    }

    local sent = pcall(function()
        exports[res]:SendTargetedAlert(OnDutyWithJobs(call.jobs), alert)
    end)
    if not sent then
        TriggerEvent('ps-dispatch:server:notify', alert)
    end
end

Adapters['qs-dispatch'] = function(call)
    TriggerEvent('qs-dispatch:server:CreateDispatchCall', {
        job          = call.jobs,
        callLocation = Vec(call.coords),
        callCode     = { code = Code(call), snippet = call.label },
        message      = Details(call),
        flashes      = call.priority == 1,
        image        = nil,
        blip = {
            sprite  = 60,
            scale   = 1.0,
            colour  = Colour(call),
            flashes = call.priority == 1,
            text    = call.label,
            time    = 180000,
        },
    })
end

Adapters['cd_dispatch'] = function(call)
    TriggerClientEvent('cd_dispatch:AddNotification', -1, {
        job_table = call.jobs,
        coords    = Vec(call.coords),
        title     = ('%s - %s'):format(Code(call), call.label),
        message   = Details(call),
        flash     = call.priority == 1 and 1 or 0,
        unique_id = tostring(math.random(1000000, 9999999)),
        sound     = call.callType == 'PANIC' and 3 or 1,
        blip = {
            sprite  = 60,
            scale   = 1.0,
            colour  = Colour(call),
            flashes = call.priority == 1,
            text    = call.label,
            time    = 3,
            radius  = 0,
        },
    })
end

Adapters['core_dispatch'] = function(call, res)
    local extra = { { icon = 'fa-comment', info = call.description or call.label } }
    if call.street and call.street ~= '' then
        extra[#extra + 1] = { icon = 'fa-map-marker-alt', info = call.street }
    end
    local urgent = call.priority == 1

    local sent = pcall(function()
        exports[res]:sendAlert({
            code      = Code(call),
            message   = call.label,
            extraInfo = extra,
            coords    = Vec(call.coords),
            priority  = urgent,
            job       = call.jobs,
            time      = 10000,
            blip      = 60,
            color     = Colour(call),
        })
    end)
    if sent then return end

    local c = Vec(call.coords)
    for _, job in ipairs(call.jobs or {}) do
        TriggerEvent('core_dispatch:addCall', Code(call), call.label, extra, { c.x, c.y, c.z }, job, 10000, 60, Colour(call), urgent)
    end
end

Adapters['rcore_dispatch'] = function(call)
    TriggerEvent('rcore_dispatch:server:sendAlert', {
        code             = ('%s - %s'):format(Code(call), call.label),
        default_priority = call.priority == 1 and 'high' or call.priority == 3 and 'low' or 'medium',
        coords           = Vec(call.coords),
        job              = call.jobs,
        text             = Details(call),
        type             = 'alerts',
        blip = {
            sprite  = 60,
            colour  = Colour(call),
            scale   = 1.0,
            text    = call.label,
            flashes = call.priority == 1,
            radius  = 0,
        },
    })
end

Adapters['linden_outlawalert'] = function(call)
    TriggerEvent('wf-alerts:svNotify', {
        dispatchData = {
            displayCode   = Code(call),
            description   = call.label,
            isImportant   = call.priority == 1 and 1 or 0,
            recipientList = call.jobs,
            length        = 10000,
            infoM         = 'fa-info-circle',
            info          = call.description,
            infoM2        = call.street and 'fa-map-marker-alt' or nil,
            info2         = call.street,
            blipSprite    = 60,
            blipColour    = Colour(call),
            blipScale     = 1.0,
        },
        caller = call.caller or 'Dispatch',
        coords = Vec(call.coords),
    })
end

local alertsOn, callsOn, running = {}, {}, {}

MdtMirroring = false

local function Squash(s) return ((s or ''):lower():gsub('[^%w]', '')) end

local function Find(id)
    local named = Config.DispatchAlertResources and Config.DispatchAlertResources[id]
    if named then return GetResourceState(named) == 'started' and named or nil end

    if GetResourceState(id) == 'started' then return id end

    local want, loose = Squash(id), nil
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and GetResourceState(name) == 'started' then
            if name:lower() == id:lower() then return name end
            if not loose and Squash(name):sub(1, #want) == want then loose = name end
        end
    end
    return loose
end

local function Pick(setting)
    local out = {}
    if setting == false or setting == 'off' then return out end
    if type(setting) == 'table' then
        for _, id in ipairs(setting) do
            if Adapters[id] and running[id] then out[#out + 1] = id end
        end
    else
        for id in pairs(Adapters) do
            if running[id] then out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end

local function Names(list)
    local names = {}
    for _, id in ipairs(list) do
        names[#names + 1] = running[id] == id and id or ('%s (%s)'):format(id, running[id])
    end
    return table.concat(names, ', ')
end

local lastReport

local function Resolve()
    running = {}
    for id in pairs(Adapters) do running[id] = Find(id) end

    local alerts, calls = Pick(Config.DispatchAlerts), Pick(Config.DispatchCalls)
    alertsOn, callsOn = {}, {}
    for _, id in ipairs(alerts) do alertsOn[id] = true end
    for _, id in ipairs(calls) do callsOn[id] = true end

    GlobalState['xs-mdt:feed'] = #calls > 0 and not MdtDispatchBridge.IsExternal()

    local report = Names(alerts) .. '|' .. Names(calls)
    if report == lastReport then return end
    lastReport = report
    if #alerts > 0 then print(('[XS-MDT] dispatch alerts going to: %s'):format(Names(alerts))) end
    if #calls > 0 then print(('[XS-MDT] taking dispatch calls from: %s'):format(Names(calls))) end
end

AddEventHandler('onResourceStart', function(name)
    if name == GetCurrentResourceName() then
        SetTimeout(2000, Resolve)
    else
        SetTimeout(500, Resolve)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then SetTimeout(500, Resolve) end
end)

function MdtDispatchFeeding(id)
    return callsOn[id] == true and running[id] ~= nil
end

function MdtDispatchAlerts(call)
    if not next(alertsOn) then return end
    if not call or not call.coords then return end

    for id in pairs(alertsOn) do
        MdtMirroring = true
        local ok, err = pcall(Adapters[id], call, running[id] or id)
        MdtMirroring = false
        if not ok then
            print(('[XS-MDT] %s rejected the alert (%s). The adapter in server/dispatch-adapters.lua may need its fields adjusting for your version.'):format(id, err))
        end
    end
end

exports('SendDispatchAlert', function(call) return MdtDispatchAlerts(call) end)

exports('GetDispatchAlertTargets', function()
    local out = {}
    for id in pairs(Adapters) do
        local res = Find(id)
        out[#out + 1] = {
            id = id, resource = res, started = res ~= nil,
            enabled = alertsOn[id] == true, feeding = callsOn[id] == true,
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)
