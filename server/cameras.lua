--[[  Cameras and footage

      The MDT does not play video, and pretending otherwise would be a worse
      lie than being honest about it. What it does is know which cameras exist,
      where they are, and what footage has been pulled from them — which is
      what an officer actually needs: somewhere to look, and a record that
      somebody looked.

      A camera or dashcam resource can push clips in through the RegisterFootage
      export rather than writing to these tables itself, the same way the
      dispatch bridge works.
]]

local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetOfficerInfo = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end
local IsSupervisor = function(src) return exports['XS-MDT']:IsSupervisor(src) end
local Audit = function(src, action, details, target) return exports['XS-MDT']:AuditLog(action, src, details, target) end

local function NextFootageNumber()
    local year = os.date('%y')
    local last = MySQL.scalar.await(
        "SELECT footage_number FROM mdt_footage WHERE footage_number LIKE ? ORDER BY footage_number DESC LIMIT 1",
        { ('FT-%s-%%'):format(year) })
    local n = last and tonumber(last:match('(%d+)$')) or 0
    return ('FT-%s-%04d'):format(year, n + 1)
end

--[[ Seed the camera list from Config.DefaultCameras.

     INSERT IGNORE, so a camera renamed or moved in the panel survives a
     restart. A camera DELETED in the panel comes back if it is still listed
     in the config, which is the tradeoff for the list living there: remove it
     from config.lua instead. ]]
