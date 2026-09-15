local M = {}

local state = {
    alarmTriggered = false,
    alarmStartTime = 0,
    isAlarmPlaying = false,
    nextAlarmTime = 0,
    hazardsControlledByAlarm = false,
    hazardsStartTime = 0,
    initialLoad = true,
    lastIgnitionLevel = 3,
    lastSpeed = 0,
    lastSystemActive = 0,
    lastSoundActive = 0
}

local SPEED_THRESHOLD_ALARM = 0.8
local ALARM_DURATION = 60
local ALARM_INTERVAL = 1.4
local HAZARDS_DELAY = 1

local cache = {
    ignitionLevel = 0,
    speed = 0,
    hazardState = 0,
    systemActive = 0,
    soundActive = 0
}

local lastCacheUpdate = 0
local CACHE_UPDATE_INTERVAL = 0.05

local function updateCache()
    if not electrics or not electrics.values then return end
    
    cache.ignitionLevel = electrics.values.ignitionLevel or 0
    cache.hazardState = electrics.values.hazard or 0
    cache.systemActive = electrics.values.alarmSystemActive or 0
    cache.soundActive = electrics.values.alarmSoundActive or 0
    
    if obj then
        cache.speed = obj:getVelocity():length()
    end
end

local function setElectricValue(key, value)
    if electrics.values[key] ~= value then
        electrics.values[key] = value
        
        if key == "alarmSystemActive" then
            cache.systemActive = value
        elseif key == "alarmSoundActive" then
            cache.soundActive = value
        end
    end
end

local function playAlarm()
    if not obj then return end

    obj:createSFXSource("/vehicles/sdd_g82/sounds/alarm.mp3", "AudioClosest3D", "alarmSound", -1)
    obj:playSFXOnce("alarmSound", 471, 2, 1)
    state.nextAlarmTime = os.clock() + ALARM_INTERVAL
end

local function queueIgnitionChange(level)
    if cache.ignitionLevel ~= level then
        obj:queueLuaCommand("electrics.setIgnitionLevel(" .. level .. ")")
    end
end

local function toggleHazards()
    if cache.hazardState ~= 1 then
        electrics.toggle_warn_signal()
        state.hazardsControlledByAlarm = true
    end
end

local function stopAlarmSequence()
    if not state.isAlarmPlaying then return end

    log('D', 'alarm', string.format("Stopping alarm sequence - Hazard state: %d", cache.hazardState))
    
    if state.hazardsControlledByAlarm and cache.hazardState == 1 then
        log('D', 'alarm', "Turning off hazards")
        electrics.toggle_warn_signal()
    end
    
    queueIgnitionChange(0)
    
    state.hazardsControlledByAlarm = false
    state.isAlarmPlaying = false
    state.nextAlarmTime = 0
    state.hazardsStartTime = 0
    
    log('D', 'alarm', "Alarm sequence stopped")
end

local function processAlarmLogic(currentTime, clockTime)
    if not obj then return end
    
    if cache.ignitionLevel == 0 then
        setElectricValue("alarmSystemActive", 1)
    end
    
    if cache.systemActive == 1 and not state.alarmTriggered then
        if cache.speed > SPEED_THRESHOLD_ALARM then
            state.alarmTriggered = true
            state.alarmStartTime = currentTime
            setElectricValue("alarmSoundActive", 1)
            state.isAlarmPlaying = true
            
            queueIgnitionChange(1)
            state.hazardsStartTime = currentTime + HAZARDS_DELAY
            
            playAlarm()
        end
    end
    
    if state.isAlarmPlaying and cache.soundActive == 1 then
        if cache.ignitionLevel < 2 then
            queueIgnitionChange(1)
        end
        
        if state.hazardsStartTime > 0 and currentTime >= state.hazardsStartTime then
            toggleHazards()
            state.hazardsStartTime = 0
        end
        
        if clockTime >= state.nextAlarmTime then
            playAlarm()
        end
        
        if cache.ignitionLevel > 1 then
            state.alarmTriggered = false
            setElectricValue("alarmSystemActive", 0)
            setElectricValue("alarmSoundActive", 0)
            stopAlarmSequence()
            return
        end
    end
    
    if state.alarmTriggered and (currentTime - state.alarmStartTime) >= ALARM_DURATION then
        state.alarmTriggered = false
        setElectricValue("alarmSoundActive", 0)
        queueIgnitionChange(0)
        stopAlarmSequence()
    end
    
    if cache.soundActive == 0 then
        stopAlarmSequence()
    end
    
    if cache.ignitionLevel > 0 and cache.systemActive == 1 and not state.alarmTriggered then
        state.alarmTriggered = false
        setElectricValue("alarmSystemActive", 0)
        setElectricValue("alarmSoundActive", 0)
        stopAlarmSequence()
    end
end

function M.init(jbeamData)
    setElectricValue("alarmSystemActive", 0)
    setElectricValue("alarmSoundActive", 0)
    state.hazardsControlledByAlarm = false
    state.initialLoad = true
    return true
end

function M.reset()
    local currentTime = os.time()
    
    state.alarmTriggered = false
    setElectricValue("alarmSystemActive", 0)
    setElectricValue("alarmSoundActive", 0)
    
    if state.hazardsControlledByAlarm and cache.hazardState == 1 then
        electrics.toggle_warn_signal()
    end
    state.hazardsControlledByAlarm = false
    
    stopAlarmSequence()

    if state.initialLoad then
        queueIgnitionChange(3)
        state.initialLoad = false
    else
        queueIgnitionChange(state.lastIgnitionLevel)
    end
end

function M.updateGFX(dt)
    lastCacheUpdate = lastCacheUpdate + dt
    if lastCacheUpdate >= CACHE_UPDATE_INTERVAL then
        updateCache()
        lastCacheUpdate = 0
    end
    
    if cache.ignitionLevel ~= nil then
        state.lastIgnitionLevel = cache.ignitionLevel
    end
    
    if cache.speed == state.lastSpeed and 
       cache.systemActive == state.lastSystemActive and 
       cache.soundActive == state.lastSoundActive and 
       not state.isAlarmPlaying then
        return
    end
    
    state.lastSpeed = cache.speed
    state.lastSystemActive = cache.systemActive
    state.lastSoundActive = cache.soundActive
    
    local currentTime = os.time()
    local clockTime = os.clock()
    processAlarmLogic(currentTime, clockTime)
end

return M