local M = {}


local function onInit()
	timer2 = 0
	timer = 0
	timer3 = 0
	cycleStarting = 0
	cycleComplete = 0
    electrics.values["sdd_g80_tlight_running_1"] = 1
	electrics.values["sdd_g80_tlight_running_2"] = 1
    electrics.values["sdd_g80_tlight_running_3"] = 1
    electrics.values["sdd_g80_tlight_running_4"] = 1
    electrics.values["sdd_g80_tlight_running_5"] = 1
    electrics.values["sdd_g80_tlight_running_6"] = 1
    electrics.values["sdd_g80_tlight_running_7"] = 1
    electrics.values["sdd_g80_tlight_running_8"] = 1
    electrics.values["sdd_g80_tlight_running_9"] = 1
    electrics.values["sdd_g80_tlight_running_10"] = 1
    electrics.values["sdd_g80_tlight_running_11"] = 1
    electrics.values["sdd_g80_tlight_running_12"] = 1
    electrics.values["sdd_g80_tlight_running_13"] = 1
    electrics.values["sdd_g80_tlight_running_14"] = 1
	  electrics.values["sdd_g80_tlight_running_15"] = 1
end

local function onReset()
	timer2 = 0
	timer = 0
	timer3 = 0
	cycleStarting = 0
	cycleComplete = 0
    electrics.values["sdd_g80_tlight_running_1"] = 1
	electrics.values["sdd_g80_tlight_running_2"] = 1
    electrics.values["sdd_g80_tlight_running_3"] = 1
    electrics.values["sdd_g80_tlight_running_4"] = 1
    electrics.values["sdd_g80_tlight_running_5"] = 1
    electrics.values["sdd_g80_tlight_running_6"] = 1
    electrics.values["sdd_g80_tlight_running_7"] = 1
    electrics.values["sdd_g80_tlight_running_8"] = 1
    electrics.values["sdd_g80_tlight_running_9"] = 1
    electrics.values["sdd_g80_tlight_running_10"] = 1
    electrics.values["sdd_g80_tlight_running_11"] = 1
    electrics.values["sdd_g80_tlight_running_12"] = 1
    electrics.values["sdd_g80_tlight_running_13"] = 1
    electrics.values["sdd_g80_tlight_running_14"] = 1
	   electrics.values["sdd_g80_tlight_running_15"] = 1
	   electrics.values["sdd_g80_tlight_running_16"] = 1
end

