Config = {}


-- ═══════════════════════════════════════════════════════════════════════════
--  FRAMEWORK
--  'auto' picks whichever of qbx_core or qb-core is started. Force it only if
--  you run both for a migration and want the MDT pinned to one.
-- ═══════════════════════════════════════════════════════════════════════════
Config.Framework = 'auto'   -- auto | qbox | qbcore

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
        color     = '#3b82f6',   -- NUI accent
        blipColor = 3,           -- GTA blip colour (3 = blue)
        icon      = 'shield',   -- an icon name from html/css/icons.css
        jobs      = { 'police', 'sheriff', 'swat', 'statepolice' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians', 'vehicles',
            'warrants', 'bolos', 'arrests', 'citations', 'incidents', 'penal',
            'cases', 'evidence', 'weapons', 'cameras',
            'cad', 'callhistory', 'bulletins',
            'mugshots', 'shiftlog',
            'ia', 'fto', 'sop', 'management',
        },
    },

    ems = {
        label     = 'Emergency Medical Services',
        short     = 'EMS',
        color     = '#2fbf6b',
        blipColor = 5,           -- yellow
        icon      = 'cross',
        jobs      = { 'ambulance', 'ems' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians',
            'cases', 'cameras',
            'pcr', 'medhistory', 'narclog',
            'cad', 'callhistory', 'bulletins',
            'shiftlog',
            'ia', 'fto', 'sop', 'management',
        },
    },

    fire = {
        label     = 'Fire Department',
        short     = 'FD',
        color     = '#e5533d',
        blipColor = 1,           -- red
        icon      = 'flame',
        jobs      = { 'fire', 'firefighter' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians',
            'cases', 'cameras',
            'fireincidents', 'hazmat', 'apparatus',
            'cad', 'callhistory', 'bulletins',
            'shiftlog',
            'ia', 'fto', 'sop', 'management',
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

-- The start-up screen the first time the MDT is opened each session.
-- Any key or a click skips it.
Config.BootScreen = true

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
-- ═══════════════════════════════════════════════════════════════════════════
--  CAMERAS
--  The places that actually have cameras: shops, banks, forecourts, the
--  casino. Seeded into mdt_cameras on start with INSERT IGNORE, so a camera
--  you rename or move in the panel is never overwritten by a restart.
--
--  Add your own here rather than only in the panel — a camera added in the
--  panel is fine, but one DELETED in the panel comes back on the next restart
--  if it is still listed below. Remove it here instead.
--
--  Coordinates are the front of the building, near enough for a waypoint.
--  kind: fixed | traffic | atm | transit | private
-- ═══════════════════════════════════════════════════════════════════════════
Config.SeedCameras = true

Config.DefaultCameras = {
    -- ── Banks ─────────────────────────────────────────────────────────────
    { code = 'BNK-01', label = 'Fleeca — Legion Square',        area = 'Downtown',      kind = 'private', coords = { x = 149.1,   y = -1040.2, z = 29.4 } },
    { code = 'BNK-02', label = 'Fleeca — Hawick Avenue',        area = 'Rockford Hills', kind = 'private', coords = { x = 313.2,   y = -284.5,  z = 54.2 } },
    { code = 'BNK-03', label = 'Fleeca — Alta Street',          area = 'Burton',        kind = 'private', coords = { x = -351.5,  y = -49.5,   z = 49.0 } },
    { code = 'BNK-04', label = 'Fleeca — Great Ocean Highway',  area = 'Banham Canyon', kind = 'private', coords = { x = -1212.0, y = -330.8,  z = 37.8 } },
    { code = 'BNK-05', label = 'Fleeca — Route 68',             area = 'Harmony',       kind = 'private', coords = { x = 1175.0,  y = 2706.6,  z = 38.1 } },
    { code = 'BNK-06', label = 'Fleeca — Paleto Bay',           area = 'Paleto Bay',    kind = 'private', coords = { x = -2962.6, y = 482.2,   z = 15.7 } },
    { code = 'BNK-07', label = 'Pacific Standard — main floor', area = 'Pillbox Hill',  kind = 'private', coords = { x = 253.9,   y = 225.4,   z = 101.9 } },
    { code = 'BNK-08', label = 'Blaine County Savings',         area = 'Paleto Bay',    kind = 'private', coords = { x = -109.3,  y = 6464.1,  z = 31.6 } },

    -- ── Shops ─────────────────────────────────────────────────────────────
    { code = 'STR-01', label = "24/7 — Strawberry",             area = 'Strawberry',    kind = 'private', coords = { x = 25.7,    y = -1347.3, z = 29.5 } },
    { code = 'STR-02', label = "24/7 — Little Seoul",           area = 'Little Seoul',  kind = 'private', coords = { x = -709.1,  y = -904.2,  z = 19.2 } },
    { code = 'STR-03', label = "24/7 — Morningwood",            area = 'Morningwood',   kind = 'private', coords = { x = -1487.0, y = -379.1,  z = 40.2 } },
    { code = 'STR-04', label = "24/7 — Tataviam Mountains",     area = 'El Burro',      kind = 'private', coords = { x = 1135.8,  y = -982.3,  z = 46.4 } },
    { code = 'STR-05', label = "24/7 — Richman Glen",           area = 'Richman',       kind = 'private', coords = { x = -2968.2, y = 390.9,   z = 15.0 } },
    { code = 'STR-06', label = "24/7 — Route 68",               area = 'Harmony',       kind = 'private', coords = { x = 1959.0,  y = 3740.0,  z = 32.3 } },
    { code = 'STR-07', label = "24/7 — Grapeseed",              area = 'Grapeseed',     kind = 'private', coords = { x = 1729.2,  y = 6414.1,  z = 35.0 } },
    { code = 'STR-08', label = "24/7 — Mount Chiliad",          area = 'Chiliad',       kind = 'private', coords = { x = 2549.0,  y = 385.1,   z = 108.6 } },
    { code = 'STR-09', label = 'LTD — Grove Street',            area = 'Davis',         kind = 'private', coords = { x = -47.4,   y = -1757.5, z = 29.4 } },
    { code = 'STR-10', label = 'LTD — Mirror Park',             area = 'Mirror Park',   kind = 'private', coords = { x = 1163.4,  y = -323.8,  z = 69.2 } },
    { code = 'STR-11', label = "Rob's Liquor — Prosperity",     area = 'Vespucci',      kind = 'private', coords = { x = -1222.9, y = -906.9,  z = 12.3 } },
    { code = 'STR-12', label = "Rob's Liquor — Sandy Shores",   area = 'Sandy Shores',  kind = 'private', coords = { x = 1166.0,  y = 2708.9,  z = 38.2 } },

    -- ── Jewellers, guns, gambling ─────────────────────────────────────────
    { code = 'HVT-01', label = 'Vangelico Jewelers',            area = 'Rockford Hills', kind = 'private', coords = { x = -630.1, y = -238.4,  z = 38.1 } },
    { code = 'HVT-02', label = 'Ammu-Nation — Pillbox Hill',    area = 'Pillbox Hill',  kind = 'private', coords = { x = 21.7,    y = -1106.7, z = 29.8 } },
    { code = 'HVT-03', label = 'Ammu-Nation — Sandy Shores',    area = 'Sandy Shores',  kind = 'private', coords = { x = 1692.5,  y = 3759.5,  z = 34.7 } },
    { code = 'HVT-04', label = 'Diamond Casino — main entrance', area = 'East Vinewood', kind = 'private', coords = { x = 925.3,  y = 46.3,    z = 81.1 } },
    { code = 'HVT-05', label = 'Vanilla Unicorn — car park',    area = 'Strawberry',    kind = 'private', coords = { x = 127.4,   y = -1298.0, z = 29.2 } },

    -- ── Street and traffic ────────────────────────────────────────────────
    { code = 'TRF-01', label = 'Legion Square — north corner',  area = 'Downtown',      kind = 'fixed',   coords = { x = 195.4,   y = -933.8,  z = 30.7 } },
    { code = 'TRF-02', label = 'Alta Street junction',          area = 'Downtown',      kind = 'traffic', coords = { x = 121.3,   y = -740.9,  z = 45.8 } },
    { code = 'TRF-03', label = 'Vespucci Boulevard',            area = 'Vespucci',      kind = 'traffic', coords = { x = -1210.8, y = -1152.4, z = 7.6 } },
    { code = 'TRF-04', label = 'Route 68 — eastbound',          area = 'Harmony',       kind = 'traffic', coords = { x = 1163.2,  y = 2664.1,  z = 37.9 } },
    { code = 'TRF-05', label = 'Great Ocean Highway — Paleto',  area = 'Paleto Bay',    kind = 'traffic', coords = { x = -232.6,  y = 6318.1,  z = 31.5 } },
    { code = 'TRF-06', label = 'Del Perro Freeway — La Puerta', area = 'La Puerta',     kind = 'traffic', coords = { x = -717.4,  y = -1284.1, z = 5.1 } },
    { code = 'TRF-07', label = 'Elgin Avenue',                  area = 'Mission Row',   kind = 'traffic', coords = { x = 440.7,   y = -984.9,  z = 30.7 } },

    -- ── Transit ───────────────────────────────────────────────────────────
    { code = 'TRN-01', label = 'LS Transit — Pillbox Hill',     area = 'Pillbox Hill',  kind = 'transit', coords = { x = -541.1,  y = -1275.9, z = 26.6 } },
    { code = 'TRN-02', label = 'LS International — terminal',   area = 'LSIA',          kind = 'transit', coords = { x = -1037.7, y = -2737.9, z = 20.2 } },
    { code = 'TRN-03', label = 'Paleto Bay — transit stop',     area = 'Paleto Bay',    kind = 'transit', coords = { x = -232.6,  y = 6318.1,  z = 31.5 } },
}


-- ═══════════════════════════════════════════════════════════════════════════
--  CERTIFICATIONS
--  What a supervisor can issue on the roster. These are labels only — the MDT
--  records who holds what and who signed it off, and nothing here gates a
--  weapon or a vehicle. Keyed by department.
-- ═══════════════════════════════════════════════════════════════════════════
Config.Certifications = {
    police = {
        'Field Training Officer', 'Firearms Instructor', 'Taser', 'Less Lethal',
        'Rifle', 'Air Unit', 'Marine Unit', 'K9 Handler', 'Motorcycle',
        'Pursuit Driving', 'SWAT', 'Negotiator', 'Detective', 'Evidence Technician',
        'Accident Reconstruction', 'Drone Operator',
    },
    ems = {
        'EMT Basic', 'EMT Advanced', 'Paramedic', 'Flight Medic',
        'Field Training Officer', 'Trauma', 'Pediatrics', 'Ambulance Driving',
    },
    fire = {
        'Firefighter I', 'Firefighter II', 'Driver Operator', 'Engineer',
        'Hazmat Technician', 'Rescue Technician', 'Fire Investigator',
        'Field Training Officer', 'Aerial Operator',
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
--  FIELD TRAINING
--  The phases a trainee moves through. A phase is passed or failed by a
--  trainer on the FTO panel; the names are yours to change.
-- ═══════════════════════════════════════════════════════════════════════════
Config.FTOPhases = {
    police = { 'Phase 1 — Observation', 'Phase 2 — Primary', 'Phase 3 — Solo Evaluation', 'Sign Off' },
    ems    = { 'Phase 1 — Ride Along', 'Phase 2 — Primary Care', 'Phase 3 — Lead Medic', 'Sign Off' },
    fire   = { 'Phase 1 — Probationary', 'Phase 2 — Engine', 'Phase 3 — Truck', 'Sign Off' },
}

Config.SupervisorGrade = 3

-- Fine deduction from player bank accounts
Config.FineDeduction = {
    Enabled               = true,   -- Master toggle for all automatic fine deductions
    AutoDeductArrests     = true,   -- Deduct arrest fines immediately if player is online
    AutoDeductCitations   = false,  -- Deduct citation fines immediately on issue (false = pay-later model)
    AutoDeductOnMarkPaid  = true,   -- Deduct from bank when a supervisor marks citation paid
}

-- Body camera logging — records key officer actions
-- ═══════════════════════════════════════════════════════════════════════════
--  BODY CAMS
--  Two things share this block: the action log every officer writes as they
--  work, and the live view a supervisor can open on an on-duty officer.
--
--  The live view is a chest-mounted camera, so it looks where the officer's
--  body faces rather than where their head turns — which is what a real body
--  cam does. Watching is written to the audit log every time, and by default
--  the officer is told it is happening.
-- ═══════════════════════════════════════════════════════════════════════════
Config.BodyCam = {
    Enabled       = true,
    RetentionDays = 30,  -- Auto-purge logs older than this (0 = keep forever)

    Live = {
        Enabled       = true,
        SupervisorOnly = true,   -- false lets any officer watch their own department
        NotifyOfficer  = true,   -- tell the officer their cam is being viewed
        SameDepartment = true,   -- a fire captain has no business on a police cam

        -- Where the camera sits. Bone is SKEL_Spine3 (chest); the offset is
        -- metres, forward on Y and up on Z. Pitch tilts it down slightly, the
        -- way a clipped-on camera sits.
        Bone   = 24818,
        Offset = { x = 0.0, y = 0.22, z = 0.0 },
        Pitch  = -4.0,
        Fov    = 80.0,

        -- Dropped if the officer goes off duty, disconnects or leaves the
        -- watcher's streaming range for this long.
        SignalLossSeconds = 8,
    },
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
-- ═══════════════════════════════════════════════════════════════════════════
--  DISPATCH ALERTS (outbound)
--  The MDT keeps its own CAD, and every call it creates is ALSO pushed to
--  whatever dispatch resource you already run, because half the department
--  has that UI open and not this one.
--
--    'auto'                  every supported resource that is started
--    { 'ps-dispatch' }       only the ones you name
--    false                   off
--
--  Supported out of the box: ps-dispatch, qs-dispatch, cd_dispatch,
--  core_dispatch, linden_outlawalert. Each one is a single function in
--  server/dispatch-adapters.lua — if your version takes different fields,
--  that is the one place to change, and a mismatch prints a line rather
--  than breaking anything.
--
--  This is separate from Config.DispatchAdapters below, which is for a
--  resource that REPLACES the CAD rather than mirroring it.
-- ═══════════════════════════════════════════════════════════════════════════
Config.DispatchAlerts = 'auto'

-- Only needed if your dispatch runs under a folder name the MDT can't match.
-- Example: { ['ps-dispatch'] = 'my-dispatch' }
Config.DispatchAlertResources = {}

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

-- Job names alerted for a call type. Dispatch resources filter by job, not
-- by department, so this flattens the departments back out.
function Dept.JobsForCall(callType)
    local jobs = {}
    for _, key in ipairs(Dept.DepartmentsForCall(callType)) do
        local dept = Config.Departments[key]
        for _, job in ipairs(dept and dept.jobs or {}) do jobs[#jobs + 1] = job end
    end
    return jobs
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

    -- Granting a licence someone does not hold. Set true to leave that to
    -- supervisors.
    GrantRequiresSupervisor = false,

    Types = {
        { key = 'driver',   label = 'Driver',   icon = '🚗' },
        { key = 'weapon',   label = 'Weapon',   icon = '🔫' },
        { key = 'business', label = 'Business', icon = '💼' },
    },
}
