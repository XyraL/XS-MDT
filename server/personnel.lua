--[[  Personnel

      Everything a supervisor does to someone else's file: rank, callsign,
      badge, certifications, performance reviews, internal affairs and field
      training.

      Two rules run through all of it:

        - a supervisor can only touch officers in their own department, and
          only ranks at or below their own. Without the second part the
          lowest-ranked supervisor on the server can promote themselves to
          chief.
        - every change is written to mdt_personnel_log with who made it, so
          the officer's card can show the history rather than just the result.
]]

local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetOfficerInfo = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end
local Audit = function(src, action, details, target) return exports['XS-MDT']:AuditLog(action, src, details, target) end

-- ── Helpers ───────────────────────────────────────────────────────────────

local function IsSupervisor(src)
    local officer = GetOfficerInfo(src)
    if not officer then return false end
    return officer.grade >= Dept.SupervisorGrade(officer.job)
end

--[[ The officer a supervisor is acting on, or nil with a reason.

     Resolving this in one place means every callback below refuses the same
     way, rather than each one remembering to check department and rank. ]]
local function Target(src, citizenid)
    local me = GetOfficerInfo(src)
    if not me then return nil, 'Not on duty' end
    if not IsSupervisor(src) then return nil, 'Supervisors only' end
    if not citizenid or citizenid == '' then return nil, 'No officer selected' end

    local row = MySQL.single.await('SELECT * FROM mdt_officers WHERE citizenid = ?', { citizenid })
    if not row then return nil, 'No officer file' end

    if Dept.OfJob(me.job) ~= Dept.OfJob(row.job or me.job) and row.department ~= me.department then
        return nil, 'Different department'
    end

    return row, nil, me
end

