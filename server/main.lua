-- Every framework call goes through bridge/framework.lua, which is loaded
-- first. Keeping a local alias here means the rest of this file reads the same
-- whichever framework is running.
local function GetPlayer(src)
    return Framework.GetPlayer(src)
end

-- Checks if the source player has an authorized job and is on duty
local function IsAuthorized(src)
    local player = GetPlayer(src)
    if not player then return false end
    local job = player.PlayerData.job
    if not Config.AuthorizedJobs[job.name] then return false end
    if Config.OnDutyOnly and not job.onduty then return false end
    if job.grade.level < Config.MinGrade then return false end
    return true
end

-- Returns basic officer info pulled from QBX player data
local function JobColors()
    local out = {}
    for _, cfg in pairs(Config.Departments or {}) do
        for _, job in ipairs(cfg.jobs or {}) do out[job] = cfg.color end
    end
    return out
end

local function DepartmentList()
    local out = {}
    for key, cfg in pairs(Config.Departments or {}) do
        out[#out + 1] = { key = key, label = cfg.short or cfg.label or key, color = cfg.color }
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

local function GetOfficerInfo(src)
    local player = GetPlayer(src)
    if not player then return nil end
    local pd = player.PlayerData
    local deptKey = Dept.OfJob(pd.job.name)
    local deptCfg = deptKey and Config.Departments[deptKey] or nil
    return {
        citizenid = pd.citizenid,
        name = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
        job = pd.job.name,
        grade = pd.job.grade.level,
        gradeLabel = pd.job.grade.name,
        onduty = pd.job.onduty,
        -- Department context — drives the sidebar, theming and every permission check
        department      = deptKey,
        departmentLabel = deptCfg and deptCfg.label or 'Unknown',
        departmentShort = deptCfg and deptCfg.short or '--',
        departmentColor = deptCfg and deptCfg.color or '#3b82f6',
        -- Every department, so the live map can colour units that are not
        -- the viewer own. The map used to carry a copy of these and drifted
        -- the first time config changed.
        jobColors       = JobColors(),
        departments     = DepartmentList(),
        departmentIcon  = deptCfg and deptCfg.icon or '⬡',
        panels          = Dept.PanelsOfJob(pd.job.name),
    }
end

-- Panel-level permission gate. Every department-specific callback calls this
-- instead of IsAuthorized, so a job can never reach data its department's
-- panel list doesn't include — even by crafting the NUI request by hand.
local function HasPanel(src, panel)
    if not IsAuthorized(src) then return false end
    local player = GetPlayer(src)
    return Dept.HasPanel(player.PlayerData.job.name, panel)
end

-- Is this player a supervisor within their own department?
local function IsSupervisor(src)
    local player = GetPlayer(src)
    if not player then return false end
    local pd = player.PlayerData
    return pd.job.grade.level >= Dept.SupervisorGrade(pd.job.name)
end

--[[ Audit.

     Call sites written before 3.0 pass the officer's display name as a string,
     which is all this table used to store — and why two officers called
     J. Reyes produced rows nobody could tell apart. Those still work. New call
     sites pass the source instead, and the row then carries their citizenid,
     their department, and the person the action was about.

       AuditLog('ARREST_LOGGED', officer.name, details)      -- old, still fine
       AuditLog('RANK_CHANGED', source, details, citizenid)  -- new ]]
local function AuditLog(action, officer, details, target)
    local name, citizenid, department = officer, nil, nil

    if type(officer) == 'number' then
        local info = GetOfficerInfo(officer)
        name       = info and info.name or ('source ' .. officer)
        citizenid  = info and info.citizenid or nil
        department = info and info.department or nil
    end

    local targetId, targetName
    if type(target) == 'table' then
        targetId, targetName = target.citizenid, target.name
    elseif type(target) == 'string' then
        targetId = target
    end

    if Config.AuditWebhook ~= '' then
        local fields = {
            { name = 'Action', value = action, inline = true },
            { name = 'Officer', value = name, inline = true },
            { name = 'Details', value = details or 'N/A', inline = false },
        }
        if targetId then
            fields[#fields + 1] = { name = 'Subject', value = targetName or targetId, inline = true }
        end
        PerformHttpRequest(Config.AuditWebhook, function() end, 'POST', json.encode({
            embeds = {{
                title = 'XS-MDT Audit',
                color = 3447003,
                fields = fields,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            }}
        }), { ['Content-Type'] = 'application/json' })
    end

    MySQL.insert([[
        INSERT INTO mdt_audit_log (action, officer_name, details, citizenid, department, target_citizenid, target_name)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { action, name, details, citizenid, department, targetId, targetName })
end

-- Audit log retrieval (supervisor-only, with optional filters)
lib.callback.register('XS-MDT:server:getAuditLog', function(source, data)
    if not IsAuthorized(source) then return nil end
    local officer = GetOfficerInfo(source)
    if not officer or officer.grade < Dept.SupervisorGrade(officer.job) then return nil end

    data = data or {}
    local where, params = {}, {}

    if data.action and #data.action > 0 then
        where[#where+1] = 'action = ?'
        params[#params+1] = data.action
    end
    if data.officer and #data.officer >= 2 then
        where[#where+1] = 'officer_name LIKE ?'
        params[#params+1] = '%' .. data.officer .. '%'
    end
    if data.dateFrom and #data.dateFrom > 0 then
        where[#where+1] = 'DATE(created_at) >= ?'
        params[#params+1] = data.dateFrom
    end
    if data.dateTo and #data.dateTo > 0 then
        where[#where+1] = 'DATE(created_at) <= ?'
        params[#params+1] = data.dateTo
    end

    local sql = 'SELECT * FROM mdt_audit_log'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY created_at DESC LIMIT 200'

    return MySQL.query.await(sql, params)
end)

-- Expose helpers to other server files
exports('IsAuthorized', IsAuthorized)
exports('GetOfficerInfo', GetOfficerInfo)
exports('AuditLog', AuditLog)
exports('GetPlayer', GetPlayer)
exports('HasPanel', HasPanel)
exports('IsSupervisor', IsSupervisor)

-- Search connected players by character name (replaces CID lookup in forms)
lib.callback.register('XS-MDT:server:searchPlayersByName', function(source, query)
    if not IsAuthorized(source) then return nil end
    if not query or #query < 2 then return {} end
    local search = query:lower()
    -- Warrant counts are criminal data — police only.
    local showWarrants = HasPanel(source, 'warrants')
    local results = {}
    local players = Framework.GetPlayers()
    for src, player in pairs(players) do
        local pd = player.PlayerData
        local fullname = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
        if fullname:lower():find(search, 1, true) then
            -- Sync to mdt_civilians
            MySQL.insert.await([[
                INSERT INTO mdt_civilians (citizenid, firstname, lastname, dob, gender, phone)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE firstname=VALUES(firstname), lastname=VALUES(lastname),
                dob=VALUES(dob), gender=VALUES(gender), phone=VALUES(phone)
            ]], { pd.citizenid, pd.charinfo.firstname, pd.charinfo.lastname,
                  pd.charinfo.birthdate, pd.charinfo.gender, pd.charinfo.phone })

            local warrantCount = showWarrants and (MySQL.scalar.await(
                "SELECT COUNT(*) FROM mdt_warrants WHERE citizenid=? AND status='active'", { pd.citizenid }) or 0) or nil

            results[#results+1] = {
                citizenid  = pd.citizenid,
                name       = fullname,
                firstname  = pd.charinfo.firstname,
                lastname   = pd.charinfo.lastname,
                dob        = pd.charinfo.birthdate,
                gender     = pd.charinfo.gender,
                phone      = pd.charinfo.phone,
                source     = src,
                online     = true,
                warrants   = warrantCount,
            }
        end
    end
    -- Also search offline civilians
    local dbResults = MySQL.query.await(([[
        SELECT c.citizenid, c.firstname, c.lastname, c.dob, c.gender, c.phone%s
        FROM mdt_civilians c
        WHERE CONCAT(c.firstname,' ',c.lastname) LIKE ?
        LIMIT 12
    ]]):format(showWarrants
        and [[, (SELECT COUNT(*) FROM mdt_warrants w WHERE w.citizenid=c.citizenid AND w.status='active') as warrants]]
        or ''),
    { '%'..query..'%' })
    for _, row in ipairs(dbResults) do
        local already = false
        for _, r in ipairs(results) do if r.citizenid == row.citizenid then already = true break end end
        if not already then
            results[#results+1] = {
                citizenid = row.citizenid,
                name      = row.firstname..' '..row.lastname,
                firstname = row.firstname,
                lastname  = row.lastname,
                dob       = row.dob,
                gender    = row.gender,
                phone     = row.phone,
                online    = false,
                warrants  = showWarrants and (row.warrants or 0) or nil,
            }
        end
    end
    return results
end)

-- Main MDT open callback — validates access and returns initial data
lib.callback.register('XS-MDT:server:open', function(source)
    if not IsAuthorized(source) then return nil end
    local officer = GetOfficerInfo(source)
    officer.isSupervisor = officer.grade >= Dept.SupervisorGrade(officer.job)

    -- The officer record is what the roster and the officer search read for
    -- anyone who is not online, so it carries the name, department key and
    -- rank as of the last time they opened the MDT. The department was stored
    -- as the job name before, so an 'ambulance' medic never matched the 'ems'
    -- roster.
    MySQL.update.await([[
        UPDATE mdt_officers SET name = ?, department = ?, `rank` = ? WHERE citizenid = ?
    ]], { officer.name, officer.department, officer.gradeLabel, officer.citizenid })

    -- Body cam: log MDT open
    if Config.BodyCam.Enabled then
        MySQL.insert.await('INSERT INTO mdt_bodycam (citizenid, officer_name, action, details) VALUES (?,?,?,?)', {
            officer.citizenid, officer.name, 'MDT_OPENED', 'MDT session started'
        })
    end

    local profile = MySQL.single.await('SELECT badge, callsign, status FROM mdt_officers WHERE citizenid = ?', { officer.citizenid })
    if profile then
        officer.badge, officer.callsign, officer.status = profile.badge, profile.callsign, profile.status
    end
    officer.bootScreen = Config.BootScreen ~= false
    return officer
end)
