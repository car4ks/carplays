local M = {}
M.type = "auxiliary"

-- Bass Gain ranges from 0-100 (representing 0% to 200% gain)
-- 50 = 100% (unity gain), 0 = 0% (off), 100 = 200% (max boost)
local currentGain = 50
local targetGain = 50
local lastGain = 50
local gainChangeSpeed = 100
local isGainChanging = false

local lastGainUp = 0
local lastGainDown = 0

local updateTimer = 0
local invFPS = 1/30

local initialized = false

local function init(jbeamData)
    initialized = false
end

local function initializeElectrics()
    if electrics and electrics.values and not initialized then
        -- bassGain: 0-1 for the prop rotation
        electrics.values.bassGain = currentGain / 100
        
        -- bassGainMultiplier: 0-2 for actual audio/hydro multiplier
        electrics.values.bassGainMultiplier = currentGain / 50
        
        electrics.values.subGain_up = 0
        electrics.values.subGain_down = 0
        
        -- Signal to music controller that bass gain changed
        electrics.values.bassGainChanged = 1
        
        initialized = true
        print("Bass Gain Controller: Initialized at " .. currentGain .. "% (multiplier: " .. string.format("%.2f", currentGain / 50) .. "x)")
        return true
    end
    return false
end

local function updateBassGainOutput()
    if not initialized or not electrics or not electrics.values then
        return
    end
    
    electrics.values.bassGain = currentGain / 100
    electrics.values.bassGainMultiplier = currentGain / 50
    
    -- DEBUG: Remove after testing
    print(string.format("PROP DEBUG: bassGain = %.2f, currentGain = %.0f", electrics.values.bassGain, currentGain))
end

local function processGainInput(dt)
    if not initialized then
        return
    end
    
    local gainUp = electrics.values.subGain_up or 0
    local gainDown = electrics.values.subGain_down or 0
    
    local gainChanged = false
    
    -- Gain Up - works like volume control
    if gainUp == 1 then
        if lastGainUp == 0 then
            -- Initial press - small increment
            targetGain = math.min(100, currentGain + 3)
            isGainChanging = true
            gainChanged = true
        else
            -- Held down - continuous increase (faster)
            local increment = 80 * dt
            targetGain = math.min(100, targetGain + increment)
            isGainChanging = true
            gainChanged = true
        end
    end
    
    -- Gain Down - works like volume control
    if gainDown == 1 then
        if lastGainDown == 0 then
            -- Initial press - small decrement
            targetGain = math.max(0, currentGain - 3)
            isGainChanging = true
            gainChanged = true
        else
            -- Held down - continuous decrease (faster)
            local decrement = 80 * dt
            targetGain = math.max(0, targetGain - decrement)
            isGainChanging = true
            gainChanged = true
        end
    end
    
    -- Smooth gain changes
    if isGainChanging then
        local gainDiff = targetGain - currentGain
        if math.abs(gainDiff) > 0.1 then
            currentGain = currentGain + (gainDiff * dt * gainChangeSpeed / 10)
        else
            currentGain = targetGain
            isGainChanging = false
        end
        gainChanged = true
    end
    
    -- Update outputs if changed
    if gainChanged then
        updateBassGainOutput()
        
        -- Log significant changes
        if math.abs(currentGain - lastGain) > 2 then
            local multiplier = currentGain / 50
            print(string.format("Bass Gain: %d%% (%.2fx multiplier)", math.floor(currentGain), multiplier))
            lastGain = currentGain
        end
    end
    
    lastGainUp = gainUp
    lastGainDown = gainDown
end

local function updateGFX(dt)
    if not initialized then
        initializeElectrics()
    end
    
    updateTimer = updateTimer + dt
    
    if updateTimer > invFPS then
        updateTimer = 0
        processGainInput(dt)
    end
end

local function onReset()
    -- Reset to unity gain (50 = 1x multiplier)
    currentGain = 50
    targetGain = 50
    lastGain = 50
    isGainChanging = false
    
    lastGainUp = 0
    lastGainDown = 0
    updateTimer = 0
    
    if electrics and electrics.values then
        electrics.values.bassGain = 0.5
        electrics.values.bassGainMultiplier = 1.0
        electrics.values.subGain_up = 0
        electrics.values.subGain_down = 0
        electrics.values.bassGainChanged = 1
    end
    
    print("Bass Gain Controller: Reset to 50% (1.0x multiplier)")
end

local function onDestroy()
end

local function onExtensionLoaded()
    initializeElectrics()
end

M.init = init
M.updateGFX = updateGFX
M.onReset = onReset
M.onDestroy = onDestroy
M.onExtensionLoaded = onExtensionLoaded

return M