-- XS-MDT — EMS backend.
-- Patient Care Reports, per-civilian medical history, and the controlled
-- substance log. Every callback gates on the panel, not just the job, so a
-- department without 'pcr' in its panel list can't reach any of this.

local HasPanel  = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetInfo   = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end
local IsSuper   = function(src) return exports['XS-MDT']:IsSupervisor(src) end
local AuditLog  = function(...) return exports['XS-MDT']:AuditLog(...) end

-- ═══════════════════════════════════════════════════════════════════════════
--  PATIENT CARE REPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local function decodePCR(r)
    if not r then return nil end
    r.injuries   = r.injuries   and json.decode(r.injuries)   or {}
    r.treatments = r.treatments and json.decode(r.treatments) or {}
    r.vitals     = r.vitals     and json.decode(r.vitals)     or {}
    return r
end

lib.callback.register('XS-MDT:server:getPCRs', function(source, data)
    if not HasPanel(source, 'pcr') then return nil end
    local medic  = GetInfo(source)
    local filter = (type(data) == 'table' and data.filter) or 'all'
    local search = (type(data) == 'table' and data.search) or nil

    local sql, params = 'SELECT * FROM mdt_pcr', {}
    local where = {}
    if filter == 'mine' then
        where[#where + 1] = 'medic_citizenid = ?'
        params[#params + 1] = medic.citizenid
    elseif filter == 'open' then
        where[#where + 1] = "status = 'open'"
    end
    if search and #search >= 2 then
        where[#where + 1] = '(patient_name LIKE ? OR chief_complaint LIKE ?)'
        params[#params + 1] = '%' .. search .. '%'
        params[#params + 1] = '%' .. search .. '%'
    end
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY created_at DESC LIMIT 100'

    local rows = MySQL.query.await(sql, params) or {}
    for _, r in ipairs(rows) do decodePCR(r) end
    return rows
end)

lib.callback.register('XS-MDT:server:getPCR', function(source, id)
    if not HasPanel(source, 'pcr') then return nil end
    return decodePCR(MySQL.single.await('SELECT * FROM mdt_pcr WHERE id = ?', { id }))
end)

lib.callback.register('XS-MDT:server:createPCR', function(source, data)
    if not HasPanel(source, 'pcr') then return false end
    local medic = GetInfo(source)
    if not data or not data.patient_citizenid or not data.chief_complaint then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_pcr
            (patient_citizenid, patient_name, chief_complaint, narrative,
             injuries, treatments, vitals, disposition, transported_to,
             priority, status, medic_citizenid, medic_name)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        data.patient_citizenid, data.patient_name or 'Unknown',
        data.chief_complaint, data.narrative or '',
        json.encode(data.injuries or {}),
        json.encode(data.treatments or {}),
        json.encode(data.vitals or {}),
        data.disposition or 'treated_released',
        data.transported_to or nil,
        data.priority or 3,
        data.status or 'open',
        medic.citizenid, medic.name,
    })

    AuditLog('PCR Created', medic.name, ('PCR #%d — %s'):format(id, data.patient_name or 'Unknown'))
    return id
end)

lib.callback.register('XS-MDT:server:updatePCR', function(source, data)
    if not HasPanel(source, 'pcr') then return false end
    local medic = GetInfo(source)
    if not data or not data.id then return false end

    -- Authors edit their own reports; supervisors edit anyone's.
    local owner = MySQL.scalar.await('SELECT medic_citizenid FROM mdt_pcr WHERE id = ?', { data.id })
    if not owner then return false end
    if owner ~= medic.citizenid and not IsSuper(source) then return false, 'Not your report' end

    MySQL.update.await([[
        UPDATE mdt_pcr SET chief_complaint = ?, narrative = ?, injuries = ?, treatments = ?,
            vitals = ?, disposition = ?, transported_to = ?, priority = ?, status = ?
        WHERE id = ?
    ]], {
        data.chief_complaint, data.narrative or '',
        json.encode(data.injuries or {}),
        json.encode(data.treatments or {}),
        json.encode(data.vitals or {}),
        data.disposition or 'treated_released',
        data.transported_to or nil,
        data.priority or 3,
        data.status or 'open',
        data.id,
    })

    AuditLog('PCR Updated', medic.name, 'PCR #' .. data.id)
    return true
end)

lib.callback.register('XS-MDT:server:deletePCR', function(source, id)
    if not HasPanel(source, 'pcr') then return false end
    if not IsSuper(source) then return false, 'Supervisor only' end
    local medic = GetInfo(source)
    MySQL.query.await('DELETE FROM mdt_pcr WHERE id = ?', { id })
    AuditLog('PCR Deleted', medic.name, 'PCR #' .. tostring(id))
    return true
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  MEDICAL HISTORY
--  Persistent per-civilian record: allergies, conditions, medications, blood
--  type, plus dated entries. Police never see any of this.
-- ═══════════════════════════════════════════════════════════════════════════

lib.callback.register('XS-MDT:server:getMedicalRecord', function(source, citizenid)
    if not HasPanel(source, 'medhistory') then return nil end
    if not citizenid then return nil end

    local civ = MySQL.single.await(
        'SELECT citizenid, firstname, lastname, dob, gender, phone FROM mdt_civilians WHERE citizenid = ?',
        { citizenid })
    if not civ then return nil end

    local rec = MySQL.single.await('SELECT * FROM mdt_medical WHERE citizenid = ?', { citizenid })
    if not rec then
        MySQL.insert.await('INSERT INTO mdt_medical (citizenid) VALUES (?)', { citizenid })
        rec = MySQL.single.await('SELECT * FROM mdt_medical WHERE citizenid = ?', { citizenid })
    end

    rec.allergies   = rec.allergies   and json.decode(rec.allergies)   or {}
    rec.conditions  = rec.conditions  and json.decode(rec.conditions)  or {}
    rec.medications = rec.medications and json.decode(rec.medications) or {}

    return {
        civilian = civ,
        record   = rec,
        history  = MySQL.query.await(
            'SELECT * FROM mdt_medical_history WHERE citizenid = ? ORDER BY created_at DESC LIMIT 50',
            { citizenid }) or {},
        pcrs = MySQL.query.await([[
            SELECT id, chief_complaint, disposition, priority, medic_name, created_at
            FROM mdt_pcr WHERE patient_citizenid = ? ORDER BY created_at DESC LIMIT 25
        ]], { citizenid }) or {},
    }
end)

lib.callback.register('XS-MDT:server:updateMedicalRecord', function(source, data)
    if not HasPanel(source, 'medhistory') then return false end
    local medic = GetInfo(source)
    if not data or not data.citizenid then return false end

    MySQL.query.await([[
        INSERT INTO mdt_medical (citizenid, blood_type, allergies, conditions, medications, dnr, organ_donor, notes)
        VALUES (?,?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
            blood_type=VALUES(blood_type), allergies=VALUES(allergies), conditions=VALUES(conditions),
            medications=VALUES(medications), dnr=VALUES(dnr), organ_donor=VALUES(organ_donor), notes=VALUES(notes)
    ]], {
        data.citizenid, data.blood_type or nil,
        json.encode(data.allergies or {}),
        json.encode(data.conditions or {}),
        json.encode(data.medications or {}),
        data.dnr and 1 or 0,
        data.organ_donor and 1 or 0,
        data.notes or '',
    })

    AuditLog('Medical Record Updated', medic.name, 'Patient ' .. data.citizenid)
    return true
end)

lib.callback.register('XS-MDT:server:addMedicalEntry', function(source, data)
    if not HasPanel(source, 'medhistory') then return false end
    local medic = GetInfo(source)
    if not data or not data.citizenid or not data.entry then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_medical_history (citizenid, entry_type, entry, author_citizenid, author_name)
        VALUES (?,?,?,?,?)
    ]], { data.citizenid, data.entry_type or 'note', data.entry, medic.citizenid, medic.name })

    AuditLog('Medical Entry Added', medic.name, 'Patient ' .. data.citizenid)
    return id
end)

lib.callback.register('XS-MDT:server:deleteMedicalEntry', function(source, id)
    if not HasPanel(source, 'medhistory') then return false end
    if not IsSuper(source) then return false, 'Supervisor only' end
    MySQL.query.await('DELETE FROM mdt_medical_history WHERE id = ?', { id })
    return true
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  CONTROLLED SUBSTANCE LOG
--  Narcotics drawn / administered / wasted, with a witness field. Supervisors
--  get a reconciliation summary.
-- ═══════════════════════════════════════════════════════════════════════════

lib.callback.register('XS-MDT:server:getNarcLog', function(source, data)
    if not HasPanel(source, 'narclog') then return nil end
    local medic  = GetInfo(source)
    local filter = (type(data) == 'table' and data.filter) or 'mine'

    local rows
    if filter == 'all' then
        if not IsSuper(source) then return nil end   -- full log is supervisor-only
        rows = MySQL.query.await('SELECT * FROM mdt_narc_log ORDER BY created_at DESC LIMIT 200') or {}
    else
        rows = MySQL.query.await(
            'SELECT * FROM mdt_narc_log WHERE medic_citizenid = ? ORDER BY created_at DESC LIMIT 100',
            { medic.citizenid }) or {}
    end

    -- Running totals per drug, so a supervisor can spot a discrepancy fast.
    local totals = {}
    for _, r in ipairs(rows) do
        local t = totals[r.drug] or { drawn = 0, administered = 0, wasted = 0 }
        t[r.action] = (t[r.action] or 0) + (tonumber(r.amount) or 0)
        totals[r.drug] = t
    end

    return { entries = rows, totals = totals, isSupervisor = IsSuper(source) }
end)

lib.callback.register('XS-MDT:server:addNarcEntry', function(source, data)
    if not HasPanel(source, 'narclog') then return false end
    local medic = GetInfo(source)
    if not data or not data.drug or not data.action then return false end

    local action = data.action
    if action ~= 'drawn' and action ~= 'administered' and action ~= 'wasted' then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_narc_log
            (drug, amount, unit, action, patient_citizenid, patient_name, witness_name, notes,
             medic_citizenid, medic_name, pcr_id)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        data.drug, tonumber(data.amount) or 0, data.unit or 'mg', action,
        data.patient_citizenid or nil, data.patient_name or nil,
        data.witness_name or nil, data.notes or '',
        medic.citizenid, medic.name, data.pcr_id or nil,
    })

    AuditLog('Narcotics Log', medic.name, ('%s %s%s of %s'):format(
        action, tostring(data.amount or 0), data.unit or 'mg', data.drug))
    return id
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  EMS DASHBOARD STATS
-- ═══════════════════════════════════════════════════════════════════════════

lib.callback.register('XS-MDT:server:getEMSStats', function(source)
    if not HasPanel(source, 'pcr') then return nil end
    local medic = GetInfo(source)

    return {
        pcrs_today = MySQL.scalar.await(
            'SELECT COUNT(*) FROM mdt_pcr WHERE DATE(created_at) = CURDATE()') or 0,
        pcrs_week = MySQL.scalar.await(
            'SELECT COUNT(*) FROM mdt_pcr WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)') or 0,
        my_pcrs = MySQL.scalar.await(
            'SELECT COUNT(*) FROM mdt_pcr WHERE medic_citizenid = ?', { medic.citizenid }) or 0,
        open_pcrs = MySQL.scalar.await(
            "SELECT COUNT(*) FROM mdt_pcr WHERE status = 'open'") or 0,
        transports_week = MySQL.scalar.await(
            "SELECT COUNT(*) FROM mdt_pcr WHERE disposition = 'transported' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)") or 0,
        top_medics = MySQL.query.await([[
            SELECT medic_name, COUNT(*) AS pcr_count FROM mdt_pcr
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
            GROUP BY medic_citizenid, medic_name ORDER BY pcr_count DESC LIMIT 5
        ]]) or {},
    }
end)
