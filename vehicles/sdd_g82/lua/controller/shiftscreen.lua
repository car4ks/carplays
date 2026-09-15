local M = {}
M.type = "auxiliary"

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

local updateInterval = 0.1

local function updateGFX(dt)
    if htmlTexture then
        updateTimer = updateTimer + dt
        if updateTimer > invFPS and screenMaterialName and textureCreated then
            updateTimer = 0
            local shiftData = {
                electrics = {
                    rpm = electrics.values.rpm or 0,
                    wheelspeed = electrics.values.wheelspeed or 0,
                    led0 = electrics.values.led0 or 0,
                    led1 = electrics.values.led1 or 0,
                    led2 = electrics.values.led2 or 0,
                    led3 = electrics.values.led3 or 0,
                    led4 = electrics.values.led4 or 0,
                    led5 = electrics.values.led5 or 0,
                    led6 = electrics.values.led6 or 0,
                    led7 = electrics.values.led7 or 0,
                    led8 = electrics.values.led8 or 0
                }
            }
            if type(htmlTexture.call) == "function" then
                pcall(function()
                    htmlTexture.call(screenMaterialName, "updateDisplay", shiftData)
                end)
            end
        end
    end
end

local function init(jbeamData)
    if not htmlTexture then
        return
    end

    screenMaterialName = jbeamData.materialName or "@sdd_g82_shiftscreen"
    htmlFilePath = jbeamData.htmlPath or "local://local/vehicles/sdd_g82/Screen/shiftscreen.html"
    textureWidth = jbeamData.textureWidth or 256
    textureHeight = jbeamData.textureHeight or 128
    textureFPS = jbeamData.textureFPS or 60
    
    if type(htmlTexture.create) == "function" then
        textureCreated = pcall(function()
            htmlTexture.create(screenMaterialName, htmlFilePath, textureWidth, textureHeight, textureFPS, "automatic")
        end)
    end
end

local function reset()
    updateTimer = 0
end

local function destroy()
    if htmlTexture and type(htmlTexture.destroy) == "function" and screenMaterialName then
        pcall(function()
            htmlTexture.destroy(screenMaterialName)
        end)
    end
end

M.init = init
M.updateGFX = updateGFX
M.reset = reset
M.destroy = destroy

return M