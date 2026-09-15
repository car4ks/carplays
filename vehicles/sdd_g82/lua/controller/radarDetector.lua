local M = {}

-- Dependencies for HTML texture
local htmlTexture = nil
pcall(function() htmlTexture = require("htmlTexture") end)

-- Module variables
M.alertDurations = {
    xBand = 10.0,   -- 10-second timeout for each band
    kBand = 10.0,
    kaBand = 10.0,
    laser = 10.0    -- Laser timeout
}
M.alertTimers = {
    xBand = 0,
    kBand = 0,
    kaBand = 0,
    laser = 0
}
M.soundPlayed = {
    xBand = false,
    kBand = false,
    kaBand = false,
    laser = false
}
M.bandAlertPlayed = {
    xBand = false,
    kBand = false,
    kaBand = false
}
M.blinkTimer = 0
M.blinkInterval = 0.2
M.blinkState = false
M.lastSightValue = 0  -- Track previous sight value for increasing detection
M.isInitialized = false  -- Track initialization state
M.beepTimers = {        -- Track beep intervals for each band
    xBand = 0,
    kBand = 0,
    kaBand = 0
}
M.beepIntervals = {     -- Current beep intervals (in seconds)
    xBand = 1.0,
    kBand = 1.0,
    kaBand = 1.0
}
M.lastBeepTime = {      -- Track last beep time for each band
    xBand = 0,
    kBand = 0,
    kaBand = 0
}
M.activeBand = nil      -- Currently active radar band

-- HTML texture variables
local screenMaterialName = nil
local htmlFilePath = nil
local textureWidth = 256
local textureHeight = 128
local textureFPS = 60
local updateTimer = 0
local invFPS = 1 / 60
local textureCreated = false

local debugMode = false  -- Optional debug toggle, set to true for testing
local lastSentData = nil

local function dbgprint(...)
    if debugMode then
        print("[RadarDetector]", ...)
    end
end

local function areTablesEqual(t1, t2)
    if type(t1) ~= "table" or type(t2) ~= "table" then return false end
    for k, v in pairs(t1) do
        if t2[k] ~= v then return false end
    end
    for k, v in pairs(t2) do
        if t1[k] ~= v then return false end
    end
    return true
end

local function getRandomBand()
    -- Randomly select a band with Ka-band having 70% probability, X-band and K-band each 15%
    local rand = math.random()
    if rand < 0.70 then
        return "kaBand"
    elseif rand < 0.85 then
        return "kBand"
    else
        return "xBand"
    end
end

local function calculateBeepInterval(sightValue)
    -- Calculate beep interval based on sightValue (0.7s at low, 0.15s at high)
    local minInterval = 0.1
    local maxInterval = 0.7
    local normalizedValue = math.min(sightValue, 1.0)  -- Cap at 1.0 for simplicity
    return maxInterval - (maxInterval - minInterval) * normalizedValue
end

local function playBeepSound(band)
    if not obj then return end

    local soundPath = ""
    if band == "xBand" then
        soundPath = "vehicles/sdd_g82/sounds/xbandbeep.mp3"
    elseif band == "kBand" then
        soundPath = "vehicles/sdd_g82/sounds/kbandbeep.mp3"
    elseif band == "kaBand" then
        soundPath = "vehicles/sdd_g82/sounds/kabandbeep.mp3"
    end

    if soundPath ~= "" then
        local success, error = pcall(function()
            obj:createSFXSource(soundPath, "AudioClosest3D", band .. "BeepSound", -1)
            obj:playSFXOnce(band .. "BeepSound", 369, 2, 1)
        end)

        if not success then
            pcall(function()
                local fallbackPaths = {
                    soundPath,
                    "vehicles/common/sounds/beep.mp3",
                    "/vehicles/common/sounds/beep.mp3"
                }
                for _, path in ipairs(fallbackPaths) do
                    obj:createSFXSource(path, "AudioClosest3D", band .. "BeepSound", -1)
                    obj:playSFXOnce(band .. "BeepSound", 369, 2, 1)
                    break -- Exit after first successful sound
                end
            end)
        end
    end
end

