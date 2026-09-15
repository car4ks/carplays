local M = {}

local window_sfx_table = {}
local current_window_sfx_L = nil
local current_window_sfx_R = nil

local SOUNDS = {
  up = "/vehicles/sdd_g80/sounds/Window Up.ogg",
  down = "/vehicles/sdd_g80/sounds/Window Down.ogg"
}

local function loadWindowSound(sound_path)
  if sound_path and not window_sfx_table[sound_path] then
      window_sfx_table[sound_path] = obj:createSFXSource(sound_path, "AudioDefault3D", "", 5)
      return true
  end
  return window_sfx_table[sound_path] ~= nil
end

local function playWindowSound(sound_path, isRight)
   if sound_path and window_sfx_table[sound_path] then
       local current_sfx = isRight and current_window_sfx_R or current_window_sfx_L
       local windowVal = isRight and (electrics.values.sdd_g80_glass_R or 0) or (electrics.values.sdd_g80_glass_L or 0)
       
       -- Play sound if window is moving (between 0 and 1)
       if windowVal > 0 and windowVal < 1 then
           -- Stop any existing sound to allow restarting
           if current_sfx then
               obj:stopSFX(current_sfx)
               current_sfx = nil
               if isRight then current_window_sfx_R = nil else current_window_sfx_L = nil end
           end
           
           local sfx_to_play = window_sfx_table[sound_path]
           obj:setVolumePitch(sfx_to_play, 3, 1)
           obj:playSFX(sfx_to_play)
           print("Playing sound: " .. sound_path .. " for " .. (isRight and "right" or "left") .. " window")
           
           if isRight then
               current_window_sfx_R = sfx_to_play
           else
               current_window_sfx_L = sfx_to_play 
           end
       end
   end
end

local function stopSound(isRight)
  if isRight then
      if current_window_sfx_R then
          obj:stopSFX(current_window_sfx_R)
          obj:deleteSFXSource(current_window_sfx_R)
          current_window_sfx_R = nil
          print("Stopped right window sound")
      end
  else
      if current_window_sfx_L then
          obj:stopSFX(current_window_sfx_L)
          obj:deleteSFXSource(current_window_sfx_L)
          current_window_sfx_L = nil
          print("Stopped left window sound")
      end
  end
end

local function updateCabinFilter()
    if not electrics or not electrics.values then
        obj:queueGameEngineLua("core_sounds.cabinFilterStrength = 1.0")
        return
    end
    local left = electrics.values.sdd_g80_glass_L or 0
    local right = electrics.values.sdd_g80_glass_R or 0
    local windowOpenness = math.max(left, right)
    local cabinFilterStrength = 1.0 - windowOpenness
    obj:queueGameEngineLua(string.format("core_sounds.cabinFilterStrength = %f", cabinFilterStrength))
end

local function updateGFX(dt)
   if not electrics or not electrics.values then return end
   if electrics.values.ignitionLevel == 0 then 
       electrics.values.sdd_g80_glass_L = 0
       electrics.values.sdd_g80_glass_R = 0
       updateCabinFilter()
       return 
   end

   if not electrics.values.sdd_g80_glass_L then
       electrics.values.sdd_g80_glass_L = 0
       electrics.values.sdd_g80_glass_L_down = 0
       electrics.values.sdd_g80_glass_L_up = 0
       electrics.values.sdd_g80_glass_R = 0
       electrics.values.sdd_g80_glass_R_down = 0
       electrics.values.sdd_g80_glass_R_up = 0
   end

   local prevL = electrics.values.sdd_g80_glass_L
   local prevR = electrics.values.sdd_g80_glass_R
   local speed = 0.00575 * (dt/0.016667)

   if electrics.values.window_lock_R ~= 1 then
       if electrics.values.sdd_g80_glass_L_down == 1 then
           -- Trigger sound when movement starts or continues
           if prevL < 1 then
               playWindowSound(SOUNDS.down, false)
           end
           electrics.values.sdd_g80_glass_L = math.min(1, electrics.values.sdd_g80_glass_L + speed)
           if electrics.values.sdd_g80_glass_L >= 1 then
               stopSound(false)
           end
       elseif electrics.values.sdd_g80_glass_L_up == 1 then
           if prevL > 0 then
               playWindowSound(SOUNDS.up, false)
           end
           electrics.values.sdd_g80_glass_L = math.max(0, electrics.values.sdd_g80_glass_L - speed)
           if electrics.values.sdd_g80_glass_L <= 0 then
               stopSound(false)
           end
       else
           stopSound(false)
       end
   end

   if electrics.values.window_lock ~= 1 then
       if electrics.values.sdd_g80_glass_R_down == 1 then
           if prevR < 1 then
               playWindowSound(SOUNDS.down, true)
           end
           electrics.values.sdd_g80_glass_R = math.min(1, electrics.values.sdd_g80_glass_R + speed)
           if electrics.values.sdd_g80_glass_R >= 1 then
               stopSound(true)
           end
       elseif electrics.values.sdd_g80_glass_R_up == 1 then
           if prevR > 0 then
               playWindowSound(SOUNDS.up, true) 
           end
           electrics.values.sdd_g80_glass_R = math.max(0, electrics.values.sdd_g80_glass_R - speed)
           if electrics.values.sdd_g80_glass_R <= 0 then
               stopSound(true)
           end
       else
           stopSound(true)
       end
   end

   updateCabinFilter()
end

local function init()
  loadWindowSound(SOUNDS.up)
  loadWindowSound(SOUNDS.down)
end

local function reset()
  stopSound(false)
  stopSound(true)
  
  for _, sfx in pairs(window_sfx_table) do
      obj:deleteSFXSource(sfx)
  end
  window_sfx_table = {}
  
  init()
  if electrics and electrics.values then
      electrics.values.sdd_g80_glass_L = 0
      electrics.values.sdd_g80_glass_R = 0
  end
  updateCabinFilter()
end

local function onVehicleActiveChanged(active)
  if active then
      electrics.registerHandler("updateGFX", updateGFX)
      init()
      updateCabinFilter()
  else
      stopSound(false)
      stopSound(true)
      obj:queueGameEngineLua("core_sounds.cabinFilterStrength = 1.0")
  end
end

local function destroy()
  stopSound(false)
  stopSound(true)
  
  for _, sfx in pairs(window_sfx_table) do
      obj:deleteSFXSource(sfx)
  end
  window_sfx_table = {}
  obj:queueGameEngineLua("core_sounds.cabinFilterStrength = 1.0")
end

M.onVehicleActiveChanged = onVehicleActiveChanged
M.onReset = reset
M.updateGFX = updateGFX
M.init = init
M.destroy = destroy

return M