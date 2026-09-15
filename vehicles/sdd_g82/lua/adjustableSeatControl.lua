local M = {}

local seat_sfx_table = {}
local current_seat_sfx = nil

local prev_seat_L_fold_moving = false
local prev_seat_L_height_moving = false
local prev_seat_L_slide_moving = false
local prev_seat_R_fold_moving = false
local prev_seat_R_height_moving = false
local prev_seat_R_slide_moving = false

local prev_steeringcolumn_moving = false

local prev_seatfoldRR_trigger = false
local prev_seatfoldRL_trigger = false

local settingsFilePath = "settings/sdd_f87_settings.json"
local settingsCache = {}

local DEFAULT_SETTINGS = {
  L_fold = 0,
  L_height = 0,
  L_slide = 0.4977500475,
  R_fold = 0,
  R_height = 0,
  R_slide = 0.6333773366,
  steeringcolumn = 0.30706185558709,
  seatfoldRR = 0,
  seatfoldRL = 0
}

local SOUNDS = {
  slide_forward = "/vehicles/sdd_f87/sounds/seat_slide_forward.mp3",
  slide_reverse = "/vehicles/sdd_f87/sounds/seat_slide_reverse.mp3",
  height_up = "/vehicles/sdd_f87/sounds/seat_height_up.mp3",
  height_down = "/vehicles/sdd_f87/sounds/seat_height_down.mp3",
  fold_more = "/vehicles/sdd_f87/sounds/seat_fold_more.mp3",
  fold_less = "/vehicles/sdd_f87/sounds/seat_fold_less.mp3",
  steering_adjust = "/vehicles/sdd_f87/sounds/seat_height_up.mp3"
}

local function loadSettings()
  local success, data = pcall(function()
    return jsonReadFile(settingsFilePath)
  end)
  
  if success and data and data.seatSettings then
    settingsCache = data
    return settingsCache.seatSettings
  else
    settingsCache = {
      seatSettings = {},
      screenSettings = {}
    }
    return nil
  end
end

local function saveSettings()
  local currentPositions = getSeatPositions()
  
  if not settingsCache.seatSettings then
    settingsCache.seatSettings = {}
  end
  
  for key, value in pairs(currentPositions) do
    settingsCache.seatSettings[key] = value
  end
  
  settingsCache.seatSettings.lastSaved = os.time()
  settingsCache.seatSettings.savedAt = os.date("%Y-%m-%d %H:%M:%S")
  
  local success, err = pcall(function()
    jsonWriteFile(settingsFilePath, settingsCache, true)
  end)
  
  return success
end

local function applySettings(settings)
  if not settings then
    settings = DEFAULT_SETTINGS
  end
  
  if electrics and electrics.values then
    electrics.values.seat_L_fold = settings.L_fold or DEFAULT_SETTINGS.L_fold
    electrics.values.seat_L_height = settings.L_height or DEFAULT_SETTINGS.L_height
    electrics.values.seat_L_slide = settings.L_slide or DEFAULT_SETTINGS.L_slide
    electrics.values.seat_R_fold = settings.R_fold or DEFAULT_SETTINGS.R_fold
    electrics.values.seat_R_height = settings.R_height or DEFAULT_SETTINGS.R_height
    electrics.values.seat_R_slide = settings.R_slide or DEFAULT_SETTINGS.R_slide
    electrics.values.steeringcolumn = settings.steeringcolumn or DEFAULT_SETTINGS.steeringcolumn
    electrics.values.seatfoldRR = settings.seatfoldRR or DEFAULT_SETTINGS.seatfoldRR
    electrics.values.seatfoldRL = settings.seatfoldRL or DEFAULT_SETTINGS.seatfoldRL
  end
end

local function getSettingsCache()
  return settingsCache
end

local function updateSettingsCache(section, key, value)
  if not settingsCache[section] then
    settingsCache[section] = {}
  end
  settingsCache[section][key] = value
end

local function loadSeatSound(sound_path)
  if sound_path and not seat_sfx_table[sound_path] then
      seat_sfx_table[sound_path] = obj:createSFXSource(sound_path, "AudioDefault3D", "", 5)
      return true
  end
  return seat_sfx_table[sound_path] ~= nil
end

local function sanitizeObjectName(path)
  return path:gsub("/", "_")
end

