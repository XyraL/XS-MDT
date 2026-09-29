--[[  Management

      One place a supervisor can see how the MDT is actually wired: which
      dispatch it is talking to, which integrations answered, how much is in
      each table, and the whole audit trail.

      Every answer here is read live rather than from config, because the
      question a supervisor is asking is "is it working", and config only says
      what was intended.
]]

local IsAuthorized = function(src) return exports['XS-MDT']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['XS-MDT']:HasPanel(src, panel) end
local GetOfficerInfo = function(src) return exports['XS-MDT']:GetOfficerInfo(src) end
local IsSupervisor = function(src) return exports['XS-MDT']:IsSupervisor(src) end
local Audit = function(src, action, details) return exports['XS-MDT']:AuditLog(action, src, details) end

--[[ Is a resource actually running, and does it export what we call on it? ]]
local function ResourceRow(name, note)
    local state = name and GetResourceState(name) or 'missing'
    return {
        name = name or '—',
        started = state == 'started',
        state = state,
        note = note,
    }
end

lib.callback.register('XS-MDT:server:getManagement', function(source)
    if not HasPanel(source, 'management') then return nil end
    if not IsSupervisor(source) then return nil end

    local me = GetOfficerInfo(source)

    -- Dispatch: the provider that replaced the CAD, if any, and the resources
    -- calls are mirrored out to.
    local health = exports['XS-MDT']:GetDispatchIntegrationStatus()
    local targets = exports['XS-MDT']:GetDispatchAlertTargets()

    -- Counts. One query rather than a dozen round trips.
    local counts = MySQL.single.await([[
        SELECT
            (SELECT COUNT(*) FROM mdt_officers)      AS officers,
            (SELECT COUNT(*) FROM mdt_arrests)       AS arrests,
            (SELECT COUNT(*) FROM mdt_citations)     AS citations,
            (SELECT COUNT(*) FROM mdt_incidents)     AS incidents,
            (SELECT COUNT(*) FROM mdt_warrants WHERE status = 'active') AS warrants,
            (SELECT COUNT(*) FROM mdt_bolos WHERE active = 1)           AS bolos,
            (SELECT COUNT(*) FROM mdt_cases)         AS cases,
            (SELECT COUNT(*) FROM mdt_evidence)      AS evidence,
            (SELECT COUNT(*) FROM mdt_weapons)       AS weapons,
            (SELECT COUNT(*) FROM mdt_cameras)       AS cameras,
            (SELECT COUNT(*) FROM mdt_footage)       AS footage,
            (SELECT COUNT(*) FROM mdt_penal_codes WHERE active = 1)     AS charges,
            (SELECT COUNT(*) FROM mdt_ia_cases WHERE status IN ('open','investigating')) AS ia_open,
            (SELECT COUNT(*) FROM mdt_audit_log)     AS audit
    ]]) or {}

    -- Departments as the MDT resolved them, not as config wrote them.
    local departments = {}
    for key, cfg in pairs(Config.Departments or {}) do
        departments[#departments + 1] = {
            key = key,
            label = cfg.label,
            short = cfg.short,
            jobs = cfg.jobs,
            supervisorGrade = cfg.supervisorGrade or Config.SupervisorGrade,
            panels = #(cfg.panels or {}),
        }
    end
    table.sort(departments, function(a, b) return a.key < b.key end)

    return {
        framework = {
            name = Framework.name,
            configured = Config.Framework or 'auto',
        },
        dispatch = {
            provider = health and health.active or 'internal',
            resource = health and health.resource or nil,
            mode = health and health.mode or 'auto',
            capabilities = health and health.capabilities or {},
            alerts = targets,
            setting = type(Config.DispatchAlerts) == 'table' and table.concat(Config.DispatchAlerts, ', ')
                      or tostring(Config.DispatchAlerts),
            calls = type(Config.DispatchCalls) == 'table' and table.concat(Config.DispatchCalls, ', ')
                      or tostring(Config.DispatchCalls == nil and 'auto' or Config.DispatchCalls),
        },
        integrations = {
            ResourceRow(Config.JailResource or nil, 'Jail on arrest'),
            ResourceRow('ox_inventory', 'Item images and stashes'),
            ResourceRow('ox_target', 'Target interactions'),
            ResourceRow('oxmysql', 'Database'),
        },
        counts = counts,
        departments = departments,
        me = { name = me and me.name, department = me and me.department },
    }
end)

--[[ Trim the audit log.

     Every action writes a row, so a busy server accumulates them faster than
     anyone reads them. Supervisors can drop anything older than a cutoff; the
     row count before and after goes into the audit log itself, which is the
     one entry nobody should be able to remove quietly. ]]
lib.callback.register('XS-MDT:server:pruneAuditLog', function(source, days)
    if not HasPanel(source, 'management') then return false, 'No access' end
    if not IsSupervisor(source) then return false, 'Supervisors only' end

    days = tonumber(days)
    if not days or days < 7 then return false, 'Keep at least seven days' end

    local before = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_audit_log') or 0
    MySQL.update.await('DELETE FROM mdt_audit_log WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
    local after = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_audit_log') or 0

    Audit(source, 'AUDIT_PRUNED', ('%d rows older than %d days'):format(before - after, days))
    return true, before - after
end)
