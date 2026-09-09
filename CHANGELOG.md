# Changelog

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
