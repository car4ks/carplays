local M = {}

local accessoryTimer = 0
local lastAccessoryActive = false

local seatHeaterLState = 0
local lastSeatHeaterLInput = 0
local seatHeaterRState = 0
local lastSeatHeaterRInput = 0

local recirculationState = 0
local lastRecirculationInput = 0

local rearDefrostState = 0
local lastReardefrostInput = 0
local frontDefrostState = 0
local lastFrontdefrostInput = 0

local acState = 0
local lastacInput = 0

local parkingAssistState = 0
local lastparkingAssistInput = 0

local cdEjectState = 0
local lastCdInput = 0
local cdPosition = 0
local cdEjectSpeed = 2.0

local visorRState = 0
local lastVisorRInput = 0
local visorRPosition = 0

local visorLState = 0
local lastVisorLInput = 0
local visorLPosition = 0

local visorSpeed = 3.0

local cdSoundNode = "dsh2"
local cdEjectSoundPath = "/vehicles/sdd_f87/sounds/cdEject.mp3"
local cdRetractSoundPath = "/vehicles/sdd_f87/sounds/cdRetract.mp3"

local function resolveNodeID(nodeName)
  local v = _G.v
  if not v or not v.data or not v.data.nodes then return 0 end
  for _, node in pairs(v.data.nodes) do
    if node.name == nodeName then return node.cid end
  end
  return 0
end

local function playCDSound(soundPath)
  local nodeId = resolveNodeID(cdSoundNode)
  if nodeId > 0 then
    local safeName = soundPath:gsub("/", "_") .. "_" .. nodeId .. "_" .. math.random(1000)
    local sfx = obj:createSFXSource(soundPath, "AudioDefault3D", safeName, nodeId)
    if sfx then
      obj:setVolumePitch(sfx, 0.7, 1.0)
      obj:playSFX(sfx)
    end
  end
end