local function updateGFX(dt) 

  if electrics.values["lowhighbeam"] == 0 and cycleStarting == 0 then
	cycleStarting = 1
	cycleComplete = 0
  elseif electrics.values["lowhighbeam"] ==  1 and cycleStarting == 1 then
	timer3 = timer3 + dt
	
	if timer3 >= 0.0714 then
	electrics.values["sdd_g80_tlight_running_1"] = 1
	end
	if timer3 >= 0.143 then
	electrics.values["sdd_g80_tlight_running_2"] = 1
	end
	if timer3 >= 0.214 then
	electrics.values["sdd_g80_tlight_running_3"] = 1
	end
	if timer3 >= 0.286 then
	electrics.values["sdd_g80_tlight_running_4"] = 1
	end
	if timer3 >= 0.357 then
	electrics.values["sdd_g80_tlight_running_5"] = 1
	end
	if timer3 >= 0.428 then
	electrics.values["sdd_g80_tlight_running_6"] = 1
	end
	if timer3 >= 0.5 then
	electrics.values["sdd_g80_tlight_running_7"] = 1
	end
	if timer3 >= 0.571 then
	electrics.values["sdd_g80_tlight_running_8"] = 1
	end
	if timer3 >= 0.643 then
	electrics.values["sdd_g80_tlight_running_9"] = 1
	end
	if timer3 >= 0.714 then
	electrics.values["sdd_g80_tlight_running_10"] = 1
	end
	if timer3 >= 0.785 then
	electrics.values["sdd_g80_tlight_running_11"] = 1
	end
	if timer3 >= 0.857 then
	electrics.values["sdd_g80_tlight_running_12"] = 1
	end
	if timer3 >= 0.928 then
	electrics.values["sdd_g80_tlight_running_13"] = 1
	end
		if timer3 >= 0.928 then
	electrics.values["sdd_g80_tlight_running_14"] = 1
	end
	if timer3 >= 0.999 then
	electrics.values["sdd_g80_tlight_running_15"] = 1
	end
		if timer3 >= 1.0714 then
	electrics.values["sdd_g80_tlight_running_15"] = 0
	end
	if timer3 >= 1.143 then
	electrics.values["sdd_g80_tlight_running_14"] = 0
	end
	if timer3 >= 1.214 then
	electrics.values["sdd_g80_tlight_running_13"] = 0
	end
		if timer3 >= 1.286 then
	electrics.values["sdd_g80_tlight_running_12"] = 0
	end
			if timer3 >= 1.357 then
	electrics.values["sdd_g80_tlight_running_11"] = 0
	end
			if timer3 >= 1.428 then
	electrics.values["sdd_g80_tlight_running_10"] = 0
	end
			if timer3 >= 1.5 then
	electrics.values["sdd_g80_tlight_running_9"] = 0
	end
			if timer3 >= 1.571 then
	electrics.values["sdd_g80_tlight_running_8"] = 0
	end
			if timer3 >= 1.643 then
	electrics.values["sdd_g80_tlight_running_7"] = 0
	end
			if timer3 >= 1.714 then
	electrics.values["sdd_g80_tlight_running_6"] = 0
	end
				if timer3 >= 1.785 then
	electrics.values["sdd_g80_tlight_running_5"] = 0
	end
				if timer3 >= 1.857 then
	electrics.values["sdd_g80_tlight_running_4"] = 0
	end
				if timer3 >= 1.928 then
	electrics.values["sdd_g80_tlight_running_3"] = 0
	end
				if timer3 >= 1.999 then
	electrics.values["sdd_g80_tlight_running_2"] = 0
	end
				if timer3 >= 2.1 then
	electrics.values["sdd_g80_tlight_running_1"] = 0
	end
	if timer3 >= 2.3 then
	electrics.values["sdd_g80_tlight_running_1"] = 1
	end
	if timer3 >= 2.5 then
	electrics.values["sdd_g80_tlight_running_2"] = 1
	end
	if timer3 >= 2.7 then
	electrics.values["sdd_g80_tlight_running_3"] = 1
	end
	if timer3 >= 2.9 then
	electrics.values["sdd_g80_tlight_running_4"] = 1
	end
	if timer3 >= 3.1 then
	electrics.values["sdd_g80_tlight_running_5"] = 1
	end
	if timer3 >= 3.3 then
	electrics.values["sdd_g80_tlight_running_6"] = 1
	end
	if timer3 >= 3.5 then
	electrics.values["sdd_g80_tlight_running_7"] = 1
	end
		if timer3 >= 3.7 then
	electrics.values["sdd_g80_tlight_running_8"] = 1
	end
		if timer3 >= 3.9 then
	electrics.values["sdd_g80_tlight_running_9"] = 1
	end
		if timer3 >= 4.1 then
	electrics.values["sdd_g80_tlight_running_10"] = 1
	end
	if timer3 >= 4.3 then
	electrics.values["sdd_g80_tlight_running_11"] = 1
	end
		if timer3 >= 4.5 then
	electrics.values["sdd_g80_tlight_running_12"] = 1
	end
			if timer3 >= 4.7 then
	electrics.values["sdd_g80_tlight_running_13"] = 1
	end
				if timer3 >= 4.9 then
	electrics.values["sdd_g80_tlight_running_14"] = 1
	end
		if timer3 >= 5.1 then
	electrics.values["sdd_g80_tlight_running_15"] = 1
	end
		if timer3 >= 5.3 then
	electrics.values["sdd_g80_tlight_running_16"] = 1
	cycleStarting = 0
	timer3 = 0
	cycleComplete = 1
	end
  end

  if electrics.values["lowhighbeam"] == 1 and cycleComplete == 1 then
    electrics.values["sdd_g80_tlight_running_1"] = 1
	electrics.values["sdd_g80_tlight_running_2"] = 1
    electrics.values["sdd_g80_tlight_running_3"] = 1
    electrics.values["sdd_g80_tlight_running_4"] = 1
    electrics.values["sdd_g80_tlight_running_5"] = 1
    electrics.values["sdd_g80_tlight_running_6"] = 1
    electrics.values["sdd_g80_tlight_running_7"] = 1
    electrics.values["sdd_g80_tlight_running_8"] = 1
    electrics.values["sdd_g80_tlight_running_9"] = 1
    electrics.values["sdd_g80_tlight_running_10"] = 1
    electrics.values["sdd_g80_tlight_running_11"] = 1
    electrics.values["sdd_g80_tlight_running_12"] = 1
    electrics.values["sdd_g80_tlight_running_13"] = 1
    electrics.values["sdd_g80_tlight_running_14"] = 1
	   electrics.values["sdd_g80_tlight_running_15"] = 1
	     electrics.values["sdd_g80_tlight_running_16"] = 1
  elseif electrics.values["lowhighbeam"] == 0 and cycleComplete == 0 then
    electrics.values["sdd_g80_tlight_running_1"] = 0
	electrics.values["sdd_g80_tlight_running_2"] = 0
    electrics.values["sdd_g80_tlight_running_3"] = 0
    electrics.values["sdd_g80_tlight_running_4"] = 0
    electrics.values["sdd_g80_tlight_running_5"] = 0
    electrics.values["sdd_g80_tlight_running_6"] = 0
    electrics.values["sdd_g80_tlight_running_7"] = 0
    electrics.values["sdd_g80_tlight_running_8"] = 0
    electrics.values["sdd_g80_tlight_running_9"] = 0
    electrics.values["sdd_g80_tlight_running_10"] = 0
    electrics.values["sdd_g80_tlight_running_11"] = 0
    electrics.values["sdd_g80_tlight_running_12"] = 0
    electrics.values["sdd_g80_tlight_running_13"] = 0
    electrics.values["sdd_g80_tlight_running_14"] = 0
	   electrics.values["sdd_g80_tlight_running_15"] = 0
	     electrics.values["sdd_g80_tlight_running_16"] = 0
  end

  -- The taillight segment materials (LCI laser / CSL / GT3 / convertible) read the
  -- g82-named electrics, but this animation was authored against g80. Mirror the
  -- staged values onto the g82 names so the staged DRLs actually light up.
  for i = 1, 16 do
    electrics.values["sdd_g82_tlight_running_" .. i] = electrics.values["sdd_g80_tlight_running_" .. i] or 0
  end
end

M.onInit = onInit
M.onReset = onReset
M.updateGFX = updateGFX

return M