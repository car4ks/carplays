local M = {}
M.type = "auxiliary"

local htmlTexture = require("htmlTexture")

-- Configuration
local airliftMaterial = nil
local htmlPath = nil
local textureWidth = 0
local textureHeight = 0
local textureFPS = 0
local updateTimer = 0
local invFPS = 1 / 30

-- Constants
local AIRLIFT_SPEED = 0.2
local MIN_AIRLIFT = -1
local MAX_AIRLIFT = 1
local DISPLAY_SCALE = 50

-- Corner configuration
local corners = {"FL", "FR", "RL", "RR"}
local groups = {"F", "R"} -- Front and Rear groups

-- Cache for electrics values
local electricsCache = {}
local lastDisplayValues = {}

-- State tracking
local lastPlayerSeated = false

local function initializeElectricsCache()
    electricsCache = {}
    
    -- Cache corner positions
    for i = 1, #corners do
        local corner = corners[i]
        electricsCache['airlift' .. corner] = 0
        electricsCache['airlift_' .. corner .. '_up'] = 0
        electricsCache['airlift_' .. corner .. '_down'] = 0
        lastDisplayValues[corner] = 0
    end
    
    -- Cache group controls
    for i = 1, #groups do
        local group = groups[i]
        electricsCache['airlift_' .. group .. '_up'] = 0
        electricsCache['airlift_' .. group .. '_down'] = 0
    end
end

local function updateElectricsCache()
    -- Update corner positions and individual controls
    for i = 1, #corners do
        local corner = corners[i]
        electricsCache['airlift' .. corner] = electrics.values['airlift' .. corner] or 0
        electricsCache['airlift_' .. corner .. '_up'] = electrics.values['airlift_' .. corner .. '_up'] or 0
        electricsCache['airlift_' .. corner .. '_down'] = electrics.values['airlift_' .. corner .. '_down'] or 0
    end
    
    -- Update group controls
    for i = 1, #groups do
        local group = groups[i]
        electricsCache['airlift_' .. group .. '_up'] = electrics.values['airlift_' .. group .. '_up'] or 0
        electricsCache['airlift_' .. group .. '_down'] = electrics.values['airlift_' .. group .. '_down'] or 0
    end
end

local function setElectricValue(key, value)
    if electrics.values[key] ~= value then
        electrics.values[key] = value
        electricsCache[key] = value
    end
end

local function toDisplayValue(value)
    return math.floor((1 - value) * DISPLAY_SCALE)
end

local function updateAirbag(corner, dt)
    local speed = AIRLIFT_SPEED * dt
    local current = electricsCache['airlift' .. corner]
    local changed = false
    
    -- Individual corner controls
    if electricsCache['airlift_' .. corner .. '_up'] > 0 then
        current = current - speed
        changed = true
    elseif electricsCache['airlift_' .. corner .. '_down'] > 0 then
        current = current + speed
        changed = true
    end
    
    -- Group controls (F or R)
    local group = corner:sub(1, 1)
    if electricsCache['airlift_' .. group .. '_up'] > 0 then
        current = current - speed
        changed = true
    elseif electricsCache['airlift_' .. group .. '_down'] > 0 then
        current = current + speed
        changed = true
    end
    
    if changed then
        current = math.max(MIN_AIRLIFT, math.min(MAX_AIRLIFT, current))
        setElectricValue('airlift' .. corner, current)
    end
end

local function shouldUpdateHtml()
    if not playerInfo.anyPlayerSeated then
        return false
    end
    
    -- Check if any display values have changed significantly
    for i = 1, #corners do
        local corner = corners[i]
        local current = electricsCache['airlift' .. corner]
        local displayValue = toDisplayValue(current)
        
        if math.abs(displayValue - lastDisplayValues[corner]) >= 1 then
            return true
        end
    end
    
    return false
end

local function updateHtmlTexture()
    if not airliftMaterial or not htmlTexture then return end
    
    local data = {
        electrics = {}
    }
    
    -- Update display values and cache them
    for i = 1, #corners do
        local corner = corners[i]
        local displayValue = toDisplayValue(electricsCache['airlift' .. corner])
        data.electrics['airlift' .. corner] = displayValue
        lastDisplayValues[corner] = displayValue
    end
    
    local success, error = pcall(function()
        htmlTexture.call(airliftMaterial, "updateData", data)
    end)
    
    if not success and error then
        log("W", "airlift", "HTML texture update failed: " .. tostring(error))
    end
end

local function updateGFX(dt)
    if not electrics or not electrics.values then return end
    
    updateElectricsCache()
    
    -- Check if any controls are active for early exit
    local anyControlActive = false
    for i = 1, #corners do
        local corner = corners[i]
        if electricsCache['airlift_' .. corner .. '_up'] > 0 or 
           electricsCache['airlift_' .. corner .. '_down'] > 0 then
            anyControlActive = true
            break
        end
    end
    
    for i = 1, #groups do
        local group = groups[i]
        if electricsCache['airlift_' .. group .. '_up'] > 0 or 
           electricsCache['airlift_' .. group .. '_down'] > 0 then
            anyControlActive = true
            break
        end
    end
    
    -- Update airbag positions
    if anyControlActive then
        for i = 1, #corners do
            updateAirbag(corners[i], dt)
        end
    end
    
    -- Handle HTML texture updates with throttling
    updateTimer = updateTimer + dt
    if updateTimer > invFPS then
        updateTimer = 0
        
        if shouldUpdateHtml() then
            updateHtmlTexture()
        end
    end
end

local function init(jbeamData)
    airliftMaterial = jbeamData.materialName
    htmlPath = jbeamData.htmlPath
    textureWidth = jbeamData.textureWidth or 256
    textureHeight = jbeamData.textureHeight or 128
    textureFPS = jbeamData.textureFPS or 30
    invFPS = 1 / textureFPS

    initializeElectricsCache()
    
    -- Initialize all airlift positions
    for i = 1, #corners do
        setElectricValue('airlift' .. corners[i], 0)
    end

    if airliftMaterial and htmlPath then
        local success, error = pcall(function()
            htmlTexture.create(airliftMaterial, htmlPath, textureWidth, textureHeight, textureFPS, "automatic")
        end)
        
        if not success and error then
            log("E", "airlift", "Failed to create HTML texture: " .. tostring(error))
        end
    end
end

local function reset()
    initializeElectricsCache()
    updateTimer = 0
    
    -- Reset all positions
    for i = 1, #corners do
        setElectricValue('airlift' .. corners[i], 0)
        lastDisplayValues[corners[i]] = 0
    end
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M