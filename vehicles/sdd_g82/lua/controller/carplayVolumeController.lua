local M = {}
M.type = "auxiliary"

local htmlTexture = require("htmlTexture")

local screenMaterialName = "@sdd_g82_screen"

-- Load saved volume preference
local volumePreferencesPath = "/settings/music_preferences.json"

local function loadVolumePreference()
    local success, data = pcall(function() return jsonReadFile(volumePreferencesPath) end)
    if success and data and type(data) == "table" and data.volume then
        return data.volume
    end
    return 75
end

local currentVolume = loadVolumePreference()
local targetVolume = currentVolume
local lastVolume = currentVolume
local volumeChangeSpeed = 100
local isVolumeChanging = false
local volumeDisplayTimer = 0
local VOLUME_DISPLAY_DURATION = 2.0

local lastVolumeUp = 0
local lastVolumeDown = 0

local updateTimer = 0
local invFPS = 1/15

local initialized = false

-- Performance optimizations
local lastHtmlVolumeUpdate = 0
local HTML_VOLUME_UPDATE_INTERVAL = 0.1
local volumeChangedFlag = false

local function init(jbeamData)
    initialized = false
    currentVolume = loadVolumePreference()
    targetVolume = currentVolume
    lastVolume = currentVolume
end

local function initializeElectrics()
    if electrics and electrics.values and not initialized then
        electrics.values.carplayVolume = currentVolume
        electrics.values.carplayVolumeVisible = 0
        electrics.values.volumeControl_up = 0
        electrics.values.volumeControl_down = 0
        initialized = true
        print("[CarPlay Volume] Initialized with volume: " .. currentVolume)
        return true
    end
    return false
end

local function updateCarPlayVolume()
    if screenMaterialName then
        local now = os.clock()
        if (now - lastHtmlVolumeUpdate) > HTML_VOLUME_UPDATE_INTERVAL then
            local volumeData = {
                volume = math.floor(currentVolume + 0.5),
                isVisible = volumeDisplayTimer > 0,
                maxVolume = 100
            }
            
            htmlTexture.call(screenMaterialName, "updateVolumeDisplay", volumeData)
            lastHtmlVolumeUpdate = now
        end
    end
end

local function processVolumeInput(dt)
    if not initialized then
        return
    end
    
    local volumeUp = electrics.values.volumeControl_up or 0
    local volumeDown = electrics.values.volumeControl_down or 0
    
    local volumeChanged = false
    
    -- Process volume up
    if volumeUp == 1 then
        if lastVolumeUp == 0 then
            targetVolume = math.min(100, currentVolume + 2)
            isVolumeChanging = true
            volumeDisplayTimer = VOLUME_DISPLAY_DURATION
            volumeChanged = true
        else
            local increment = 30 * dt
            targetVolume = math.min(100, targetVolume + increment)
            isVolumeChanging = true
            volumeDisplayTimer = VOLUME_DISPLAY_DURATION
            volumeChanged = true
        end
    end
    
    -- Process volume down
    if volumeDown == 1 then
        if lastVolumeDown == 0 then
            targetVolume = math.max(0, currentVolume - 2)
            isVolumeChanging = true
            volumeDisplayTimer = VOLUME_DISPLAY_DURATION
            volumeChanged = true
        else
            local decrement = 30 * dt
            targetVolume = math.max(0, targetVolume - decrement)
            isVolumeChanging = true
            volumeDisplayTimer = VOLUME_DISPLAY_DURATION
            volumeChanged = true
        end
    end
    
    -- Smooth volume transition
    if isVolumeChanging then
        local volumeDiff = targetVolume - currentVolume
        if math.abs(volumeDiff) > 0.1 then
            currentVolume = currentVolume + (volumeDiff * dt * volumeChangeSpeed / 10)
        else
            currentVolume = targetVolume
            isVolumeChanging = false
        end
        volumeChanged = true
    end
    
    -- Update electrics whenever volume changes
    if volumeChanged and electrics and electrics.values then
        local roundedVolume = math.floor(currentVolume + 0.5)
        
        electrics.values.carplayVolume = roundedVolume
        electrics.values.carplayVolumeVisible = volumeDisplayTimer > 0 and 1 or 0
        volumeChangedFlag = true
        lastVolume = currentVolume
        
        print("[CarPlay Volume] Volume changed to: " .. roundedVolume)
    end
    
    lastVolumeUp = volumeUp
    lastVolumeDown = volumeDown
end

local function updateVolumeDisplay(dt)
    if volumeDisplayTimer > 0 then
        volumeDisplayTimer = volumeDisplayTimer - dt
        
        if volumeDisplayTimer <= 0 then
            volumeDisplayTimer = 0
            if electrics and electrics.values then
                electrics.values.carplayVolumeVisible = 0
            end
            volumeChangedFlag = true
        end
    end
end

local function updateGFX(dt)
    if not initialized then
        initializeElectrics()
        return
    end
    
    updateTimer = updateTimer + dt
    
    if updateTimer > invFPS then
        processVolumeInput(updateTimer)
        updateVolumeDisplay(updateTimer)
        
        if volumeChangedFlag then
            updateCarPlayVolume()
            volumeChangedFlag = false
        end
        
        updateTimer = 0
    end
end

local function onReset()
    lastVolumeUp = 0
    lastVolumeDown = 0
    updateTimer = 0
    
    targetVolume = currentVolume
    isVolumeChanging = false
    volumeDisplayTimer = 0
    
    lastHtmlVolumeUpdate = 0
    volumeChangedFlag = false
    
    if electrics and electrics.values then
        electrics.values.carplayVolume = math.floor(currentVolume + 0.5)
        electrics.values.carplayVolumeVisible = 0
        electrics.values.volumeControl_up = 0
        electrics.values.volumeControl_down = 0
    end
end

local function onDestroy()
    initialized = false
end

local function onExtensionLoaded()
    currentVolume = loadVolumePreference()
    targetVolume = currentVolume
    lastVolume = currentVolume
    initializeElectrics()
end

M.init = init
M.updateGFX = updateGFX
M.onReset = onReset
M.onDestroy = onDestroy
M.onExtensionLoaded = onExtensionLoaded

return M