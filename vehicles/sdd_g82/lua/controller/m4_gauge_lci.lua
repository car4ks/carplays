local M = {}
M.type = "auxiliary"
local texturePath = "/vehicles/sdd_g82/textures/Leather_2.dds"
local function fileExists(relativeFilePath)
    if FS and FS.fileExists then
        return FS:fileExists(relativeFilePath)
    else
        local file = io.open(relativeFilePath, "r")
        if file then
            file:close()
            return true
        end
        return false
    end
end

local htmlTexture = nil
pcall(function() htmlTexture = require("htmlTexture") end)

local screenMaterialName = nil
local htmlFilePath = nil
local textureWidth = 0
local textureHeight = 0
local textureFPS = 0
local updateTimer = 0
local invFPS = 1 / 60
local textureCreated = false

local engineMode = "comfort"
local suspensionMode = "comfort"
local steeringMode = "comfort"
local brakeMode = "comfort"

local function updateGFX(dt)
    if not fileExists(texturePath) then return end
    if not htmlTexture then return end
    
    updateTimer = updateTimer + dt
    
    if updateTimer > invFPS and screenMaterialName and textureCreated then
        updateTimer = 0
        
        if electrics.values.engineMode then engineMode = electrics.values.engineMode end
        if electrics.values.suspensionMode then suspensionMode = electrics.values.suspensionMode end
        if electrics.values.steeringMode then steeringMode = electrics.values.steeringMode end
        if electrics.values.brakeMode then brakeMode = electrics.values.brakeMode end
        
        local accX = electrics.values.accXSmooth or 0
        local accY = electrics.values.accYSmooth or 0
        local gForceX = accX / 9.81
        local gForceY = accY / 9.81
        
        local deadzone = 0.15
        if math.abs(gForceX) < deadzone then gForceX = 0 end
        if math.abs(gForceY) < deadzone then gForceY = 0 end
        
        local vehicleData = {
            rpm = electrics.values.rpm or 0,
            gear = electrics.values.gear or -2,
            wheelspeed = electrics.values.wheelspeed or 0,
            engineMode = engineMode,
            suspensionMode = suspensionMode,
            steeringMode = steeringMode,
            brakeMode = brakeMode,
            transfercase_state = electrics.values.transfercase_state or 0.33,
            accelerationData = {
                xSmooth = gForceX * 9.81,
                ySmooth = gForceY * 9.81
            }
        }
        
        if type(htmlTexture.call) == "function" then
            pcall(function()
                htmlTexture.call(screenMaterialName, "updateWithBeamNGData", vehicleData)
            end)
        end
    end
end

local function init(jbeamData)
    if not fileExists(texturePath) then return end
    if not htmlTexture then return end
    
    screenMaterialName = jbeamData.materialName or "@sdd_g82_gauges"
    htmlFilePath = jbeamData.htmlPath or "local://local/vehicles/sdd_g82/Screen/m4_gauge.html"
    textureWidth = jbeamData.textureWidth or 512
    textureHeight = jbeamData.textureHeight or 256
    textureFPS = jbeamData.textureFPS or 60
    
    if type(htmlTexture.create) == "function" then
        textureCreated = pcall(function()
            htmlTexture.create(screenMaterialName, htmlFilePath, textureWidth, textureHeight, textureFPS, "automatic")
        end)
    end
end

function M.reset() 
    if not fileExists(texturePath) then return end
end

function M.destroy() 
end

M.init = init
M.updateGFX = updateGFX

return M