local function updateGFX(dt)
 
  local fuel = electrics.values.fuel or 0
  local ignition = electrics.values.ignitionLevel or 0
  for i = 1, 7 do
    local threshold = 0.05 + (i - 1) * 0.125
    if ignition < 1 then
      electrics.values["fuel_" .. i] = 0
    else
      electrics.values["fuel_" .. i] = (fuel >= threshold) and 1 or 0
    end
  end

  local waterTemp = electrics.values.watertemp or 0
  local tempMin = 40
  local tempMax = 160
  local normalized = math.min(math.max((waterTemp - tempMin) / (tempMax - tempMin), 0), 1)

  for i = 1, 7 do
    local threshold = 0.05 + (i - 1) * 0.125
    if ignition < 1 then
      electrics.values["temp_" .. i] = 0
    else
      electrics.values["temp_" .. i] = (normalized >= threshold) and 1 or 0
    end
  end

  local screenValue = 0
  if electrics.values.ignitionLevel >= 1 then
    screenValue = 1
  end

  electrics.values.mainScreen = 0
  electrics.values.mainScreenSport = 0

  if electrics.values.sportMode == 1 then
    electrics.values.mainScreenSport = screenValue
  else
    electrics.values.mainScreen = screenValue
  end  

  local ignitionLevel = electrics.values.ignitionLevel or 0
  local engineRunning = electrics.values.engineRunning or 0

  if ignitionLevel >= 2 then
    electrics.values.ignitionAccessory = 1
    accessoryTimer = 0
    lastAccessoryActive = false
  elseif ignitionLevel == 1 and engineRunning == 0 then
    if not lastAccessoryActive then
      accessoryTimer = 0
      lastAccessoryActive = true
    else
      accessoryTimer = accessoryTimer + dt
    end

    if accessoryTimer >= 2.5 then
      electrics.values.ignitionAccessory = 0
    else
      electrics.values.ignitionAccessory = 2
    end
  else
    electrics.values.ignitionAccessory = 0
    accessoryTimer = 0
    lastAccessoryActive = false
  end

  local ABS = electrics.values.hasABS or 0
  if ABS == 0 then
    electrics.values.absDisabled = 1
  else
    electrics.values.absDisabled = 0
  end

  if ignitionLevel > 1 then
    local seatInputL = electrics.values.seat_heater_L_input or 0
    if seatInputL == 1 and lastSeatHeaterLInput == 0 then
      seatHeaterLState = (seatHeaterLState + 1) % 4
    end
    lastSeatHeaterLInput = seatInputL
    electrics.values.seatHeaterL = seatHeaterLState

    local seatInputR = electrics.values.seat_heater_R_input or 0
    if seatInputR == 1 and lastSeatHeaterRInput == 0 then
      seatHeaterRState = (seatHeaterRState + 1) % 4
    end
    lastSeatHeaterRInput = seatInputR
    electrics.values.seatHeaterR = seatHeaterRState
  else
    seatHeaterLState = 0
    seatHeaterRState = 0
    lastSeatHeaterLInput = 0
    lastSeatHeaterRInput = 0
    electrics.values.seatHeaterL = 0
    electrics.values.seatHeaterR = 0
  end

  local recircInput = electrics.values.recirculation_input or 0

  if ignitionLevel > 1 then
    if recircInput == 1 and lastRecirculationInput == 0 then
      recirculationState = (recirculationState + 1) % 3
    end
    lastRecirculationInput = recircInput
  else
    recirculationState = 0
    lastRecirculationInput = 0
  end

  electrics.values.recirculation = recirculationState

  local reardefrostInput = electrics.values.rear_defrost_input or 0

  if ignitionLevel > 1 then
    if reardefrostInput == 1 and lastReardefrostInput == 0 then
      rearDefrostState = 1 - rearDefrostState 
    end
    lastReardefrostInput = reardefrostInput
  else
    rearDefrostState = 0
    lastReardefrostInput = 0
  end

  electrics.values.rearDefrost = rearDefrostState

  local frontDefrostInput = electrics.values.front_defrost_input or 0

  if ignitionLevel > 1 then
    if frontDefrostInput == 1 and lastFrontdefrostInput == 0 then
      frontDefrostState = 1 - frontDefrostState 
    end
    lastFrontdefrostInput = frontDefrostInput
  else
    frontDefrostState = 0
    lastFrontdefrostInput = 0
  end

  electrics.values.frontDefrost = frontDefrostState

  local parkingAssistInput = electrics.values.parkingAssistInput or 0

  if ignitionLevel > 1 then
    if parkingAssistInput == 1 and lastparkingAssistInput == 0 then
      parkingAssistState = 1 - parkingAssistState 
    end
    lastparkingAssistInput = parkingAssistInput
  else
    parkingAssistState = 0
    lastparkingAssistInput = 0
  end

  electrics.values.parkingAssist = parkingAssistState

  local acInput = electrics.values.ac_input or 0

  if ignitionLevel > 1 then
    if acInput == 1 and lastacInput == 0 then
      acState = 1 - acState 
    end
    lastacInput = acInput
  else
    acState = 0
    lastacInput = 0
  end

  electrics.values.ac = acState

  local cdInput = electrics.values.cd_input or 0

  if ignitionLevel >= 1 then
 
    if cdInput == 1 and lastCdInput == 0 then
      cdEjectState = 1 - cdEjectState 
      
   
      if cdEjectState == 1 then
        playCDSound(cdEjectSoundPath)
      else
        playCDSound(cdRetractSoundPath)
      end
    end
    lastCdInput = cdInput
    
    local targetPosition = cdEjectState
    
    if cdPosition < targetPosition then
      cdPosition = math.min(cdPosition + cdEjectSpeed * dt, targetPosition)
    elseif cdPosition > targetPosition then
      cdPosition = math.max(cdPosition - cdEjectSpeed * dt, targetPosition)
    end
    
  else
  
    if cdEjectState == 1 then
      cdEjectState = 0
      playCDSound(cdRetractSoundPath)
    end
    lastCdInput = 0
    if cdPosition > 0 then
      cdPosition = math.max(cdPosition - cdEjectSpeed * dt, 0)
    end
  end

  electrics.values.cd = cdPosition

  local visorRInput = electrics.values.visorR_input or 0
  local visorLInput = electrics.values.visorL_input or 0

  if ignitionLevel >= 1 then
    if visorRInput == 1 and lastVisorRInput == 0 then
      visorRState = 1 - visorRState 
    end
    lastVisorRInput = visorRInput
    
    if visorLInput == 1 and lastVisorLInput == 0 then
      visorLState = 1 - visorLState 
    end
    lastVisorLInput = visorLInput
    
    local targetPositionR = visorRState
    if visorRPosition < targetPositionR then
      visorRPosition = math.min(visorRPosition + visorSpeed * dt, targetPositionR)
    elseif visorRPosition > targetPositionR then
      visorRPosition = math.max(visorRPosition - visorSpeed * dt, targetPositionR)
    end
    
    local targetPositionL = visorLState
    if visorLPosition < targetPositionL then
      visorLPosition = math.min(visorLPosition + visorSpeed * dt, targetPositionL)
    elseif visorLPosition > targetPositionL then
      visorLPosition = math.max(visorLPosition - visorSpeed * dt, targetPositionL)
    end
    
  else
    visorRState = 0
    visorLState = 0
    lastVisorRInput = 0
    lastVisorLInput = 0
    if visorRPosition > 0 then
      visorRPosition = math.max(visorRPosition - visorSpeed * dt, 0)
    end
    if visorLPosition > 0 then
      visorLPosition = math.max(visorLPosition - visorSpeed * dt, 0)
    end
  end

  electrics.values.visorR_state = visorRPosition
  electrics.values.visorL_state = visorLPosition

  local safetyInput = electrics.values.safety_system_input or 0
  local holdThreshold = 1.0

  safetySystemState = safetySystemState or 1
  lastSafetyInput = lastSafetyInput or 0
  safetyInputHoldTimer = safetyInputHoldTimer or 0
  safetyWasForcedOff = safetyWasForcedOff or false

  if ignitionLevel >= 2 then
    if safetyWasForcedOff then
      safetySystemState = 1
      safetyWasForcedOff = false
    end

    if safetyInput == 1 then
      if lastSafetyInput == 0 then
        safetyInputHoldTimer = 0
      else
        safetyInputHoldTimer = safetyInputHoldTimer + dt
        if safetyInputHoldTimer >= holdThreshold and safetySystemState ~= 0 then
          safetySystemState = 0
        end
      end
    elseif safetyInput == 0 and lastSafetyInput == 1 then
      if safetyInputHoldTimer < holdThreshold then
        if safetySystemState == 0 then
          safetySystemState = 1
        elseif safetySystemState == 1 then
          safetySystemState = 2
        elseif safetySystemState == 2 then
          safetySystemState = 1
        end
      end
      safetyInputHoldTimer = 0
    end

    lastSafetyInput = safetyInput
  else
    if safetySystemState ~= 0 then
      safetySystemState = 0
      safetyWasForcedOff = true
    end
    lastSafetyInput = 0
    safetyInputHoldTimer = 0
  end

  electrics.values.safety_system = safetySystemState

  local daytimeLightsSetting = electrics.values.daytimeLights or 0
  local engineRunning = electrics.values.running or 0

  if daytimeLightsSetting == 1 and engineRunning == true then
    electrics.values.drlLights = 1
  else
    electrics.values.drlLights = 0
  end
end

local function onReset()
  safetySystemState = 1
  lastSafetyInput = 0
  safetyInputHoldTimer = 0
  safetyWasForcedOff = false
  
  cdEjectState = 0
  lastCdInput = 0
  cdPosition = 0
  
  visorRState = 0
  visorLState = 0
  lastVisorRInput = 0
  lastVisorLInput = 0
  visorRPosition = 0
  visorLPosition = 0
end

M.onReset = onReset
M.updateGFX = updateGFX

return M