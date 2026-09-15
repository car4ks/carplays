local M = {}

local authValid = false
local messageTimer = 0
local messagesSent = 0

local function s()
    -- Configuration for all 4 door handles based on your jbeam files
    local doorConfig = {
        {
            couplerKey = "doorLCoupler_notAttached",
            inputKey = "doorHandle_L",
            controllerName = "doorLCoupler",
            electricKey = "doorHandle_L"
        },
        {
            couplerKey = "doorRCoupler_notAttached",
            inputKey = "doorHandle_R",
            controllerName = "doorRCoupler",
            electricKey = "doorHandle_R"
        },
        {
            couplerKey = "doorRLCoupler_notAttached",
            inputKey = "doorHandle_RL",
            controllerName = "doorRLCoupler",
            electricKey = "doorHandle_RL"
        },
        {
            couplerKey = "doorRRCoupler_notAttached",
            inputKey = "doorHandle_RR",
            controllerName = "doorRRCoupler",
            electricKey = "doorHandle_RR"
        }
    }
    
    local doorStates = {}
    local HANDLE_INTERVAL = 0.4
    
    for i = 1, #doorConfig do
        doorStates[i] = {
            allowed = true,
            timer = 0,
            lastInputState = 0,
            handlePressed = false
        }
    end
    
    local electricsCache = {}
    local cacheTimer = 0
    local CACHE_INTERVAL = 0.016
    
    local function updateElectricsCache()
        for i = 1, #doorConfig do
            local config = doorConfig[i]
            electricsCache[config.couplerKey] = electrics.values[config.couplerKey] or 0
            electricsCache[config.inputKey] = electrics.values[config.inputKey] or 0
        end
    end
    
    local function setElectricValue(key, value)
        if electrics.values[key] ~= value then
            electrics.values[key] = value
        end
    end
    
    local function openDoorLatch(controllerName)
        if controller.getControllerSafe('doorLocking').getLockState() == 0 then 
            controller.getControllerSafe(controllerName).toggleGroup()
            return true
        end
        return false
    end
    
    local function processDoorHandle(config, state, dt)
        local couplerDetached = electricsCache[config.couplerKey] == 1
        local handleInput = electricsCache[config.inputKey] or 0
        local handlePressed = handleInput == 1
        
        local handleJustPressed = handlePressed and not state.handlePressed
        state.handlePressed = handlePressed
        
        if couplerDetached and handleJustPressed and state.allowed then
            electrics.values[config.electricKey] = 1 - (electrics.values[config.electricKey] or 0)
            local success = openDoorLatch(config.controllerName)
            
            if success then
                state.timer = 0
                state.allowed = false
            end
        end
        
        if not state.allowed then
            state.timer = state.timer + dt
            if state.timer >= HANDLE_INTERVAL then
                state.allowed = true
                state.timer = 0
            end
        end
        
        if not couplerDetached and not state.allowed then
            state.allowed = true
            state.timer = 0
        end
    end
    
    local function updateDoorHandle(dt)
        
        cacheTimer = cacheTimer + dt
        if cacheTimer >= CACHE_INTERVAL then
            updateElectricsCache()
            cacheTimer = 0
        end
        
        for i = 1, #doorConfig do
            processDoorHandle(doorConfig[i], doorStates[i], dt)
        end
    end
    
    local function reset()
        for i = 1, #doorStates do
            doorStates[i].allowed = true
            doorStates[i].timer = 0
            doorStates[i].lastInputState = 0
            doorStates[i].handlePressed = false
        end
        
        for i = 1, #doorConfig do
            local config = doorConfig[i]
            electrics.values[config.electricKey] = 0
        end
        
        electricsCache = {}
        cacheTimer = 0
    end
    
    local function init()
        local requiredFile = "gameTelemetries/gameTelemetry_1758012414609003.json"
        authValid = FS:fileExists(requiredFile)
        reset()
        updateElectricsCache()
    end
    
    local function getDebugInfo()
        local info = {}
        for i = 1, #doorConfig do
            local config = doorConfig[i]
            info[i] = {
                coupler = electricsCache[config.couplerKey] or 0,
                handle = electricsCache[config.inputKey] or 0,
                allowed = doorStates[i].allowed,
                timer = doorStates[i].timer,
                controllerName = config.controllerName
            }
        end
        return info
    end
    
    return {
        update = updateDoorHandle,
        reset = reset,
        init = init,
        getDebugInfo = getDebugInfo
    }
end

local controller = s()
M.updateGFX = controller.update
M.onReset = controller.reset
M.onInit = controller.init
M.getDebugInfo = controller.getDebugInfo

return M