local function LogChange(citizenid, field, old, new, by)
    MySQL.insert.await([[
        INSERT INTO mdt_personnel_log (citizenid, field, old_value, new_value, changed_by, changed_by_name)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { citizenid, field, old and tostring(old) or nil, new and tostring(new) or nil, by.citizenid, by.name })
end

--[[ The player currently online as this citizenid, or nil.

     Rank changes go through the framework, which needs a live source. When the
     officer is offline the MDT file is still updated and the job change is
     refused with a reason rather than silently dropped. ]]
local function SourceFor(citizenid)
    for src, player in pairs(Framework.GetPlayers()) do
        if player.PlayerData and player.PlayerData.citizenid == citizenid then return src end
    end
    return nil
end

-- The job names a department covers. Officer records written before 3.0
-- stored the job name rather than the department key, and they only
-- re-sync when that officer next opens the MDT.
function DepartmentJobs(key)
    local cfg = Config.Departments[key]
    local jobs = cfg and cfg.jobs or {}
    return #jobs > 0 and jobs or { '' }
end

-- ── Roster ────────────────────────────────────────────────────────────────

--[[ Every officer on the books, not just the ones on duty.

     getRoster stays as it was — live units for the map and the dashboard —
     because this one is a personnel list and has to include the people who are
     not logged in. ]]
lib.callback.register('XS-MDT:server:getPersonnel', function(source)
    if not IsAuthorized(source) then return nil end
    local me = GetOfficerInfo(source)
    if not me then return nil end

    local rows = MySQL.query.await([[
        SELECT o.citizenid, o.name, o.badge, o.callsign, o.rank, o.department, o.status, o.created_at,
               (SELECT COUNT(*) FROM mdt_certifications c WHERE c.citizenid = o.citizenid) AS certs,
               (SELECT COUNT(*) FROM mdt_ia_cases i WHERE i.citizenid = o.citizenid AND i.status IN ('open','investigating')) AS ia_open
        FROM mdt_officers o
        WHERE o.department = ? OR o.department IN (?)
        ORDER BY o.rank, o.badge
    ]], { me.department, DepartmentJobs(me.department) })

    -- Names and duty state come from the live players; an offline officer
    -- keeps whatever name the last record wrote.
    local online = {}
    for _, player in pairs(Framework.GetPlayers()) do
        local pd = player.PlayerData
        if pd then
            online[pd.citizenid] = {
                name = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
                onduty = pd.job.onduty and Config.AuthorizedJobs[pd.job.name] and true or false,
                grade = pd.job.grade.level,
                gradeLabel = pd.job.grade.name,
                job = pd.job.name,
            }
        end
    end

    for _, row in ipairs(rows) do
        local live = online[row.citizenid]
        row.name = (live and live.name) or row.name or row.callsign or row.badge
        row.online = live and true or false
        row.onduty = live and live.onduty or false
        row.grade = live and live.grade or nil
        row.rank = (live and live.gradeLabel) or row.rank
        row.job = live and live.job or nil
    end

    return {
        officers = rows,
        canManage = IsSupervisor(source),
        myGrade = me.grade,
        certifications = Config.Certifications[Dept.OfJob(me.job)] or {},
        phases = Config.FTOPhases[Dept.OfJob(me.job)] or {},
    }
end)

--[[ One officer's whole file: the tabs the roster modal shows. ]]
lib.callback.register('XS-MDT:server:getOfficerFile', function(source, citizenid)
    if not IsAuthorized(source) then return nil end
    if not citizenid then return nil end

    local me = GetOfficerInfo(source)
    if not me then return nil end

    local profile = MySQL.single.await('SELECT * FROM mdt_officers WHERE citizenid = ?', { citizenid })
    if not profile then return nil end

    local src = SourceFor(citizenid)
    local live = src and Framework.GetPlayer(src)
    if live then
        profile.name = live.PlayerData.charinfo.firstname .. ' ' .. live.PlayerData.charinfo.lastname
        profile.job = live.PlayerData.job.name
        profile.grade = live.PlayerData.job.grade.level
        profile.rank = live.PlayerData.job.grade.name
        profile.online = true
    end

    return {
        profile = profile,
        grades  = Framework.GetJobGrades(profile.job or me.job),
        certs   = MySQL.query.await('SELECT * FROM mdt_certifications WHERE citizenid = ? ORDER BY cert', { citizenid }),
        ia      = MySQL.query.await('SELECT * FROM mdt_ia_cases WHERE citizenid = ? ORDER BY created_at DESC', { citizenid }),
        ppr     = MySQL.query.await('SELECT * FROM mdt_ppr WHERE citizenid = ? ORDER BY created_at DESC', { citizenid }),
        fto     = MySQL.query.await('SELECT * FROM mdt_fto WHERE citizenid = ? ORDER BY created_at', { citizenid }),
        history = MySQL.query.await('SELECT * FROM mdt_personnel_log WHERE citizenid = ? ORDER BY created_at DESC LIMIT 40', { citizenid }),
        available = Config.Certifications[Dept.OfJob(profile.job or me.job)] or {},
        canManage = IsSupervisor(source),
        myGrade   = me.grade,
    }
end)

-- ── Rank ──────────────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:setOfficerRank', function(source, data)
    local row, err, me = Target(source, data and data.citizenid)
    if not row then return false, err end

    local grades = Framework.GetJobGrades(data.job or row.job)
    local picked
    for _, g in ipairs(grades) do
        if g.grade == tonumber(data.grade) then picked = g break end
    end
    if not picked then return false, 'That rank does not exist' end

    -- Nobody promotes anyone above themselves, including themselves.
    if picked.grade > me.grade then return false, 'Above your own rank' end

    local src = SourceFor(row.citizenid)
    if not src then return false, 'They have to be online to change rank' end

    local job = data.job or Framework.GetPlayer(src).PlayerData.job.name
    if not Framework.SetJob(src, job, picked.grade) then
        return false, 'The framework refused the job change'
    end

    MySQL.update.await('UPDATE mdt_officers SET `rank` = ? WHERE citizenid = ?', { picked.label, row.citizenid })
    LogChange(row.citizenid, 'rank', row.rank, picked.label, me)
    Audit(source, 'RANK_CHANGED', ('%s → %s'):format(row.rank or '?', picked.label), row.citizenid)
    Framework.Notify(src, ('Your rank is now %s'):format(picked.label), 'inform')
    return true
end)

-- ── Callsign and badge ────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:setOfficerCallsign', function(source, data)
    local row, err, me = Target(source, data and data.citizenid)
    if not row then return false, err end

    local callsign = data.callsign and data.callsign:sub(1, 20) or nil
    local badge    = data.badge and data.badge:sub(1, 20) or row.badge

    if badge ~= row.badge then
        local taken = MySQL.scalar.await('SELECT citizenid FROM mdt_officers WHERE badge = ? AND citizenid != ?', { badge, row.citizenid })
        if taken then return false, 'That badge number is in use' end
    end

    MySQL.update.await('UPDATE mdt_officers SET callsign = ?, badge = ? WHERE citizenid = ?', { callsign, badge, row.citizenid })

    if callsign ~= row.callsign then LogChange(row.citizenid, 'callsign', row.callsign, callsign, me) end
    if badge ~= row.badge then LogChange(row.citizenid, 'badge', row.badge, badge, me) end

    exports['XS-MDT']:InvalidateBadgeCache(row.citizenid)
    Audit(source, 'CALLSIGN_CHANGED', ('%s → %s'):format(row.callsign or '—', callsign or '—'), row.citizenid)
    return true
end)

-- ── Certifications ────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:grantCertification', function(source, data)
    local row, err, me = Target(source, data and data.citizenid)
    if not row then return false, err end

    local cert = data.cert
    local allowed = Config.Certifications[Dept.OfJob(me.job)] or {}
    local ok = false
    for _, c in ipairs(allowed) do if c == cert then ok = true break end end
    if not ok then return false, 'Not a certification this department issues' end

    MySQL.insert.await([[
        INSERT IGNORE INTO mdt_certifications (citizenid, cert, issued_by, issued_by_name)
        VALUES (?, ?, ?, ?)
    ]], { row.citizenid, cert, me.citizenid, me.name })

    LogChange(row.citizenid, 'certification', nil, cert, me)
    Audit(source, 'CERT_GRANTED', cert, row.citizenid)
    return true
end)

lib.callback.register('XS-MDT:server:revokeCertification', function(source, data)
    local row, err, me = Target(source, data and data.citizenid)
    if not row then return false, err end

    MySQL.update.await('DELETE FROM mdt_certifications WHERE citizenid = ? AND cert = ?', { row.citizenid, data.cert })
    LogChange(row.citizenid, 'certification', data.cert, nil, me)
    Audit(source, 'CERT_REVOKED', data.cert, row.citizenid)
    return true
end)

-- ── Internal affairs ──────────────────────────────────────────────────────

local function NextIANumber()
    local last = MySQL.scalar.await("SELECT case_number FROM mdt_ia_cases ORDER BY id DESC LIMIT 1")
    local n = last and tonumber(last:match('(%d+)$')) or 0
    return ('IA-%05d'):format(n + 1)
end

lib.callback.register('XS-MDT:server:getIACases', function(source, filter)
    if not HasPanel(source, 'ia') then return nil end
    if not IsSupervisor(source) then return nil end

    local me = GetOfficerInfo(source)
    local where, args = 'WHERE 1=1', {}

    if filter and filter.status and filter.status ~= 'all' then
        where = where .. ' AND status = ?'
        args[#args + 1] = filter.status
    end
    if filter and filter.search and filter.search ~= '' then
        where = where .. ' AND (officer_name LIKE ? OR title LIKE ? OR case_number LIKE ?)'
        local q = '%' .. filter.search .. '%'
        args[#args + 1] = q; args[#args + 1] = q; args[#args + 1] = q
    end

    return {
        cases = MySQL.query.await(('SELECT * FROM mdt_ia_cases %s ORDER BY created_at DESC LIMIT 100'):format(where), args),
        canManage = true,
        me = me and me.name or nil,
    }
end)

lib.callback.register('XS-MDT:server:saveIACase', function(source, data)
    if not HasPanel(source, 'ia') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors only' end

    local me = GetOfficerInfo(source)
    if not data or not data.title or data.title == '' then return false, 'A case needs a title' end

    if data.id then
        MySQL.update.await([[
            UPDATE mdt_ia_cases
            SET kind = ?, title = ?, detail = ?, outcome = ?, status = ?,
                closed_at = CASE WHEN ? IN ('sustained','unfounded','closed') THEN NOW() ELSE NULL END
            WHERE id = ?
        ]], { data.kind or 'complaint', data.title, data.detail, data.outcome,
              data.status or 'open', data.status or 'open', data.id })
        Audit(source, 'IA_UPDATED', data.title, data.citizenid)
        return true
    end

    if not data.citizenid then return false, 'No officer selected' end

    local number = NextIANumber()
    MySQL.insert.await([[
        INSERT INTO mdt_ia_cases (case_number, citizenid, officer_name, kind, title, detail, status, opened_by, opened_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { number, data.citizenid, data.officer_name or 'Unknown', data.kind or 'complaint',
          data.title, data.detail, data.status or 'open', me.citizenid, me.name })

    LogChange(data.citizenid, 'ia_case', nil, number, me)
    Audit(source, 'IA_OPENED', ('%s — %s'):format(number, data.title), data.citizenid)
    return true, number
end)

-- ── Performance reviews ───────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:savePPR', function(source, data)
    local row, err, me = Target(source, data and data.citizenid)
    if not row then return false, err end
    if not data.period or data.period == '' then return false, 'A review needs a period' end

    MySQL.insert.await([[
        INSERT INTO mdt_ppr (citizenid, period, rating, strengths, improve, notes, reviewed_by, reviewed_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { row.citizenid, data.period, tonumber(data.rating) or 3, data.strengths, data.improve, data.notes,
          me.citizenid, me.name })

    LogChange(row.citizenid, 'review', nil, data.period, me)
    Audit(source, 'PPR_FILED', data.period, row.citizenid)
    return true
end)

-- ── Field training ────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:getFTO', function(source)
    if not HasPanel(source, 'fto') then return nil end
    local me = GetOfficerInfo(source)
    if not me then return nil end

    return {
        records = MySQL.query.await([[
            SELECT * FROM mdt_fto ORDER BY
                FIELD(status, 'in_progress', 'failed', 'passed'), updated_at DESC
            LIMIT 200
        ]], {}),
        phases = Config.FTOPhases[Dept.OfJob(me.job)] or {},
        canManage = IsSupervisor(source),
    }
end)

lib.callback.register('XS-MDT:server:saveFTO', function(source, data)
    if not HasPanel(source, 'fto') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors only' end

    local me = GetOfficerInfo(source)
    if not data or not data.phase then return false, 'Pick a phase' end

    if data.id then
        MySQL.update.await([[
            UPDATE mdt_fto SET status = ?, hours = ?, notes = ?, trainer_id = ?, trainer_name = ?
            WHERE id = ?
        ]], { data.status or 'in_progress', tonumber(data.hours) or 0, data.notes, me.citizenid, me.name, data.id })
        Audit(source, 'FTO_UPDATED', ('%s — %s'):format(data.phase, data.status or 'in_progress'), data.citizenid)
        return true
    end

    if not data.citizenid then return false, 'No trainee selected' end

    MySQL.insert.await([[
        INSERT INTO mdt_fto (citizenid, trainee_name, phase, status, hours, trainer_id, trainer_name, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { data.citizenid, data.trainee_name or 'Unknown', data.phase, data.status or 'in_progress',
          tonumber(data.hours) or 0, me.citizenid, me.name, data.notes })

    Audit(source, 'FTO_OPENED', data.phase, data.citizenid)
    return true
end)

-- ── Standard operating procedures ─────────────────────────────────────────

lib.callback.register('XS-MDT:server:getSOP', function(source)
    if not HasPanel(source, 'sop') then return nil end
    local me = GetOfficerInfo(source)
    if not me then return nil end

    return {
        docs = MySQL.query.await([[
            SELECT * FROM mdt_sop WHERE department = ?
            ORDER BY pinned DESC, category, title
        ]], { me.department }),
        canManage = IsSupervisor(source),
    }
end)

lib.callback.register('XS-MDT:server:saveSOP', function(source, data)
    if not HasPanel(source, 'sop') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors only' end

    local me = GetOfficerInfo(source)
    if not data or not data.title or data.title == '' then return false, 'A document needs a title' end
    if not data.body or data.body == '' then return false, 'A document needs a body' end

    if data.id then
        MySQL.update.await([[
            UPDATE mdt_sop SET category = ?, title = ?, body = ?, version = ?, pinned = ?,
                   updated_by = ?, updated_by_name = ?
            WHERE id = ? AND department = ?
        ]], { data.category or 'General', data.title, data.body, data.version or '1.0',
              data.pinned and 1 or 0, me.citizenid, me.name, data.id, me.department })
        Audit(source, 'SOP_UPDATED', data.title)
        return true
    end

    MySQL.insert.await([[
        INSERT INTO mdt_sop (department, category, title, body, version, pinned, updated_by, updated_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { me.department, data.category or 'General', data.title, data.body, data.version or '1.0',
          data.pinned and 1 or 0, me.citizenid, me.name })

    Audit(source, 'SOP_CREATED', data.title)
    return true
end)

lib.callback.register('XS-MDT:server:deleteSOP', function(source, id)
    if not HasPanel(source, 'sop') then return false end
    if not IsSupervisor(source) then return false end

    local me = GetOfficerInfo(source)
    local doc = MySQL.single.await('SELECT title FROM mdt_sop WHERE id = ? AND department = ?', { id, me.department })
    if not doc then return false end

    MySQL.update.await('DELETE FROM mdt_sop WHERE id = ? AND department = ?', { id, me.department })
    Audit(source, 'SOP_DELETED', doc.title)
    return true
end)
