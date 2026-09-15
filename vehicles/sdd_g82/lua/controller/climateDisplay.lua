local M = {}
M.type = "auxiliary"

local htmlTexture = require("htmlTexture")
local screenMaterialName = nil
local htmlFilePath = nil
local textureWidth = 800
local textureHeight = 160
local textureFPS = 30
local name = "sdd_g82_climateDisplay"
local updateTimer = 0
local invFPS = 1 / 20
local airflowModeLeft = {1, 2}
local airflowModeRight = {1, 2}
local lastAirflowInputL = 0
local lastAirflowInputR = 0
local airflowCounterLeft = 1
local airflowCounterRight = 1 
local tempLeft = 16.0 
local tempRight = 16.0 
local tempMin = 16.0
local tempMax = 28.0
local tempStep = 0.5
local tempTimerL = 0
local tempTimerR = 0
local tempInterval = 0.2
local lastTempLUp = 0
local lastTempLDown = 0
local lastTempRUp = 0
local lastTempRDown = 0
local seatHeaterLevelL = 0
local seatHeaterLevelR = 0
local lastSeatHeaterInputL = 0
local lastSeatHeaterInputR = 0

local function init(jbeamData)
    print("Climate Display Controller initializing...")

    if jbeamData then
        screenMaterialName = jbeamData.screenMaterialName
        htmlFilePath = jbeamData.htmlFilePath
        textureWidth = jbeamData.textureWidth or 800
        textureHeight = jbeamData.textureHeight or 160
        textureFPS = jbeamData.textureFPS or 30
        name = jbeamData.name or "sdd_g82_climateDisplay"
        
        print("JBeam data received:")
        print("  - Material: " .. (screenMaterialName or "nil"))
        print("  - HTML file: " .. (htmlFilePath or "nil"))
        print("  - Texture size: " .. textureWidth .. "x" .. textureHeight)
        print("  - Name: " .. name)
    end
    
    if not screenMaterialName then
        print('ERROR: screenMaterialName is required')
        return
    end
    
    if not htmlFilePath then
        print('ERROR: htmlFilePath is required')
        return
    end
    
    htmlTexture.create(screenMaterialName, htmlFilePath, textureWidth, textureHeight, textureFPS, "automatic")
    
    print("Climate display HTML texture created: " .. screenMaterialName)
    print("Climate screen: OFF when fan=0, ON when fan>0")
    print("Temperature: 16°C to 28°C in 0.5°C steps")
    print("Default airflow: L1+L2 (feet+face), R1+R2 (face+recirculation)")
    print("Heated seats: off → 3 bars → 2 bars → 1 bar → off")
    print("Fan will default to level 2 when ignition is turned on")
    
end

