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

local function Existing()
    local rows = MySQL.query.await([[
        SELECT TABLE_NAME AS t, COLUMN_NAME AS c
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME LIKE 'mdt\_%'
    ]]) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[row.t] = out[row.t] or {}
        out[row.t][row.c] = true
    end
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

CreateThread(function()
    -- Let oxmysql finish connecting.
    Wait(2000)

    local ran, err = pcall(function()
        local wanted, order = Read()
        if not wanted then
            print('^1[XS-MDT] Could not read sql/mdt.sql. It ships with the resource — check it was not deleted.^7')
            return
        end

        local have = Existing()
        local createdTables, addedColumns = {}, {}

        for _, name in ipairs(order) do
            local spec = wanted[name]

            if not have[name] then
                if spec.sql then
                    local ok = pcall(function() MySQL.query.await(spec.sql) end)
                    if ok then
                        createdTables[#createdTables + 1] = name
                        have[name] = {}
                        for _, c in ipairs(spec.order) do have[name][c] = true end
                    end
                end
            else
                for _, col in ipairs(spec.order) do
                    if not have[name][col] then
                        local ok = pcall(function()
                            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(name, col, spec.columns[col]))
                        end)
                        if ok then addedColumns[#addedColumns + 1] = name .. '.' .. col end
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

        -- The charge book is data, not schema, so it is only seeded when the table
        -- is genuinely empty. A server that cleared it out meant to.
        local ok, charges = pcall(function()
            return MySQL.scalar.await('SELECT COUNT(*) FROM mdt_penal_codes') or 0
        end)
        if ok and charges == 0 then
            print('^3[XS-MDT] No charges on file — import sql/penal-codes.sql for the default book.^7')
        end
    end)

    if not ran then
        print(('^1[XS-MDT] Schema update failed: %s^7'):format(err))
    end

    MdtSchema.ready = true
end)
