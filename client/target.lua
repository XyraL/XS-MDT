if not Config.Target.Enabled then return end

local mdtOpen = false  -- shadow from main.lua (updated via event)

-- Target options are registered once at start, so each needs its own runtime
-- check: without one every player — civilians included — sees "Issue Citation"
-- on anyone they aim at.
local function CanUse(panel)
    local pd = exports['qbx_core']:GetPlayerData()
    if not pd or not pd.job then return false end
    if Config.OnDutyOnly and not pd.job.onduty then return false end
    return Dept.HasPanel(pd.job.name, panel)
end

AddEventHandler('XS-MDT:client:mdtStateChanged', function(state)
    mdtOpen = state
end)

CreateThread(function()
    local hasOxTarget = GetResourceState('ox_target') == 'started'
    local hasQBTarget = GetResourceState('qb-target') == 'started'
    if not hasOxTarget and not hasQBTarget then return end

    if hasOxTarget then
        -- ox_target: flat array of option tables, each needs a unique `name`
        exports.ox_target:addGlobalPlayer({
            {
                name     = 'xs_view_profile',
                label    = 'View MDT Profile',
                icon     = 'fas fa-id-card',
                distance = Config.Target.MaxDistance,
                canInteract = function() return CanUse('civilians') end,
                onSelect = function(data)
                    local playerId = GetPlayerFromEntity(data.entity)
                    if playerId == -1 then return end
                    TriggerServerEvent('XS-MDT:server:targetOpenProfile', GetPlayerServerId(playerId))
                end,
            },
            {
                name     = 'xs_issue_citation',
                label    = 'Issue Citation',
                icon     = 'fas fa-file-alt',
                distance = Config.Target.MaxDistance,
                canInteract = function() return CanUse('citations') end,
                onSelect = function(data)
                    local playerId = GetPlayerFromEntity(data.entity)
                    if playerId == -1 then return end
                    TriggerServerEvent('XS-MDT:server:targetQuickCitation', GetPlayerServerId(playerId))
                end,
            },
            {
                name     = 'xs_run_name',
                label    = 'Run Name Check',
                icon     = 'fas fa-search',
                distance = Config.Target.MaxDistance,
                canInteract = function() return CanUse('warrants') end,
                onSelect = function(data)
                    local playerId = GetPlayerFromEntity(data.entity)
                    if playerId == -1 then return end
                    TriggerServerEvent('XS-MDT:server:targetRunName', GetPlayerServerId(playerId))
                end,
            },
        })
    elseif hasQBTarget then
        -- qb-target: options wrapped in a table with `options` and `distance` keys
        exports['qb-target']:AddGlobalPlayer({
            options = {
                {
                    label  = 'View MDT Profile',
                    icon   = 'fas fa-id-card',
                    canInteract = function() return CanUse('civilians') end,
                    action = function(entity)
                        local playerId = GetPlayerFromEntity(entity)
                        if playerId == -1 then return end
                        TriggerServerEvent('XS-MDT:server:targetOpenProfile', GetPlayerServerId(playerId))
                    end,
                },
                {
                    label  = 'Issue Citation',
                    icon   = 'fas fa-file-alt',
                    canInteract = function() return CanUse('citations') end,
                    action = function(entity)
                        local playerId = GetPlayerFromEntity(entity)
                        if playerId == -1 then return end
                        TriggerServerEvent('XS-MDT:server:targetQuickCitation', GetPlayerServerId(playerId))
                    end,
                },
                {
                    label  = 'Run Name Check',
                    icon   = 'fas fa-search',
                    canInteract = function() return CanUse('warrants') end,
                    action = function(entity)
                        local playerId = GetPlayerFromEntity(entity)
                        if playerId == -1 then return end
                        TriggerServerEvent('XS-MDT:server:targetRunName', GetPlayerServerId(playerId))
                    end,
                },
            },
            distance = Config.Target.MaxDistance,
        })
    end
end)

-- Server sends back profile/citation data → open or auto-open MDT
RegisterNetEvent('XS-MDT:client:targetResult', function(civData, mode)
    if not civData then
        lib.notify({ title = 'XS-MDT', description = 'Player not found in database', type = 'error' })
        return
    end

    local pd = exports['qbx_core']:GetPlayerData()
    if not pd or not Config.AuthorizedJobs[pd.job.name] then
        lib.notify({ title = 'XS-MDT', description = 'Access denied', type = 'error' })
        return
    end

    if mdtOpen then
        SendNUIMessage({ action = 'targetResult', data = civData, mode = mode })
    else
        -- Auto-open MDT then navigate
        local officer = lib.callback.await('XS-MDT:server:open', false)
        if not officer then return end
        mdtOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openForTarget', officer = officer, data = civData, mode = mode })
    end
end)

-- Quick name check result — shown as in-game notification (no MDT needed)
RegisterNetEvent('XS-MDT:client:nameCheckResult', function(data)
    local warnText = data.warrants > 0
        and ('⚠ ' .. data.warrants .. ' ACTIVE WARRANT(S)')
        or  '✓ No active warrants'
    lib.notify({
        title       = 'Name Check — ' .. data.name,
        description = 'DOB: ' .. (data.dob or '—') .. '\n' .. warnText,
        type        = data.warrants > 0 and 'error' or 'success',
        duration    = 10000,
    })
end)
