local M = {}

-- Configuration for all controls
local controls = {
    -- Instant toggle controls (no animation)
    {
        triggerKey = "seatfoldL_trigger",
        outputKey = "seatfoldL",
        type = "instant"
    },
    {
        triggerKey = "seatfoldR_trigger", 
        outputKey = "seatfoldR",
        type = "instant"
    },
    {
        triggerKey = "seatfoldRL_trigger",
        outputKey = "seatfoldRL", 
        type = "instant"
    },
    {
        triggerKey = "seatfoldRR_trigger",
        outputKey = "seatfoldRR",
        type = "instant"
    },
    {
        triggerKey = "lampL_trigger",
        outputKey = "lampL",
        type = "instant"
    },
    {
        triggerKey = "lampR_trigger", 
        outputKey = "lampR",
        type = "instant"
    },
    -- Animated controls
    {
        triggerKey = "console_trigger",
        outputKey = "console",
        type = "animated",
        speed = 1.0
    },
    {
        triggerKey = "gascap_trigger",
        outputKey = "gascap", 
        type = "animated",
        speed = 2.0
    },
    {
        triggerKey = "visorL_trigger",
        outputKey = "visorL",
        type = "animated", 
        speed = 1.0
    },
    {
        triggerKey = "visorR_trigger",
        outputKey = "visorR",
        type = "animated",
        speed = 1.0
    },
    {
        triggerKey = "glovebox_trigger",
        outputKey = "glovebox",
        type = "animated",
        speed = 1.0
    }
}

-- Special master control for lamps
local lampMasterControl = {
    triggerKey = "lampM_trigger",
    outputKeys = {"lampL", "lampR"},
    type = "master"
}

-- State tracking
local controlStates = {}
local lastTriggerStates = {}
local electricsCache = {}

-- Initialize control states
for i = 1, #controls do
    local control = controls[i]
    controlStates[i] = {
        isExtended = false,
        position = 0
    }
    lastTriggerStates[control.triggerKey] = 0
end

-- Initialize master control state
lastTriggerStates[lampMasterControl.triggerKey] = 0

local function setElectricValue(key, value)
    if electrics.values[key] ~= value then
        electrics.values[key] = value
    end
end

local function updateElectricsCache()
    for i = 1, #controls do
        local triggerKey = controls[i].triggerKey
        electricsCache[triggerKey] = electrics.values[triggerKey] or 0
    end
    electricsCache[lampMasterControl.triggerKey] = electrics.values[lampMasterControl.triggerKey] or 0
end

local function processInstantControl(control, state, currentTrigger, lastTrigger)
    if currentTrigger == 1 and lastTrigger == 0 then
        state.isExtended = not state.isExtended
        setElectricValue(control.outputKey, state.isExtended and 1 or 0)
    end
end

local function processAnimatedControl(control, state, currentTrigger, lastTrigger, dt)
    -- Handle trigger toggle
    if currentTrigger == 1 and lastTrigger == 0 then
        state.isExtended = not state.isExtended
    end
    
    -- Update position based on state
    if state.isExtended then
        state.position = math.min(1, state.position + control.speed * dt)
    else
        state.position = math.max(0, state.position - control.speed * dt)
    end
    
    setElectricValue(control.outputKey, state.position)
end

local function processMasterControl(masterControl, currentTrigger, lastTrigger)
    if currentTrigger == 1 and lastTrigger == 0 then
        -- Find the first lamp control to determine new state
        local lampLState = nil
        local lampRState = nil
        
        for i = 1, #controls do
            if controls[i].outputKey == "lampL" then
                lampLState = controlStates[i]
            elseif controls[i].outputKey == "lampR" then
                lampRState = controlStates[i]
            end
        end
        
        if lampLState and lampRState then
            -- Toggle both to the same new state
            local newState = not lampLState.isExtended
            lampLState.isExtended = newState
            lampRState.isExtended = newState
            
            local value = newState and 1 or 0
            setElectricValue("lampL", value)
            setElectricValue("lampR", value)
        end
    end
end

local function updateGFX(dt)
    if not electrics then return end
    
    updateElectricsCache()
    
    -- Process all standard controls
    for i = 1, #controls do
        local control = controls[i]
        local state = controlStates[i]
        local currentTrigger = electricsCache[control.triggerKey]
        local lastTrigger = lastTriggerStates[control.triggerKey]
        
        if control.type == "instant" then
            processInstantControl(control, state, currentTrigger, lastTrigger)
        elseif control.type == "animated" then
            processAnimatedControl(control, state, currentTrigger, lastTrigger, dt)
        end
        
        lastTriggerStates[control.triggerKey] = currentTrigger
    end
    
    -- Process master lamp control
    local currentMasterTrigger = electricsCache[lampMasterControl.triggerKey]
    local lastMasterTrigger = lastTriggerStates[lampMasterControl.triggerKey]
    processMasterControl(lampMasterControl, currentMasterTrigger, lastMasterTrigger)
    lastTriggerStates[lampMasterControl.triggerKey] = currentMasterTrigger
end

local function resetControl(control, state)
    setElectricValue(control.outputKey, 0)
    setElectricValue(control.triggerKey, 0)
    state.isExtended = false
    state.position = 0
    lastTriggerStates[control.triggerKey] = 0
end

local function onReset()
    if not electrics then return end
    
    -- Reset all standard controls
    for i = 1, #controls do
        resetControl(controls[i], controlStates[i])
    end
    
    -- Reset master control
    setElectricValue(lampMasterControl.triggerKey, 0)
    lastTriggerStates[lampMasterControl.triggerKey] = 0
    
    -- Clear cache
    electricsCache = {}
    
    guihooks.message("Mod made by RoyalRenderings", 1, nil, "verified_user")
end

local function onVehicleActiveChanged(active)
    if active then
        electrics.registerHandler("updateGFX", updateGFX)
        onReset()
    end
end

M.onVehicleActiveChanged = onVehicleActiveChanged
M.onReset = onReset
M.updateGFX = updateGFX

return M