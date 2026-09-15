local M = {}
M.type = "auxiliary"

-- Constants
local TEXTURE_PATH = "/vehicles/sdd_g82/textures/Leather_2.dds"
local UPDATE_FPS = 30 -- Reduced from 60 for better performance
local DEBUG_INTERVAL = 120
local MAP_REQUEST_INTERVAL = 3
local SPEED_LIMIT_STABILIZATION_TIME = 1
local G_FORCE_DEADZONE = 0.15
local GRAVITY = 9.81
local ELECTRICS_CACHE_INTERVAL = 0.033 -- ~30fps
local POSITION_CHECK_INTERVAL = 0.5 -- Check position twice per second
local HTML_UPDATE_INTERVAL = 0.033 -- ~30fps for HTML updates

-- Dependencies
local htmlTexture = nil
pcall(function() htmlTexture = require("htmlTexture") end)

-- Configuration
local config = {
    screenMaterialName = nil,
    htmlFilePath = nil,
    textureWidth = 512,
    textureHeight = 256,
    textureFPS = 30, -- Reduced from 60
    textureCreated = false
}

-- State management
local state = {
    engineMode = "comfort",
    suspensionMode = "comfort", 
    steeringMode = "comfort",
    brakeMode = "comfort",
    currentSpeedLimit = nil,
    pendingSpeedLimit = nil,
    pendingSpeedLimitTime = 0,
    mapRequested = false,
    lastPosition = nil,
    lastSpeedLimitCheck = 0
}

-- Timers
local timers = {
    update = 0,
    debug = 0,
    mapRequest = 0,
    electricsCache = 0,
    positionCheck = 0,
    htmlUpdate = 0
}

-- Debug system
local debug = {
    mode = false,
    lastOutput = "",
    interval = DEBUG_INTERVAL
}

-- Cache for electrics and frequently accessed values
local cache = {
    electrics = {},
    lastVehicleData = {},
    unitPreference = nil,
    fileExists = {}
}

-- Inverse FPS
local invFPS = 1 / UPDATE_FPS

-- File existence cache to avoid repeated I/O
local function fileExists(relativeFilePath)
    if cache.fileExists[relativeFilePath] ~= nil then
        return cache.fileExists[relativeFilePath]
    end
    
    local exists = false
    if FS and FS.fileExists then
        exists = FS:fileExists(relativeFilePath)
    else
        local file = io.open(relativeFilePath, "r")
        if file then
            file:close()
            exists = true
        end
    end
    
    cache.fileExists[relativeFilePath] = exists
    return exists
end

local function updateElectricsCache()
    if not electrics or not electrics.values then return end
    
    cache.electrics = {
        engineMode = electrics.values.engineMode,
        suspensionMode = electrics.values.suspensionMode,
        steeringMode = electrics.values.steeringMode,
        brakeMode = electrics.values.brakeMode,
        rpm = electrics.values.rpm or 0,
        gear = electrics.values.gear or -2,
        wheelspeed = electrics.values.wheelspeed or 0,
        transfercase_state = electrics.values.transfercase_state or 0.33,
        accXSmooth = electrics.values.accXSmooth or 0,
        accYSmooth = electrics.values.accYSmooth or 0,
        signal_L = electrics.values.signal_L or 0,
        signal_R = electrics.values.signal_R or 0,
        lights_state = electrics.values.lights_state or 0,
        highbeam = electrics.values.highbeam or 0,
        checkengine = electrics.values.checkengine or 0
    }
end

local function debugPrint(msg)
    if not debug.mode then return end
    
    local currentTime = os.time()
    if currentTime - timers.debug >= debug.interval then
        if msg ~= debug.lastOutput then
            log('I', 'M4Gauge', msg)
            debug.lastOutput = msg
        end
        timers.debug = currentTime
    end
end

local function hasPositionChangedSignificantly(newPos)
    if not state.lastPosition then
        state.lastPosition = newPos
        return true
    end
    
    local distance = (newPos - state.lastPosition):length()
    if distance > 50 then -- Only check speed limit if moved more than 50 meters
        state.lastPosition = newPos
        return true
    end
    
    return false
end

