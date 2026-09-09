Config = {}

-- ═══════════════════════════════════════════════════════════════════════════
--  DEPARTMENTS
--  Each department maps a set of jobs to the panels those jobs can open.
--  `panels` is the single source of truth for access: the sidebar is built
--  from it, and every server callback re-checks it. Remove a panel here and
--  it disappears from the UI *and* stops answering.
--
--  Panel keys — shared:  dashboard · roster · map · civilians · cad
--                        callhistory · bulletins · shiftlog
--               police:  vehicles · warrants · bolos · arrests · citations
--                        incidents · penal · mugshots
--               ems:     pcr · medhistory · narclog
--               fire:    fireincidents · hazmat · apparatus
-- ═══════════════════════════════════════════════════════════════════════════
Config.Departments = {
    police = {
        label     = 'Police Department',
        short     = 'PD',
        color     = '#6366f1',   -- NUI accent
        blipColor = 3,           -- GTA blip colour (3 = blue)
        icon      = '⬡',
        jobs      = { 'police', 'sheriff', 'swat', 'statepolice' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians', 'vehicles',
            'warrants', 'bolos', 'arrests', 'citations', 'incidents', 'penal',
            'cad', 'callhistory', 'bulletins',
            'mugshots', 'shiftlog',
        },
    },

    ems = {
        label     = 'Emergency Medical Services',
        short     = 'EMS',
        color     = '#22c55e',
        blipColor = 5,           -- yellow
        icon      = '✚',
        jobs      = { 'ambulance', 'ems' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians',
            'pcr', 'medhistory', 'narclog',
            'cad', 'callhistory', 'bulletins',
            'shiftlog',
        },
    },

    fire = {
        label     = 'Fire Department',
        short     = 'FD',
        color     = '#ef4444',
        blipColor = 1,           -- red
        icon      = '🔥',
        jobs      = { 'fire', 'firefighter' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians',
            'fireincidents', 'hazmat', 'apparatus',
            'cad', 'callhistory', 'bulletins',
            'shiftlog',
        },
    },
}

-- Built from Config.Departments below — do not edit by hand.
-- Maps job name → department key, e.g. Config.AuthorizedJobs['ambulance'] == 'ems'.
Config.AuthorizedJobs = {}
for dept, cfg in pairs(Config.Departments) do
    for _, job in ipairs(cfg.jobs or {}) do
        Config.AuthorizedJobs[job] = dept
    end
end

-- Minimum job grade to access MDT (0 = all grades)
Config.MinGrade = 0

-- Keybind to open MDT (default: F9 — players can rebind in Settings > Key Bindings)
Config.OpenKey = 'F9'

-- How long (ms) to hold key to open MDT (0 = instant)
Config.HoldTime = 0

-- Show MDT only while on duty
Config.OnDutyOnly = true

-- CAD Settings
Config.CAD = {
    -- Auto-assign officer to call when they respond
    AutoAssign = true,
    -- Dispatch notification method: 'chat', 'notification', 'both'
    NotifyMethod = 'notification',
    -- Max units per call before it shows as over-staffed
    MaxUnitsPerCall = 6,
}

-- Civilian records: pull from QBCore players table
Config.UseQBCoreCharacters = true

-- Default penal code categories seeded on first run
Config.SeedPenalCodes = true

-- Discord webhook for audit logs (leave empty to disable)
Config.AuditWebhook = ''

-- Map blip for active CAD calls
Config.CADBlip = {
    Sprite = 161,
    Color = 1,
    Scale = 0.8,
}

