local M = {}

local htmlTexture = require('htmlTexture')

-- State variables
local currentVolume = 500
local lastVolume = 500
local lastElectricsVolume = 500

-- Constants
local VOLUME_CHANGE_SPEED = 500
local MIN_VOLUME = 0
local MAX_VOLUME = 1000
local DEFAULT_VOLUME = 500
local VOLUME_UPDATE_THRESHOLD = 1 -- Only update when change is > 1
local HTML_UPDATE_THRESHOLD = 5 -- Less frequent HTML updates to reduce lag

-- Cache for electrics
local electricsCache = {
    volUp = 0,
    volDown = 0
}

-- HTML update throttling
local htmlUpdateTimer = 0
local HTML_UPDATE_INTERVAL = 0.1 -- Update HTML at most 10 times per second
local pendingHtmlUpdate = false

local function setElectricValue(key, value)
    if electrics.values[key] ~= value then
        electrics.values[key] = value
    end
end

local function updateElectricsCache()
    electricsCache.volUp = electrics.values.VolUp or 0
    electricsCache.volDown = electrics.values.VolDown or 0
end

local function clampVolume(volume)
    return math.max(MIN_VOLUME, math.min(MAX_VOLUME, volume))
end

local function updateHtmlTexture()
    if not htmlTexture then return end
    
    local success, error = pcall(function()
        htmlTexture.call("@sdd_trx2_screen", string.format([[
            (function() {
                window.postMessage({
                    type: 'volumeChange',
                    volume: %f
                }, '*');
            })();
        ]], currentVolume / 10))
    end)
    
    if success then
        lastVolume = currentVolume
        pendingHtmlUpdate = false
    else
        -- Log error but don't spam
        if error then
            log("W", "volumeControl", "HTML texture update failed: " .. tostring(error))
        end
    end
end

local function processVolumeChange(dt)
    local volumeChanged = false
    local oldVolume = currentVolume
    
    -- Process volume up
    if electricsCache.volUp == 1 then
        currentVolume = currentVolume + VOLUME_CHANGE_SPEED * dt
        volumeChanged = true
    end
    
    -- Process volume down
    if electricsCache.volDown == 1 then
        currentVolume = currentVolume - VOLUME_CHANGE_SPEED * dt
        volumeChanged = true
    end
    
    if volumeChanged then
        currentVolume = clampVolume(currentVolume)
        
        -- Only update electrics if change is significant
        if math.abs(currentVolume - lastElectricsVolume) > VOLUME_UPDATE_THRESHOLD then
            setElectricValue("Volume", currentVolume)
            lastElectricsVolume = currentVolume
        end
        
        -- Mark HTML update as needed if change is significant
        if math.abs(currentVolume - lastVolume) > HTML_UPDATE_THRESHOLD then
            pendingHtmlUpdate = true
        end
    end
end

local function updateGFX(dt)
    if not electrics then return end
    
    updateElectricsCache()
    
    -- Early exit if no volume controls are active
    if electricsCache.volUp == 0 and electricsCache.volDown == 0 and not pendingHtmlUpdate then
        return
    end
    
    processVolumeChange(dt)
    
    -- Handle HTML texture updates with throttling
    if pendingHtmlUpdate then
        htmlUpdateTimer = htmlUpdateTimer + dt
        if htmlUpdateTimer >= HTML_UPDATE_INTERVAL then
            updateHtmlTexture()
            htmlUpdateTimer = 0
        end
    end
end

local function onReset()
    currentVolume = DEFAULT_VOLUME
    lastVolume = currentVolume
    lastElectricsVolume = currentVolume
    htmlUpdateTimer = 0
    pendingHtmlUpdate = false
    
    -- Clear cache
    electricsCache.volUp = 0
    electricsCache.volDown = 0
    
    if electrics then
        setElectricValue("Volume", currentVolume)
    end
end

local function onVehicleActiveChanged(active)
    if active then
        electrics.registerHandler("updateGFX", updateGFX)
        setElectricValue("Volume", currentVolume)
        
        -- Force initial HTML update
        pendingHtmlUpdate = true
        htmlUpdateTimer = HTML_UPDATE_INTERVAL -- Trigger immediate update
    end
end

M.onVehicleActiveChanged = onVehicleActiveChanged
M.onReset = onReset
M.updateGFX = updateGFX

return M