local function getSpeedLimit()
    if not mapmgr.mapData then
        local currentTime = os.time()
        if not state.mapRequested or (currentTime - timers.mapRequest >= MAP_REQUEST_INTERVAL) then
            mapmgr.requestMap()
            state.mapRequested = true
            timers.mapRequest = currentTime
        end
        return nil
    end
    
    local vehiclePos = obj:getPosition()
    if not vehiclePos then 
        return nil 
    end
    
    -- Only check map data if position changed significantly or it's been a while
    local currentTime = os.time()
    if not hasPositionChangedSignificantly(vehiclePos) and 
       state.currentSpeedLimit and 
       (currentTime - state.lastSpeedLimitCheck) < 2 then
        return state.currentSpeedLimit
    end
    
    state.lastSpeedLimitCheck = currentTime
    
    local n1id, n2id, dist = mapmgr.findClosestRoad(vehiclePos)
    if not (n1id and n2id) then 
        return nil 
    end
    
    if not mapmgr.mapData.graph then 
        return nil 
    end
    
    local n1 = mapmgr.mapData.graph[n1id]
    if not n1 then 
        return nil 
    end
    
    local edge = n1[n2id]
    
    if not edge then 
        local n2 = mapmgr.mapData.graph[n2id]
        if not n2 then 
            return nil 
        end
        edge = n2[n1id]
        if not edge then 
            return nil 
        end
    end
    
    local speedLimit = edge.speedLimit
    if not speedLimit or speedLimit <= 0 then
        speedLimit = edge.speed_limit or edge.limit
    end
    
    if not speedLimit or speedLimit <= 0 then 
        return nil 
    end
    
    return speedLimit * 3.6
end

local function getStabilizedSpeedLimit(dt)
    local rawSpeedLimit = getSpeedLimit()
    
    if not rawSpeedLimit then
        if state.currentSpeedLimit then
            if not state.pendingSpeedLimit then
                state.pendingSpeedLimitTime = state.pendingSpeedLimitTime + dt
                
                if state.pendingSpeedLimitTime >= SPEED_LIMIT_STABILIZATION_TIME then
                    state.currentSpeedLimit = nil
                    state.pendingSpeedLimit = nil
                    state.pendingSpeedLimitTime = 0
                end
            end
        end
        return state.currentSpeedLimit
    end
    
    rawSpeedLimit = math.floor(rawSpeedLimit + 0.5)
    
    if not state.currentSpeedLimit then
        state.currentSpeedLimit = rawSpeedLimit
        return state.currentSpeedLimit
    end
    
    if rawSpeedLimit ~= state.currentSpeedLimit then
        if state.pendingSpeedLimit ~= rawSpeedLimit then
            state.pendingSpeedLimit = rawSpeedLimit
            state.pendingSpeedLimitTime = 0
        else
            state.pendingSpeedLimitTime = state.pendingSpeedLimitTime + dt
            
            if state.pendingSpeedLimitTime >= SPEED_LIMIT_STABILIZATION_TIME then
                state.currentSpeedLimit = state.pendingSpeedLimit
                state.pendingSpeedLimit = nil
                state.pendingSpeedLimitTime = 0
            end
        end
    else
        state.pendingSpeedLimit = nil
        state.pendingSpeedLimitTime = 0
    end
    
    return state.currentSpeedLimit
end

local function processGForces()
    local accX = cache.electrics.accXSmooth
    local accY = cache.electrics.accYSmooth
    local gForceX = accX / GRAVITY
    local gForceY = accY / GRAVITY
    
    -- Apply deadzone
    if math.abs(gForceX) < G_FORCE_DEADZONE then gForceX = 0 end
    if math.abs(gForceY) < G_FORCE_DEADZONE then gForceY = 0 end
    
    return {
        xSmooth = gForceX * GRAVITY,
        ySmooth = gForceY * GRAVITY
    }
end

local function updateModeStates()
    local changed = false
    
    if cache.electrics.engineMode and cache.electrics.engineMode ~= state.engineMode then
        state.engineMode = cache.electrics.engineMode
        changed = true
    end
    if cache.electrics.suspensionMode and cache.electrics.suspensionMode ~= state.suspensionMode then
        state.suspensionMode = cache.electrics.suspensionMode
        changed = true
    end
    if cache.electrics.steeringMode and cache.electrics.steeringMode ~= state.steeringMode then
        state.steeringMode = cache.electrics.steeringMode
        changed = true
    end
    if cache.electrics.brakeMode and cache.electrics.brakeMode ~= state.brakeMode then
        state.brakeMode = cache.electrics.brakeMode
        changed = true
    end
    
    return changed
end

local function hasVehicleDataChanged(newData)
    local lastData = cache.lastVehicleData
    
    -- Check key values that would require an update
    return (
        math.abs((newData.rpm or 0) - (lastData.rpm or 0)) > 50 or
        (newData.gear or -2) ~= (lastData.gear or -2) or
        math.abs((newData.wheelspeed or 0) - (lastData.wheelspeed or 0)) > 2 or
        newData.engineMode ~= lastData.engineMode or
        newData.suspensionMode ~= lastData.suspensionMode or
        newData.steeringMode ~= lastData.steeringMode or
        newData.brakeMode ~= lastData.brakeMode or
        math.abs((newData.transfercase_state or 0.33) - (lastData.transfercase_state or 0.33)) > 0.1 or
        math.abs((newData.accelerationData.xSmooth or 0) - (lastData.accelerationData and lastData.accelerationData.xSmooth or 0)) > 1 or
        math.abs((newData.accelerationData.ySmooth or 0) - (lastData.accelerationData and lastData.accelerationData.ySmooth or 0)) > 1 or
        (newData.signal_L or 0) ~= (lastData.signal_L or 0) or
        (newData.signal_R or 0) ~= (lastData.signal_R or 0) or
        (newData.lights_state or 0) ~= (lastData.lights_state or 0) or
        (newData.highbeam or 0) ~= (lastData.highbeam or 0) or
        (newData.checkengine or 0) ~= (lastData.checkengine or 0) or
        (newData.speedLimit or 0) ~= (lastData.speedLimit or 0)
    )
