<h1 align="center">XS-MDT</h1>

<p align="center">A full MDT for <strong>QBox</strong> — Police, EMS and Fire, each with their own panels, sharing one live CAD, map and unit roster.</p>

<p align="center">
  <a href="https://github.com/XyraL/XS-MDT/releases"><img src="https://img.shields.io/github/v/release/XyraL/XS-MDT?style=flat-square&color=70baff&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/framework-QBox-55dcff?style=flat-square" alt="framework">
  <img src="https://img.shields.io/badge/price-free-30d158?style=flat-square" alt="price">
  <a href="https://xyralscripts.dev/docs-xs-mdt"><img src="https://img.shields.io/badge/docs-xyralscripts.dev-a889ff?style=flat-square" alt="docs"></a>
  <a href="https://discord.gg/XRURAw4TM2"><img src="https://img.shields.io/badge/support-discord-5865F2?style=flat-square" alt="support"></a>
</p>

<p align="center">
  <a href="https://xyralscripts.dev/xs-mdt">Website</a> &nbsp;·&nbsp;
  <a href="https://xyralscripts.dev/docs-xs-mdt">Setup guide</a> &nbsp;·&nbsp;
  <a href="https://github.com/XyraL/XS-MDT/releases">Releases</a> &nbsp;·&nbsp;
  <a href="https://discord.gg/XRURAw4TM2">Discord</a>
</p>

<!-- SCREENSHOTS: drop 2-3 in-game shots here once captured -->

---

## Features

### Multi-department

- **Three departments in one resource** — Police, EMS and Fire each get their own sidebar, panels and accent colour, resolved from the player's job
- **Panel-level permissions** — `Config.Departments[dept].panels` is the single source of truth: the sidebar is built from it *and* every server callback re-checks it, so a panel a department doesn't have can't be reached even by hand-crafting the request
- **Live unit blips** — Police, EMS and Fire see each other on the game map, coloured per department. Fully toggleable so you can run your own blip script instead
- **Live map panel** — Leaflet tile map of San Andreas with department-coloured
  unit markers, heading arrows, active CAD calls, follow-a-unit, and click-to-waypoint
- **Department call routing** — `Config.CallRouting` decides who is alerted: medical goes to EMS, structure fires to Fire *and* EMS, crashes to all three. Panic and backup always reach everyone
- **Data separation** — EMS and Fire see identity and medical data; criminal history, warrants and officer notes stay with Police

### EMS

- **Patient Care Reports** — Chief complaint, injuries, treatments, vitals (BP/pulse/SpO₂/GCS), disposition, transport destination and priority
- **Medical Records** — Per-civilian blood type, allergies, conditions, medications, DNR and organ-donor flags, plus a dated history and prior PCRs
- **Controlled Substance Log** — Every draw, administration and waste with a witness field, and a reconciliation view that flags discrepancies

### Fire

- **Fire Incident Reports** — Type, alarm level, cause, structure type, units and personnel, casualties, damage estimate, acres burned and water used
- **Hazmat** — Substance, UN number, hazard class, containment state, evacuation radius and injuries
- **Apparatus** — Fleet roster with status, plus an inspection log; a failed check takes the unit out of service automatically

### Police

- **Report search** — one box that searches case numbers, titles, narratives and officers across every report
- **Evidence** — photos, items and notes logged on a report with who logged what and when. Your own entries can be removed for 15 minutes; after that it takes a supervisor
- **Department stats** — arrests, citations, reports, active warrants and fines on the dashboard with a daily activity chart, switchable between 7 and 30 days. Every officer sees the numbers; the top-officers list stays with supervisors
- **Licence status** — Driver, weapon and business licences on the civilian profile, with suspend, revoke and reinstate. Qbox only tracks whether someone *holds* a licence; the MDT adds the state it is in, who changed it, and why. Suspending also flips the Qbox flag so other resources agree, and it will never hand back a licence that was never held. Revoking is supervisor-only by default
- **Aliases** — Record street names and false identities, and find people by them. Searching by phone number works too, with or without dashes
- **Partial plate search** — An officer who caught three characters of a plate gets a shortlist instead of nothing. Plates with no registration still report an outstanding BOLO
- **Report lifecycle** — Reports move through draft, open, under review and closed. Drafts are visible only to their author. Authors move their own reports; supervisors move anyone's
- **Report templates** — Traffic stop, use of force, pursuit, robbery and assault skeletons that prompt for the things a report is useless without. Edit them at the top of `html/js/panels/incidents.js`
- **Autosaved narratives** — What you are typing is saved locally as you go, and offered back if the panel closes on you
- **Case numbers** — Generated as `INC-<year>-<id>` instead of being typed by hand