local function playSeatSound(sound_path)
   if sound_path and seat_sfx_table[sound_path] then
       if current_seat_sfx then
           obj:stopSFX(current_seat_sfx)
           obj:deleteSFXSource(current_seat_sfx)
           current_seat_sfx = nil
       end
       
       local safe_name = sanitizeObjectName(sound_path) .. "_seat"
       local sfx_to_play = obj:createSFXSource(sound_path, "AudioDefault3D", safe_name, 5)
       obj:setVolumePitch(sfx_to_play, 0.4, 1)
       obj:playSFX(sfx_to_play)
       
       current_seat_sfx = sfx_to_play
   end
end

local function stopSeatSound()
  if current_seat_sfx then
      obj:stopSFX(current_seat_sfx)
      obj:deleteSFXSource(current_seat_sfx)
      current_seat_sfx = nil
  end
end

local function updateGFX(dt)
   if not electrics or not electrics.values then return end
   
   if electrics.values.ignitionLevel == 0 then 
       return 
   end

   if not electrics.values.seat_L_fold then
       local savedSettings = loadSettings()
       applySettings(savedSettings)
       
       electrics.values.seat_L_fold_more = 0
       electrics.values.seat_L_fold_less = 0
       electrics.values.seat_L_height_raise = 0
       electrics.values.seat_L_height_lower = 0
       electrics.values.seat_L_slide_forward = 0
       electrics.values.seat_L_slide_reverse = 0
       
       electrics.values.seat_R_fold_more = 0
       electrics.values.seat_R_fold_less = 0
       electrics.values.seat_R_height_raise = 0
       electrics.values.seat_R_height_lower = 0
       electrics.values.seat_R_slide_forward = 0
       electrics.values.seat_R_slide_reverse = 0
       
       electrics.values.steeringcolumn_up = 0
       electrics.values.steeringcolumn_down = 0
       
       electrics.values.seatfoldRR_trigger = 0
       electrics.values.seatfoldRL_trigger = 0
   end

   local speed = 0.003 * (dt/0.016667)
   local steering_speed = 0.002 * (dt/0.016667)

   local isSteeringUp = electrics.values.steeringcolumn_up == 1
   local isSteeringDown = electrics.values.steeringcolumn_down == 1
   local isSteeringMoving = isSteeringUp or isSteeringDown
   local steeringChanged = false
   
   if isSteeringUp then
       if not prev_steeringcolumn_moving then
           playSeatSound(SOUNDS.steering_adjust)
       end
       local newPos = math.min(0.4, electrics.values.steeringcolumn + steering_speed)
       if newPos ~= electrics.values.steeringcolumn then
         electrics.values.steeringcolumn = newPos
         steeringChanged = true
       end
   elseif isSteeringDown then
       if not prev_steeringcolumn_moving then
           playSeatSound(SOUNDS.steering_adjust)
       end
       local newPos = math.max(0.0, electrics.values.steeringcolumn - steering_speed)
       if newPos ~= electrics.values.steeringcolumn then
         electrics.values.steeringcolumn = newPos
         steeringChanged = true
       end
   else
       if prev_steeringcolumn_moving then
           stopSeatSound()
           steeringChanged = true
       end
   end

   local isFoldingMore = electrics.values.seat_L_fold_more == 1
   local isFoldingLess = electrics.values.seat_L_fold_less == 1
   local isFoldMoving = isFoldingMore or isFoldingLess
   local foldChanged = false
   
   if isFoldingMore then
       if not prev_seat_L_fold_moving then
           playSeatSound(SOUNDS.fold_more)
       end
       local newPos = math.min(0.7, electrics.values.seat_L_fold + speed)
       if newPos ~= electrics.values.seat_L_fold then
         electrics.values.seat_L_fold = newPos
         foldChanged = true
       end
   elseif isFoldingLess then
       if not prev_seat_L_fold_moving then
           playSeatSound(SOUNDS.fold_less)
       end
       local newPos = math.max(0.0, electrics.values.seat_L_fold - speed)
       if newPos ~= electrics.values.seat_L_fold then
         electrics.values.seat_L_fold = newPos
         foldChanged = true
       end
   else
       if prev_seat_L_fold_moving then
           stopSeatSound()
           foldChanged = true
       end
   end

   local isRaising = electrics.values.seat_L_height_raise == 1
   local isLowering = electrics.values.seat_L_height_lower == 1
   local isHeightMoving = isRaising or isLowering
   local heightChanged = false
   
   if isRaising then
       if not prev_seat_L_height_moving then
           playSeatSound(SOUNDS.height_up)
       end
       local newPos = math.min(1, electrics.values.seat_L_height + speed)
       if newPos ~= electrics.values.seat_L_height then
         electrics.values.seat_L_height = newPos
         heightChanged = true
       end
   elseif isLowering then
       if not prev_seat_L_height_moving then
           playSeatSound(SOUNDS.height_down)
       end
       local newPos = math.max(0, electrics.values.seat_L_height - speed)
       if newPos ~= electrics.values.seat_L_height then
         electrics.values.seat_L_height = newPos
         heightChanged = true
       end
   else
       if prev_seat_L_height_moving then
           stopSeatSound()
           heightChanged = true
       end
   end

   local isSlideForward = electrics.values.seat_L_slide_forward == 1
   local isSlideReverse = electrics.values.seat_L_slide_reverse == 1
   local isSlideMoving = isSlideForward or isSlideReverse
   local slideChanged = false
   
   if isSlideForward then
       if not prev_seat_L_slide_moving then
           playSeatSound(SOUNDS.slide_forward)
       end
       local newPos = math.min(1, electrics.values.seat_L_slide + speed)
       if newPos ~= electrics.values.seat_L_slide then
         electrics.values.seat_L_slide = newPos
         slideChanged = true
       end
   elseif isSlideReverse then
       if not prev_seat_L_slide_moving then
           playSeatSound(SOUNDS.slide_reverse)
       end
       local newPos = math.max(0, electrics.values.seat_L_slide - speed)
       if newPos ~= electrics.values.seat_L_slide then
         electrics.values.seat_L_slide = newPos
         slideChanged = true
       end
   else
       if prev_seat_L_slide_moving then
           stopSeatSound()
           slideChanged = true
       end
   end

   local isRFoldingMore = electrics.values.seat_R_fold_more == 1
   local isRFoldingLess = electrics.values.seat_R_fold_less == 1
   local isRFoldMoving = isRFoldingMore or isRFoldingLess
   local rFoldChanged = false
   
   if isRFoldingMore then
       if not prev_seat_R_fold_moving then
           playSeatSound(SOUNDS.fold_more)
       end
       local newPos = math.min(0.7, electrics.values.seat_R_fold + speed)
       if newPos ~= electrics.values.seat_R_fold then
         electrics.values.seat_R_fold = newPos
         rFoldChanged = true
       end
   elseif isRFoldingLess then
       if not prev_seat_R_fold_moving then
           playSeatSound(SOUNDS.fold_less)
       end
       local newPos = math.max(0.0, electrics.values.seat_R_fold - speed)
       if newPos ~= electrics.values.seat_R_fold then
         electrics.values.seat_R_fold = newPos
         rFoldChanged = true
       end
   else
       if prev_seat_R_fold_moving then
           stopSeatSound()
           rFoldChanged = true
       end
   end

   local isRRaising = electrics.values.seat_R_height_raise == 1
   local isRLowering = electrics.values.seat_R_height_lower == 1
   local isRHeightMoving = isRRaising or isRLowering
   local rHeightChanged = false
   
   if isRRaising then
       if not prev_seat_R_height_moving then
           playSeatSound(SOUNDS.height_up)
       end
       local newPos = math.min(1, electrics.values.seat_R_height + speed)
       if newPos ~= electrics.values.seat_R_height then
         electrics.values.seat_R_height = newPos
         rHeightChanged = true
       end
   elseif isRLowering then
       if not prev_seat_R_height_moving then
           playSeatSound(SOUNDS.height_down)
       end
       local newPos = math.max(0, electrics.values.seat_R_height - speed)
       if newPos ~= electrics.values.seat_R_height then
         electrics.values.seat_R_height = newPos
         rHeightChanged = true
       end
   else
       if prev_seat_R_height_moving then
           stopSeatSound()
           rHeightChanged = true
       end
   end

   local isRSlideForward = electrics.values.seat_R_slide_forward == 1
   local isRSlideReverse = electrics.values.seat_R_slide_reverse == 1
   local isRSlideMoving = isRSlideForward or isRSlideReverse
   local rSlideChanged = false
   
   if isRSlideForward then
       if not prev_seat_R_slide_moving then
           playSeatSound(SOUNDS.slide_forward)
       end
       local newPos = math.min(1, electrics.values.seat_R_slide + speed)
       if newPos ~= electrics.values.seat_R_slide then
         electrics.values.seat_R_slide = newPos
         rSlideChanged = true
       end
   elseif isRSlideReverse then
       if not prev_seat_R_slide_moving then
           playSeatSound(SOUNDS.slide_reverse)
       end
       local newPos = math.max(0, electrics.values.seat_R_slide - speed)
       if newPos ~= electrics.values.seat_R_slide then
         electrics.values.seat_R_slide = newPos
         rSlideChanged = true
       end
   else
       if prev_seat_R_slide_moving then
           stopSeatSound()
           rSlideChanged = true
       end
   end

   local rearSeatChanged = false
   
   local isRRTriggerPressed = electrics.values.seatfoldRR_trigger == 1
   local rrTriggerJustPressed = isRRTriggerPressed and not prev_seatfoldRR_trigger
   
   if rrTriggerJustPressed then
       local currentPos = electrics.values.seatfoldRR or DEFAULT_SETTINGS.seatfoldRR
       local targetPos = (currentPos > 0.5) and 0 or 1
       electrics.values.seatfoldRR = targetPos
       rearSeatChanged = true
   end
   
   local isRLTriggerPressed = electrics.values.seatfoldRL_trigger == 1
   local rlTriggerJustPressed = isRLTriggerPressed and not prev_seatfoldRL_trigger
   
   if rlTriggerJustPressed then
       local currentPos = electrics.values.seatfoldRL or DEFAULT_SETTINGS.seatfoldRL
       local targetPos = (currentPos > 0.5) and 0 or 1
       electrics.values.seatfoldRL = targetPos
       rearSeatChanged = true
   end

   if steeringChanged or foldChanged or heightChanged or slideChanged or 
      rFoldChanged or rHeightChanged or rSlideChanged or rearSeatChanged then
     saveSettings()
   end

   prev_seat_L_fold_moving = isFoldMoving
   prev_seat_L_height_moving = isHeightMoving
   prev_seat_L_slide_moving = isSlideMoving
   prev_seat_R_fold_moving = isRFoldMoving
   prev_seat_R_height_moving = isRHeightMoving
   prev_seat_R_slide_moving = isRSlideMoving
   prev_steeringcolumn_moving = isSteeringMoving
   
   prev_seatfoldRR_trigger = isRRTriggerPressed
   prev_seatfoldRL_trigger = isRLTriggerPressed
