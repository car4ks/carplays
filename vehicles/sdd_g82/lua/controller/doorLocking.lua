local M = {}

local state = {
    lockState = 0,
    hazardStartTime = 0,
    hazardTimeout = 0,
    hazardsTurnedOn = false,
    lastLockStateElectric = -1,
    lastDoorStates = {
        doorR = false,
        doorL = false
    }
}

local HAZARD_START_DELAY = 0.6
local HAZARD_DURATION = 1.0
local SOUND_NODE = 369
local SOUND_VOLUME = 2
local SOUND_PITCH = 1

local cache = {
    hazardState = 0,
    ignitionLevel = 0,
    doorROpen = false,
    doorLOpen = false
}

local lastCacheUpdate = 0
local CACHE_UPDATE_INTERVAL = 0.1
local DEBUG_MODE = true

-- Store original door functions to restore when unlocked
local originalDoorFunctions = {}
local doorControllersOverridden = false

local function debugLog(message)
    if DEBUG_MODE then
        log('D', 'doorLocking', message)
    end
end

-- Function to discover and override ALL door controllers
local function overrideAllDoorControllers()
    if doorControllersOverridden then return end
    
    debugLog("Searching for and overriding door controllers...")
    
    -- Get all controllers
    local allControllers = controller.getControllerList and controller.getControllerList() or {}
    
    for name, ctrl in pairs(allControllers) do
        -- Check if this looks like a door controller
        local isRightDoor = string.find(string.lower(name), "door") and 
                           (string.find(string.lower(name), "r") or 
                            string.find(string.lower(name), "right") or 
                            string.find(string.lower(name), "1") or
                            string.find(string.lower(name), "passenger")) or
                           name == "door_R_coupler"  -- Your specific controller!
                            
        local isLeftDoor = string.find(string.lower(name), "door") and 
                          (string.find(string.lower(name), "l") or 
                           string.find(string.lower(name), "left") or 
                           string.find(string.lower(name), "0") or
                           string.find(string.lower(name), "driver")) or
                          name == "door_L_coupler"  -- Your specific controller!
        
        if isRightDoor or isLeftDoor then
            debugLog("Found door controller: " .. name)
            
            -- Store original functions
            if ctrl.toggleGroup then
                originalDoorFunctions[name] = {
                    toggleGroup = ctrl.toggleGroup,
                    open = ctrl.open,
                    close = ctrl.close,
                    setGroupPosition = ctrl.setGroupPosition
                }
                
                -- Override with lock-aware versions
                ctrl.toggleGroup = function(...)
                    if state.lockState == 1 then
                        debugLog("Blocked toggleGroup on " .. name .. " (locked)")
                        return false
                    end
                    return originalDoorFunctions[name].toggleGroup(...)
                end
                
                if ctrl.open then
                    ctrl.open = function(...)
                        if state.lockState == 1 then
                            debugLog("Blocked open on " .. name .. " (locked)")
                            return false
                        end
                        return originalDoorFunctions[name].open(...)
                    end
                end
                
                if ctrl.setGroupPosition then
                    ctrl.setGroupPosition = function(pos, ...)
                        if state.lockState == 1 and pos > 0 then
                            debugLog("Blocked setGroupPosition on " .. name .. " (locked)")
                            return false
                        end
                        return originalDoorFunctions[name].setGroupPosition(pos, ...)
                    end
                end
                
                debugLog("Overridden functions for controller: " .. name)
            end
        end
    end
    
    doorControllersOverridden = true
end

-- Function to restore original door controller functions
local function restoreOriginalDoorControllers()
    if not doorControllersOverridden then return end
    
    debugLog("Restoring original door controller functions...")
    
    for name, originalFuncs in pairs(originalDoorFunctions) do
        local ctrl = controller.getController(name)
        if ctrl then
            ctrl.toggleGroup = originalFuncs.toggleGroup
            if originalFuncs.open then ctrl.open = originalFuncs.open end
            if originalFuncs.close then ctrl.close = originalFuncs.close end
            if originalFuncs.setGroupPosition then ctrl.setGroupPosition = originalFuncs.setGroupPosition end
            debugLog("Restored functions for controller: " .. name)
        end
    end