- **CAD Dispatch** — Create, update, and respond to live calls with P1/P2/P3 priority, elapsed timer, unit notes, GPS routing, and call history
- **Civilian Lookup** — Full profiles with mugshot, flags, arrest history, citations, vehicles, warrants, and officer notes
- **Vehicle Lookup** — Plate search with registration details and traffic stop shortcut
- **Arrest Records** — Collapsible cards with charges, fine/jail info, tags, and officer/date filters
- **Citation Records** — Same as arrests; supervisor can mark citations paid with optional auto bank deduction
- **Incident Reports** — Narrative reports with severity, involved persons/officers, linked arrests/citations
- **Warrants** — Issue, clear, and expire warrants; active count badge on nav
- **BOLOs** — Person and vehicle lookups with active badge
- **Penal Codes** — Searchable, supervisor-editable code library used in arrest/citation modals
- **Department Bulletins** — Supervisor-posted notices with Normal/Urgent/Critical priority, pinning, and auto-expiry
- **Civilian Flags** — Chip-based flag editor with 9 presets and custom flags; flags display in profile banner
- **Tags** — Color-coded tags on arrests, citations, and incidents
- **Body Camera Log** — Auto-records key officer actions; viewable per-officer by supervisors
- **Audit Log** — Supervisor-only viewer with action/officer/date filters (also posts to Discord webhook)
- **Supervisor Stats** — Weekly arrests, citations, fines, and top officer leaderboard on the dashboard
- **ox_target / qb-target** — Right-click players in-world to open MDT or issue citation
- **Sound Effects** — Subtle Web Audio API sounds, no extra files required
- **Real-time CAD** — New calls and status changes broadcast live to all on-duty officers

---

## Dependencies