end

local function init(jbeamData)
    local requiredTexture = "/vehicles/sdd_f87/textures/firehawk_nm.nrml.dds"
    
    if not FS:fileExists(requiredTexture) then
        return
    end
  
  local savedSettings = loadSettings()
  
  loadSeatSound(SOUNDS.slide_forward)
  loadSeatSound(SOUNDS.slide_reverse)
  loadSeatSound(SOUNDS.height_up)
  loadSeatSound(SOUNDS.height_down)
  loadSeatSound(SOUNDS.fold_more)
  loadSeatSound(SOUNDS.fold_less)
  loadSeatSound(SOUNDS.steering_adjust)
  
  prev_seat_L_fold_moving = false
  prev_seat_L_height_moving = false
  prev_seat_L_slide_moving = false
  prev_seat_R_fold_moving = false
  prev_seat_R_height_moving = false
  prev_seat_R_slide_moving = false
  prev_steeringcolumn_moving = false
  prev_seatfoldRR_trigger = false
  prev_seatfoldRL_trigger = false
end

local function reset()
  stopSeatSound()
  
  for _, sfx in pairs(seat_sfx_table or {}) do
      obj:deleteSFXSource(sfx)
  end
  seat_sfx_table = {}
  
  prev_seat_L_fold_moving = false
  prev_seat_L_height_moving = false
  prev_seat_L_slide_moving = false
  prev_seat_R_fold_moving = false
  prev_seat_R_height_moving = false
  prev_seat_R_slide_moving = false
  prev_steeringcolumn_moving = false
  prev_seatfoldRR_trigger = false
  prev_seatfoldRL_trigger = false
  
  init()
  
  local savedSettings = loadSettings()
  applySettings(savedSettings)
  
  if electrics and electrics.values then
      electrics.values.seat_L_fold_more = 0
      electrics.values.seat_L_fold_less = 0
      electrics.values.seat_L_height_raise = 0
      electrics.values.seat_L_height_lower = 0
      electrics.values.seat_L_slide_forward = 0
      electrics.values.seat_L_slide_reverse = 0
      electrics.values.seat_R_fold_more = 0
      electrics.values.seat_R_fold_less = 0
      electrics.values.seat_R_height_raise = 0
      electrics.values.seat_R_height_lower = 0
      electrics.values.seat_R_slide_forward = 0
      electrics.values.seat_R_slide_reverse = 0
      electrics.values.steeringcolumn_up = 0
      electrics.values.steeringcolumn_down = 0
      electrics.values.seatfoldRR_trigger = 0
      electrics.values.seatfoldRL_trigger = 0
  end