local function playBandAlertSound(band)
    if not obj then return end

    local soundPath = ""
    if band == "xBand" then
        soundPath = "vehicles/sdd_g82/sounds/xband_alert.mp3"
    elseif band == "kBand" then
        soundPath = "vehicles/sdd_g82/sounds/kband_alert.mp3"
    elseif band == "kaBand" then
        soundPath = "vehicles/sdd_g82/sounds/kaband_alert.mp3"
    end

    -- Fallback to regular beep if specific alert doesn't exist
    if soundPath == "" then
        if band == "xBand" then
            soundPath = "vehicles/sdd_g82/sounds/xbandbeep.mp3"
        elseif band == "kBand" then
            soundPath = "vehicles/sdd_g82/sounds/kbandbeep.mp3"
        elseif band == "kaBand" then
            soundPath = "vehicles/sdd_g82/sounds/kabandbeep.mp3"
        end
    end

    if soundPath ~= "" then
        local success, error = pcall(function()
            obj:createSFXSource(soundPath, "AudioClosest3D", band .. "AlertSound", -1)
            obj:playSFXOnce(band .. "AlertSound", 369, 2, 1)
        end)

        if not success then
            pcall(function()
                local fallbackPaths = {
                    soundPath,
                    "vehicles/common/sounds/beep.mp3",
                    "/vehicles/common/sounds/beep.mp3"
                }
                for _, path in ipairs(fallbackPaths) do
                    obj:createSFXSource(path, "AudioClosest3D", band .. "AlertSound", -1)
                    obj:playSFXOnce(band .. "AlertSound", 369, 2, 1)
                    break -- Exit after first successful sound
                end
            end)
        end
    end
end

local function updateHTML(dt)
    if not htmlTexture or not screenMaterialName or not textureCreated then
        dbgprint("HTML update skipped: texture not ready")
        return
    end

    updateTimer = updateTimer + dt
    if updateTimer > invFPS then
        updateTimer = 0

        local radarData = {
            electrics = {
                wheelspeed = electrics.values.wheelspeed or 0,
                xBand = electrics.values.xBand or 0,
                kBand = electrics.values.kBand or 0,
                kaBand = electrics.values.kaBand or 0,
                laser = electrics.values.laser or 0,
                radarSightValue = electrics.values.radarSightValue or 0  -- Add this line
            }
        }
        dbgprint("Preparing to update HTML with data:", jsonEncode(radarData))

        if not areTablesEqual(lastSentData, radarData.electrics) then
            local success, err = pcall(function()
                htmlTexture.call(screenMaterialName, "updateDisplay", radarData)
            end)
            if not success then
                dbgprint("Failed to update HTML texture: " .. tostring(err))
            else
                lastSentData = radarData.electrics
                dbgprint("Successfully updated HTML texture with:", jsonEncode(radarData.electrics))
            end
        else
            dbgprint("No changes in HTML data, skipping update")
        end
    end
end

-- Initialize the radar detector and HTML texture
function M.init(jbeamData)
    -- Initialize radar variables to safe defaults
    electrics.values.radarSightValue = 0
    electrics.values.xBand = 0
    electrics.values.kBand = 0
    electrics.values.kaBand = 0
    electrics.values.laser = 0
    for band, _ in pairs(M.alertTimers) do
        M.alertTimers[band] = 0
        M.soundPlayed[band] = false
        M.bandAlertPlayed[band] = false
        M.beepTimers[band] = 0
        M.beepIntervals[band] = 1.0
        M.lastBeepTime[band] = 0
    end
    M.lastSightValue = 0
    M.blinkTimer = 0
    M.blinkState = false
    M.isInitialized = false
    M.activeBand = nil
    dbgprint("Initializing radar detector")

    -- Initialize HTML texture
    if not htmlTexture then
        dbgprint("htmlTexture not available - check Lua API or dependencies")
        return
    end

    screenMaterialName = jbeamData.materialName or "@sdd_g82_radarscreen"
    htmlFilePath = jbeamData.htmlPath or "local://local/vehicles/sdd_g82/Screen/radar_screen.html"
    textureWidth = jbeamData.textureWidth or 256
    textureHeight = jbeamData.textureHeight or 128
    textureFPS = jbeamData.textureFPS or 60
    
    if not screenMaterialName or not htmlFilePath then
        dbgprint("HTML texture initialization failed - missing material or HTML path")
        return
    end

    dbgprint("Attempting to create HTML texture with material:", screenMaterialName, "path:", htmlFilePath)
    local success, err = pcall(function()
        htmlTexture.create(screenMaterialName, htmlFilePath, textureWidth, textureHeight, textureFPS, "automatic")
    end)
    textureCreated = success
    if not success then
        dbgprint("Failed to create HTML texture: " .. tostring(err))
    else
        dbgprint("HTML texture created successfully for material:", screenMaterialName)
        -- Send initial setup for units (optional)
        local setupData = { uiUnitLength = "metric" } -- Default to metric, can be adjusted
        local setupSuccess, setupErr = pcall(function()
            htmlTexture.call(screenMaterialName, "setup", setupData)
        end)
        if not setupSuccess then
            dbgprint("Failed to send setup data: " .. tostring(setupErr))
        end
    end

    print("VEHICLE: Radar detector initialized")
    M.isInitialized = true
end

