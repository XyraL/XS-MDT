--[[  Outbound dispatch adapters

      server/integrations.lua handles the case where another resource REPLACES
      the CAD — the MDT asks it for calls and hands actions back. That is not
      what most servers want. Most servers want to keep the MDT's CAD as the
      record and ALSO have the alert pop up in whatever dispatch they already
      run, because half the department has that UI open and not this one.

      So: when the MDT creates a call, every enabled adapter below is handed
      the same call and sends it on in that resource's own shape.

      Each adapter is one function. If a resource changes its signature, the
      fix is visible and local — edit the function, not a table of strings —
      and a mismatch cannot take the MDT down, because every call is wrapped.
      The second argument is the name the resource is running under, which is
      not always the name it shipped with.

      Adding your own:

          Adapters['my-dispatch'] = function(call, res)
              exports[res]:Alert({
                  title = call.label, text = call.description,
                  coords = call.coords, jobs = call.jobs,
              })
          end

      `call` is:
          callType     'STORE_ROBBERY'
          label        'Store Robbery'
          description  what the caller reported
          coords       { x, y, z }
          street       street name, already resolved
          priority     1 high, 2 normal, 3 low
          callNumber   'CAD-20260926-004'
          jobs         { 'police', 'sheriff' } — the jobs being alerted
          caller       who reported it
]]

local Adapters = {}

local JOB_TYPES = { police = 'leo', ems = 'ems', fire = 'fire' }

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

--[[ ps-dispatch (Project Sloth)

     CustomAlert is a client export, so a server has to go another way. Current
     versions take SendTargetedAlert with the players to show it to; older ones
     only have their notify event. ]]
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
        code        = call.code or '10-90',
        icon        = 'fas fa-bullhorn',
        priority    = call.priority == 1 and 1 or 2,
        coords      = vector3(call.coords.x + 0.0, call.coords.y + 0.0, (call.coords.z or 0.0) + 0.0),
        street      = call.street,
        information = call.description,
        jobs        = jobs,
        addToList   = true,
        alert = {
            radius = 0, sprite = 60, color = call.priority == 1 and 1 or 5, scale = 1.0, length = 3,
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

--[[ qs-dispatch (Quasar)

     Same idea, different field names. `code` rather than displayCode, and the
     blip block is flat. ]]
Adapters['qs-dispatch'] = function(call, res)
    exports[res]:CustomAlert({
        coords      = call.coords,
        job         = call.jobs,
        code        = call.code or '10-90',
        title       = call.label,
        message     = call.description,
        street      = call.street,
        blip = {
            sprite  = 60,
            scale   = 1.0,
            colour  = call.priority == 1 and 1 or 5,
            flashes = call.priority == 1,
            text    = call.label,
            time    = 3,
        },
    })
end

--[[ cd_dispatch

     A server event rather than an export, and it wants the job list as a
     table of job names. unique_id keeps repeat alerts from stacking. ]]
Adapters['cd_dispatch'] = function(call)
    TriggerEvent('cd_dispatch:AddNotification', {
        job_table    = call.jobs,
        coords       = call.coords,
        title        = call.code or '10-90',
        message      = call.street and ('%s — %s'):format(call.description, call.street) or call.description,
        flash        = call.priority == 1 and 1 or 0,
        unique_id    = call.callNumber,
        sound        = 1,
        blip = {
            sprite    = 60,
            scale     = 1.0,
            colour    = call.priority == 1 and 1 or 5,
            flashes   = call.priority == 1,
            text      = call.label,
            time      = 3,
        },
    })
end

--[[ core_dispatch

     Positional arguments, not a table. Length is in minutes. ]]
Adapters['core_dispatch'] = function(call)
    TriggerEvent('core_dispatch:addCall',
        call.code or '10-90',
        call.label,
        { { icon = 'fa-user', info = call.caller or 'Caller' },
          { icon = 'fa-comment', info = call.description } },
        { call.coords.x, call.coords.y, call.coords.z },
        call.jobs,
        3,
        60,
        call.priority == 1 and 1 or 5)
end

--[[ linden_outlawalert

     Takes a dispatchData block with its own display fields. ]]
Adapters['linden_outlawalert'] = function(call)
    TriggerEvent('wf-alerts:svNotify', {
        dispatchData = {
            displayCode = call.code or '10-90',
            description = call.description,
            isImportant = call.priority == 1 and 1 or 0,
            recipientList = call.jobs,
            length = '3',
            infoM = 'fa-info-circle',
            information = call.street or call.label,
        },
        caller = call.caller or 'Dispatch',
        coords = call.coords,
    })
end

-- ── Wiring ────────────────────────────────────────────────────────────────

local enabled, running = {}, {}

local function Squash(s) return ((s or ''):lower():gsub('[^%w]', '')) end

--[[ The name a dispatch is running under. A download from GitHub unzips as
     ps-dispatch-main, and plenty of servers rename theirs, so an exact match
     alone missed installs that were up and running. ]]
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

--[[ Which adapters are on.

     'auto' turns on every adapter whose resource is started, which is what a
     server owner expects and needs no config. A list names them explicitly,
     and false turns the whole thing off. ]]
local function Resolve()
    enabled, running = {}, {}
    for id in pairs(Adapters) do running[id] = Find(id) end

    local setting = Config.DispatchAlerts
    if setting == false or setting == 'off' then return end

    if type(setting) == 'table' then
        for _, id in ipairs(setting) do
            if Adapters[id] and running[id] then enabled[#enabled + 1] = id end
        end
    else
        for id in pairs(Adapters) do
            if running[id] then enabled[#enabled + 1] = id end
        end
    end

    table.sort(enabled)
    if #enabled > 0 then
        local names = {}
        for _, id in ipairs(enabled) do
            names[#names + 1] = running[id] == id and id or ('%s (%s)'):format(id, running[id])
        end
        print(('[XS-MDT] dispatch alerts going to: %s'):format(table.concat(names, ', ')))
    end
end

AddEventHandler('onResourceStart', function(name)
    if name == GetCurrentResourceName() then
        -- Resolve after everything else has had a chance to start.
        SetTimeout(2000, Resolve)
    else
        SetTimeout(500, Resolve)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then SetTimeout(500, Resolve) end
end)

--[[ Send a call to every enabled dispatch resource.

     Called by server/dispatch.lua when a CAD call is created. Wrapped per
     adapter: a resource with a different signature than the one written above
     logs a line and the others still fire. ]]
function MdtDispatchAlerts(call)
    if #enabled == 0 then return end
    if not call or not call.coords then return end

    for _, id in ipairs(enabled) do
        local ok, err = pcall(Adapters[id], call, running[id] or id)
        if not ok then
            print(('[XS-MDT] %s rejected the alert (%s). The adapter in server/dispatch-adapters.lua may need its fields adjusting for your version.'):format(id, err))
        end
    end
end

exports('SendDispatchAlert', function(call) return MdtDispatchAlerts(call) end)

--[[ Which adapters are live, for the management panel. ]]
exports('GetDispatchAlertTargets', function()
    local on = {}
    for _, id in ipairs(enabled) do on[id] = true end

    local out = {}
    for id in pairs(Adapters) do
        local res = Find(id)
        out[#out + 1] = { id = id, resource = res, started = res ~= nil, enabled = on[id] == true }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)
