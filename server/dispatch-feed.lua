local Feeds = {}

local TYPE_DEPT = { leo = 'police', police = 'police', ems = 'ems', ambulance = 'ems', fire = 'fire' }

local function Clamp(s, max)
    if #s <= max then return s end
    return (s:sub(1, max):gsub('[\192-\255][\128-\191]*$', ''))
end

local function Str(v, max)
    if type(v) == 'number' then v = tostring(v) end
    if type(v) ~= 'string' then return nil end
    v = v:gsub('<[^>]*>', ' '):gsub('%c', ' '):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    if not utf8.len(v) then v = v:gsub('[\128-\255]', '') end
    v = Clamp(v, max)
    if v == '' then return nil end
    return v
end

local function Lines(list)
    local out = {}
    for _, line in ipairs(list) do
        line = Str(line, 300)
        if line then out[#out + 1] = line end
    end
    return table.concat(out, '\n')
end

local function Coords(v)
    local t = type(v)
    if t ~= 'table' and t ~= 'vector3' and t ~= 'vector4' then return nil end
    local x, y, z = tonumber(v.x or v[1]), tonumber(v.y or v[2]), tonumber(v.z or v[3]) or 0.0
    if not x or not y or math.abs(x) > 20000 or math.abs(y) > 20000 then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function SplitCode(s)
    s = Str(s, 100)
    if not s then return nil, nil end
    local code, rest = s:match('^(%d[%w%-]*)%s+[%-|]%s+(.+)$')
    if not code then code, rest = s:match('^(%d[%w%-]*):%s*(.+)$') end
    if code then return code, rest end
    if s:match('^%d[%w%-]*$') then return s, nil end
    return nil, s
end

local function Jobs(v)
    if type(v) == 'string' then return { v } end
    if type(v) ~= 'table' then return {} end
    local out = {}
    for _, j in pairs(v) do
        if type(j) == 'string' then out[#out + 1] = j end
    end
    return out
end

Feeds['ps-dispatch'] = {
    ['ps-dispatch:server:notify'] = function(data)
        if type(data) ~= 'table' or data.codeName == 'mdt_call' then return nil end
        local lines = { data.information or false }
        if data.name then
            lines[#lines + 1] = 'Caller: ' .. tostring(data.name) .. (data.number and (' (' .. tostring(data.number) .. ')') or '')
        end
        if data.vehicle then
            lines[#lines + 1] = 'Vehicle: ' .. tostring(data.vehicle)
                .. (data.plate and (' · ' .. tostring(data.plate)) or '')
                .. (type(data.color) == 'string' and (' · ' .. data.color) or '')
        end
        if data.weapon then lines[#lines + 1] = 'Weapon: ' .. tostring(data.weapon) end
        if data.gender then lines[#lines + 1] = 'Suspect: ' .. tostring(data.gender) end
        return {
            kind = data.codeName, code = data.code, title = data.message,
            details = Lines(lines), street = data.street, coords = data.coords,
            priority = (tonumber(data.priority) or 2) <= 1 and 1 or 2,
            jobs = data.jobs, caller = data.name,
        }
    end,
}

Feeds['qs-dispatch'] = {
    ['qs-dispatch:server:CreateDispatchCall'] = function(data)
        if type(data) ~= 'table' then return nil end
        local callCode = type(data.callCode) == 'table' and data.callCode or {}
        local blip = type(data.blip) == 'table' and data.blip or {}
        local lines = { data.message or false }
        for _, row in ipairs(type(data.otherData) == 'table' and data.otherData or {}) do
            if type(row) == 'table' then lines[#lines + 1] = row.text or false end
        end
        local code = SplitCode(callCode.code)
        if not code then code = SplitCode(callCode.snippet) end
        return {
            kind = callCode.code or blip.text, code = code,
            title = Str(blip.text, 80) or Str(callCode.snippet, 80) or callCode.code,
            details = Lines(lines), coords = data.callLocation,
            priority = data.flashes == true and 1 or 2,
            jobs = data.job,
        }
    end,
}

Feeds['cd_dispatch'] = {
    ['cd_dispatch:AddNotification'] = function(data)
        if type(data) ~= 'table' then return nil end
        local code, title = SplitCode(data.title)
        local blip = type(data.blip) == 'table' and data.blip or {}
        return {
            kind = data.title, code = code, title = title or blip.text,
            details = Lines({ data.message or false }), coords = data.coords,
            priority = (tonumber(data.flash) == 1 or tonumber(data.sound) == 3) and 1 or 2,
            jobs = data.job_table, ref = data.unique_id,
        }
    end,
}

local function CoreExtra(extraInfo)
    local lines, street = {}, nil
    for _, row in ipairs(type(extraInfo) == 'table' and extraInfo or {}) do
        if type(row) == 'table' and row.info then
            local icon = tostring(row.icon or '')
            if not street and (icon:find('globe') or icon:find('map')) then
                street = row.info
            else
                lines[#lines + 1] = row.info
            end
        end
    end
    return lines, street
end

Feeds['core_dispatch'] = {
    ['core_dispatch:addCall'] = function(code, title, extraInfo, coords, job, _, _, _, priority)
        local lines, street = CoreExtra(extraInfo)
        return {
            kind = title, code = code, title = title,
            details = Lines(lines), street = street, coords = coords,
            priority = priority == true and 1 or 2,
            jobs = Jobs(job),
        }
    end,
    ['core_dispatch:addMessage'] = function(message, coords, job, _, _, _, priority)
        return {
            kind = 'message', title = 'Emergency call',
            details = Lines({ message or false }), coords = coords,
            priority = priority == true and 1 or 2,
            jobs = Jobs(job),
        }
    end,
}

Feeds['rcore_dispatch'] = {
    ['rcore_dispatch:server:sendAlert'] = function(data)
        if type(data) ~= 'table' then return nil end
        local code, title = SplitCode(data.code)
        local blip = type(data.blip) == 'table' and data.blip or {}
        return {
            kind = data.code, code = code, title = title or blip.text or data.type,
            details = Lines({ data.text or false }), coords = data.coords,
            priority = data.default_priority == 'high' and 1 or data.default_priority == 'low' and 3 or 2,
            jobs = Jobs(data.job),
        }
    end,
}

local LINDEN = {
    melee       = { '10-10', 'Fight in progress', { 'police' } },
    officerdown = { '10-99', 'Officer down', { 'police', 'ambulance' } },
    persondown  = { '10-52', 'Person down', { 'police', 'ambulance' } },
    autotheft   = { '10-16', 'Vehicle theft', { 'police' } },
    speeding    = { '10-66', 'Speeding vehicle', { 'police' } },
    shooting    = { '10-13', 'Shots fired', { 'police' } },
    driveby     = { '10-13', 'Drive-by shooting', { 'police' } },
}

Feeds['linden_outlawalert'] = {
    ['wf-alerts:svNotify'] = function(data)
        if type(data) ~= 'table' then return nil end
        local known = LINDEN[data.dispatchCode]
        if known then
            return {
                kind = data.dispatchCode, code = known[1], title = known[2],
                details = Lines({ data.info or false, data.info2 or false }), coords = data.coords,
                priority = data.dispatchCode == 'officerdown' and 1 or 2,
                jobs = known[3], caller = data.caller,
            }
        end
        local custom = type(data.dispatchData) == 'table' and data.dispatchData or nil
        if not custom then return nil end
        return {
            kind = custom.description, code = custom.displayCode, title = custom.description,
            details = Lines({ data.info or custom.info or false, data.info2 or custom.info2 or false }),
            coords = data.coords,
            priority = tonumber(custom.isImportant) == 1 and 1 or 2,
            jobs = custom.recipientList, caller = data.caller,
        }
    end,
    ['wf-alerts:svNotify911'] = function(message, caller, coords)
        return {
            kind = '911', code = '911', title = 'Emergency call',
            details = Lines({ message or false }), coords = coords,
            priority = 2, jobs = { 'police', 'ambulance' }, caller = caller,
        }
    end,
}

local recent, perPlayer, pendingStreet = {}, {}, {}

local function Departments(jobs)
    local out, any = {}, false
    for _, j in ipairs(Jobs(jobs)) do
        local dept = Dept.OfJob(j) or TYPE_DEPT[j:lower()]
        if dept and Config.Departments[dept] then
            out[dept] = true
            any = true
        end
    end
    return any and out or nil
end

local function Merged(origin, kind, coords)
    local now = os.time()
    for i = #recent, 1, -1 do
        local r = recent[i]
        if now - r.t > 60 then
            table.remove(recent, i)
        elseif r.origin == origin and r.kind == kind then
            local dx, dy = r.x - coords.x, r.y - coords.y
            if dx * dx + dy * dy <= 75.0 * 75.0 then
                r.t = now
                return true
            end
        end
    end
    recent[#recent + 1] = { origin = origin, kind = kind, x = coords.x, y = coords.y, t = now }
    return false
end

local function Allowed(src)
    if not src or src <= 0 then return true end
    local now = os.time()
    local bucket = perPlayer[src]
    if not bucket or now - bucket.start >= 60 then
        bucket = { start = now, n = 0 }
        perPlayer[src] = bucket
    end
    bucket.n = bucket.n + 1
    return bucket.n <= 10
end

local function Insert(row)
    for _ = 1, 3 do
        local n = MySQL.scalar.await(
            "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
        local number = ('CAD-%s-%03d'):format(os.date('%Y%m%d'), n)
        local ok, id = pcall(MySQL.insert.await, [[
            INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, units, notes, status, priority, caller_name, origin, external_id)
            VALUES (?, ?, ?, ?, ?, '[]', '[]', 'active', ?, ?, ?, ?)
        ]], { number, row.call_type, row.description, row.location, json.encode(row.coords), row.priority, row.caller_name, row.origin, row.external_id })
        if ok and id then return id, number end
    end
end

local function Ingest(origin, call, src)
    if MdtDispatchBridge.IsExternal() then return end

    local coords = Coords(call.coords)
    if not coords then return end

    local depts = Departments(call.jobs)
    if not depts then return end

    local code = Str(call.code, 20)
    local title = Str(call.title, 80) or 'Dispatch Call'
    if Merged(origin, Str(call.kind, 60) or title, coords) then return end
    if not Allowed(src) then return end

    local recipients = {}
    for psrc, p in pairs(Framework.GetPlayers()) do
        local job = p.PlayerData and p.PlayerData.job
        local dept = job and Dept.OfJob(job.name)
        if dept and depts[dept] and (not Config.OnDutyOnly or job.onduty) then
            recipients[#recipients + 1] = tonumber(psrc)
        end
    end

    local street = Str(call.street, 120)
    local details = type(call.details) == 'string' and call.details ~= '' and Clamp(call.details, 1000) or nil
    local row = {
        call_type = Clamp(code and not title:find(code, 1, true) and (code .. ' · ' .. title) or title, 100),
        description = details or title,
        location = street or 'Unknown Location',
        coords = coords,
        priority = tonumber(call.priority) or 2,
        caller_name = Str(call.caller, 100),
        origin = origin,
        external_id = Str(call.ref, 64),
    }

    MdtSchema.Wait()
    local id, number = Insert(row)
    if not id then return end

    local payload = {
        id = id, call_number = number, call_type = row.call_type, description = row.description,
        location = row.location, coords = coords, status = 'active', priority = row.priority,
        caller_name = row.caller_name, units = {}, notes = {}, origin = origin,
        created_at = os.date('%Y-%m-%dT%H:%M:%SZ'),
    }
    for _, psrc in ipairs(recipients) do
        TriggerClientEvent('XS-MDT:client:newCall', psrc, payload)
    end

    if street then return end
    local resolver = (src and src > 0 and GetPlayerName(src)) and src or recipients[1]
    if resolver then
        pendingStreet[id] = { src = resolver, at = os.time() }
        TriggerClientEvent('XS-MDT:client:resolveStreet', resolver, id, coords)
    end
end

RegisterNetEvent('XS-MDT:server:callStreet', function(callId, text)
    local src = source
    local pending = pendingStreet[callId]
    if not pending or pending.src ~= src then return end
    pendingStreet[callId] = nil
    text = Str(text, 120)
    if not text then return end
    MySQL.update.await('UPDATE mdt_cad_calls SET location = ? WHERE id = ?', { text, callId })
    TriggerClientEvent('XS-MDT:client:callUpdated', -1, { id = callId, location = text })
end)

for id, events in pairs(Feeds) do
    for event, parse in pairs(events) do
        RegisterNetEvent(event, function(...)
            if MdtMirroring or not MdtDispatchFeeding(id) then return end
            local src = tonumber(source)
            local ok, call = pcall(parse, ...)
            if ok and type(call) == 'table' then Ingest(id, call, src) end
        end)
    end
end

local function Expire()
    local minutes = Config.DispatchCallsExpire == nil and 30 or tonumber(Config.DispatchCallsExpire) or 0
    if minutes <= 0 then return end
    local rows = MySQL.query.await([[
        SELECT id FROM mdt_cad_calls
        WHERE origin IS NOT NULL AND status = 'active'
          AND (units IS NULL OR JSON_LENGTH(units) = 0)
          AND created_at < DATE_SUB(NOW(), INTERVAL ? MINUTE)
        LIMIT 50
    ]], { minutes }) or {}
    for _, r in ipairs(rows) do
        local changed = MySQL.update.await("UPDATE mdt_cad_calls SET status = 'cancelled' WHERE id = ? AND status = 'active'", { r.id })
        if changed and changed > 0 then TriggerClientEvent('XS-MDT:client:callClosed', -1, r.id) end
    end
end

CreateThread(function()
    MdtSchema.Wait()
    while true do
        Wait(60000)
        local now = os.time()
        for callId, pending in pairs(pendingStreet) do
            if now - pending.at > 60 then pendingStreet[callId] = nil end
        end
        for src, bucket in pairs(perPlayer) do
            if now - bucket.start >= 60 then perPlayer[src] = nil end
        end
        pcall(Expire)
    end
end)
