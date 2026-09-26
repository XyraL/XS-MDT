# Changelog

## [3.0.0] — 2026-09-26

A new look and a lot more MDT. Cases, an evidence locker, a weapons registry,
cameras, internal affairs, field training, SOPs, a management panel, a proper
charge book, and it runs on QBCore as well as QBox.

> **Upgrading:** update the resource and start it. The MDT brings its own
> database up to date — it reads the schema it ships with, adds whatever is
> missing, seeds the charge book if there is none, and says what it did.

### The look

Colour means state now, and nothing else. Priority, duty, charge class, alerts.
The old dashboard put eight stat cards in eight colours, which told you nothing
about which one mattered. Everything else is one neutral ramp, and the
department accent tints chrome only — swapping police blue for fire orange
never changes what a red row means.

Data is tabular monospace: codes, callsigns, plates, times, money. A column of
plates is scannable in mono and is not in a UI font.

All 242 emoji are gone, replaced by an icon set that paints in the current text
colour, so an icon in a red row is red.

### QBCore

Every framework call goes through `bridge/framework.lua`, which talks to
whichever of `qbx_core` or `qb-core` is started. `Config.Framework` pins it if
you run both during a migration. Job grades come from the framework, so a server
that renamed its ranks sees its own names.

### Charges

178 charges across seven titles, written as `PC 1.34 A` — title 1, section 34,
subsection A. The old seed was 25 real California codes, which meant every
server either used 25 charges or typed their own book in by hand.

The browser is one grid with a class filter, so the code column lines up from
the first charge to the last and "show me the felonies" is one click.

### Cases

A case used to be a free-text string typed onto an incident, so `CASE-2025-1`
and `CASE-2025-01` were two different cases and neither knew. A case is a record
now. Reports, arrests, citations, warrants, BOLOs, evidence, people, vehicles
and firearms attach to it, and notes go on the case so the story of it is not
buried in one officer's report.

### Evidence

Evidence used to hang off an incident, so it could only be logged after somebody
wrote one. It is booked when it is collected now, with its own number, a status,
a shelf and a case. Every status change writes a custody row. Releasing or
destroying evidence is a supervisor's call; everything else the officer holding
it can do.

### Weapons

A serial-first registry, because that is how a seized firearm is looked up, and
a serial that is not on it is an unregistered one.

### Cameras

35 real places that would have cameras — the six Fleecas, Pacific Standard,
Blaine County Savings, the 24/7s, the LTDs, Rob's Liquor, Vangelico,
Ammu-Nation, the casino, plus street and transit cameras. A camera with
coordinates sets a GPS waypoint from its card, and a new one takes the officer's
own position.

**Live body cams.** Command picks an on-duty officer and watches what their
chest camera sees. It is a real spectate — the watcher is moved to them,
made invisible and frozen, and a camera is attached to SKEL_Spine3 taking
the ped's body rotation, so it looks where their chest faces rather than
where their head turns. That is what a real body cam does, and it is also
the only rotation you can read off a remote ped reliably.

The officer is told their camera is being viewed, every viewing and its
duration goes to the audit log, and a supervisor can only watch their own
department. All three are switches in `Config.BodyCam.Live`.

Footage is one row per clip from a street camera, a dashcam or a bodycam, with
what it shows, how long it is, and the case it belongs to. The MDT does not play
video — it points you at the camera and records that somebody looked.

### Personnel

The roster listed whoever was on duty, which is right for a shift and wrong for
managing people: the officer you need to promote is usually the one who just
logged off. It lists the whole department now, marks who is on, and a supervisor
opens anyone's file from it — rank, callsign, certifications, performance
reviews and IA history in one modal.

A rank change calls the framework, so it is a real job change and not a label in
our table. A supervisor can only touch officers in their own department, and
only ranks at or below their own.

Three panels come with it: Internal Affairs, Field Training and SOP.

### Dispatch

Every call the MDT creates is pushed out to `ps-dispatch`, `qs-dispatch`,
`cd_dispatch`, `core_dispatch` and `linden_outlawalert`, whichever are started,
so the alert appears in whatever dispatch your department already has open. Each
one is a single function in `server/dispatch-adapters.lua`, and a mismatch
prints a line rather than breaking anything.

### Management

One panel showing how the MDT is actually wired: which framework answered, which
dispatch is in use and which resources are receiving alerts, what every
department resolved to, how much is in each table, and the whole audit trail.

### Audit

Rows now record the citizenid of who acted and who it was about. A name alone
made two officers called J. Reyes the same person.

### The SQL files

`sql/mdt.sql` is the tables and nothing else. Six versions of commented ALTER
statements had piled up above the first CREATE TABLE, so a first-time install
opened to sixty lines of upgrade history for versions they never ran. Tables
are in dependency order, which alphabetical was not — mdt_case_links carries a
foreign key to mdt_cases and would have failed on a fresh import.

