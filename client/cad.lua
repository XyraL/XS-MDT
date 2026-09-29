local cadBlips = {} -- callId -> blip handle

-- Add a map blip for a new CAD call
RegisterNetEvent('XS-MDT:client:newCall', function(call)
    if not call.coords or call.origin then return end
    if cadBlips[call.id] then return end

    local blip = AddBlipForCoord(call.coords.x, call.coords.y, call.coords.z or 0.0)
    SetBlipSprite(blip, Config.CADBlip.Sprite)
    SetBlipColour(blip, Config.CADBlip.Color)
    SetBlipScale(blip, Config.CADBlip.Scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(call.call_number .. ': ' .. (call.call_type or call.type or 'Call'))
    EndTextCommandSetBlipName(blip)

    cadBlips[call.id] = blip
end)

-- Remove blip when call is closed
RegisterNetEvent('XS-MDT:client:callClosed', function(callId)
    if cadBlips[callId] then
        RemoveBlip(cadBlips[callId])
        cadBlips[callId] = nil
    end
end)

-- Set GPS route to a call's location
RegisterNUICallback('routeToCall', function(data, cb)
    if not data.coords then cb('no_coords') return end
    SetNewWaypoint(data.coords.x, data.coords.y)
    lib.notify({ title = 'GPS Set', description = 'Routing to ' .. (data.location or 'call'), type = 'success' })
    cb('ok')
end)

RegisterNetEvent('XS-MDT:client:resolveStreet', function(callId, coords)
    if type(coords) ~= 'table' or not coords.x then return end
    local z = coords.z or 0.0
    local main, cross = GetStreetNameAtCoord(coords.x, coords.y, z)
    local text = GetStreetNameFromHashKey(main)
    if cross and cross ~= 0 then
        local second = GetStreetNameFromHashKey(cross)
        if second and second ~= '' then text = text .. ' / ' .. second end
    end
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, z))
    if zone and zone ~= '' and zone ~= 'NULL' then text = text .. ', ' .. zone end
    TriggerServerEvent('XS-MDT:server:callStreet', callId, text)
end)
