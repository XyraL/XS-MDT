local QBX = exports['qbx_core']

-- Returns the QBCore player object or nil
local function GetPlayer(src)
    return QBX:GetPlayer(src)
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
        departmentColor = deptCfg and deptCfg.color or '#6366f1',
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

-- Audit log helper — saves to DB and optionally posts to Discord webhook
local function AuditLog(action, officer, details)
    if Config.AuditWebhook ~= '' then
        PerformHttpRequest(Config.AuditWebhook, function() end, 'POST', json.encode({
            embeds = {{
                title = '📋 XSMDT Audit',
                color = 3447003,
                fields = {
                    { name = 'Action', value = action, inline = true },
                    { name = 'Officer', value = officer, inline = true },
                    { name = 'Details', value = details or 'N/A', inline = false },
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            }}
        }), { ['Content-Type'] = 'application/json' })
    end
    -- Always persist to DB for in-game viewer (non-blocking)
    MySQL.insert('INSERT INTO mdt_audit_log (action, officer_name, details) VALUES (?, ?, ?)', {
        action, officer, details
    })
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
    local players = exports['qbx_core']:GetQBPlayers()
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

    -- Body cam: log MDT open
    if Config.BodyCam.Enabled then
        MySQL.insert.await('INSERT INTO mdt_bodycam (citizenid, officer_name, action, details) VALUES (?,?,?,?)', {
            officer.citizenid, officer.name, 'MDT_OPENED', 'MDT session started'
        })
    end
    return officer
end)
