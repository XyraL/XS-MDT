if not Config.Sounds.Enabled then return end

-- Play a named sound via NUI Web Audio (all sounds are generated tones, no files needed)
local function PlayMDTSound(soundName)
    SendNUIMessage({ action = 'playSound', sound = soundName })
end

-- Expose for other client files
exports('PlayMDTSound', PlayMDTSound)

-- Panic button fired — loud in-game siren burst
RegisterNetEvent('XS-MDT:client:panicAlert', function()
    PlaySoundFrontend(-1, 'TIMER_STOP', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    Wait(200)
    PlaySoundFrontend(-1, 'TIMER_STOP', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
end)

-- New CAD call — subtle in-game beep
RegisterNetEvent('XS-MDT:client:newCall', function()
    PlaySoundFrontend(-1, 'Countdown_Beep', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
end)

-- Warrant alert — attention tone
RegisterNetEvent('XS-MDT:client:warrantAlert', function()
    PlaySoundFrontend(-1, 'Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
end)
