local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end

-- Codes read  PC <title>.<section> <subsection>  — PC 1.34 A is title 1,
-- section 34, subsection A. The parts are stored alongside the code so the
-- book sorts in its own order; a server that writes its own codes in some
-- other format just gets nils and sorts to the end.
local function ParseCode(code)
    if type(code) ~= 'string' then return nil end
    local title, section, sub = code:match('^%s*[Pp][Cc]%s+(%d+)%.(%d+)%s*(%a?)')
    if not title then return nil end
    return tonumber(title), tonumber(section), (sub ~= '' and sub:upper() or nil)
end

local function IsAdmin(source)
    local player = Framework.GetPlayer(source)
    return player and player.PlayerData.job.grade.level >= 3
end

lib.callback.register('XS-MDT:server:getPenalCodes', function(source)
    if not HasPanel(source, 'penal') then return nil end

    local codes = MySQL.query.await([[
        SELECT * FROM mdt_penal_codes
        WHERE active = 1
        ORDER BY title_no IS NULL, title_no, section_no, subsection, code
    ]], {})

    -- Group by category, keeping the order the query came back in so the
    -- titles read 1 through 7 rather than alphabetically.
    local grouped, order = {}, {}
    for _, code in ipairs(codes) do
        if not grouped[code.category] then
            grouped[code.category] = { category = code.category, codes = {} }
            order[#order + 1] = grouped[code.category]
        end
        local list = grouped[code.category].codes
        list[#list + 1] = code
    end
    return order
end)

-- Admin only: add/edit/remove penal codes
lib.callback.register('XS-MDT:server:addPenalCode', function(source, data)
    if not HasPanel(source, 'penal') then return false end
    if not IsAdmin(source) then return false end

    local title, section, sub = ParseCode(data.code)

    MySQL.insert.await([[
        INSERT INTO mdt_penal_codes
            (category, code, name, type, fine_amount, jail_time, description, title_no, section_no, subsection)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { data.category, data.code, data.name, data.type, data.fine_amount or 0, data.jail_time or 0,
          data.description, title, section, sub })
    return true
end)

lib.callback.register('XS-MDT:server:updatePenalCode', function(source, data)
    if not HasPanel(source, 'penal') then return false end
    if not IsAdmin(source) then return false end

    local title, section, sub = ParseCode(data.code)

    MySQL.update.await([[
        UPDATE mdt_penal_codes
        SET category = ?, code = ?, name = ?, type = ?, fine_amount = ?, jail_time = ?, description = ?,
            title_no = ?, section_no = ?, subsection = ?
        WHERE id = ?
    ]], { data.category, data.code, data.name, data.type, data.fine_amount, data.jail_time, data.description,
          title, section, sub, data.id })
    return true
end)

lib.callback.register('XS-MDT:server:deletePenalCode', function(source, id)
    if not HasPanel(source, 'penal') then return false end
    if not IsAdmin(source) then return false end

    MySQL.update.await('UPDATE mdt_penal_codes SET active = 0 WHERE id = ?', { id })
    return true
end)
