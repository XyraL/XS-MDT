-- Licence status.
--
-- Qbox stores whether a character holds a licence as a boolean in
-- metadata.licences. That answers "do they have one" and nothing else, so an
-- officer at a traffic stop cannot tell a clean licence from one suspended an
-- hour ago, or see why.
--
-- This keeps the missing half: status, reason, who changed it, and when. The
-- two are merged on read — Qbox says whether it exists, this says what state
-- it is in.
local IsAuthorized  = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel      = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local IsSupervisor  = function(src) return exports['XS-MDT']:IsSupervisor(src) end
local GetOfficer    = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end
local AuditLog      = function(a, o, d) exports['XS-MDT']:AuditLog(a, o, d) end

local VALID_STATUS = { valid = true, suspended = true, revoked = true }

-- Qbox spells it "licences"; some builds and older forks use "licenses". Read
-- whichever is present rather than making the server operator care.
local function MetaLicences(player)
    if not player then return nil, nil end
    local meta = player.PlayerData and player.PlayerData.metadata
    if not meta then return nil, nil end
    if meta.licences then return meta.licences, 'licences' end
    if meta.licenses then return meta.licenses, 'licenses' end
    return nil, nil
end

-- Everything the profile needs for one citizen, one row per configured type.
local function BuildLicences(citizenid)
    if not Config.Licences or not Config.Licences.Enabled then return {} end

    local overrides = {}
    local rows = MySQL.query.await('SELECT * FROM mdt_licences WHERE citizenid = ?', { citizenid }) or {}
    for _, row in ipairs(rows) do overrides[row.type] = row end

    -- Online players carry live metadata; offline ones are read from the
    -- players table so a lookup works whether or not they are connected.
    local held = {}
    local ok, player = pcall(function() return exports.qbx_core:GetPlayerByCitizenId(citizenid) end)
    if not ok then player = nil end
    local meta = MetaLicences(player)

    if meta then
        held = meta
    else
        local row = MySQL.single.await('SELECT metadata FROM players WHERE citizenid = ?', { citizenid })
        if row and row.metadata then
            local ok, decoded = pcall(json.decode, row.metadata)
            if ok and decoded then held = decoded.licences or decoded.licenses or {} end
        end
    end

    local out = {}
    for _, spec in ipairs(Config.Licences.Types) do
        local override = overrides[spec.key]
        out[#out + 1] = {
            key       = spec.key,
            label     = spec.label,
            icon      = spec.icon,
            held      = held[spec.key] and true or false,
            status    = override and override.status or 'valid',
            reason    = override and override.reason or nil,
            changed_by_name = override and override.changed_by_name or nil,
            changed_at      = override and override.changed_at or nil,
        }
    end
    return out
end

exports('GetLicences', BuildLicences)

lib.callback.register('XS-MDT:server:getLicences', function(source, citizenid)
    if not HasPanel(source, 'civilians') then return nil end
    if not citizenid then return nil end
    return BuildLicences(citizenid)
end)

lib.callback.register('XS-MDT:server:setLicenceStatus', function(source, data)
    if not IsAuthorized(source) then return { ok = false, error = 'Not authorised' } end
    if not HasPanel(source, 'civilians') then return { ok = false, error = 'Not authorised' } end
    if not Config.Licences or not Config.Licences.Enabled then return { ok = false, error = 'Licences are disabled' } end

    if type(data) ~= 'table' or not data.citizenid or not data.type then
        return { ok = false, error = 'Missing citizen or licence type' }
    end
    if not VALID_STATUS[data.status] then return { ok = false, error = 'Unknown status' } end

    -- Only types the server actually configured, so a crafted NUI message
    -- cannot invent a licence.
    local spec
    for _, t in ipairs(Config.Licences.Types) do
        if t.key == data.type then
            spec = t
            break
        end
    end
    if not spec then return { ok = false, error = 'Unknown licence type' } end

    if data.status == 'revoked' and Config.Licences.RevokeRequiresSupervisor and not IsSupervisor(source) then
        return { ok = false, error = 'Revoking requires a supervisor' }
    end

    local officer = GetOfficer(source)
    if not officer then return { ok = false, error = 'No officer record' } end

    local reason = data.reason and tostring(data.reason):sub(1, 500) or nil
    if data.status ~= 'valid' and (not reason or reason == '') then
        return { ok = false, error = 'A reason is required' }
    end

    MySQL.insert.await([[
        INSERT INTO mdt_licences (citizenid, type, status, reason, changed_by, changed_by_name)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE status = VALUES(status), reason = VALUES(reason),
            changed_by = VALUES(changed_by), changed_by_name = VALUES(changed_by_name)
    ]], { data.citizenid, data.type, data.status, reason, officer.citizenid, officer.name })

    -- Mirror into Qbox so anything else that gates on the licence agrees with
    -- what the MDT is showing. Only touches players who actually hold one —
    -- reinstating must not hand out a licence that was never earned.
    if Config.Licences.WriteBackToMetadata then
        local okPlayer, player = pcall(function() return exports.qbx_core:GetPlayerByCitizenId(data.citizenid) end)
        if not okPlayer then player = nil end
        local meta, field = MetaLicences(player)
        if player and meta and meta[data.type] ~= nil then
            meta[data.type] = (data.status == 'valid')
            player.Functions.SetMetaData(field, meta)
        end
    end

    AuditLog('Licence ' .. data.status, officer.name,
        ('%s licence for %s — %s'):format(spec.label, data.citizenid, reason or 'reinstated'))

    return { ok = true }
end)
