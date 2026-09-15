local M = {}

local startButtonPress = 0

local volumeKnobRotation = 0
local volumeLevel = 5
local maxVolumeLevel = 10

local headlightKnobRotation = 0
local headlightState = 1
local headlightDirection = 1
local headlightPositions = {0, 0.25, 0.5, 0.75}
local headlightStateNames = {"Off", "Running Lights", "Auto", "Headlights On"}

local consoleRotation = 0
local consoleState = 0
local consoleTargetRotation = 0
local consoleAnimationSpeed = 3.0

local visorLRotation = 0
local visorRRotation = 0
local visorLState = 0
local visorRState = 0
local visorLTargetRotation = 0
local visorRTargetRotation = 0
local visorAnimationSpeed = 2.5

local gloveBoxRotation = 0
local gloveBoxState = 0
local gloveBoxTargetRotation = 0
local gloveBoxAnimationSpeed = 2.0

local lampLState = 0
local lampRState = 0
local lampMState = 0
local lampBrightness = 1.0
local lampAutoDoor = true
local doorLampBrightness = 0.8

local lastConsoleTrigger = 0
local lastVisorLTrigger = 0
local lastVisorRTrigger = 0
local lastGloveBoxTrigger = 0
local lastLampLTrigger = 0
local lastLampRTrigger = 0
local lastLampMTrigger = 0
local lastAnyDoorOpen = false

local function updateElectrics()
    electrics.values.startButtonPress = startButtonPress
    electrics.values.volumeKnobRotation = volumeKnobRotation
    electrics.values.headlightKnobRotation = headlightKnobRotation

    electrics.values.volumeLevel = volumeLevel
    electrics.values.headlightState = headlightState
    electrics.values.headlightStateName = headlightStateNames[headlightState]
    electrics.values.headlightDirection = headlightDirection

    electrics.values.console = consoleRotation
    electrics.values.consoleState = consoleState

    electrics.values.visorL = visorLRotation
    electrics.values.visorR = visorRRotation
    electrics.values.visorLState = visorLState
    electrics.values.visorRState = visorRState

    electrics.values.gloveBox = gloveBoxRotation
    electrics.values.gloveBoxState = gloveBoxState

    electrics.values.lampLState = lampLState
    electrics.values.lampRState = lampRState
    electrics.values.lampMState = lampMState

    local doorLOpen = electrics.values.door_L_coupler_notAttached or 0
    local doorROpen = electrics.values.door_R_coupler_notAttached or 0
    local anyDoorOpen = (doorLOpen > 0) or (doorROpen > 0)

    local finalLampL = 0
    local finalLampR = 0
    
    if lampAutoDoor and anyDoorOpen then
        finalLampL = doorLampBrightness
        finalLampR = doorLampBrightness
    else

        finalLampL = lampLState * lampBrightness
        finalLampR = lampRState * lampBrightness

        if lampMState == 1 then
            finalLampL = lampBrightness
            finalLampR = lampBrightness
        end
    end

    electrics.values.lampL = finalLampL
    electrics.values.lampR = finalLampR

    electrics.values.doorLOpen = doorLOpen
    electrics.values.doorROpen = doorROpen
    electrics.values.anyDoorOpen = anyDoorOpen and 1 or 0
end

local function smoothLerp(current, target, speed, dt)
    local diff = target - current
    if math.abs(diff) < 0.001 then
        return target
    end
    return current + diff * speed * dt
end

local function onVolumeControl()

    volumeLevel = volumeLevel + 1
    if volumeLevel > maxVolumeLevel then
        volumeLevel = 0
    end

    volumeKnobRotation = volumeLevel / maxVolumeLevel
    
    log('I', 'dashboardProps', 'Volume changed to: ' .. volumeLevel .. '/10')
    log('I', 'dashboardProps', 'Volume knob rotation: ' .. string.format("%.2f", volumeKnobRotation))
end