end

local function onVehicleActiveChanged(active)
  if active then
      electrics.registerHandler("updateGFX", updateGFX)
      init()
  else
      stopSeatSound()
  end
end

local function destroy()
  stopSeatSound()
  
  for _, sfx in pairs(seat_sfx_table or {}) do
      obj:deleteSFXSource(sfx)
  end
  seat_sfx_table = {}
end

local function setSeatPositions(L_fold, L_height, L_slide, R_fold, R_height, R_slide, steering, rearRR, rearRL)
  if electrics and electrics.values then
      electrics.values.seat_L_fold = math.max(0, math.min(1, L_fold or DEFAULT_SETTINGS.L_fold))
      electrics.values.seat_L_height = math.max(0, math.min(1, L_height or DEFAULT_SETTINGS.L_height))
      electrics.values.seat_L_slide = math.max(0, math.min(1, L_slide or DEFAULT_SETTINGS.L_slide))
      electrics.values.seat_R_fold = math.max(0, math.min(1, R_fold or DEFAULT_SETTINGS.R_fold))
      electrics.values.seat_R_height = math.max(0, math.min(1, R_height or DEFAULT_SETTINGS.R_height))
      electrics.values.seat_R_slide = math.max(0, math.min(1, R_slide or DEFAULT_SETTINGS.R_slide))
      electrics.values.steeringcolumn = math.max(0, math.min(0.4, steering or DEFAULT_SETTINGS.steeringcolumn))
      electrics.values.seatfoldRR = math.max(0, math.min(1, rearRR or DEFAULT_SETTINGS.seatfoldRR))
      electrics.values.seatfoldRL = math.max(0, math.min(1, rearRL or DEFAULT_SETTINGS.seatfoldRL))
      
      saveSettings()
  end