The upgrade statements are gone entirely, because the resource does it now.
On start it reads the schema it ships with, compares it to the database and
adds any missing table or column. `CREATE TABLE IF NOT EXISTS` never touches a
table that already exists, which is why “just re-run the SQL” has never been
true and why missing columns surfaced as query errors from whatever panel
needed them.

### Fixed

- A refusal from the server now reaches the panel. `lib.callback`'s second
  return value was dropped at the NUI bridge, so "Above your own rank" arrived
  as nothing happening
- Every modal in the MDT was unstyled after the redesign, because `createModal`
  sets `className` rather than writing a class attribute
- The evidence table's cascading foreign key is gone — deleting a report should
  not destroy the evidence it mentioned

### Added for integrators

- `RegisterCameras(list)` — publish a camera list into the MDT, keyed by code
- `RegisterFootage(data)` — file a clip with no player behind the call
- `SendDispatchAlert(call)` — push a call to every enabled dispatch resource
- `GetDispatchAlertTargets()` — which ones are live

## [2.1.0] — 2026-08-28

Adds a bridge for Cipher-Evidence. If you run both, cases and evidence line up
across the two.

> **Upgrading:** just update the resource. No SQL changes, nothing to configure.

### Added

- Two server exports, `CreateIncidentExternal` and `AttachEvidence`, so
  Cipher-Evidence (or anything else) can open an incident and add evidence to it
  without a player behind the request. Nothing changes if you don't use them.

## [1.5.0] — 2026-08-13

XS-MDT becomes multi-department: Police, EMS and Fire in one resource.

> **Upgrading:** re-run `sql/mdt.sql` (adds eight tables, touches nothing existing),
> then review `Config.Departments` in `config.lua` and map your server's job names.

### Added

- **Departments** — `Config.Departments` maps jobs → department → the panels that
  department may open. The sidebar is built from that list and every server
  callback re-checks it, so UI and permissions can't drift apart.
- **EMS panels** — Patient Care Reports (injuries, treatments, vitals, disposition,
  transport, priority), Medical Records (blood type, allergies, conditions,
  medications, DNR/organ donor, dated history), Controlled Substance Log with
  witness field and reconciliation that flags discrepancies.
- **Fire panels** — Fire Incident Reports (type, alarm level, cause, structure,
  units, personnel, casualties, damage, acres, water), Hazmat (UN number, hazard
  class, containment, evacuation radius), Apparatus roster with inspection log —
  a failed check takes the unit out of service automatically.
- **Live unit blips** — Police, EMS and Fire see each other on the game map,
  coloured per department. `Config.Blips` controls everything, including a master
  `Enabled` toggle for servers running their own blip script.
- **Live Map panel** — Leaflet over a tile pyramid of the San Andreas satellite
  render: inertial pan, anchored scroll zoom, crisp at every level. Department-
  coloured unit markers with heading arrows and callsign tags, active CAD call
  markers, click-to-follow a unit, and click anywhere to drop a GPS waypoint.
  Leaflet 1.9.4 is vendored locally (BSD-2) — NUI has no reliable internet.
- **Call routing** — `Config.CallRouting` decides which departments are alerted per
  call type. Panic and backup always reach everyone.
- **Per-department supervisor grade** — `Config.Departments[dept].supervisorGrade`.

### Changed

- `Config.AuthorizedJobs` is now derived from `Config.Departments` — it maps a job
  to its department key rather than a boolean. Existing truthiness checks still work.
- Civilian lookup is department-scoped: criminal data requires the `warrants` panel,
  medical data requires `medhistory`. Police and EMS see their own side only.
- Roster, live units and CAD stay shared across departments by design.
- Supervisors only see their own department's body cam logs.
- Dashboard stat cards and quick actions are assembled from the player's panels.

### Fixed

- **Permission audit** — the pre-existing police callbacks only checked
  `IsAuthorized`, which is true for any MDT-enabled job. Once EMS and Fire existed,
  that let a medic issue warrants, log arrests and issue citations. All enforcement
  and records callbacks are now panel-gated server-side.
- In-world target options (View Profile / Issue Citation / Run Name Check) had no
  runtime permission check, so every player saw them. They are now gated per panel.
- The quick Name Check returns a warrant count and is gated on `warrants` rather
  than `civilians`, so EMS cannot use it to see criminal data.
- `copyBtn()` threw on a missing field, taking down the whole list render.
- The blip badge lookup ran a query per tracked player every tick; it is now cached
  and invalidated on profile edit.
- The old canvas Live Map was never loaded (missing script tag), its refresh
  interval was never cleared when leaving the tab, and it set `display` inline —
  which outranks `.tab-panel` and left the map painted over every other tab once
  opened. It has been replaced by the Leaflet map above.