end

-- Override JBeam door opening if applicable
local function overrideJBeamDoors()
    -- Override common electric door controls
    local doorElectrics = {
        "doorL_input", "doorR_input", 
        "door_L_input", "door_R_input",
        "leftDoor_input", "rightDoor_input",
        "driverDoor_input", "passengerDoor_input"
    }
    
    for _, electric in ipairs(doorElectrics) do
        if electrics and electrics.values and electrics.values[electric] ~= nil then
            -- Monitor this electric value
            debugLog("Monitoring electric door control: " .. electric)
        end
    end
end

local function updateCache()
    if electrics and electrics.values then
        cache.hazardState = electrics.values.hazard or 0
        cache.ignitionLevel = electrics.values.ignitionLevel or 0
        cache.doorROpen = electrics.values.doorROpen or false
        cache.doorLOpen = electrics.values.doorLOpen or false
    end
end

local function setElectricValue(key, value)
    if not electrics or not electrics.values then return end
    
    if electrics.values[key] ~= value then
        electrics.values[key] = value
        debugLog("Set electric value: " .. key .. " = " .. tostring(value))
    end
end

local function queueIgnitionChange(level)
    if cache.ignitionLevel ~= level then
        obj:queueLuaCommand("electrics.setIgnitionLevel(" .. level .. ")")
        debugLog("Queued ignition level change to: " .. level)
    end
end

local function playSoundPair(sound1, sound2, soundName1, soundName2)
    if not obj then 
        debugLog("Warning: obj not available for sound playback")
        return 
    end
    
    obj:createSFXSource(sound1, "AudioClosest3D", soundName1, -1)
    obj:playSFXOnce(soundName1, SOUND_NODE, SOUND_VOLUME, SOUND_PITCH)
    obj:createSFXSource(sound2, "AudioClosest3D", soundName2, -1)
    obj:playSFXOnce(soundName2, SOUND_NODE, SOUND_VOLUME, SOUND_PITCH)
    
    debugLog("Played sound pair: " .. soundName1 .. ", " .. soundName2)
end

local function playLockSound()
    playSoundPair(
        "vehicles/sdd_f87/sounds/lock.mp3",
        "vehicles/sdd_f87/sounds/lockchirp.mp3",
        "lockSound",
        "lockChirpSound"
    )
end

local function playUnlockSound()
    playSoundPair(
        "vehicles/sdd_f87/sounds/unlock.mp3", 
        "vehicles/sdd_f87/sounds/unlockchirp.mp3",
        "unlockSound",
        "unlockChirpSound"
    )
end

local function initiateHazardSequence()
    if cache.ignitionLevel == 0 then
        queueIgnitionChange(1)
    end
    
    local currentTime = os.time()
    state.hazardStartTime = currentTime + HAZARD_START_DELAY
    state.hazardTimeout = state.hazardStartTime + HAZARD_DURATION
    
    debugLog("Initiated hazard sequence - start: " .. state.hazardStartTime .. ", timeout: " .. state.hazardTimeout)
end

local function processHazardSequence(currentTime)
    if state.hazardStartTime > 0 and currentTime >= state.hazardStartTime then
        if electrics and electrics.toggle_warn_signal then
            electrics.toggle_warn_signal()
            state.hazardsTurnedOn = true
            debugLog("Hazards turned ON")
        end
        state.hazardStartTime = 0
    end

    if state.hazardTimeout > 0 and currentTime >= state.hazardTimeout then
        if state.hazardsTurnedOn then
            if electrics and electrics.toggle_warn_signal then
                electrics.toggle_warn_signal()
                state.hazardsTurnedOn = false
                debugLog("Hazards turned OFF")
            end
        end
        state.hazardTimeout = 0
    end
