local M = {}

local electrics_values = electrics.values
local htmlTexture = require("htmlTexture")

local royalAfterFire
local htmlPath
local lastState = 0
local updateTimer = 0
local UPDATE_INTERVAL = 0.033

function M.init(jbeamData)
    royalAfterFire = jbeamData.materialName
    htmlPath = jbeamData.htmlPath

    htmlTexture.create(
        royalAfterFire,
        htmlPath,
        jbeamData.textureWidth,
        jbeamData.textureHeight,
        glowFor,
        "automatic"
    )
    
    electrics_values.nos = 0
end

function M.updateGFX(dt)
    updateTimer = updateTimer + dt
    if updateTimer < UPDATE_INTERVAL then return end
    updateTimer = 0
    
    local newState = electrics_values.rpmTacho > 3350 and electrics_values.nitrousOxideArm == 1 and 2 or 0
    
    if newState ~= lastState then
        electrics_values.nos = newState
        lastState = newState
    end
end

M.type = "auxiliary"
M.relevantDevice = nil

return M