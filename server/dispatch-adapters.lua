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

      Adding your own:

          Adapters['my-dispatch'] = function(call)
              exports['my-dispatch']:Alert({
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

--[[ ps-dispatch (Project Sloth)

     Server export taking one table. dispatchCode is the short code shown in
     the alert header; radius 0 means the blip sits on the coords rather than
     covering an area. ]]
Adapters['ps-dispatch'] = function(call)
    exports['ps-dispatch']:CustomAlert({
        coords       = call.coords,
        job          = call.jobs,
        displayCode  = call.code or '10-90',
        description  = call.description,
        message      = call.street and ('%s — %s'):format(call.label, call.street) or call.label,
        radius       = 0,
        sprite       = 60,
        color        = call.priority == 1 and 1 or 5,
        scale        = 1.0,
        length       = 3,
        alert        = { radius = 0, recipientList = call.jobs, sprite = 60, color = call.priority == 1 and 1 or 5, scale = 1.0, length = 3 },
    })
end

--[[ qs-dispatch (Quasar)

     Same idea, different field names. `code` rather than displayCode, and the
     blip block is flat. ]]
Adapters['qs-dispatch'] = function(call)
    exports['qs-dispatch']:CustomAlert({
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

local enabled = {}

--[[ Which adapters are on.

     'auto' turns on every adapter whose resource is started, which is what a
     server owner expects and needs no config. A list names them explicitly,
     and false turns the whole thing off. ]]
local function Resolve()
    enabled = {}
    local setting = Config.DispatchAlerts

    if setting == false or setting == 'off' then return end

    if type(setting) == 'table' then
        for _, id in ipairs(setting) do
            if Adapters[id] then enabled[#enabled + 1] = id end
        end
    else
        for id in pairs(Adapters) do
            if GetResourceState(id) == 'started' then enabled[#enabled + 1] = id end
        end
    end

    table.sort(enabled)
    if #enabled > 0 then
        print(('[XS-MDT] dispatch alerts going to: %s'):format(table.concat(enabled, ', ')))
    end
end

AddEventHandler('onResourceStart', function(name)
    if name == GetCurrentResourceName() then
        -- Resolve after everything else has had a chance to start.
        SetTimeout(2000, Resolve)
    elseif Adapters[name] then
        Resolve()
    end
end)

AddEventHandler('onResourceStop', function(name)
    if Adapters[name] then Resolve() end
end)

--[[ Send a call to every enabled dispatch resource.

     Called by server/dispatch.lua when a CAD call is created. Wrapped per
     adapter: a resource with a different signature than the one written above
     logs a line and the others still fire. ]]
function MdtDispatchAlerts(call)
    if #enabled == 0 then return end
    if not call or not call.coords then return end

    for _, id in ipairs(enabled) do
        local ok, err = pcall(Adapters[id], call)
        if not ok then
            print(('[XS-MDT] %s rejected the alert (%s). The adapter in server/dispatch-adapters.lua may need its fields adjusting for your version.'):format(id, err))
        end
    end
end

exports('SendDispatchAlert', function(call) return MdtDispatchAlerts(call) end)

--[[ Which adapters are live, for the management panel. ]]
exports('GetDispatchAlertTargets', function()
    local out = {}
    for id in pairs(Adapters) do
        out[#out + 1] = { id = id, started = GetResourceState(id) == 'started', enabled = false }
    end
    for _, id in ipairs(enabled) do
        for _, row in ipairs(out) do if row.id == id then row.enabled = true end end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)
