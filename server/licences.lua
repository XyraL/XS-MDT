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

local function OnlinePlayer(citizenid)
    local ok, player = pcall(function() return Framework.GetPlayerByCitizenId(citizenid) end)
    return ok and player or nil
end

-- What the character's metadata says they hold, online or not.
local function HeldList(citizenid)
    local meta = MetaLicences(OnlinePlayer(citizenid))
    if meta then return meta end

    local row = MySQL.single.await('SELECT metadata FROM players WHERE citizenid = ?', { citizenid })
    if row and row.metadata then
        local ok, decoded = pcall(json.decode, row.metadata)
        if ok and type(decoded) == 'table' then return decoded.licences or decoded.licenses or {} end
    end
    return {}
end

--[[ Set one licence flag on the character itself, so anything else on the
     server that checks the licence agrees with the MDT. Online players go
     through the framework; offline ones are written to the players table,
     which is what the framework loads them from next time. ]]
local function SetHeld(citizenid, key, value, onlyIfPresent)
    local player = OnlinePlayer(citizenid)
    if player then
        local meta, field = MetaLicences(player)
        if onlyIfPresent and (not meta or meta[key] == nil) then return false end
        meta = meta or {}
        meta[key] = value
        player.Functions.SetMetaData(field or 'licences', meta)
        return true
    end

    local row = MySQL.single.await('SELECT metadata FROM players WHERE citizenid = ?', { citizenid })
    if not row then return false end
    local ok, decoded = pcall(json.decode, row.metadata or '{}')
    if not ok or type(decoded) ~= 'table' then return false end

    local field = decoded.licences and 'licences' or decoded.licenses and 'licenses' or 'licences'
    decoded[field] = decoded[field] or {}
    if onlyIfPresent and decoded[field][key] == nil then return false end
    decoded[field][key] = value

    MySQL.update.await('UPDATE players SET metadata = ? WHERE citizenid = ?', { json.encode(decoded), citizenid })
    return true
end

-- Everything the profile needs for one citizen, one row per configured type.
local function BuildLicences(citizenid)
    if not Config.Licences or not Config.Licences.Enabled then return {} end

    local overrides = {}
    local rows = MySQL.query.await('SELECT * FROM mdt_licences WHERE citizenid = ?', { citizenid }) or {}
    for _, row in ipairs(rows) do overrides[row.type] = row end

    local held = HeldList(citizenid)

    local out = {}
    for _, spec in ipairs(Config.Licences.Types) do
        local override = overrides[spec.key]
        -- A suspension turns the metadata flag off, so the flag alone would
        -- read a suspended licence as one that was never held.
        local isHeld = held[spec.key] == true or (override ~= nil and override.status ~= 'valid')
        out[#out + 1] = {
            key       = spec.key,
            label     = spec.label,
            icon      = spec.icon,
            held      = isHeld,
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

local function SpecFor(key)
    for _, t in ipairs(Config.Licences.Types) do
        if t.key == key then return t end
    end
    return nil
end

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
    local spec = SpecFor(data.type)
    if not spec then return { ok = false, error = 'Unknown licence type' } end

    if data.status == 'revoked' and Config.Licences.RevokeRequiresSupervisor and not IsSupervisor(source) then
        return { ok = false, error = 'Revoking requires a supervisor' }
    end

    local officer = GetOfficer(source)
    if not officer then return { ok = false, error = 'No officer record' } end

    local reason = data.reason and tostring(data.reason):sub(1, 500) or nil
    if reason == '' then reason = nil end
    if data.status ~= 'valid' and not reason then
        return { ok = false, error = 'A reason is required' }
    end

    MySQL.insert.await([[
        INSERT INTO mdt_licences (citizenid, type, status, reason, changed_by, changed_by_name)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE status = VALUES(status), reason = VALUES(reason),
            changed_by = VALUES(changed_by), changed_by_name = VALUES(changed_by_name)
    ]], { data.citizenid, data.type, data.status, reason, officer.citizenid, officer.name })

    -- Only touches characters who actually hold one: reinstating must not hand
    -- out a licence that was never earned. Granting is the way to do that.
    if Config.Licences.WriteBackToMetadata then
        SetHeld(data.citizenid, data.type, data.status == 'valid', true)
    end

    AuditLog('Licence ' .. data.status, officer.name,
        ('%s licence for %s — %s'):format(spec.label, data.citizenid, reason or 'reinstated'))

    return { ok = true }
end)

lib.callback.register('XS-MDT:server:grantLicence', function(source, data)
    if not IsAuthorized(source) then return { ok = false, error = 'Not authorised' } end
    if not HasPanel(source, 'civilians') then return { ok = false, error = 'Not authorised' } end
    if not Config.Licences or not Config.Licences.Enabled then return { ok = false, error = 'Licences are disabled' } end
    if type(data) ~= 'table' or not data.citizenid or not data.type then
        return { ok = false, error = 'Missing citizen or licence type' }
    end

    local spec = SpecFor(data.type)
    if not spec then return { ok = false, error = 'Unknown licence type' } end

    if Config.Licences.GrantRequiresSupervisor and not IsSupervisor(source) then
        return { ok = false, error = 'Granting licences requires a supervisor' }
    end

    local officer = GetOfficer(source)
    if not officer then return { ok = false, error = 'No officer record' } end

    local exists = MySQL.scalar.await('SELECT citizenid FROM players WHERE citizenid = ?', { data.citizenid })
    if not exists then return { ok = false, error = 'No character with that citizen ID' } end

    if not SetHeld(data.citizenid, data.type, true, false) then
        return { ok = false, error = 'Could not update the character' }
    end

    local note = data.reason and tostring(data.reason):sub(1, 500) or nil
    if note == '' then note = nil end

    MySQL.insert.await([[
        INSERT INTO mdt_licences (citizenid, type, status, reason, changed_by, changed_by_name)
        VALUES (?, ?, 'valid', ?, ?, ?)
        ON DUPLICATE KEY UPDATE status = VALUES(status), reason = VALUES(reason),
            changed_by = VALUES(changed_by), changed_by_name = VALUES(changed_by_name)
    ]], { data.citizenid, data.type, note or 'Granted', officer.citizenid, officer.name })

    AuditLog('Licence granted', officer.name, ('%s licence for %s'):format(spec.label, data.citizenid))
    return { ok = true }
end)
