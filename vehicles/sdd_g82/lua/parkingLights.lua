local M = {}

-- State variables
local leftTimer = 0
local rightTimer = 0
local strobeTimer = 0
local strobeCount = 0
local isLeftActive = true

-- Cache for electrics values
local electricsCache = {}
local lastElectricsState = {}

-- Light configuration
local lightOutputs = {
    drlL = "drlL",
    drlR = "drlR", 
    taillightL = "sdd_g82_taillight_L",
    taillightR = "sdd_g82_taillight_R"
}

-- Constants
local STROBE_INTERVAL = 0.1
local PARKING_LIGHT_DURATION = 0.3
local STROBE_CYCLE_COUNT = 5

local function setElectricValue(key, value)
    if electrics.values[key] ~= value then
        electrics.values[key] = value
        lastElectricsState[key] = value
    end
end

local function updateElectricsCache()
    electricsCache.running = electrics.values.running or false
    electricsCache.ignition = electrics.values.ignition or false
    electricsCache.lightbarSignal = electrics.values.lightbar_signal or 0
    electricsCache.lightbar = electrics.values.lightbar or 0
    electricsCache.emergencyLights = electrics.values.emergencyLights or 0
    electricsCache.lights = electrics.values.lights or 0
end

local function isIgnitionOff()
    local ignition = electricsCache.ignition
    return (type(ignition) == "number" and ignition == 0) or 
           (type(ignition) == "boolean" and not ignition)
end

local function isEngineRunning()
    local running = electricsCache.running
    return (type(running) == "number" and running > 0) or 
           (type(running) == "boolean" and running)
end

local function isLightbarActive()
    return electricsCache.lightbarSignal > 0 or 
           electricsCache.lightbar > 0 or 
           electricsCache.emergencyLights > 0
end

local function areHeadlightsOn()
    return electricsCache.lights > 0
end

local function setAllLights(drlL, drlR, tailL, tailR)
    setElectricValue(lightOutputs.drlL, drlL)
    setElectricValue(lightOutputs.drlR, drlR)
    setElectricValue(lightOutputs.taillightL, tailL)
    setElectricValue(lightOutputs.taillightR, tailR)
end

local function handleStrobeMode(dt)
    strobeTimer = strobeTimer + dt
    
    if strobeTimer >= STROBE_INTERVAL then
        strobeTimer = 0
        strobeCount = strobeCount + 1
        
        if strobeCount >= STROBE_CYCLE_COUNT then
            strobeCount = 0
            isLeftActive = not isLeftActive
        end
        
        if isLeftActive then
            setAllLights(
                1 - (lastElectricsState[lightOutputs.drlL] or 0), -- Toggle
                0,
                1 - (lastElectricsState[lightOutputs.taillightL] or 0), -- Toggle
                0
            )
        else
            setAllLights(
                0,
                1 - (lastElectricsState[lightOutputs.drlR] or 0), -- Toggle
                0,
                1 - (lastElectricsState[lightOutputs.taillightR] or 0) -- Toggle
            )
        end
    end
end

local function handleNormalRunningMode()
    local headlightsValue = areHeadlightsOn() and 1 or 0
    setAllLights(1, 1, headlightsValue, headlightsValue)
end

local function handleIgnitionOffMode(dt)
    -- Handle left timer
    if leftTimer > 0 then
        setElectricValue(lightOutputs.drlL, 1)
        setElectricValue(lightOutputs.taillightL, 1)
        leftTimer = leftTimer - dt
        if leftTimer <= 0 then
            setElectricValue(lightOutputs.drlL, 0)
            setElectricValue(lightOutputs.taillightL, 0)
        end
    else
        setElectricValue(lightOutputs.drlL, 0)
        setElectricValue(lightOutputs.taillightL, 0)
    end
    
    -- Handle right timer
    if rightTimer > 0 then
        setElectricValue(lightOutputs.drlR, 1)
        setElectricValue(lightOutputs.taillightR, 1)
        rightTimer = rightTimer - dt
        if rightTimer <= 0 then
            setElectricValue(lightOutputs.drlR, 0)
            setElectricValue(lightOutputs.taillightR, 0)
        end
    else
        setElectricValue(lightOutputs.drlR, 0)
        setElectricValue(lightOutputs.taillightR, 0)
    end
end

local function init()
    -- Initialize all lights to off
    setAllLights(0, 0, 0, 0)
    
    leftTimer = 0
    rightTimer = 0
    strobeTimer = 0
    strobeCount = 0
    isLeftActive = true
    
    -- Store original signal functions
    local origToggleLeftSignal = electrics.toggle_left_signal
    local origToggleRightSignal = electrics.toggle_right_signal
    
    electrics.toggle_left_signal = function()
        updateElectricsCache() -- Update cache for current check
        if isIgnitionOff() then
            leftTimer = PARKING_LIGHT_DURATION
        else
            origToggleLeftSignal()
        end
    end
    
    electrics.toggle_right_signal = function()
        updateElectricsCache() -- Update cache for current check
        if isIgnitionOff() then
            rightTimer = PARKING_LIGHT_DURATION
        else
            origToggleRightSignal()
        end
    end
end

local function updateGFX(dt)
    if not electrics or not electrics.values then return end
    
    updateElectricsCache()
    
    if isEngineRunning() then
        if isLightbarActive() then
            handleStrobeMode(dt)
        else
            handleNormalRunningMode()
        end
    elseif not isIgnitionOff() then
        -- Engine not running but ignition on - turn off all lights and reset timers
        setAllLights(0, 0, 0, 0)
        leftTimer = 0
        rightTimer = 0
    else
        -- Ignition off - handle parking light timers
        handleIgnitionOffMode(dt)
    end
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M