local function onToggleHeadlights()

    headlightState = headlightState + headlightDirection

    if headlightState > 4 then
        headlightState = 3
        headlightDirection = -1
    elseif headlightState < 1 then
        headlightState = 2
        headlightDirection = 1
    end

    headlightKnobRotation = headlightPositions[headlightState]

    if headlightState == 1 then
        -- Off
        electrics.values.lights = 0
        electrics.values.headlights = 0
        electrics.values.lowbeam = 0
        electrics.values.lightbar = 0
    elseif headlightState == 2 then
        electrics.values.lights = 0
        electrics.values.headlights = 0
        electrics.values.lowbeam = 0
        electrics.values.lightbar = 0
    elseif headlightState == 3 then
        electrics.values.lights = 0
        electrics.values.headlights = 0
        electrics.values.lowbeam = 0
        electrics.values.lightbar = 0
    elseif headlightState == 4 then
        electrics.values.lights = 2
        electrics.values.headlights = 1
        electrics.values.lowbeam = 1
        electrics.values.lightbar = 1
    end
    
    log('I', 'dashboardProps', 'Headlight state: ' .. headlightStateNames[headlightState] .. ' (direction: ' .. (headlightDirection == 1 and 'up' or 'down') .. ')')
    log('I', 'dashboardProps', 'Headlight knob rotation: ' .. string.format("%.2f", headlightKnobRotation))
    log('I', 'dashboardProps', 'Electrical values - lights: ' .. (electrics.values.lights or 0) .. ', headlights: ' .. (electrics.values.headlights or 0) .. ', lowbeam: ' .. (electrics.values.lowbeam or 0) .. ', lightbar: ' .. (electrics.values.lightbar or 0))
end

local function onToggleIgnition()
    startButtonPress = 1
    
    log('I', 'dashboardProps', 'Start button pressed')

    obj:queueGameEngineLua(string.format(
        "be:getObjectByID(%d):queueLuaCommand('controller.getControllerSafe(\"dashboardProps\").releaseStartButton()')", 
        obj:getID()
    ), 0.25)
end

local function onToggleConsole()
    consoleState = consoleState == 0 and 1 or 0
    consoleTargetRotation = consoleState
    
    log('I', 'dashboardProps', 'Console ' .. (consoleState == 1 and 'opening' or 'closing'))
    log('I', 'dashboardProps', 'Console target rotation: ' .. consoleTargetRotation)
end

local function setConsoleState(state)
    if state == 0 or state == 1 then
        consoleState = state
        consoleTargetRotation = state
        log('I', 'dashboardProps', 'Console state set to: ' .. (state == 1 and 'open' or 'closed'))
    end
end

local function onToggleVisorL()
    visorLState = visorLState == 0 and 1 or 0
    visorLTargetRotation = visorLState
    
    log('I', 'dashboardProps', 'Left visor ' .. (visorLState == 1 and 'lowering' or 'raising'))
end

local function onToggleVisorR()
    visorRState = visorRState == 0 and 1 or 0
    visorRTargetRotation = visorRState
    
    log('I', 'dashboardProps', 'Right visor ' .. (visorRState == 1 and 'lowering' or 'raising'))
end

local function setVisorLState(state)
    if state == 0 or state == 1 then
        visorLState = state
        visorLTargetRotation = state
        log('I', 'dashboardProps', 'Left visor state set to: ' .. (state == 1 and 'down' or 'up'))
    end
end

local function setVisorRState(state)
    if state == 0 or state == 1 then
        visorRState = state
        visorRTargetRotation = state
        log('I', 'dashboardProps', 'Right visor state set to: ' .. (state == 1 and 'down' or 'up'))
    end
end

local function onToggleGloveBox()
    gloveBoxState = gloveBoxState == 0 and 1 or 0
    gloveBoxTargetRotation = gloveBoxState
    
    log('I', 'dashboardProps', 'Glove box ' .. (gloveBoxState == 1 and 'opening' or 'closing'))
end

local function setGloveBoxState(state)
    if state == 0 or state == 1 then
        gloveBoxState = state
        gloveBoxTargetRotation = state
        log('I', 'dashboardProps', 'Glove box state set to: ' .. (state == 1 and 'open' or 'closed'))
    end
end

local function onToggleLampL()
    lampLState = lampLState == 0 and 1 or 0
    log('I', 'dashboardProps', 'Left lamp ' .. (lampLState == 1 and 'on' or 'off'))
end

local function onToggleLampR()
    lampRState = lampRState == 0 and 1 or 0
    log('I', 'dashboardProps', 'Right lamp ' .. (lampRState == 1 and 'on' or 'off'))
end

local function onToggleLampM()
    lampMState = lampMState == 0 and 1 or 0
    log('I', 'dashboardProps', 'Both lamps ' .. (lampMState == 1 and 'on' or 'off'))
end

local function setLampLState(state)
    if state == 0 or state == 1 then
        lampLState = state
        log('I', 'dashboardProps', 'Left lamp set to: ' .. (state == 1 and 'on' or 'off'))
    end