-- ═══════════════════════════════════════════════════════════════════════════
--  LIVE UNIT BLIPS
--  Police, EMS and Fire see each other on the map, coloured per department.
--  Set Enabled = false to turn the whole system off (no position broadcast,
--  no blips) if you'd rather run your own blip script.
-- ═══════════════════════════════════════════════════════════════════════════
Config.Blips = {
    Enabled = true,

    -- Which jobs broadcast a position and appear on the map.
    -- nil  → every job listed in Config.Departments (the usual choice)
    -- list → explicit override, e.g. { 'police', 'ambulance' }
    TrackedJobs = nil,

    -- true  → all departments see each other (PD sees EMS sees Fire)
    -- false → you only see units from your own department
    CrossDepartment = true,

    -- Only show units who are on duty. Independent of Config.OnDutyOnly so an
    -- off-duty officer can still read the MDT without appearing on the map.
    OnDutyOnly = true,

    UpdateInterval = 2000,  -- ms between position broadcasts (2000 is plenty)
    StaleAfter     = 15,    -- seconds without an update before a unit drops off

    Scale      = 0.82,
    ShortRange = false,     -- false = visible at every map zoom level
    ShowName   = true,
    ShowBadge  = true,
    ShowVehicle= true,      -- append [VEH] / [AIR] / [BOAT] to the label

    -- Per-department colour override. Falls back to the department's
    -- blipColor in Config.Departments when a job isn't listed here.
    JobColors = {
        -- ['swat'] = 27,   -- example: give SWAT its own colour
    },
}

-- Grade level (numeric) required for supervisor features:
-- editing penal codes, deleting incidents, marking citations paid, viewing body cams.
-- Per-department overrides live in Config.Departments[dept].supervisorGrade.
Config.SupervisorGrade = 3

-- Fine deduction from player bank accounts
Config.FineDeduction = {
    Enabled               = true,   -- Master toggle for all automatic fine deductions
    AutoDeductArrests     = true,   -- Deduct arrest fines immediately if player is online
    AutoDeductCitations   = false,  -- Deduct citation fines immediately on issue (false = pay-later model)
    AutoDeductOnMarkPaid  = true,   -- Deduct from bank when a supervisor marks citation paid
}

-- Body camera logging — records key officer actions
Config.BodyCam = {
    Enabled       = true,
    RetentionDays = 30,  -- Auto-purge logs older than this (0 = keep forever)
}

-- ox_target / qb-target integration — right-click players in-world
Config.Target = {
    Enabled     = true,
    MaxDistance = 3.0,
}

-- UI sound effects inside the MDT NUI
Config.Sounds = {
    Enabled = true,
    Volume  = 0.08,  -- 0.0 – 1.0
}

-- Jail integration — triggers when an arrest with jail time is logged
-- Options: 'qb-prison'  → TriggerEvent('qb-prison:server:sendToJail', src, minutes)
--          'ps-prison'  → TriggerEvent('prison:server:SendToJail', src, minutes)
--          'custom'     → exports['XS-MDT']:OnJailPlayer(src, minutes) — implement your own handler
--          false        → disabled (fires client event only, handle in client/main.lua)
Config.JailResource = false

-- 'auto' selects the first running adapter and safely falls back to the
-- built-in CAD. A provider can also be forced by its id, or set to 'internal'.
Config.DispatchProvider = 'auto'
Config.DisableInternalDispatchDetection = false
Config.DispatchAdapters = {
    { id = 'XS-Dispatch', resource = 'XS-Dispatch', priority = 100 },
    -- Generic export adapter example:
    -- { id = 'my-dispatch', resource = 'my-dispatch', priority = 50, exports = {
    --     getActiveCalls='GetActiveCalls', createCall='CreateCall', respond='RespondUnit',
    --     setCallStatus='SetCallStatus', addCallNote='AddCallNote' } },
}

-- ═══════════════════════════════════════════════════════════════════════════
--  CALL ROUTING
--  Which departments are alerted for each dispatch call type. A call type
--  that isn't listed uses Default. Officer-safety alerts (panic, backup)
--  bypass this entirely and always reach everyone.
-- ═══════════════════════════════════════════════════════════════════════════
Config.CallRouting = {
    Default = { 'police' },

    Types = {
        SHOTS_FIRED   = { 'police' },
        FIGHT         = { 'police' },
        ROBBERY       = { 'police' },
        BANK_ROBBERY  = { 'police' },
        STORE_ROBBERY = { 'police' },
        TRAFFIC_STOP  = { 'police' },
        SUSPICIOUS    = { 'police' },

        MEDICAL       = { 'ems' },
        FIRE          = { 'fire', 'ems' },            -- EMS stages on every structure fire
        VEHICLE_CRASH = { 'police', 'ems', 'fire' },  -- full response

        CUSTOM        = { 'police', 'ems', 'fire' },  -- manual calls go out wide
    },
}