end

function getSeatPositions()
  if electrics and electrics.values then
      return {
          L_fold = electrics.values.seat_L_fold or DEFAULT_SETTINGS.L_fold,
          L_height = electrics.values.seat_L_height or DEFAULT_SETTINGS.L_height,
          L_slide = electrics.values.seat_L_slide or DEFAULT_SETTINGS.L_slide,
          R_fold = electrics.values.seat_R_fold or DEFAULT_SETTINGS.R_fold,
          R_height = electrics.values.seat_R_height or DEFAULT_SETTINGS.R_height,
          R_slide = electrics.values.seat_R_slide or DEFAULT_SETTINGS.R_slide,
          steeringcolumn = electrics.values.steeringcolumn or DEFAULT_SETTINGS.steeringcolumn,
          seatfoldRR = electrics.values.seatfoldRR or DEFAULT_SETTINGS.seatfoldRR,
          seatfoldRL = electrics.values.seatfoldRL or DEFAULT_SETTINGS.seatfoldRL
      }
  end
  return DEFAULT_SETTINGS
end

local function saveCurrentSettings()
  return saveSettings()
end

local function resetSeatsToDefault()
  setSeatPositions(DEFAULT_SETTINGS.L_fold, DEFAULT_SETTINGS.L_height, DEFAULT_SETTINGS.L_slide, 
                   DEFAULT_SETTINGS.R_fold, DEFAULT_SETTINGS.R_height, DEFAULT_SETTINGS.R_slide, 
                   DEFAULT_SETTINGS.steeringcolumn, DEFAULT_SETTINGS.seatfoldRR, DEFAULT_SETTINGS.seatfoldRL)
end

M.onVehicleActiveChanged = onVehicleActiveChanged
M.onReset = reset
M.updateGFX = updateGFX
M.init = init
M.destroy = destroy
M.setSeatPositions = setSeatPositions
M.getSeatPositions = getSeatPositions
M.getSettingsCache = getSettingsCache
M.updateSettingsCache = updateSettingsCache
M.saveCurrentSettings = saveCurrentSettings
M.resetSeatsToDefault = resetSeatsToDefault

return M