| Resource | Required |
|---|---|
| [qbx_core](https://github.com/Qbox-project/qbx_core) | Yes |
| [ox_lib](https://github.com/overextended/ox_lib) | Yes |
| [oxmysql](https://github.com/overextended/oxmysql) | Yes |
| [ox_target](https://github.com/overextended/ox_target) **or** [qb-target](https://github.com/qbcore-framework/qb-target) | Optional |
| [XS-Dispatch](https://github.com/XyraL/XS-Dispatch) *(or any adapter)* | Optional — falls back to the built-in CAD |

> **Note:** qbx_core is required. Standard QBCore (`qb-core`) is not directly supported.

---

## Installation

### 1. Add the resource

Place the `XS-MDT` folder in your `resources` directory (e.g. `resources/[standalone]/XS-MDT`).

Add to your `server.cfg`:
```cfg
ensure XS-MDT
```

### 2. Import the database

Run `sql/mdt.sql` against your database. It uses `CREATE TABLE IF NOT EXISTS` throughout, so it is safe to re-run.

If you are **upgrading from a previous version**, run only the commented `ALTER TABLE` lines at the top of the SQL file that match your current version.

> **Upgrading to 2.0:** run the `v1.6 → v2.0` block at the top of `sql/mdt.sql`
> (one new table, `mdt_evidence`). Nothing existing is touched.

> **Upgrading to 1.6:** run the `v1.5 → v1.6` block at the top of `sql/mdt.sql`.
> It adds `mdt_licences` and four columns, and touches nothing existing. Licence
> status starts empty, which reads as "valid" for everyone until an officer
> changes one.

> **Upgrading to multi-department:** re-run `sql/mdt.sql`. It adds eight new
> tables (`mdt_pcr`, `mdt_medical`, `mdt_medical_history`, `mdt_narc_log`,
> `mdt_fire_incidents`, `mdt_hazmat`, `mdt_apparatus`, `mdt_apparatus_log`) and
> leaves every existing table untouched.

### 3. Configure

Open `config.lua` and adjust the settings for your server (see [Configuration](#configuration) below).

### 4. Restart

```
restart XS-MDT
```

---

## Configuration

All options are in `config.lua`.

### Departments

`Config.Departments` maps jobs to a department, and each department to the panels
its members may open. This one table drives the sidebar, the theming and every
permission check.

```lua
Config.Departments = {
    police = {
        label = 'Police Department', short = 'PD',
        color = '#6366f1', blipColor = 3, icon = '⬡',
        jobs  = { 'police', 'sheriff', 'swat', 'statepolice' },
        supervisorGrade = 3,
        panels = { 'dashboard', 'roster', 'map', 'civilians', 'vehicles',
                   'warrants', 'bolos', 'arrests', 'citations', 'incidents',
                   'penal', 'cad', 'callhistory', 'bulletins', 'mugshots', 'shiftlog' },
    },
    ems  = { jobs = { 'ambulance', 'ems' },        panels = { …, 'pcr', 'medhistory', 'narclog' } },
    fire = { jobs = { 'fire', 'firefighter' },     panels = { …, 'fireincidents', 'hazmat', 'apparatus' } },
}
```

Adding a job to a department is all it takes — no other file needs editing.
Removing a panel from the list hides it in the UI **and** makes its server
callbacks refuse to answer, so the two can never drift apart.

**Available panel keys**

| Group | Keys |
|---|---|
| Shared | `dashboard` `roster` `map` `civilians` `cad` `callhistory` `bulletins` `shiftlog` |
| Police | `vehicles` `warrants` `bolos` `arrests` `citations` `incidents` `penal` `mugshots` |
| EMS | `pcr` `medhistory` `narclog` |
| Fire | `fireincidents` `hazmat` `apparatus` |

Two panel keys double as data gates on the shared civilian lookup:

- `warrants` — grants criminal data (warrants, arrests, citations, registered vehicles, officer notes)
- `medhistory` — grants medical data (blood type, allergies, conditions, medications, history)

By default Police has the first and EMS the second, so neither sees the other's
records. Give Fire `medhistory` if your firefighters are cross-trained EMTs.

The gate covers **actions as well as data**: the Issue Warrant / Citation / Log
Arrest buttons only render for a department with the `warrants` panel, and every
enforcement callback re-checks server-side — so an EMS medic can't file a warrant
even by crafting the request by hand. Supervisor scope is per-department too
(`supervisorGrade`), and a supervisor only ever sees their own department's
officers.

### Live unit blips

Police, EMS and Fire see each other on the map, coloured per department.

```lua
Config.Blips = {
    Enabled         = true,   -- false disables the whole system: no broadcast, no blips
    TrackedJobs     = nil,    -- nil = every job in Config.Departments; or an explicit list
    CrossDepartment = true,   -- false = you only see your own department
    OnDutyOnly      = true,
    UpdateInterval  = 2000,   -- ms between position broadcasts
    StaleAfter      = 15,     -- seconds before a silent unit drops off
    ShowName = true, ShowBadge = true, ShowVehicle = true,
    JobColors = { --[[ ['swat'] = 27 ]] },  -- per-job colour override
}
```

Set `Enabled = false` if you'd rather run your own blip script — the position
broadcast loop never starts, so it costs nothing.

### Live map

The map is Leaflet over a tile pyramid of the San Andreas satellite render, not
the game's own pause map — that one is an engine render target the NUI browser
has no access to, so every MDT uses an image map.

Everything it needs ships with the resource: `html/vendor/leaflet/` (BSD-2) and
`html/assets/maps/tiles/`. Nothing is fetched from the internet at runtime.

If the map is blank, the F8 console names the tile URL that failed — that is
almost always the manifest not shipping `html/assets/maps/tiles/*.webp`, or the
tiles not having reached the server.

If unit dots land slightly off where they should be, calibrate `MAP.world` at the
top of `html/js/panels/map.js`: stand somewhere recognisable in-game, note your
coords, open the Live Map, and nudge the bounds until the dot sits on you.

To use a different render, drop it in as `html/assets/maps/san-andreas-satellite.webp`
and rebuild the tiles:

```bash
npm install sharp
node tools/build-map-tiles.js
```

The script prints the native zoom it used — put that in `MAP.nativeZoom`, along
with the new `imageW` / `imageH`. See `html/assets/maps/README.md`.

### Call routing

`Config.CallRouting` decides which departments are alerted for each call type.
A type that isn't listed falls back to `Default`.

```lua
Config.CallRouting = {
    Default = { 'police' },
    Types = {
        MEDICAL       = { 'ems' },
        FIRE          = { 'fire', 'ems' },            -- EMS stages on every structure fire
        VEHICLE_CRASH = { 'police', 'ems', 'fire' },  -- full response
        SHOTS_FIRED   = { 'police' },
        CUSTOM        = { 'police', 'ems', 'fire' },
    },
}
```

Panic buttons and backup requests ignore routing — every department always
receives officer-safety alerts.

### Dispatch provider selection

`Config.DispatchProvider = 'auto'` is the recommended setting. XS-MDT uses
XS-Dispatch when it is running, selects another registered adapter by
priority, and falls back to its internal CAD when no external provider exists.
The resources may start or stop in either order; provider state is reevaluated
without a hard manifest dependency.

Use `'internal'` to force built-in CAD or a registered provider ID to force a
specific integration. External dispatch resources can register through
`RegisterDispatchProvider`; export-only resources can be mapped in
`Config.DispatchAdapters`. The reference implementation is documented in
`XS-Dispatch/adapters/README.md`.

```lua
-- Jobs allowed to access the MDT
Config.AuthorizedJobs = {
    ['police']      = true,
    ['sheriff']     = true,
    ['swat']        = true,
    ['statepolice'] = true,
}

-- Minimum job grade to access MDT (0 = all grades)
Config.MinGrade = 0

-- Key to open MDT (players can rebind in GTA Settings > Key Bindings)
Config.OpenKey = 'F9'

-- Require player to be on-duty to open MDT
Config.OnDutyOnly = true

-- Job grade required for supervisor features:
--   editing penal codes, deleting incidents, marking citations paid,
--   viewing audit log, posting bulletins, viewing body cam logs
Config.SupervisorGrade = 3

-- Fine deduction from player bank accounts
Config.FineDeduction = {
    Enabled               = true,
    AutoDeductArrests     = true,   -- deduct immediately when arrest is logged
    AutoDeductCitations   = false,  -- false = pay-later model (recommended)
    AutoDeductOnMarkPaid  = true,   -- deduct when supervisor marks citation paid
}

-- Jail integration
-- 'qb-prison'  → uses TriggerEvent('qb-prison:server:sendToJail', src, minutes)
-- 'ps-prison'  → uses TriggerEvent('prison:server:SendToJail', src, minutes)
-- false        → disabled (fires XS-MDT:client:jailPlayer so you can handle it)
Config.JailResource = false

-- Discord webhook for audit log entries (leave empty '' to disable)
Config.AuditWebhook = ''

-- ox_target / qb-target integration
Config.Target = {
    Enabled     = true,
    MaxDistance = 3.0,
}

-- Body camera logging
Config.BodyCam = {
    Enabled       = true,
    RetentionDays = 30,  -- 0 = keep forever
}
```

---

## Dispatch Integration

XS-MDT includes auto-detection for common in-game events (gunshots, vehicle crashes, fights). To send a dispatch call **from another resource**, use any of the methods below.

### Server Export (recommended)
```lua
exports['XS-MDT']:CreateDispatchCall({
    callType    = 'BANK_ROBBERY',
    description = 'Silent alarm triggered at Maze Bank.',
    coords      = { x = 148.0, y = -1044.0, z = 29.0 },
    street      = 'Alta Street',   -- optional, auto-detected if omitted
    callerName  = '911 Caller',    -- optional
})
```

### Client Event
```lua
TriggerEvent('XS-MDT:client:dispatch:custom',
    'ROBBERY',                          -- call type key (see table below)
    'Armed robbery in progress.',       -- description
    vector3(24.8, -1347.3, 29.5)        -- coords
)
```

### Server Net Event
```lua
TriggerServerEvent('XS-MDT:server:autoDispatch', {
    callType    = 'SHOTS_FIRED',
    description = 'Gunshots reported in the area.',
    street      = 'Forum Drive',
    coords      = { x = 80.0, y = -1283.0, z = 29.0 },
})
```

### Built-in Call Type Keys

| Key | Label |
|---|---|
| `SHOTS_FIRED` | Shots Fired |
| `FIGHT` | Fight / Assault |
| `VEHICLE_CRASH` | Vehicle Crash |
| `ROBBERY` | Robbery in Progress |
| `BANK_ROBBERY` | Bank Robbery |
| `STORE_ROBBERY` | Store Robbery |
| `TRAFFIC_STOP` | Traffic Stop |
| `MEDICAL` | Medical Emergency |
| `FIRE` | Structure Fire |
| `SUSPICIOUS` | Suspicious Activity |

Any other key will display the raw string as the call type label.

### Testing Dispatch (F8 Client Console)

```lua
TriggerServerEvent('XS-MDT:server:autoDispatch', {
    callType = 'SHOTS_FIRED',
    description = 'Multiple shots fired near the bank.',
    street = 'Alta Street',
    coords = { x = 148.0, y = -1044.0, z = 29.0 }
})
```

> Auto-dispatch has a **60-second rate limit** per player per call type to prevent spam. If a test call doesn't appear, wait 60 seconds and try again.

---

## Jailing Through MDT

1. Set `Config.JailResource` in `config.lua` to match your jail resource:
   ```lua
   Config.JailResource = 'qb-prison'   -- or 'ps-prison'
   ```
2. When logging an arrest via **ox_target → Log Arrest** (targeting a player in-world), the arrest modal receives that player's server ID. If a jail time is filled in, the player is automatically jailed on submit.
3. Arrests filed from the civilian search panel (without a live target) do not have a source ID — jailing won't fire. This is by design; the suspect may not be online or present.

---

## Supervisor Features

Officers at or above `Config.SupervisorGrade` unlock:

| Feature | Location |
|---|---|
| Department Statistics | Dashboard |
| Department Bulletins | Bulletins panel |
| Audit Log Viewer | Dashboard → Audit Log button |
| Body Camera Log Viewer | Officers panel |
| Edit Penal Codes | Penal Codes panel |
| Mark Citations Paid | Citations panel |
| Delete Incidents | Incidents panel |

---

## Server Exports

```lua
-- Check if a player has MDT access
exports['XS-MDT']:IsAuthorized(src)           -- returns bool

-- Get officer info for a player
exports['XS-MDT']:GetOfficerInfo(src)
-- returns { citizenid, name, job, grade, gradeLabel, onduty }

-- Write to the audit log (also fires Discord webhook if configured)
exports['XS-MDT']:AuditLog('Action Name', 'Officer Name', 'Details string')

-- Create a dispatch call from server-side
exports['XS-MDT']:CreateDispatchCall({ callType, description, coords, ... })
```

---

## Troubleshooting

**MDT doesn't open**
- Check `Config.AuthorizedJobs` includes your job name — it is case-sensitive and must match the QBCore job name exactly.
- If `Config.OnDutyOnly = true`, the player must be clocked on duty.
- Check `Config.MinGrade` — the player's grade must be at or above this number.

**Dispatch alerts not appearing**
- Use the correct call type key format (`SHOTS_FIRED`, not `Shots Fired` or `shots_fired`).
- Auto-dispatch has a 60-second rate limit per player per call type.
- Verify the resource is running: `status XS-MDT` in the server console.

**SQL errors on start**
- Ensure you ran `sql/mdt.sql` fully before starting the resource.
- If upgrading, run only the ALTER TABLE blocks for your previous version.

**Fine deduction not working**
- Set `Config.FineDeduction.Enabled = true`.
- The target player must be online for immediate deduction.
- For citations the default is `AutoDeductCitations = false` (pay-later model). Set to `true` to deduct on citation creation instead.

**Jailing not working**
- Verify `Config.JailResource` matches your jail resource name exactly.
- The arrest must be submitted via ox_target on a live, online player to carry a source ID for jailing.

---

Released under the MIT License. Free to use, modify, and redistribute with attribution.

---

## Documentation

Full setup guide, requirements and troubleshooting:
**[xyralscripts.dev/docs-xs-mdt](https://xyralscripts.dev/docs-xs-mdt)**

## Support

- **Found a bug?** [Open an issue](https://github.com/XyraL/XS-MDT/issues)
- **Need setup help?** [Join the Discord](https://discord.gg/XRURAw4TM2) — check the setup guide first, it usually has the answer

## My other scripts

All free, all source-available.

| Script | What it is |
|---|---|
| **[XS-CriminalTablet](https://github.com/XyraL/XS-CriminalTablet)** | modular criminal device for QBox and QBCore — gang ops, blackmarket and boosting in one encrypted tablet. |
| **[XS-AdminMenu](https://github.com/XyraL/XS-AdminMenu)** | advanced admin suite for QBox and QBCore — player management, bans, reports, inventory tools and entity inspection. |
| **[XS-Drone](https://github.com/XyraL/XS-Drone)** | deployable police drone for QBox and QBCore — smooth flight, thermal, spotlight, tracker darts and real counterplay. |
| **[XS-Trucking](https://github.com/XyraL/XS-Trucking)** | civilian trucking job for QBox and QBCore — live route map, truck ownership, fuel and maintenance, and companies. |
| **[XS-MultiCharacter](https://github.com/XyraL/XS-MultiCharacter)** | cinematic character selection for QBox and QBCore — identity dossiers, saved appearances, spawn cameras and configurable slots. |
| **[XS-Dispatch](https://github.com/XyraL/XS-Dispatch)** | multi-department live dispatch for QBox and QBCore — responder tracking, priority calls, TAC radio and provider integrations. |

## License

Free to use on any server you own or operate, including commercial ones.
**Do not redistribute or resell** — see [LICENSE](LICENSE) for the full terms.
