--[[  Schema

      The MDT brings its own database up to date on start. It reads the schema
      it ships with, compares it to what is actually there, and adds whatever
      is missing.

      This exists because "run sql/mdt.sql" does not do what people reasonably
      assume it does. CREATE TABLE IF NOT EXISTS creates missing TABLES; it
      never touches a table that already exists, so a column added in a later
      version never arrives. What you get instead is "Unknown column 'aliases'"
      thrown from whichever panel happened to need it, with nothing in the
      message about which file to run.

      So sql/mdt.sql is the single source of truth and this applies it. Nothing
      is ever dropped, renamed or narrowed — only created and only added.
]]

--[[ The gate.

     Anything that touches the database on start has to wait for this, not for
     a timer. The camera seeder did not, and ran its INSERT against columns the
     migration had not added yet.

     It is set even when the migration fails, so a waiter is never stuck. ]]
MdtSchema = { ready = false }

function MdtSchema.Wait()
    while not MdtSchema.ready do Wait(50) end
end

local function Read()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/mdt.sql')
    if not raw then return nil end

    local tables, order = {}, {}

    for name, body in raw:gmatch('CREATE TABLE IF NOT EXISTS `([%w_]+)`%s*%((.-)\n%) ENGINE') do
        local columns, colOrder = {}, {}

        for line in body:gmatch('[^\n]+') do
            -- A column line starts with a backticked name. Everything else in
            -- there is a KEY, a PRIMARY KEY or a CONSTRAINT.
            local col, def = line:match('^%s*`([%w_]+)`%s+(.+)$')
            if col and not line:match('^%s*[A-Z]') then
                columns[col] = (def:gsub(',%s*$', ''))
                colOrder[#colOrder + 1] = col
            end
        end

        -- The closing paren has to be a real one. `%)` is an escaped literal,
        -- so it does not close the capture this opens with.
        local create = raw:match('(CREATE TABLE IF NOT EXISTS `' .. name .. '`.-\n%) ENGINE[^;]*;)')

        tables[name] = { columns = columns, order = colOrder, sql = create }
        order[#order + 1] = name
    end

    return tables, order
end

--[[ The columns a table really has, straight from the database.

     Read per table rather than trusted from a spec: a CREATE that quietly
     did nothing, or a table missed by the sweep below, both used to leave the
     pass thinking every column was present. ]]
local function ColumnsOf(name)
    local rows = MySQL.query.await([[
        SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { name }) or {}

    local out = {}
    for _, row in ipairs(rows) do out[row.c] = true end
    return out
end

--[[ Things a plain ADD COLUMN cannot express.

     mdt_evidence.incident_id was NOT NULL with a cascading foreign key, back
     when evidence could only hang off a report. Evidence is booked before any
     report exists now, so the column has to accept NULL and the cascade has to
     go — deleting a report should not destroy the evidence it mentioned. ]]
local function FixUps()
    local fk = MySQL.scalar.await([[
        SELECT CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mdt_evidence'
          AND CONSTRAINT_TYPE = 'FOREIGN KEY' AND CONSTRAINT_NAME = 'fk_evidence_incident'
    ]])
    if fk then
        MySQL.query.await('ALTER TABLE `mdt_evidence` DROP FOREIGN KEY `fk_evidence_incident`')
        print('[XS-MDT] dropped the evidence-to-report foreign key')
    end

    local nullable = MySQL.scalar.await([[
        SELECT IS_NULLABLE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mdt_evidence' AND COLUMN_NAME = 'incident_id'
    ]])
    if nullable == 'NO' then
        MySQL.query.await('ALTER TABLE `mdt_evidence` MODIFY COLUMN `incident_id` INT DEFAULT NULL')
        print('[XS-MDT] evidence no longer requires a report')
    end
end

-- The 35 charges every release before 3.0 seeded, exactly as they shipped.
local OLD_CHARGES = {
    { '12500(a) VC', 'Driving Without a License' }, { '22350 VC', 'Speeding' },
    { '23152(a) VC', 'Driving Under the Influence' }, { '23153(a) VC', 'DUI Causing Injury' },
    { '20001 VC', 'Hit and Run (Felony)' }, { '20002 VC', 'Hit and Run (Misdemeanor)' },
    { '2800.2 VC', 'Evading a Peace Officer' }, { '10851 VC', 'Vehicle Theft' },
    { '187 PC', 'Murder' }, { '664/187 PC', 'Attempted Murder' },
    { '245(a)(1) PC', 'Assault with a Deadly Weapon' }, { '240 PC', 'Assault' },
    { '242 PC', 'Battery' }, { '207 PC', 'Kidnapping' }, { '261 PC', 'Rape' },
    { '211 PC', 'Robbery' }, { '212.5 PC', 'Home Invasion Robbery' }, { '459 PC', 'Burglary' },
    { '487 PC', 'Grand Theft' }, { '488 PC', 'Petty Theft' }, { '594 PC', 'Vandalism' },
    { '25400 PC', 'Carrying a Concealed Weapon' }, { '26350 PC', 'Open Carry (Unloaded)' },
    { '417 PC', 'Brandishing a Weapon' }, { '12022.5 PC', 'Using a Firearm During a Felony' },
    { '11350 HS', 'Possession of a Controlled Substance' }, { '11351 HS', 'Possession for Sale' },
    { '11352 HS', 'Transportation/Sale of Controlled Substance' },
    { '11357 HS', 'Possession of Marijuana (Over Limit)' },
    { '69 PC', 'Obstruction of Justice' }, { '148(a)(1) PC', 'Resisting Arrest' },
    { '647(b) PC', 'Disorderly Conduct' }, { '13523 PC', 'Impersonating an Officer' },
    { '32 PC', 'Accessory After the Fact' }, { '182 PC', 'Criminal Conspiracy' },
}

local function OldChargeMatch()
    local parts, args = {}, {}
    for _, c in ipairs(OLD_CHARGES) do
        parts[#parts + 1] = '(code = ? AND name = ?)'
        args[#args + 1] = c[1]
        args[#args + 1] = c[2]
    end
    return '(' .. table.concat(parts, ' OR ') .. ')', args
end

--[[ The charge book ships with the resource, so nobody should have to import
     it by hand. It is seeded into an empty table, or into one holding nothing
     but the old default charges, which is a server upgrading from 2.x. A table
     with charges of the server's own is left alone.

     Once the book is in, the old defaults that came before it are retired, so
     the picker does not list both. Only rows exactly as they shipped: one a
     server renamed or re-priced is theirs now. ]]
local function ChargeBook()
    local match, args = OldChargeMatch()

    local total = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_penal_codes') or 0
    local book = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_penal_codes WHERE code LIKE 'PC %'") or 0
    local old = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_penal_codes WHERE ' .. match, args) or 0

    if book == 0 and (total == 0 or total == old) then
        local file = LoadResourceFile(GetCurrentResourceName(), 'sql/penal-codes.sql')
        if not file then
            print('^3[XS-MDT] sql/penal-codes.sql is missing, so the charge book could not be seeded.^7')
            return
        end
        -- The file is a header comment and one INSERT, which MySQL takes as a
        -- single statement, comment and all.
        MySQL.query.await(file)
        local n = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_penal_codes WHERE code LIKE 'PC %'") or 0
        print(('[XS-MDT] seeded the charge book: %d charges'):format(n))
    end

    local firstBook = MySQL.scalar.await("SELECT MIN(id) FROM mdt_penal_codes WHERE code LIKE 'PC %'")
    if not firstBook then return end

    local retiredArgs = { firstBook }
    for _, v in ipairs(args) do retiredArgs[#retiredArgs + 1] = v end
    local retired = MySQL.update.await(
        'UPDATE mdt_penal_codes SET active = 0 WHERE active = 1 AND id < ? AND ' .. match, retiredArgs) or 0
    if retired > 0 then
        print(('[XS-MDT] retired %d old default charges now the charge book is in'):format(retired))
    end
end

CreateThread(function()
    -- Let oxmysql finish connecting.
    Wait(2000)

    local ran, err = pcall(function()
        local wanted, order = Read()
        if not wanted then
            print('^1[XS-MDT] Could not read sql/mdt.sql. It ships with the resource — check it was not deleted.^7')
            return
        end

        local createdTables, addedColumns, failures = {}, {}, {}

        for _, name in ipairs(order) do
            local spec = wanted[name]

            --[[ No columns back means the table is not there.

                 CREATE TABLE IF NOT EXISTS succeeds as a no-op on a table that
                 already exists, so its success says nothing at all. Trusting
                 it — and assuming the table therefore matched the spec — is
                 what made a table skip its column check and add nothing. ]]
            local cols = ColumnsOf(name)

            if not next(cols) and spec.sql then
                local ok, e = pcall(function() MySQL.query.await(spec.sql) end)
                if ok then createdTables[#createdTables + 1] = name
                else failures[#failures + 1] = ('%s: %s'):format(name, e) end
                cols = ColumnsOf(name)
            end

            if next(cols) then
                for _, col in ipairs(spec.order) do
                    if not cols[col] and spec.columns[col] then
                        local ok, e = pcall(function()
                            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(name, col, spec.columns[col]))
                        end)
                        if ok then addedColumns[#addedColumns + 1] = name .. '.' .. col
                        else failures[#failures + 1] = ('%s.%s: %s'):format(name, col, e) end
                    end
                end
            end
        end

        pcall(FixUps)

        if #createdTables > 0 then
            print(('[XS-MDT] created %d table(s): %s'):format(#createdTables, table.concat(createdTables, ', ')))
        end
        if #addedColumns > 0 then
            print(('[XS-MDT] added %d column(s): %s'):format(#addedColumns, table.concat(addedColumns, ', ')))
        end
        if #createdTables == 0 and #addedColumns == 0 then
            print('[XS-MDT] database is up to date')
        end

        if #failures > 0 then
            print(('^1[XS-MDT] %d change(s) could not be applied:^7'):format(#failures))
            for i = 1, math.min(#failures, 8) do print('^1[XS-MDT]   ' .. failures[i] .. '^7') end
        end

        local ok, e = pcall(ChargeBook)
        if not ok then print(('^1[XS-MDT] Could not check the charge book: %s^7'):format(e)) end
    end)

    if not ran then
        print(('^1[XS-MDT] Schema update failed: %s^7'):format(err))
    end

    MdtSchema.ready = true
end)