local function updateGFX(dt)
    updateTimer = updateTimer + dt
    
    local tempLUp = electrics.values.temp_L_up or 0
    local tempLDown = electrics.values.temp_L_down or 0
    local tempRUp = electrics.values.temp_R_up or 0
    local tempRDown = electrics.values.temp_R_down or 0
    
    if tempLUp == 1 or tempLDown == 1 then
        if (tempLUp == 1 and lastTempLUp == 0) or (tempLDown == 1 and lastTempLDown == 0) then
            tempTimerL = 0
            if tempLUp == 1 and tempLeft < tempMax then
                tempLeft = math.min(tempMax, tempLeft + tempStep)
            elseif tempLDown == 1 and tempLeft > tempMin then
                tempLeft = math.max(tempMin, tempLeft - tempStep)
            end
        else

            tempTimerL = tempTimerL + dt
            if tempTimerL >= tempInterval then
                tempTimerL = 0
                if tempLUp == 1 and tempLeft < tempMax then
                    tempLeft = math.min(tempMax, tempLeft + tempStep)
                elseif tempLDown == 1 and tempLeft > tempMin then
                    tempLeft = math.max(tempMin, tempLeft - tempStep)
                end
            end
        end
    else
        tempTimerL = 0
    end
    
    if tempRUp == 1 or tempRDown == 1 then
        if (tempRUp == 1 and lastTempRUp == 0) or (tempRDown == 1 and lastTempRDown == 0) then
            tempTimerR = 0
            if tempRUp == 1 and tempRight < tempMax then
                tempRight = math.min(tempMax, tempRight + tempStep)
            elseif tempRDown == 1 and tempRight > tempMin then
                tempRight = math.max(tempMin, tempRight - tempStep)
            end
        else
            tempTimerR = tempTimerR + dt
            if tempTimerR >= tempInterval then
                tempTimerR = 0
                if tempRUp == 1 and tempRight < tempMax then
                    tempRight = math.min(tempMax, tempRight + tempStep)
                elseif tempRDown == 1 and tempRight > tempMin then
                    tempRight = math.max(tempMin, tempRight - tempStep)
                end
            end
        end
    else
        tempTimerR = 0
    end
    
    lastTempLUp = tempLUp
    lastTempLDown = tempLDown
    lastTempRUp = tempRUp
    lastTempRDown = tempRDown
    
    if updateTimer > invFPS then
        updateTimer = 0
        
        local airflowInputL = electrics.values.airflow_input_L or 0
        local airflowInputR = electrics.values.airflow_input_R or 0
        
        if airflowInputL == 1 and lastAirflowInputL == 0 then
            airflowCounterLeft = airflowCounterLeft + 1
            
            if airflowCounterLeft == 1 then
                airflowModeLeft = {1, 2}
            elseif airflowCounterLeft == 2 then
                airflowModeLeft = {1, 2, 3}
            elseif airflowCounterLeft == 3 then
                airflowModeLeft = {1}
            elseif airflowCounterLeft == 4 then
                airflowModeLeft = {2}
            else
                airflowModeLeft = {1, 2}
                airflowCounterLeft = 1
            end
            
            print("LEFT airflow changed: " .. table.concat(airflowModeLeft, "+") .. " (1=feet,2=face,3=windshield)")
        end
        lastAirflowInputL = airflowInputL
        
        if airflowInputR == 1 and lastAirflowInputR == 0 then
            airflowCounterRight = airflowCounterRight + 1
            
            if airflowCounterRight == 1 then
                airflowModeRight = {1, 2}
            elseif airflowCounterRight == 2 then
                airflowModeRight = {1}
            elseif airflowCounterRight == 3 then
                airflowModeRight = {2}
            else
                airflowModeRight = {1, 2}
                airflowCounterRight = 1
            end
            
            print("RIGHT airflow changed: " .. table.concat(airflowModeRight, "+") .. " (1=face,2=recirculation)")
        end
        lastAirflowInputR = airflowInputR
        
        local seatHeaterInputL = electrics.values.seatHeater_L_input or 0
        if seatHeaterInputL == 1 and lastSeatHeaterInputL == 0 then
            if seatHeaterLevelL == 0 then
                seatHeaterLevelL = 3
            elseif seatHeaterLevelL == 3 then
                seatHeaterLevelL = 2
            elseif seatHeaterLevelL == 2 then
                seatHeaterLevelL = 1
            else
                seatHeaterLevelL = 0
            end
            
            local levelText = seatHeaterLevelL == 0 and "OFF" or (seatHeaterLevelL .. " bar" .. (seatHeaterLevelL > 1 and "s" or ""))
            print("LEFT seat heater changed: " .. levelText)
        end
        lastSeatHeaterInputL = seatHeaterInputL

        local seatHeaterInputR = electrics.values.seatHeater_R_input or 0
        if seatHeaterInputR == 1 and lastSeatHeaterInputR == 0 then
            if seatHeaterLevelR == 0 then
                seatHeaterLevelR = 3
            elseif seatHeaterLevelR == 3 then
                seatHeaterLevelR = 2
            elseif seatHeaterLevelR == 2 then
                seatHeaterLevelR = 1
            else
                seatHeaterLevelR = 0
            end
            
            local levelText = seatHeaterLevelR == 0 and "OFF" or (seatHeaterLevelR .. " bar" .. (seatHeaterLevelR > 1 and "s" or ""))
            print("RIGHT seat heater changed: " .. levelText)
        end
        lastSeatHeaterInputR = seatHeaterInputR
        
        electrics.values.seatHeaterL = seatHeaterLevelL
        electrics.values.seatHeaterR = seatHeaterLevelR
        
        local fanLevel = 0
        for i = 1, 7 do
            local blowerValue = electrics.values["blower_" .. i] or 0
            if blowerValue > 0 then
                fanLevel = i
            end
        end
        
        local ignitionLevel = electrics.values.ignitionLevel or 0
        local oldClimateScreen = electrics.values.climateScreen or 0
        
        if ignitionLevel <= 0 then
            electrics.values.climateScreen = 0
        else
            if fanLevel == 0 then
                electrics.values.climateScreen = 0
            else
                electrics.values.climateScreen = 1
            end
        end
        
        local newClimateScreen = electrics.values.climateScreen or 0
        
        if not M.lastFanLevel or M.lastFanLevel ~= fanLevel or oldClimateScreen ~= newClimateScreen then
            if M.lastFanLevel and M.lastFanLevel ~= fanLevel then
                print("Fan level changed: " .. M.lastFanLevel .. " -> " .. fanLevel)
            end
            if oldClimateScreen ~= newClimateScreen then
                print("Climate screen: " .. (newClimateScreen == 1 and "ON" or "OFF") .. " (value=" .. newClimateScreen .. ")")
            end
            M.lastFanLevel = fanLevel
        end
        
        local climateData = {
            fanLevel = fanLevel,
            blower_1 = electrics.values.blower_1 or 0,
            blower_2 = electrics.values.blower_2 or 0,
            blower_3 = electrics.values.blower_3 or 0,
            blower_4 = electrics.values.blower_4 or 0,
            blower_5 = electrics.values.blower_5 or 0,
            blower_6 = electrics.values.blower_6 or 0,
            blower_7 = electrics.values.blower_7 or 0,
            
            ac = electrics.values.ac or 0,
            frontDefrost = electrics.values.frontDefrost or 0,
            rearDefrost = electrics.values.rearDefrost or 0,
            recirculation = electrics.values.recirculation or 0,
            seatHeaterL = seatHeaterLevelL,
            seatHeaterR = seatHeaterLevelR,
            
            airflowModeLeft = airflowModeLeft,
            airflowModeRight = airflowModeRight,
            
            tempLeft = tempLeft,
            tempRight = tempRight,
            
            climateScreen = electrics.values.climateScreen or 0,
            ignitionLevel = electrics.values.ignitionLevel or 0,
            engineRunning = electrics.values.engineRunning or 0,
        }
        
        if screenMaterialName then
            htmlTexture.call(screenMaterialName, "updateFromVehicle", climateData)
        end
    end
end

local function onReset()
    print("Climate Display Controller reset")
    updateTimer = 0
    airflowModeLeft = {1, 2}
    airflowModeRight = {1, 2}
    lastAirflowInputL = 0
    lastAirflowInputR = 0
    airflowCounterLeft = 1
    airflowCounterRight = 1
    
    tempLeft = 16.0
    tempRight = 16.0
    tempTimerL = 0
    tempTimerR = 0
    lastTempLUp = 0
    lastTempLDown = 0
    lastTempRUp = 0
    lastTempRDown = 0
    
    seatHeaterLevelL = 0
    seatHeaterLevelR = 0
    lastSeatHeaterInputL = 0
    lastSeatHeaterInputR = 0
    
    M.lastFanLevel = nil
    
    electrics.values.climateScreen = 0
    electrics.values.seatHeaterL = 0
    electrics.values.seatHeaterR = 0
end

local function onDestroy()
    if screenMaterialName then
        htmlTexture.destroy(screenMaterialName)
        print("Climate display HTML texture destroyed")
    end
end

M.init = init
M.updateGFX = updateGFX
M.onReset = onReset
M.onDestroy = onDestroy

return M