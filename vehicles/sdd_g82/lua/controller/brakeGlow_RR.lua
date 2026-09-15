-- Brake glow mod with reset handling
local M = {}
M.type = "auxiliary"

-- Local variables
local htmlTexture = require("htmlTexture")
local updateInterval = 1/30 -- 30 FPS update rate
local timeSinceLastUpdate = 0
local textureHandle = nil
local htmlPath = nil
local isInitialized = false
local DEFAULT_TEMP = 15 -- Default temperature for reset

-- Error checking function
local function validateConfig(config)
    if not config then
        log('E', 'brakeGlow', 'No configuration data provided')
        return false
    end
    
    if not config.materialName then
        log('E', 'brakeGlow', 'No material name specified')
        return false
    end
    
    if not config.htmlPath then
        log('E', 'brakeGlow', 'No HTML path specified')
        return false
    end
    
    return true
end

local function onExtensionLoaded()
    -- Initialize with default state
    isInitialized = false
end

local function resetBrakeTemp()
    if isInitialized and textureHandle then
        htmlTexture.call(textureHandle, "update", DEFAULT_TEMP)
        electrics.values.brakeTempRR = DEFAULT_TEMP
    end
end

-- Called when vehicle is reset
local function onReset()
    resetBrakeTemp()
end

-- Called when physics are reset
local function onBeamReset()
    resetBrakeTemp()
end

local function init(jbeamData)
    -- Safety check for jbeamData
    if not validateConfig(jbeamData) then
        log('E', 'brakeGlow', 'Failed to initialize due to missing configuration')
        return
    end

    -- Initialize with validated data
    textureHandle = jbeamData.materialName
    htmlPath = jbeamData.htmlPath
    local width = jbeamData.textureWidth or 512
    local height = jbeamData.textureHeight or 512
    
    -- Create and initialize texture
    if textureHandle and htmlPath then
        htmlTexture.create(textureHandle, htmlPath, width, height, 30, "automatic")
        htmlTexture.call(textureHandle, "init", DEFAULT_TEMP)
        isInitialized = true
        log('I', 'brakeGlow', 'Successfully initialized brake glow mod')
    end
end

local function updateGFX(dt)
    -- Only update if properly initialized
    if not isInitialized then return end
    
    timeSinceLastUpdate = timeSinceLastUpdate + dt
    if timeSinceLastUpdate >= updateInterval then
        local brakeTemp = DEFAULT_TEMP -- Start with default temperature
        
        -- Safely check for wheel thermal data
        if electrics and electrics.values and electrics.values.wheelThermals then
            local wheelThermals = electrics.values.wheelThermals
            if wheelThermals.RR and wheelThermals.RR.brakeSurfaceTemperature then
                brakeTemp = wheelThermals.RR.brakeSurfaceTemperature
            elseif wheelThermals.RR1 and wheelThermals.RR1.brakeSurfaceTemperature then
                brakeTemp = wheelThermals.RR1.brakeSurfaceTemperature
            end
        end
        
        -- Update texture if handle exists
        if textureHandle then
            htmlTexture.call(textureHandle, "update", brakeTemp)
            electrics.values.brakeTempRR = brakeTemp
        end
        
        timeSinceLastUpdate = 0
    end
end

-- Expose module functions
M.onExtensionLoaded = onExtensionLoaded
M.init = init
M.updateGFX = updateGFX
M.onReset = onReset
M.onBeamReset = onBeamReset

return M