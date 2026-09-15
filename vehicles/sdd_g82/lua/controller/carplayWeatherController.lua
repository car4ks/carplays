local M = {}
M.type = "auxiliary"

local updateTimer = 0
local invFPS = 1/10

local lastWeatherSignals = {
    clear = 0,
    drizzle = 0,
    rain = 0,
    heavyRain = 0,
    thunderstorm = 0
}

local function processWeatherControls()
    local currentSignals = {
        clear = electrics.values.weatherClear or 0,
        drizzle = electrics.values.weatherDrizzle or 0,
        rain = electrics.values.weatherRain or 0,
        heavyRain = electrics.values.weatherHeavyRain or 0,
        thunderstorm = electrics.values.weatherThunderstorm or 0
    }
    
    for weatherType, signal in pairs(currentSignals) do
        if signal == 1 and lastWeatherSignals[weatherType] == 0 then
            obj:queueGameEngineLua(string.format("extensions.carplayWeather.setWeather('%s')", weatherType))
            
            -- Set the weatherType for the wiper system
            electrics.values.weatherType = weatherType
            print("Weather controller: Set weatherType to " .. weatherType .. " for wiper system")
            
            if weatherType == "clear" then
                electrics.values.weatherClear = 0
            elseif weatherType == "drizzle" then
                electrics.values.weatherDrizzle = 0
            elseif weatherType == "rain" then
                electrics.values.weatherRain = 0
            elseif weatherType == "heavyRain" then
                electrics.values.weatherHeavyRain = 0
            elseif weatherType == "thunderstorm" then
                electrics.values.weatherThunderstorm = 0
            end
        end
    end
    
    lastWeatherSignals = currentSignals
end

local function init(jbeamData)
    electrics.values.weatherClear = 0
    electrics.values.weatherDrizzle = 0
    electrics.values.weatherRain = 0
    electrics.values.weatherHeavyRain = 0
    electrics.values.weatherThunderstorm = 0
    
    electrics.values.weatherType = "clear"  -- Initialize to clear
    electrics.values.weatherRainAmount = 0
    electrics.values.weatherRoadWet = 0
    electrics.values.weatherHasThunder = 0
    
    print("Weather controller initialized - weatherType set to: clear")
end

local function updateGFX(dt)
    updateTimer = updateTimer + dt
    
    if updateTimer > invFPS then
        updateTimer = 0
        processWeatherControls()
    end
end

local function onReset()
    electrics.values.weatherClear = 0
    electrics.values.weatherDrizzle = 0
    electrics.values.weatherRain = 0
    electrics.values.weatherHeavyRain = 0
    electrics.values.weatherThunderstorm = 0
    electrics.values.weatherType = "clear"  -- Reset to clear
end

M.init = init
M.updateGFX = updateGFX
M.onReset = onReset

return M