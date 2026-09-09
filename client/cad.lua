local cadBlips = {} -- callId -> blip handle

-- Add a map blip for a new CAD call
RegisterNetEvent('XS-MDT:client:newCall', function(call)
    if not call.coords then return end
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