end

local function updateGFX(dt)
    if not fileExists(TEXTURE_PATH) then return end
    if not htmlTexture then return end
    
    -- Update electrics cache at reduced frequency
    timers.electricsCache = timers.electricsCache + dt
    if timers.electricsCache >= ELECTRICS_CACHE_INTERVAL then
        updateElectricsCache()
        timers.electricsCache = 0
    end
    
    timers.update = timers.update + dt
    timers.htmlUpdate = timers.htmlUpdate + dt
    
    if timers.update > invFPS and config.screenMaterialName and config.textureCreated then
        timers.update = 0
        
        updateModeStates()
        
        local accelerationData = processGForces()
        local speedLimit = getStabilizedSpeedLimit(dt)
        
        -- Get unit preference (cache it to avoid repeated calls)
        if not cache.unitPreference and settings and settings.getValue then
            cache.unitPreference = settings.getValue("uiUnitLength")
        end
        
        local vehicleData = {
            rpm = cache.electrics.rpm,
            gear = cache.electrics.gear,
            wheelspeed = cache.electrics.wheelspeed,
            engineMode = state.engineMode,
            suspensionMode = state.suspensionMode,
            steeringMode = state.steeringMode,
            brakeMode = state.brakeMode,
            transfercase_state = cache.electrics.transfercase_state,
            accelerationData = accelerationData,
            signal_L = cache.electrics.signal_L,
            signal_R = cache.electrics.signal_R,
            lights_state = cache.electrics.lights_state,
            highbeam = cache.electrics.highbeam,
            checkengine = cache.electrics.checkengine,
            speedLimit = speedLimit,
            uiUnitLength = cache.unitPreference
        }
        
        -- Only update HTML if data has actually changed
        if timers.htmlUpdate >= HTML_UPDATE_INTERVAL and hasVehicleDataChanged(vehicleData) then
            if type(htmlTexture.call) == "function" then
                local success, error = pcall(function()
                    htmlTexture.call(config.screenMaterialName, "updateWithBeamNGData", vehicleData)
                end)
                
                if success then
                    cache.lastVehicleData = vehicleData
                    timers.htmlUpdate = 0
                elseif error then
                    log("W", "M4Gauge", "HTML texture update failed: " .. tostring(error))
                end
            end
        end
    end
end

local function init(jbeamData)
    if not fileExists(TEXTURE_PATH) then return end
    if not htmlTexture then return end
    
    config.screenMaterialName = jbeamData.materialName or "@sdd_g82_gauges"
    config.htmlFilePath = jbeamData.htmlPath or "local://local/vehicles/sdd_g82/Screen/m4_gauge.html"
    config.textureWidth = jbeamData.textureWidth or 512
    config.textureHeight = jbeamData.textureHeight or 256
    config.textureFPS = jbeamData.textureFPS or 15 -- Reduced from 60
    invFPS = 1 / UPDATE_FPS
    
    if type(htmlTexture.create) == "function" then
        local success, error = pcall(function()
            htmlTexture.create(config.screenMaterialName, config.htmlFilePath, 
                             config.textureWidth, config.textureHeight, config.textureFPS, "automatic")
        end)
        
        config.textureCreated = success
        if not success and error then
            log("E", "M4Gauge", "Failed to create HTML texture: " .. tostring(error))
        end
    end
    
    -- Initialize unit preference
    if settings and settings.getValue then
        cache.unitPreference = settings.getValue("uiUnitLength")
        if cache.unitPreference and config.textureCreated and type(htmlTexture.call) == "function" then
            pcall(function()
                htmlTexture.call(config.screenMaterialName, "setup", {uiUnitLength = cache.unitPreference})
            end)
        end
    end
end

function M.reset()
    if not fileExists(TEXTURE_PATH) then return end
    
    state.mapRequested = false
    state.currentSpeedLimit = nil
    state.pendingSpeedLimit = nil
    state.pendingSpeedLimitTime = 0
    state.lastPosition = nil
    state.lastSpeedLimitCheck = 0
    cache.unitPreference = nil
    cache.lastVehicleData = {}
    
    -- Reset timers
    for key, _ in pairs(timers) do
        timers[key] = 0
    end
end

function M.destroy()
    -- Clean up if needed
end

M.init = init
M.updateGFX = updateGFX

return M