end

local function setLampRState(state)
    if state == 0 or state == 1 then
        lampRState = state
        log('I', 'dashboardProps', 'Right lamp set to: ' .. (state == 1 and 'on' or 'off'))
    end
end

local function setLampMState(state)
    if state == 0 or state == 1 then
        lampMState = state
        log('I', 'dashboardProps', 'Both lamps set to: ' .. (state == 1 and 'on' or 'off'))
    end
end

local function setLampBrightness(brightness)
    if brightness >= 0 and brightness <= 1 then
        lampBrightness = brightness
        log('I', 'dashboardProps', 'Lamp brightness set to: ' .. string.format("%.2f", brightness))
    end
end

local function setDoorLampBrightness(brightness)
    if brightness >= 0 and brightness <= 1 then
        doorLampBrightness = brightness
        log('I', 'dashboardProps', 'Door lamp brightness set to: ' .. string.format("%.2f", brightness))
    end
end

local function setLampAutoDoor(enabled)
    lampAutoDoor = enabled
    log('I', 'dashboardProps', 'Automatic door lighting ' .. (enabled and 'enabled' or 'disabled'))
end

local function getLampAutoDoor()
    return lampAutoDoor
end

local function releaseStartButton()
    startButtonPress = 0
    log('I', 'dashboardProps', 'Start button released')
end

local function setVolume(level)
    if level >= 0 and level <= maxVolumeLevel then
        volumeLevel = level
        volumeKnobRotation = volumeLevel / maxVolumeLevel
        log('I', 'dashboardProps', 'Volume set to: ' .. volumeLevel .. '/10')
    end
end

local function setHeadlightState(state)
    if state >= 1 and state <= 4 then
        headlightState = state
        headlightKnobRotation = headlightPositions[headlightState]
        
        if headlightState == 1 then
            headlightDirection = 1
        elseif headlightState == 4 then
            headlightDirection = -1
        end
        
        if headlightState == 1 then
            -- Off
            electrics.values.lights = 0
            electrics.values.headlights = 0
            electrics.values.lowbeam = 0
            electrics.values.lightbar = 0
        elseif headlightState == 2 then
            electrics.values.lights = 0
            electrics.values.headlights = 0
            electrics.values.lowbeam = 0
            electrics.values.lightbar = 0
        elseif headlightState == 3 then
            electrics.values.lights = 0
            electrics.values.headlights = 0
            electrics.values.lowbeam = 0
            electrics.values.lightbar = 0
        elseif headlightState == 4 then
            electrics.values.lights = 2
            electrics.values.headlights = 1
            electrics.values.lowbeam = 1
            electrics.values.lightbar = 1
        end
        
        log('I', 'dashboardProps', 'Headlight state set to: ' .. headlightStateNames[headlightState])
        log('I', 'dashboardProps', 'Electrical values - lights: ' .. (electrics.values.lights or 0) .. ', headlights: ' .. (electrics.values.headlights or 0) .. ', lowbeam: ' .. (electrics.values.lowbeam or 0) .. ', lightbar: ' .. (electrics.values.lightbar or 0))
    end
end

