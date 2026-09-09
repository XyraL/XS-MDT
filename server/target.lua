if not Config.Target.Enabled then return end

local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

-- Officer right-clicked a player → send back their civilian profile data to open in MDT
RegisterNetEvent('XS-MDT:server:targetOpenProfile')
AddEventHandler('XS-MDT:server:targetOpenProfile', function(targetSrc)
    local src = source
    if not HasPanel(src, 'civilians') then return end

    local targetPlayer = exports['qbx_core']:GetPlayer(targetSrc)
    if not targetPlayer then
        TriggerClientEvent('XS-MDT:client:targetResult', src, nil, 'profile')
        return
    end
    local pd = targetPlayer.PlayerData
    TriggerClientEvent('XS-MDT:client:targetResult', src, {
        citizenid = pd.citizenid,
        name      = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
        dob       = pd.charinfo.birthdate,
    }, 'profile')
end)

-- Officer right-clicked a player → quick citation pre-filled with their info
RegisterNetEvent('XS-MDT:server:targetQuickCitation')
AddEventHandler('XS-MDT:server:targetQuickCitation', function(targetSrc)
    local src = source
    if not HasPanel(src, 'citations') then return end

    local targetPlayer = exports['qbx_core']:GetPlayer(targetSrc)
    if not targetPlayer then return end
    local pd = targetPlayer.PlayerData
    TriggerClientEvent('XS-MDT:client:targetResult', src, {
        citizenid = pd.citizenid,
        name      = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
        dob       = pd.charinfo.birthdate,
    }, 'citation')
end)

-- Officer right-clicked a player → quick name/warrant check (no MDT needed)
RegisterNetEvent('XS-MDT:server:targetRunName')
AddEventHandler('XS-MDT:server:targetRunName', function(targetSrc)
    local src = source
    -- Returns a warrant count, so it gates on 'warrants' rather than 'civilians'
    -- — EMS has the civilian lookup but must not see criminal data.
    if not HasPanel(src, 'warrants') then return end

    local targetPlayer = exports['qbx_core']:GetPlayer(targetSrc)
    if not targetPlayer then return end
    local pd = targetPlayer.PlayerData
    local fullname = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
    local warrants = MySQL.scalar.await(
        "SELECT COUNT(*) FROM mdt_warrants WHERE citizenid = ? AND status = 'active'", { pd.citizenid }) or 0

    -- Notify requesting officer via lib.notify (works without MDT open)
    TriggerClientEvent('XS-MDT:client:nameCheckResult', src, {
        name     = fullname,
        dob      = pd.charinfo.birthdate,
        warrants = warrants,
    })
end)