-- Department resolver lives in config.lua so it is guaranteed to exist on
-- both client and server, even when a server owner updates only core files.
Dept = Dept or {}

-- Departments alerted for a call type.
function Dept.DepartmentsForCall(callType)
    local routing = Config.CallRouting or {}
    return (routing.Types or {})[callType] or routing.Default or { 'police' }
end

-- Should this job be alerted about this call? `callType` nil means an
-- officer-safety broadcast, which every department receives.
function Dept.ReceivesCall(jobName, callType)
    local dept = Dept.OfJob(jobName)
    if not dept then return false end
    if not callType then return true end
    for _, candidate in ipairs(Dept.DepartmentsForCall(callType)) do
        if candidate == dept then return true end
    end
    return false
end

function Dept.OfJob(jobName)
    return jobName and Config.AuthorizedJobs[jobName] or nil
end

function Dept.ConfigOfJob(jobName)
    local key = Dept.OfJob(jobName)
    return key and Config.Departments[key] or nil
end

function Dept.PanelsOfJob(jobName)
    local cfg = Dept.ConfigOfJob(jobName)
    return cfg and cfg.panels or {}
end

function Dept.HasPanel(jobName, panel)
    for _, candidate in ipairs(Dept.PanelsOfJob(jobName)) do
        if candidate == panel then return true end
    end
    return false
end

function Dept.SupervisorGrade(jobName)
    local cfg = Dept.ConfigOfJob(jobName)
    return (cfg and cfg.supervisorGrade) or Config.SupervisorGrade or 3
end

function Dept.IsTracked(jobName)
    local blips = Config.Blips or {}
    if not blips.Enabled then return false end
    if blips.TrackedJobs then
        for _, trackedJob in ipairs(blips.TrackedJobs) do
            if trackedJob == jobName then return true end
        end
        return false
    end
    return Dept.OfJob(jobName) ~= nil
end

function Dept.CanSeeUnit(viewerJob, unitJob)
    if not Dept.IsTracked(viewerJob) or not Dept.IsTracked(unitJob) then return false end
    if (Config.Blips or {}).CrossDepartment then return true end
    return Dept.OfJob(viewerJob) == Dept.OfJob(unitJob)
end

function Dept.BlipColor(jobName)
    local override = ((Config.Blips or {}).JobColors or {})[jobName]
    if override then return override end
    local cfg = Dept.ConfigOfJob(jobName)
    return (cfg and cfg.blipColor) or 3
end

-- Licences shown on a civilian profile.
--
-- Qbox already tracks whether a character HOLDS each of these, in
-- metadata.licences. What it has no concept of is a licence being suspended —
-- who did it, why, or until when — which is most of what an officer wants at a
-- traffic stop. The MDT stores that layer alongside it.
--
-- `key` must match the key Qbox uses in metadata.licences. Anything listed
-- here that Qbox does not know about simply shows as "not held".
Config.Licences = {
    Enabled = true,

    -- Suspending or revoking also flips the Qbox metadata flag off, so any
    -- other resource that checks `metadata.licences.driver` sees it too. Turn
    -- this off to keep the MDT's view advisory only.
    WriteBackToMetadata = true,

    -- Only supervisors may revoke. Suspension is an ordinary officer action,
    -- because it is reversible and happens roadside.
    RevokeRequiresSupervisor = true,

    Types = {
        { key = 'driver',   label = 'Driver',   icon = '🚗' },
        { key = 'weapon',   label = 'Weapon',   icon = '🔫' },
        { key = 'business', label = 'Business', icon = '💼' },
    },
}
