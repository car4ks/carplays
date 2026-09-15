local M = {}

local isPlaying = false
local lastIgnitionLevel = -1 -- Initialize to invalid state to force first check
local SOUND_EVENT = 'event:event_test'
local SOUND_NAME = 'event_test'

local function stopSound()
    if isPlaying then
        sound.stop(SOUND_NAME)
        isPlaying = false
    end
end

local function updateSound()
    local ignitionLevel = electrics.values.ignitionLevel or 0
    
    -- Only process if ignition level actually changed
    if ignitionLevel == lastIgnitionLevel then
        return
    end
    
    if ignitionLevel == 1 and not isPlaying then
        sound.play(SOUND_EVENT, 1, true)
        isPlaying = true
    elseif (ignitionLevel == 0 or ignitionLevel == 3) and isPlaying then
        stopSound()
    end
    
    lastIgnitionLevel = ignitionLevel
end

function M.onReset()
    stopSound()
    lastIgnitionLevel = -1 -- Reset to force recheck on next update
end

function M.onUpdate(dt)
    updateSound()
end

function M.deactivate()
    stopSound()
    lastIgnitionLevel = -1
end

return M