end

function M.init()
    state.lockState = 0
    state.hazardStartTime = 0
    state.hazardTimeout = 0
    state.hazardsTurnedOn = false
    state.lastLockStateElectric = -1
    state.lastDoorStates.doorR = false
    state.lastDoorStates.doorL = false
    
    -- Override door controllers on init
    overrideAllDoorControllers()
    overrideJBeamDoors()
    
    debugLog("Door locking system initialized with comprehensive door control")
    return true
end

function M.reset()
    -- Restore original functions before reset
    restoreOriginalDoorControllers()
    
    state.lockState = 0
    state.hazardStartTime = 0
    state.hazardTimeout = 0
    state.hazardsTurnedOn = false
    state.lastLockStateElectric = -1
    
    -- Reset override flags
    doorControllersOverridden = false
    originalDoorFunctions = {}
    
    updateCache()
    cache.hazardState = 0
    cache.ignitionLevel = 0
    
    debugLog("Door locking system reset")
end

function M.updateGFX(dt)
    lastCacheUpdate = lastCacheUpdate + dt
    if lastCacheUpdate >= CACHE_UPDATE_INTERVAL then
        updateCache()
        lastCacheUpdate = 0
    end

    -- Update electric values to match your existing system
    if state.lockState ~= state.lastLockStateElectric then
        setElectricValue("lockState", state.lockState)
        setElectricValue("doorsLocked", state.lockState)
        setElectricValue("door_is_locked", state.lockState)  -- Your existing variable!
        state.lastLockStateElectric = state.lockState
    end
    
    -- Ensure door controllers stay overridden
    if not doorControllersOverridden then
        overrideAllDoorControllers()
    end
    
    -- Process hazard sequence
    if state.hazardStartTime > 0 or state.hazardTimeout > 0 then
        local currentTime = os.time()
        processHazardSequence(currentTime)
    end
end

function M.toggleLock()
    local previousState = state.lockState
    state.lockState = state.lockState == 0 and 1 or 0
    
    debugLog("Lock toggled from " .. previousState .. " to " .. state.lockState)
    
    if state.lockState ~= previousState then
        if state.lockState == 1 then
            playLockSound()
            debugLog("Doors LOCKED - All door controllers overridden")
            -- Ensure overrides are active
            overrideAllDoorControllers()
        else
            playUnlockSound()
            debugLog("Doors UNLOCKED - Door controllers restored")
        end
        initiateHazardSequence()
    end
    
    return state.lockState
end

function M.setLockState(newState)
    if newState ~= state.lockState then
        local previousState = state.lockState
        state.lockState = newState
        
        debugLog("Lock state set from " .. previousState .. " to " .. state.lockState)
        
        if state.lockState == 1 then
            playLockSound()
            overrideAllDoorControllers()
            debugLog("Doors LOCKED (direct) - All controllers overridden")
        else
            playUnlockSound()
            debugLog("Doors UNLOCKED (direct)")
        end
        initiateHazardSequence()
    end
    
    return state.lockState
end

function M.getLockState()
    return state.lockState
end

function M.isDoorLocked()
    return state.lockState == 1
end

function M.canOpenDoor(doorSide)
    local canOpen = state.lockState == 0
    if not canOpen then
        debugLog("Door operation blocked - doors are locked (" .. (doorSide or "unknown") .. ")")
    end
    return canOpen
end

function M.listAvailableControllers()
    debugLog("=== Available Controllers ===")
    local allControllers = controller.getControllerList and controller.getControllerList() or {}
    for name, ctrl in pairs(allControllers) do
        local isDoor = string.find(string.lower(name), "door")
        debugLog("Controller: " .. name .. (isDoor and " [DOOR-RELATED]" or ""))
    end
    debugLog("=== Overridden Controllers ===")
    for name, _ in pairs(originalDoorFunctions) do
        debugLog("Overridden: " .. name)
    end
    debugLog("=== End Controller List ===")
end

return M