local function updateGFX(dt)

    local consoleTrigger = electrics.values.console_trigger or 0
    local visorLTrigger = electrics.values.visorL_trigger or 0  
    local visorRTrigger = electrics.values.visorR_trigger or 0
    local gloveBoxTrigger = electrics.values.gloveBox_trigger or 0
    local lampLTrigger = electrics.values.lampL_trigger or 0
    local lampRTrigger = electrics.values.lampR_trigger or 0
    local lampMTrigger = electrics.values.lampM_trigger or 0
    
    if consoleTrigger > 0 and lastConsoleTrigger == 0 then
        onToggleConsole()
    end
    
    if visorLTrigger > 0 and lastVisorLTrigger == 0 then
        onToggleVisorL()
    end
    
    if visorRTrigger > 0 and lastVisorRTrigger == 0 then
        onToggleVisorR()
    end
    
    if gloveBoxTrigger > 0 and lastGloveBoxTrigger == 0 then
        onToggleGloveBox()
    end
    
    if lampLTrigger > 0 and lastLampLTrigger == 0 then
        onToggleLampL()
    end
    
    if lampRTrigger > 0 and lastLampRTrigger == 0 then
        onToggleLampR()
    end
    
    if lampMTrigger > 0 and lastLampMTrigger == 0 then
        onToggleLampM()
    end
    
    local doorLOpen = electrics.values.door_L_coupler_notAttached or 0
    local doorROpen = electrics.values.door_R_coupler_notAttached or 0
    local anyDoorOpen = (doorLOpen > 0) or (doorROpen > 0)
    
    if anyDoorOpen ~= lastAnyDoorOpen then
        if lampAutoDoor then
            log('I', 'dashboardProps', 'Door state changed - ' .. (anyDoorOpen and 'door opened, turning on lamps' or 'doors closed, reverting to manual control'))
        else
            log('I', 'dashboardProps', 'Door state changed but auto-door lighting is disabled')
        end
        lastAnyDoorOpen = anyDoorOpen
    end
    
    lastConsoleTrigger = consoleTrigger
    lastVisorLTrigger = visorLTrigger
    lastVisorRTrigger = visorRTrigger
    lastGloveBoxTrigger = gloveBoxTrigger
    lastLampLTrigger = lampLTrigger
    lastLampRTrigger = lampRTrigger
    lastLampMTrigger = lampMTrigger
    
    consoleRotation = smoothLerp(consoleRotation, consoleTargetRotation, consoleAnimationSpeed, dt)
    
    visorLRotation = smoothLerp(visorLRotation, visorLTargetRotation, visorAnimationSpeed, dt)
    visorRRotation = smoothLerp(visorRRotation, visorRTargetRotation, visorAnimationSpeed, dt)
    
    gloveBoxRotation = smoothLerp(gloveBoxRotation, gloveBoxTargetRotation, gloveBoxAnimationSpeed, dt)
    
    updateElectrics()
end

local function reset()
    startButtonPress = 0
    volumeKnobRotation = 0.5
    volumeLevel = 5
    headlightKnobRotation = 0
    headlightState = 1
    headlightDirection = 1
    
    consoleRotation = 0
    consoleState = 0
    consoleTargetRotation = 0
    
    visorLRotation = 0
    visorRRotation = 0
    visorLState = 0
    visorRState = 0
    visorLTargetRotation = 0
    visorRTargetRotation = 0
    
    gloveBoxRotation = 0
    gloveBoxState = 0
    gloveBoxTargetRotation = 0
    
    lampLState = 0
    lampRState = 0
    lampMState = 0
    
    lastConsoleTrigger = 0
    lastVisorLTrigger = 0
    lastVisorRTrigger = 0
    lastGloveBoxTrigger = 0
    lastLampLTrigger = 0
    lastLampRTrigger = 0
    lastLampMTrigger = 0
    lastAnyDoorOpen = false

    electrics.values.lights = 0
    electrics.values.headlights = 0
    electrics.values.lowbeam = 0
    electrics.values.lightbar = 0
    
    updateElectrics()
end

local function init()
    reset()
    log('I', 'dashboardProps', 'Dashboard Props Controller initialized')
    log('I', 'dashboardProps', 'Volume: ' .. volumeLevel .. '/10, Headlights: ' .. headlightStateNames[headlightState])
    log('I', 'dashboardProps', 'Console: closed, Visors: up, Glove box: closed, Lamps: off')
    log('I', 'dashboardProps', 'Automatic door lighting: ' .. (lampAutoDoor and 'enabled' or 'disabled'))
    log('I', 'dashboardProps', 'Headlight control: Only "Headlights On" position will turn on lights')
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.onVolumeControl = onVolumeControl
M.onToggleHeadlights = onToggleHeadlights
M.onToggleIgnition = onToggleIgnition
M.releaseStartButton = releaseStartButton
M.setVolume = setVolume
M.setHeadlightState = setHeadlightState

M.onToggleConsole = onToggleConsole
M.setConsoleState = setConsoleState

M.onToggleVisorL = onToggleVisorL
M.onToggleVisorR = onToggleVisorR
M.setVisorLState = setVisorLState
M.setVisorRState = setVisorRState

M.onToggleGloveBox = onToggleGloveBox
M.setGloveBoxState = setGloveBoxState

M.onToggleLampL = onToggleLampL
M.onToggleLampR = onToggleLampR
M.onToggleLampM = onToggleLampM
M.setLampLState = setLampLState
M.setLampRState = setLampRState
M.setLampMState = setLampMState
M.setLampBrightness = setLampBrightness
M.setDoorLampBrightness = setDoorLampBrightness
M.setLampAutoDoor = setLampAutoDoor
M.getLampAutoDoor = getLampAutoDoor

return M