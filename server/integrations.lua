MdtDispatchBridge = MdtDispatchBridge or { providers = {}, active = nil, revision = 0 }
local inboundRevisions = {}

local required = { 'getActiveCalls', 'createCall', 'respond', 'setCallStatus', 'addCallNote', 'setUnitStatus' }

local function resourceStarted(name)
    return not name or name == '' or GetResourceState(name) == 'started'
end

local function capabilities(provider)
    local result = {}
    for _, method in ipairs(required) do result[method] = type(provider[method]) == 'function' end
    return result
end

local function register(id, provider)
    if type(id) ~= 'string' or type(provider) ~= 'table' then return false end
    provider.id = id
    provider.priority = tonumber(provider.priority) or 0
    provider.capabilities = capabilities(provider)
    MdtDispatchBridge.providers[id] = provider
    return true
end

exports('RegisterDispatchProvider', register)

local function dynamicExport(resource, exportName, ...)
    if not exportName or not resourceStarted(resource) then return false, 'provider unavailable' end
    local args = { ... }
    local ok, a, b = pcall(function() return exports[resource][exportName](table.unpack(args)) end)
    if not ok then return false, a end
    return a, b
end

for _, adapter in ipairs(Config.DispatchAdapters or {}) do
    if adapter.id ~= 'XS-Dispatch' then
        local names = adapter.exports or {}
        register(adapter.id, {
            resource = adapter.resource, priority = adapter.priority,
            getActiveCalls = function() return dynamicExport(adapter.resource, names.getActiveCalls) end,
            createCall = function(source, data) return dynamicExport(adapter.resource, names.createCall, data, source) end,
            respond = function(source, id) return dynamicExport(adapter.resource, names.respond, source, id) end,
            setCallStatus = function(source, id, status) return dynamicExport(adapter.resource, names.setCallStatus, source, id, status) end,
            addCallNote = function(source, id, note) return dynamicExport(adapter.resource, names.addCallNote, id, note, source) end,
            setUnitStatus = function(source, status) return dynamicExport(adapter.resource, names.setUnitStatus, source, status, true) end,
        })
    end
end

register('XS-Dispatch', {
    resource = 'XS-Dispatch', priority = 100,
    getActiveCalls = function() return exports['XS-Dispatch']:GetActiveCalls() end,
    createCall = function(source, data) return exports['XS-Dispatch']:CreateCall(data) end,
    respond = function(source, id) return exports['XS-Dispatch']:RespondUnit(source, id) end,
    setCallStatus = function(source, id, status) return exports['XS-Dispatch']:SetCallStatus(source, id, status) end,
    addCallNote = function(source, id, note) return exports['XS-Dispatch']:AddCallNote(id, note) end,
    setUnitStatus = function(source, status) return exports['XS-Dispatch']:SetUnitStatus(source, status, true) end,
})

function MdtDispatchBridge.Resolve()
    local configured = Config.DispatchProvider or 'auto'
    local selected
    if configured ~= 'auto' and configured ~= 'internal' then
        local candidate = MdtDispatchBridge.providers[configured]
        if candidate and resourceStarted(candidate.resource) then selected = candidate end
    elseif configured == 'auto' then
        for _, candidate in pairs(MdtDispatchBridge.providers) do
            if resourceStarted(candidate.resource) and (not selected or candidate.priority > selected.priority) then selected = candidate end
        end
    end
    MdtDispatchBridge.active = selected
    MdtDispatchBridge.revision = MdtDispatchBridge.revision + 1
    return selected
end

function MdtDispatchBridge.Get()
    local active = MdtDispatchBridge.active
    if active and not resourceStarted(active.resource) then return MdtDispatchBridge.Resolve() end
    return active or MdtDispatchBridge.Resolve()
end

function MdtDispatchBridge.IsExternal() return MdtDispatchBridge.Get() ~= nil end

function MdtDispatchBridge.Call(method, ...)
    local provider = MdtDispatchBridge.Get()
    if not provider or type(provider[method]) ~= 'function' then return false, 'unsupported capability' end
    local ok, a, b = pcall(provider[method], ...)
    if not ok then return false, a end
    return a, b
end

function MdtDispatchBridge.Health()
    local provider = MdtDispatchBridge.Get()
    return {
        mode = Config.DispatchProvider or 'auto', active = provider and provider.id or 'internal',
        resource = provider and provider.resource or GetCurrentResourceName(),
        capabilities = provider and provider.capabilities or { getActiveCalls=true, createCall=true, respond=true, setCallStatus=true, addCallNote=true, setUnitStatus=true },
        revision = MdtDispatchBridge.revision,
    }
end

exports('GetDispatchIntegrationStatus', function() return MdtDispatchBridge.Health() end)

-- Stable inbound contract for any dispatch adapter. origin/revision prevent an
-- adapter from reflecting the same change back into its source.
exports('IngestDispatchUpdate', function(action, call, envelope)
    envelope = envelope or {}
    if envelope.origin == GetCurrentResourceName() then return false end
    if type(call) ~= 'table' or not call.id then return false end
    local key = tostring(envelope.origin or 'external') .. ':' .. tostring(call.id)
    local revision = tonumber(envelope.revision or call.revision) or 1
    if revision <= (inboundRevisions[key] or 0) then return false end
    inboundRevisions[key] = revision
    local normalized = {
        id=call.id, call_number=call.call_number or call.id,
        call_type=call.call_type or call.title or call.type, type=call.type,
        description=call.description, location=call.location or call.street,
        coords=call.coords, priority=call.priority, units=call.units or {}, notes=call.notes or {},
        status=call.status, caller_name=call.caller_name or call.caller,
        created_at=call.created_at or os.date('!%Y-%m-%dT%H:%M:%SZ', call.createdAt or os.time()),
        operation=call.operation, external=true, provider=envelope.origin, revision=revision,
    }
    if action == 'closed' then TriggerClientEvent('XS-MDT:client:callClosed', -1, call.id)
    elseif action == 'created' then TriggerClientEvent('XS-MDT:client:newCall', -1, normalized)
    else TriggerClientEvent('XS-MDT:client:callUpdated', -1, normalized) end
    return true
end)

AddEventHandler('onResourceStart', function() SetTimeout(250, function() MdtDispatchBridge.Resolve() end) end)
AddEventHandler('onResourceStop', function() SetTimeout(0, function() MdtDispatchBridge.Resolve() end) end)
MdtDispatchBridge.Resolve()