local function SeedCameras()
    if Config.SeedCameras == false then return end

    local list = Config.DefaultCameras or {}
    if #list == 0 then return end

    local rows = {}
    for _, cam in ipairs(list) do
        if cam.code and cam.label then
            rows[#rows + 1] = {
                cam.code:upper():sub(1, 20), cam.label, cam.area, cam.kind or 'fixed',
                cam.coords and json.encode(cam.coords) or nil,
                tonumber(cam.heading) or 0.0, tonumber(cam.pitch) or -14.0, 'Default',
            }
        end
    end
    if #rows == 0 then return end

    MySQL.prepare.await([[
        INSERT IGNORE INTO mdt_cameras (camera_code, label, area, kind, coords, heading, pitch, added_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], rows)
end

AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end

    -- The seed writes heading and pitch, which the migration may not have
    -- added yet. Wait for it rather than for a timer.
    CreateThread(function()
        MdtSchema.Wait()
        local ok, err = pcall(SeedCameras)
        if not ok then
            print(('^1[XS-MDT] Could not seed the default cameras: %s^7'):format(err))
        end
    end)
end)

-- ── Cameras ───────────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:getCameras', function(source, filter)
    if not HasPanel(source, 'cameras') then return nil end

    filter = filter or {}
    local where, args = { '1=1' }, {}

    if filter.status and filter.status ~= 'all' then
        where[#where + 1] = 'status = ?'
        args[#args + 1] = filter.status
    end
    if filter.search and filter.search ~= '' then
        where[#where + 1] = '(camera_code LIKE ? OR label LIKE ? OR area LIKE ?)'
        local q = '%' .. filter.search .. '%'
        for _ = 1, 3 do args[#args + 1] = q end
    end

    local cameras = MySQL.query.await(
        ('SELECT * FROM mdt_cameras WHERE %s ORDER BY area, camera_code LIMIT 300'):format(table.concat(where, ' AND ')),
        args) or {}

    for _, cam in ipairs(cameras) do
        if type(cam.coords) == 'string' then
            local ok, decoded = pcall(json.decode, cam.coords)
            cam.coords = ok and decoded or nil
        end
    end

    return { cameras = cameras, canManage = IsSupervisor(source) }
end)

lib.callback.register('XS-MDT:server:saveCamera', function(source, data)
    if not HasPanel(source, 'cameras') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors manage the camera list' end

    local me = GetOfficerInfo(source)
    if not data or not data.label or data.label == '' then return false, 'A camera needs a name' end

    local code = (data.camera_code or ''):upper():sub(1, 20)
    if code == '' then return false, 'A camera needs a code' end

    local coords = data.coords and json.encode(data.coords) or nil

    if data.id then
        MySQL.update.await([[
            UPDATE mdt_cameras SET camera_code = ?, label = ?, area = ?, kind = ?, status = ?,
                   coords = COALESCE(?, coords), heading = COALESCE(?, heading),
                   pitch = COALESCE(?, pitch), notes = ?
            WHERE id = ?
        ]], { code, data.label, data.area, data.kind or 'fixed', data.status or 'online', coords,
              tonumber(data.heading), tonumber(data.pitch), data.notes, data.id })
        Audit(source, 'CAMERA_UPDATED', ('%s — %s'):format(code, data.label))
        return true
    end

    local taken = MySQL.scalar.await('SELECT id FROM mdt_cameras WHERE camera_code = ?', { code })
    if taken then return false, 'That camera code is already used' end

    MySQL.insert.await([[
        INSERT INTO mdt_cameras (camera_code, label, area, kind, status, coords, heading, pitch, notes, added_by, added_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { code, data.label, data.area, data.kind or 'fixed', data.status or 'online', coords,
          tonumber(data.heading) or 0.0, tonumber(data.pitch) or -12.0, data.notes,
          me.citizenid, me.name })

    Audit(source, 'CAMERA_ADDED', ('%s — %s'):format(code, data.label))
    return true
end)

lib.callback.register('XS-MDT:server:deleteCamera', function(source, id)
    if not HasPanel(source, 'cameras') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors manage the camera list' end

    local cam = MySQL.single.await('SELECT camera_code, label FROM mdt_cameras WHERE id = ?', { id })
    if not cam then return false, 'Already gone' end

    MySQL.update.await('DELETE FROM mdt_cameras WHERE id = ?', { id })
    Audit(source, 'CAMERA_REMOVED', ('%s — %s'):format(cam.camera_code, cam.label))
    return true
end)

-- ── Footage ───────────────────────────────────────────────────────────────

lib.callback.register('XS-MDT:server:getFootage', function(source, filter)
    if not HasPanel(source, 'cameras') then return nil end

    filter = filter or {}
    local where, args = { '1=1' }, {}

    if filter.source and filter.source ~= 'all' then
        where[#where + 1] = 'f.source = ?'
        args[#args + 1] = filter.source
    end
    if filter.search and filter.search ~= '' then
        where[#where + 1] = '(f.label LIKE ? OR f.footage_number LIKE ? OR f.camera_code LIKE ? OR f.unit_name LIKE ?)'
        local q = '%' .. filter.search .. '%'
        for _ = 1, 4 do args[#args + 1] = q end
    end

    return {
        clips = MySQL.query.await(([[
            SELECT f.*, c.case_number
            FROM mdt_footage f
            LEFT JOIN mdt_cases c ON c.id = f.case_id
            WHERE %s
            ORDER BY COALESCE(f.recorded_at, f.created_at) DESC
            LIMIT 200
        ]]):format(table.concat(where, ' AND ')), args) or {},
        canManage = true,
    }
end)

lib.callback.register('XS-MDT:server:logFootage', function(source, data)
    if not HasPanel(source, 'cameras') then return false, 'No access' end
    local me = GetOfficerInfo(source)
    if not me then return false, 'Not on duty' end
    if not data or not data.label or data.label == '' then return false, 'Say what the clip shows' end

    local number = NextFootageNumber()
    local id = MySQL.insert.await([[
        INSERT INTO mdt_footage (footage_number, source, camera_id, camera_code, unit_citizenid, unit_name,
                                 case_id, label, detail, recorded_at, duration, status, logged_by, logged_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { number, data.source or 'camera', data.camera_id, data.camera_code,
          data.unit_citizenid, data.unit_name, data.caseId, data.label, data.detail,
          data.recorded_at, tonumber(data.duration), data.status or 'available',
          me.citizenid, me.name })

    if data.caseId then
        MySQL.insert.await([[
            INSERT IGNORE INTO mdt_case_links (case_id, kind, ref_id, label, added_by, added_by_name)
            VALUES (?, 'evidence', ?, ?, ?, ?)
        ]], { data.caseId, 'footage:' .. id, number .. ' — ' .. data.label, me.citizenid, me.name })
    end

    Audit(source, 'FOOTAGE_LOGGED', ('%s — %s'):format(number, data.label))
    return true, number
end)

lib.callback.register('XS-MDT:server:deleteFootage', function(source, id)
    if not HasPanel(source, 'cameras') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors only' end

    local clip = MySQL.single.await('SELECT footage_number, label FROM mdt_footage WHERE id = ?', { id })
    if not clip then return false, 'Already gone' end

    MySQL.update.await('DELETE FROM mdt_footage WHERE id = ?', { id })
    Audit(source, 'FOOTAGE_REMOVED', ('%s — %s'):format(clip.footage_number, clip.label))
    return true
end)

--[[ For a camera or dashcam resource to file a clip itself.

     Takes the same shape the panel sends, plus an officer name to credit,
     because there is no player behind the call. Returns the footage number so
     the calling resource can show it.

       exports['XS-MDT']:RegisterFootage({
           source = 'dashcam', unit_name = '1-ADAM-12',
           label = 'Traffic stop, Route 68', duration = 214,
       })
]]
exports('RegisterFootage', function(data)
    if type(data) ~= 'table' or not data.label then return nil end

    local number = NextFootageNumber()
    MySQL.insert.await([[
        INSERT INTO mdt_footage (footage_number, source, camera_id, camera_code, unit_citizenid, unit_name,
                                 case_id, label, detail, recorded_at, duration, status, logged_by, logged_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { number, data.source or 'dashcam', data.camera_id, data.camera_code,
          data.unit_citizenid, data.unit_name, data.case_id, data.label, data.detail,
          data.recorded_at, tonumber(data.duration), data.status or 'available',
          data.logged_by or 'system', data.logged_by_name or 'Automatic' })

    return number
end)

--[[ For a camera resource to publish its camera list into the MDT.

     Cameras keyed by code, so calling this again after a config change updates
     the rows rather than duplicating them. ]]
exports('RegisterCameras', function(list)
    if type(list) ~= 'table' then return 0 end

    local n = 0
    for _, cam in ipairs(list) do
        if cam.code and cam.label then
            MySQL.query.await([[
                INSERT INTO mdt_cameras (camera_code, label, area, kind, coords, status, added_by_name)
                VALUES (?, ?, ?, ?, ?, ?, 'Imported')
                ON DUPLICATE KEY UPDATE label = VALUES(label), area = VALUES(area),
                    kind = VALUES(kind), coords = VALUES(coords)
            ]], { cam.code:upper():sub(1, 20), cam.label, cam.area, cam.kind or 'fixed',
                  cam.coords and json.encode(cam.coords) or nil, cam.status or 'online' })
            n = n + 1
        end
    end
    return n
end)