-- Update function called every graphics frame
function M.updateGFX(dt)
    if not M.isInitialized then return end

    local sightValue = electrics.values.radarSightValue or 0
    
    -- Reset all band values
    electrics.values.xBand = 0
    electrics.values.kBand = 0
    electrics.values.kaBand = 0
    electrics.values.laser = 0
    
    -- If we have a positive sight value
    if sightValue > 0 then
        -- If we don't have an active band or our previous sight value was 0, pick a random band
        if not M.activeBand or M.lastSightValue == 0 then
            M.activeBand = getRandomBand()
            dbgprint("Selected new active band: " .. M.activeBand)
            
            -- Play the initial band alert sound when we first detect something
            if not M.bandAlertPlayed[M.activeBand] then
                playBandAlertSound(M.activeBand)
                M.bandAlertPlayed[M.activeBand] = true
            end
        end
        
        -- Set the active band's electric value to 1 (even when laser is active)
        if M.activeBand then
            electrics.values[M.activeBand] = 1
        end
        
        -- Handle laser detection (when sight value is exactly 1.0)
        if sightValue >= 1.0 and M.lastSightValue < 1.0 then
            -- Play laser alert sound once when we first reach 1.0
            M.playAlertSound("laser")
            M.soundPlayed.laser = true
            M.alertTimers.laser = M.alertDurations.laser
            electrics.values.laser = 1
        elseif sightValue >= 1.0 then
            -- Keep the laser indicator on
            electrics.values.laser = 1
        end
        
        -- Continue beeping regardless of whether laser is active or not
        if M.activeBand then
            -- Calculate beep interval based on current sight value
            local beepInterval = calculateBeepInterval(sightValue)
            M.beepIntervals[M.activeBand] = beepInterval
            
            -- Update beep timer and play sound if needed
            M.beepTimers[M.activeBand] = M.beepTimers[M.activeBand] + dt
            if M.beepTimers[M.activeBand] >= M.beepIntervals[M.activeBand] then
                M.beepTimers[M.activeBand] = 0
                playBeepSound(M.activeBand)
                dbgprint("Playing beep for " .. M.activeBand .. " with interval " .. beepInterval)
            end
        end
    else
        -- If sight value is 0, clear the active band
        if M.activeBand then
            M.activeBand = nil
            for band, _ in pairs(M.beepTimers) do
                M.beepTimers[band] = 0
                M.bandAlertPlayed[band] = false
            end
        end
    end
    
    -- Store the current sight value for the next frame
    M.lastSightValue = sightValue
    
    -- Update HTML texture with all data
    updateHTML(dt)
end

-- Function to play the alert sound for a specific band
function M.playAlertSound(band)
    if not obj then return end

    local soundPath = ""
    if band == "laser" then
        soundPath = "vehicles/sdd_g82/sounds/laser_alert.mp3"
    end

    if soundPath ~= "" then
        local success, error = pcall(function()
            obj:createSFXSource(soundPath, "AudioClosest3D", band .. "AlertSound", -1)
            obj:playSFXOnce(band .. "AlertSound", 369, 2, 1)
        end)

        if not success then
            pcall(function()
                local fallbackPaths = {
                    soundPath,
                    "vehicles/common/sounds/beep.mp3",
                    "/vehicles/common/sounds/beep.mp3"
                }
                for _, path in ipairs(fallbackPaths) do
                    obj:createSFXSource(path, "AudioClosest3D", band .. "AlertSound", -1)
                    obj:playSFXOnce(band .. "AlertSound", 369, 2, 1)
                    break -- Exit after first successful sound
                end
            end)
        end
    end
end

-- Reset function to clear states without triggering sounds
--function M.reset()
--    electrics.values.radarSightValue = 0
--    electrics.values.xBand = 0
--    electrics.values.kBand = 0
--    electrics.values.kaBand = 0
--    electrics.values.laser = 0
--    for band, _ in pairs(M.alertTimers) do
--        M.alertTimers[band] = 0
--        M.soundPlayed[band] = false
--        M.bandAlertPlayed[band] = false
--        M.beepTimers[band] = 0
--        M.beepIntervals[band] = 1.0
--        M.lastBeepTime[band] = 0
--    end
--    M.blinkTimer = 0
--    M.blinkState = false
--    M.lastSightValue = 0
--    M.activeBand = nil
--    M.isInitialized = false -- This ensures M.init will run again
--    updateTimer = 0
--    lastSentData = nil -- Clear last sent data to force update
--    dbgprint("Radar detector reset")
--
--    -- Explicitly call HTML reset function
--    if htmlTexture and screenMaterialName and textureCreated then
--        local success, err = pcall(function()
--            htmlTexture.call(screenMaterialName, "reset")
--        end)
--        if not success then
--            dbgprint("Failed to call HTML reset: " .. tostring(err))
--        else
--            dbgprint("HTML reset called successfully")
--        end
--    end
--end

-- Cleanup function for HTML texture
function M.destroy()
    if htmlTexture and type(htmlTexture.destroy) == "function" and screenMaterialName then
        local success, err = pcall(function()
            htmlTexture.destroy(screenMaterialName)
        end)
        if not success then
            dbgprint("Failed to destroy HTML texture: " .. tostring(err))
        end
    end
end

return M