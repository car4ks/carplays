-- Save as vehicles/sdd_g82/beep_controller.lua

local M = {}

-- Variables to track states
local lastIgnitionState = 0
local lastEngineDamageState = false
local lastDrivetrainDamageState = false
local lastEngineElectricValue = 0
local lastDrivetrainElectricValue = 0
local lastDamageAlertValue = 0

-- Pre-define damage type arrays (create once, not every frame)
local engineDamageTypes = {
    "oilStarvation", "coolantHot", "oilHot", "pistonRingsDamaged", "rodBearingsDamaged",
    "headGasketDamaged", "turbochargerHot", "engineIsHydrolocking", "engineReducedTorque",
    "mildOverrevDamage", "catastrophicOverrevDamage", "overRevDanger", "overTorqueDanger",
    "catastrophicOverTorqueDamage", "engineHydrolocked", "engineDisabled", "blockMelted",
    "engineLockedUp", "radiatorLeak", "oilpanLeak", "inductionSystemDamaged", "impactDamage",
    "starvedOfOil", "oilLevelCritical", "oilLevelTooHigh", "oilOverheating", "coolantOverheating"
}

local axleDamageTypes = {
    "wheelaxleFL", "wheelaxleFR", "wheelaxleRL", "wheelaxleRR", "driveshaft", "driveshaft_F"
}

-- Cache for damage states to reduce API calls
local damageCache = {}
local cacheTimer = 0
local CACHE_INTERVAL = 0.1 -- Update cache every 100ms instead of every frame

-- Function to play the beep sound
local function playBeepSound()
    if not obj then
        log("W", "beepController", "No object available to play sound")
        return
    end
    obj:createSFXSource("vehicles/sdd_g82/sounds/test.mp3", "AudioClosest3D", "beepSound", -1)
    obj:playSFXOnce("beepSound", 369, 2, 1)
    log("I", "beepController", "Beep sound triggered")
end

-- Function to update damage cache
local function updateDamageCache()
    damageCache.engine = false
    damageCache.transmission = false
    damageCache.axle = false
    
    -- Check engine damage
    for i = 1, #engineDamageTypes do
        if damageTracker.getDamage("engine", engineDamageTypes[i]) then
            damageCache.engine = true
            break -- Early exit on first damage found
        end
    end
    
    -- Check transmission damage
    damageCache.transmission = damageTracker.getDamage("gearbox", "synchroWear") or false
    
    -- Check axle damage
    for i = 1, #axleDamageTypes do
        if damageTracker.getDamage("powertrain", axleDamageTypes[i]) then
            damageCache.axle = true
            break -- Early exit on first damage found
        end
    end
end

-- Update function called every frame
local function updateGFX(dt)
    -- Early exit if ignition is off and no damage states to track
    local ignitionState = electrics.values.ignitionLevel or 0
    if ignitionState == 0 and not lastEngineDamageState and not lastDrivetrainDamageState then
        return
    end
    
    -- Check ignition state changes
    if ignitionState ~= lastIgnitionState then
        log("I", "beepController", "Ignition changed to: " .. tostring(ignitionState))
        if ignitionState == 1 or ignitionState == 3 then
            playBeepSound()
        end
        lastIgnitionState = ignitionState
    end
    
    -- Update damage cache periodically instead of every frame
    cacheTimer = cacheTimer + dt
    if cacheTimer >= CACHE_INTERVAL then
        updateDamageCache()
        cacheTimer = 0
    end
    
    -- Check engine damage state change
    if damageCache.engine and not lastEngineDamageState then
        playBeepSound()
        -- Only set damage alert if it's not already set
        if lastDamageAlertValue ~= 1 then
            electrics.values.damageAlert = 1
            lastDamageAlertValue = 1
        end
    elseif not damageCache.engine and lastDamageAlertValue == 1 and not (damageCache.transmission or damageCache.axle) then
        -- Clear damage alert only if no other damage exists
        electrics.values.damageAlert = 0
        lastDamageAlertValue = 0
    end
    
    -- Update engine damage electric value only when changed
    local engineElectricValue = damageCache.engine and 1 or 0
    if engineElectricValue ~= lastEngineElectricValue then
        electrics.values.engineDamage = engineElectricValue
        lastEngineElectricValue = engineElectricValue
    end
    lastEngineDamageState = damageCache.engine
    
    -- Combined drivetrain damage check
    local drivetrainDamaged = damageCache.transmission or damageCache.axle
    
    if drivetrainDamaged and not lastDrivetrainDamageState then
        playBeepSound()
        -- Only set damage alert if it's not already set
        if lastDamageAlertValue ~= 1 then
            electrics.values.damageAlert = 1
            lastDamageAlertValue = 1
        end
    end
    
    -- Update drivetrain damage electric value only when changed
    local drivetrainElectricValue = drivetrainDamaged and 1 or 0
    if drivetrainElectricValue ~= lastDrivetrainElectricValue then
        electrics.values.drivetrain­Damage = drivetrainElectricValue
        lastDrivetrainElectricValue = drivetrainElectricValue
    end
    lastDrivetrainDamageState = drivetrainDamaged
end

-- Hook up the function
M.updateGFX = updateGFX

return M