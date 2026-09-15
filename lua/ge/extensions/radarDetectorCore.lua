-- File: lua/ge/extensions/radarDetectorCore.lua
local M = {}

local updateInterval = 0.5  -- Update every 0.5 seconds
local timer = 0

local function updateSightValue()
    local policeInfoExt = extensions.ui_policeInfo
    local sightValue = 0
    if policeInfoExt and policeInfoExt.enabled then
        local pursuit = gameplay_police and gameplay_police.getPursuitData()
        sightValue = pursuit and pursuit.sightValue or 0
    end
    -- Get the player vehicle and send the value
    local veh = be:getPlayerVehicle(0)
    if veh then
        veh:queueLuaCommand(string.format('electrics.values.radarSightValue = %f', sightValue))
    end
end

local function onGuiUpdate(dt)
    if not be:getEnabled() then return end
    timer = timer + dt
    if timer >= updateInterval then
        timer = 0
        updateSightValue()
    end
end

local function onExtensionLoaded()
    print("CORE: radarDetectorCore initialized")
end

M.onGuiUpdate = onGuiUpdate
M.onExtensionLoaded = onExtensionLoaded

return M